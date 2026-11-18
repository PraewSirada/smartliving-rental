const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('SmartRental - Property Registration', function () {
  let rental;
  let landlord;
  let tenant;
  let arbitrator;

  beforeEach(async function () {
    [landlord, tenant, arbitrator] = await ethers.getSigners();
    const SmartRental = await ethers.getContractFactory('SmartRental');
    rental = await SmartRental.deploy(arbitrator.address);
    await rental.waitForDeployment();
  });

  it('should register a property successfully', async function () {
    const rent = ethers.parseEther('0.01');
    const deposit = ethers.parseEther('0.02');

    await (await rental.connect(landlord).registerProperty(
      'Room A101', rent, deposit
    )).wait();

    expect(await rental.propertyCount()).to.equal(1n);
    const property = await rental.properties(1);
    expect(property.landlord).to.equal(landlord.address);
    expect(property.name).to.equal('Room A101');
    expect(property.rent).to.equal(rent);
    expect(property.deposit).to.equal(deposit);
    expect(property.exists).to.equal(true);
  });

  it('should reject a property with zero deposit', async function () {
    let rejected = false;
    try {
      await rental.registerProperty(
        'Room A101', ethers.parseEther('0.01'), 0
      );
    } catch (error) {
      rejected = String(error.message).includes('Invalid property');
    }
    expect(rejected).to.equal(true);
    expect(await rental.propertyCount()).to.equal(0n);
  });
});
describe('SmartRental - Rental Agreement', function () {
  let rental, landlord, tenant, arbitrator, outsider;

  beforeEach(async function () {
    [landlord, tenant, arbitrator, outsider] = await ethers.getSigners();

    const SmartRental = await ethers.getContractFactory('SmartRental');
    rental = await SmartRental.deploy(arbitrator.address);
    await rental.waitForDeployment();

    await rental.connect(landlord).registerProperty(
      'Room A101',
      ethers.parseEther('0.01'),
      ethers.parseEther('0.02')
    );
  });

  it('should create a rental agreement successfully', async function () {
    const latest = await ethers.provider.getBlock('latest');
    const start = latest.timestamp + 60;
    const end = start + 86400 * 30;
    const termsHash = ethers.id('Rental terms for Room A101');

    await rental.connect(landlord).createAgreement(
      1, tenant.address, start, end, termsHash
    );

    expect(await rental.agreementCount()).to.equal(1n);

    const agreement = await rental.agreements(1);
    expect(agreement.propertyId).to.equal(1n);
    expect(agreement.tenant).to.equal(tenant.address);
    expect(agreement.status).to.equal(0n);
  });

  it('should reject agreement creation by non-landlord', async function () {
    const latest = await ethers.provider.getBlock('latest');
    const start = latest.timestamp + 60;
    const end = start + 86400 * 30;

    let rejected = false;

    try {
      await rental.connect(outsider).createAgreement(
        1, tenant.address, start, end, ethers.id('Rental terms')
      );
    } catch (error) {
      rejected = String(error.message).includes('Not landlord');
    }

    expect(rejected).to.equal(true);
    expect(await rental.agreementCount()).to.equal(0n);
  });
});
