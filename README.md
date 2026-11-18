# SmartLiving — Smart Property Rental & Deposit Management

React + Vite + Solidity + ethers.js + MetaMask on Ethereum Sepolia.

## Requirements covered

1. Register Property — owner registers rental price and deposit.
2. Create Rental Agreement — owner defines tenant, dates, and SHA-256-like on-chain commitment (**Keccak-256** hash) to agreed terms.
3. Confirm Agreement — both wallets confirm independently.
4. Deposit Security — tenant deposits exact ETH amount to escrow.
5. Record Rental Payment — tenant pays rent and history is stored on-chain.
6. Refund Deposit — after end date, owner proposes refund/reason; tenant approves; contract settles.
7. Rental Dispute — either party opens dispute; designated arbitrator decides refund and records reason.

**Security rules:** Refund cannot exceed escrow balance; settlement zeroes balance before external transfers; only relevant wallets can take privileged actions; ETH rent goes to landlord; escrow ETH is isolated from rent payments. This is an educational demo, not audited production software.

## 1. Deploy contract in Remix

1. Open https://remix.ethereum.org and create `SmartRental.sol` using `contracts/SmartRental.sol`.
2. Compile with Solidity `0.8.20` or newer compatible 0.8.x compiler.
3. In **Deploy & Run**, choose **Injected Provider - MetaMask** and switch MetaMask to **Sepolia**.
4. Deploy `SmartRental` with constructor `_arbitrator` = trusted dispute resolver wallet address (can be a separate test wallet). **Do not use the landlord wallet for impartial dispute resolution.**
5. Copy deployed contract address.

## 2. Run frontend

```bash
npm install
cp .env.example .env
```

Set `VITE_CONTRACT_ADDRESS=0x...` in `.env`, then:

```bash
npm run dev
```

Open the URL printed by Vite (normally http://localhost:5173). Connect MetaMask on Sepolia. Test wallets need **Sepolia test ETH** for gas and payments.

## 3. Test flow

- Wallet A (landlord): register property, create agreement with Wallet B tenant and future end date.
- Wallet A: confirm agreement.
- Wallet B: confirm agreement; deposit exact ETH; pay rent.
- Inspect rental payment history.
- **Normal close:** after contract end date, Wallet A proposes refund with reason; Wallet B approves; either account finalizes refund.
- **Dispute alternative:** on a separate active agreement, A or B opens dispute; arbitrator wallet calls resolveDispute with refund <= escrow balance and reason.

For fast local testing, set a short end time *in the future* using Remix directly. The frontend uses date-only fields and requires a future end date. Ethereum timestamps are UTC seconds.

## GitHub push

Create an empty GitHub repository, then in this project folder:

```bash
git init
git add .
git commit -m "Build SmartLiving rental escrow dApp"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

`.env`, `node_modules` and `dist` are excluded from Git. `.env.example` is safe to commit.

## Notes and limitations

- Contract holds only the Keccak-256 hash of terms, not full terms text. Store the signed-off terms document securely off-chain, and independently verify its hash; the UI does not currently preserve that document after page reload.
- Rental payments are recorded per transaction, not automatically scheduled or linked to calendar billing cycles.
- Room inspection is represented by the landlord's proposed settlement reason and tenant approval; no third-party inspection oracle is integrated.
- The dispute arbitrator is a trusted single wallet and can decide the split without tenant approval; this must be disclosed to users.
- Anyone can view blockchain data, so **do not put sensitive personal data or private details in reason strings or terms**.
- No automated test suite or security audit is included. Test carefully with Sepolia test ETH only.
