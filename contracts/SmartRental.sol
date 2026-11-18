// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** Demo escrow contract. Use an independent security review before production. */
contract SmartRental {
    enum Status { Proposed, Active, Disputed, Closed }
    struct Property { address landlord; string name; uint256 rent; uint256 deposit; bool exists; }
    struct Agreement { uint256 propertyId; address tenant; uint64 start; uint64 end; bytes32 termsHash; bool landlordConfirmed; bool tenantConfirmed; bool funded; uint256 depositBalance; Status status; }
    struct Payment { uint256 amount; uint256 paidAt; }
    struct Resolution { uint256 refund; string reason; bool proposed; bool landlordApproved; bool tenantApproved; }
    address public immutable arbitrator;
    uint256 public propertyCount;
    uint256 public agreementCount;
    mapping(uint256 => Property) public properties;
    mapping(uint256 => Agreement) public agreements;
    mapping(uint256 => Payment[]) private payments;
    mapping(uint256 => Resolution) private resolutions;
    bool private entered;
    event PropertyRegistered(uint256 indexed id, address indexed landlord);
    event AgreementCreated(uint256 indexed id, uint256 indexed propertyId, address indexed tenant);
    event AgreementConfirmed(uint256 indexed id, address indexed signer);
    event DepositFunded(uint256 indexed id, uint256 amount);
    event RentPaid(uint256 indexed id, uint256 amount);
    event ResolutionProposed(uint256 indexed id, uint256 refund, string reason);
    event ResolutionApproved(uint256 indexed id, address indexed signer);
    event DisputeOpened(uint256 indexed id, string reason);
    event DisputeResolved(uint256 indexed id, uint256 refund, string reason);
    event DepositSettled(uint256 indexed id, uint256 tenantRefund, uint256 landlordDeduction);
    modifier nonReentrant() { require(!entered, "Reentrancy"); entered = true; _; entered = false; }
    constructor(address _arbitrator) { require(_arbitrator != address(0), "Invalid arbitrator"); arbitrator = _arbitrator; }
    function registerProperty(string calldata name, uint256 rent, uint256 deposit) external returns(uint256 id) {
        require(bytes(name).length > 0 && rent > 0 && deposit > 0, "Invalid property");
        id = ++propertyCount; properties[id] = Property(msg.sender, name, rent, deposit, true);
        emit PropertyRegistered(id, msg.sender);
    }
    function createAgreement(uint256 propertyId, address tenant, uint64 start, uint64 end, bytes32 termsHash) external returns(uint256 id) {
        Property storage p = properties[propertyId];
        require(p.exists && msg.sender == p.landlord, "Not landlord");
        require(tenant != address(0) && tenant != p.landlord && start < end && end > block.timestamp && termsHash != bytes32(0), "Invalid agreement");
        id = ++agreementCount;
        agreements[id] = Agreement(propertyId, tenant, start, end, termsHash, false, false, false, 0, Status.Proposed);
        emit AgreementCreated(id, propertyId, tenant);
    }
    function confirmAgreement(uint256 id) external {
        Agreement storage a = agreements[id]; Property storage p = properties[a.propertyId];
        require(a.tenant != address(0) && a.status == Status.Proposed, "Invalid status");
        if (msg.sender == p.landlord) { require(!a.landlordConfirmed, "Already confirmed"); a.landlordConfirmed = true; }
        else if (msg.sender == a.tenant) { require(!a.tenantConfirmed, "Already confirmed"); a.tenantConfirmed = true; }
        else revert("Not party");
        emit AgreementConfirmed(id, msg.sender);
    }
    function depositSecurity(uint256 id) external payable {
        Agreement storage a = agreements[id]; Property storage p = properties[a.propertyId];
        require(msg.sender == a.tenant && a.landlordConfirmed && a.tenantConfirmed && !a.funded && a.status == Status.Proposed, "Not ready");
        require(msg.value == p.deposit, "Wrong deposit");
        a.funded = true; a.depositBalance = msg.value; a.status = Status.Active;
        emit DepositFunded(id, msg.value);
    }
    function payRent(uint256 id) external payable {
        Agreement storage a = agreements[id]; Property storage p = properties[a.propertyId];
        require(msg.sender == a.tenant && a.status == Status.Active && a.funded, "Not active tenant");
        require(msg.value == p.rent, "Wrong rent");
        payments[id].push(Payment(msg.value, block.timestamp));
        (bool ok,) = payable(p.landlord).call{value: msg.value}(""); require(ok, "Rent transfer failed");
        emit RentPaid(id, msg.value);
    }
    function paymentCount(uint256 id) external view returns(uint256) { return payments[id].length; }
    function paymentAt(uint256 id, uint256 index) external view returns(uint256 amount, uint256 paidAt) {
        Payment storage p = payments[id][index]; return (p.amount, p.paidAt);
    }
    function proposeRefund(uint256 id, uint256 refund, string calldata reason) external {
        Agreement storage a = agreements[id]; Property storage p = properties[a.propertyId];
        require(msg.sender == p.landlord && a.status == Status.Active && block.timestamp >= a.end, "Not eligible");
        require(refund <= a.depositBalance && bytes(reason).length > 0, "Invalid resolution");
        resolutions[id] = Resolution(refund, reason, true, true, false);
        emit ResolutionProposed(id, refund, reason);
    }
    function approveRefund(uint256 id) external {
        Agreement storage a = agreements[id]; Resolution storage r = resolutions[id];
        require(msg.sender == a.tenant && a.status == Status.Active && r.proposed, "Not eligible");
        require(!r.tenantApproved, "Already approved"); r.tenantApproved = true;
        emit ResolutionApproved(id, msg.sender);
    }
    function finalizeRefund(uint256 id) external nonReentrant {
        Agreement storage a = agreements[id]; Resolution storage r = resolutions[id]; Property storage p = properties[a.propertyId];
        require(a.status == Status.Active && block.timestamp >= a.end && r.proposed && r.landlordApproved && r.tenantApproved, "Not approved");
        _settle(id, r.refund, p.landlord);
    }
    function openDispute(uint256 id, string calldata reason) external {
        Agreement storage a = agreements[id]; Property storage p = properties[a.propertyId];
        require((msg.sender == a.tenant || msg.sender == p.landlord) && a.status == Status.Active && a.funded, "Not eligible");
        require(bytes(reason).length > 0, "Reason required"); a.status = Status.Disputed;
        emit DisputeOpened(id, reason);
    }
    function resolveDispute(uint256 id, uint256 refund, string calldata reason) external nonReentrant {
        Agreement storage a = agreements[id]; Property storage p = properties[a.propertyId];
        require(msg.sender == arbitrator && a.status == Status.Disputed, "Not arbitrator/disputed");
        require(refund <= a.depositBalance && bytes(reason).length > 0, "Invalid decision");
        emit DisputeResolved(id, refund, reason);
        _settle(id, refund, p.landlord);
    }
    function getResolution(uint256 id) external view returns(uint256 refund, string memory reason, bool proposed, bool landlordApproved, bool tenantApproved) {
        Resolution storage r = resolutions[id]; return (r.refund, r.reason, r.proposed, r.landlordApproved, r.tenantApproved);
    }
    function _settle(uint256 id, uint256 refund, address landlord) private {
        Agreement storage a = agreements[id]; uint256 total = a.depositBalance;
        require(total > 0 && refund <= total, "Insufficient deposit");
        a.depositBalance = 0; a.status = Status.Closed;
        if (refund > 0) { (bool ok,) = payable(a.tenant).call{value: refund}(""); require(ok, "Refund failed"); }
        uint256 deduction = total - refund;
        if (deduction > 0) { (bool ok,) = payable(landlord).call{value: deduction}(""); require(ok, "Deduction failed"); }
        emit DepositSettled(id, refund, deduction);
    }
}
