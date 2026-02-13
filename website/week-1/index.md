# Week 1: Foundations & First Contract

**Time estimate:** ~8-10 hours (including homework) | **Difficulty:** Beginner | **Prerequisites:** Basic Solidity knowledge

---

## What You'll Learn

This week takes you from zero FHE knowledge to writing and testing your first encrypted smart contract. You'll understand:

- What Fully Homomorphic Encryption (FHE) is and why it matters for blockchain privacy
- How the FHEVM coprocessor architecture works under the hood
- The encrypted data lifecycle: encrypt → compute → authorize → decrypt
- How to set up a Foundry development environment for FHEVM
- How mock mode enables fast, deterministic local testing
- How to write, test, and reason about encrypted smart contracts

## What You'll Build

**`FHECounter.sol`** — An encrypted counter contract where the count value is always encrypted on-chain. Nobody — not validators, not block explorers, not other contracts — can see the counter's value. Only authorized users can decrypt it off-chain.

This simple contract teaches you the fundamental FHE pattern that every confidential contract uses:

```
Encrypt input → Verify → Compute on ciphertext → Authorize → Decrypt off-chain
```

## Weekly Milestones

Use this checklist to track your progress:

- [ ] **Lesson 1** — Understand FHE theory, the coprocessor model, encrypted types, and the ACL
- [ ] **Lesson 2** — Install Foundry, clone the repo, run `forge build` and `forge test` successfully
- [ ] **Lesson 3** — Walk through `FHECounter.sol` line by line, understand the test pattern, complete the multiply exercise
- [ ] **Homework** — Build `EncryptedPoll.sol` from the starter template and pass all provided tests

## Lessons

### [Lesson 1: FHE Theory](/week-1/lesson-1-fhe-theory) <span style="opacity: 0.6">~45 min</span>

The conceptual foundation. Learn what FHE is, how it compares to other privacy solutions (ZK, TEEs, MPC), and how the FHEVM coprocessor model makes encrypted computation feel like normal Solidity. Covers encrypted types, the data lifecycle, access control, and key limitations.

### [Lesson 2: Environment Setup](/week-1/lesson-2-setup) <span style="opacity: 0.6">~30 min</span>

Hands-on setup. Install Foundry, clone the bootcamp repo, understand the project structure and remappings, and learn how mock mode replaces real FHE infrastructure for fast local testing. You'll run `forge test` and see all tests pass.

### [Lesson 3: Hello FHE — Your First Encrypted Contract](/week-1/lesson-3-hello-fhe) <span style="opacity: 0.6">~60 min</span>

The main event. Walk through `FHECounter.sol` line by line, understand every import, state variable, and FHE operation. Learn the three-step test pattern (encrypt → call → decrypt) and complete a hands-on exercise adding a `multiply` function.

### [Homework: EncryptedPoll](/week-1/homework) <span style="opacity: 0.6">~4-5 hours</span>

Build an encrypted voting contract from scratch. Users cast encrypted votes, and the contract tallies them without ever revealing individual choices. Starter template and pre-written test suite provided.

---

## Key Concepts This Week

| Concept | Description |
|---------|-------------|
| FHE | Computation on encrypted data without decrypting |
| Coprocessor | Off-chain FHE executor; contracts delegate encrypted operations to it |
| `euint32` | Encrypted unsigned 32-bit integer (stored as `bytes32` handle) |
| `externalEuint32` | Unverified encrypted input from a user |
| `FHE.fromExternal()` | Verify and convert external encrypted input |
| `FHE.add()` / `FHE.sub()` | Encrypted arithmetic operations |
| `FHE.allowThis()` | Grant contract permission to reuse an encrypted value |
| `FHE.allow()` | Grant a user permission to decrypt a value |
| Mock mode | Local testing with plaintext stand-ins for FHE operations |

---

**Ready?** Start with [Lesson 1: FHE Theory](/week-1/lesson-1-fhe-theory).
