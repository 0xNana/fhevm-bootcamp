# Week 4: Capstone & Production

**Time estimate:** ~10-12 hours (including capstone homework) | **Difficulty:** Advanced | **Prerequisites:** [Week 1](/week-1/), [Week 2](/week-2/), and [Week 3](/week-3/) completed

---

## What You'll Learn

This is the final week — you'll bring everything together by building a **production-grade sealed-bid auction** and then **deploying it to a real network**. You'll master the most advanced FHE patterns and learn the operational skills needed to ship confidential contracts to mainnet:

- **State machine design** — phase-based flow control (Bidding → Closed → Revealed) to enforce auction lifecycle rules
- **`eaddress`** — an encrypted Ethereum address type for hiding the winner's identity until reveal
- **`FHE.gt()` + `FHE.select()` for ranking** — encrypted greater-than comparison to track the highest bidder without revealing any bids
- **Incremental winner tracking** — updating the winner on each bid instead of batch-comparing at close time
- **Deployment to Sepolia** — moving from mock mode to a real FHEVM-enabled testnet with `forge script`
- **`fhevmjs` client SDK** — real client-side encryption with `createEncryptedInput` and off-chain decryption
- **Security checklist** — production readiness audit covering ACL, privacy leaks, side-channels, and operational best practices

## What You'll Build

**`SealedBidAuction.sol`** — A complete sealed-bid auction where bids are encrypted, the winner is determined by encrypted comparison, and only the winning bid is ever revealed. This contract is directly inspired by **Zama Auction**, the first application launched on the Zama Protocol mainnet.

Then you'll **deploy it** — writing a Forge deployment script, targeting Sepolia, integrating `fhevmjs` for real encryption, and verifying the contract on Etherscan.

```
State machine → Encrypted bids → FHE.gt ranking → Selective reveal → Deploy → Frontend integration
```

## Weekly Milestones

Use this checklist to track your progress:

- [ ] **Lesson 1** — Understand sealed-bid auction design, implement state machine phases (Bidding → Closed → Revealed), use `eaddress` for encrypted winner tracking, use `FHE.gt()` + `FHE.select()` for incremental bid comparison, and walk through the full `SealedBidAuction.sol` contract and test suite
- [ ] **Lesson 2** — Understand mock vs real mode differences, write and execute a Forge deployment script for Sepolia, integrate `fhevmjs` for client-side encryption and decryption, verify contracts on Etherscan, and complete the mainnet deployment checklist
- [ ] **Capstone Homework** — Extend `SealedBidAuction.sol` into a Vickrey (second-price) auction with additional features and pass all provided tests

## Lessons

### [Lesson 1: Building a Sealed-Bid Auction](/week-4/lesson-1-auction) <span style="opacity: 0.6">~90 min</span>

Build a complete sealed-bid auction with encrypted bids. Learn why sealed auctions solve front-running and bid sniping, implement a three-phase state machine, use `eaddress` for encrypted winner identity, and master `FHE.gt()` + `FHE.select()` for encrypted ranking — the same patterns used in Zama's production auction.

### [Lesson 2: From Mock to Mainnet — Deployment & Frontend](/week-4/lesson-2-deployment) <span style="opacity: 0.6">~60 min</span>

Take your contracts from local mock testing to a real FHEVM-enabled testnet. Learn the differences between mock and real mode, write deployment scripts with `forge script`, integrate `fhevmjs` for client-side encryption and decryption, verify contracts on Etherscan, and complete a comprehensive mainnet security checklist.

### [Capstone Homework: Vickrey Auction](/week-4/homework) <span style="opacity: 0.6">~6-8 hours</span>

Extend the sealed-bid auction into a Vickrey (second-price) auction — the winner pays the second-highest bid. Add bid deposits, minimum bid enforcement, and multi-item support. This is the final project that demonstrates mastery of the full FHEVM stack.

---

## Key Concepts This Week

| Concept | Description |
|---------|-------------|
| `eaddress` | Encrypted Ethereum address — hides identity until explicitly decrypted |
| `FHE.asEaddress()` | Trivially encrypt a plaintext address into an encrypted handle |
| `FHE.gt()` | Encrypted greater-than comparison — returns `ebool` without revealing operands |
| State machine (Phase enum) | Enforce auction lifecycle: Bidding → Closed → Revealed |
| Incremental tracking | Update highest bidder on each `placeBid` instead of batch-comparing at close |
| Selective revelation | Only the winning bid is ever revealed — losers' bids stay encrypted forever |
| `fhevmjs` | Client-side SDK for real encryption (`createEncryptedInput`) and decryption |
| `forge script` | Foundry's deployment automation for testnet and mainnet |
| Silent-zero pattern | Privacy-preserving error handling — never revert on encrypted conditions |
| Mainnet checklist | Production readiness audit covering ACL, privacy, security, and operations |

---

**Ready?** Start with [Lesson 1: Building a Sealed-Bid Auction](/week-4/lesson-1-auction).
