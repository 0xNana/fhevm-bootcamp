# Week 3: Confidential DeFi

**Time estimate:** ~8-10 hours (including homework) | **Difficulty:** Intermediate-Advanced | **Prerequisites:** [Week 1](/week-1/) and [Week 2](/week-2/) completed

---

## What You'll Learn

This week you graduate from single-user vaults to **multi-party confidential finance**. You'll build a full ERC20-compatible token where balances, transfer amounts, and allowances are all encrypted on-chain. Along the way, you'll master the patterns that power every confidential DeFi protocol:

- **Encrypted ERC20 balances** with `mapping(address => euint64)` — the same per-user pattern from Week 2, now in a token context
- **Trivial encryption** with `FHE.asEuint64()` — converting plaintext values into encrypted handles for mixed-mode operations
- **The silent-zero pattern** for transfers — never revert on insufficient balance, silently transfer zero instead
- **Encrypted `approve` / `transferFrom`** — multi-party allowance management with encrypted values
- **Double protection** — layered allowance check + balance check, both operating entirely on ciphertext
- **The permission dance** — why every balance-mutating operation must call both `FHE.allowThis` and `FHE.allow`

## What You'll Build

**`ConfidentialERC20.sol`** — A fully functional ERC20-compatible token with encrypted balances, encrypted transfers, encrypted approvals, and encrypted `transferFrom`. From the outside it looks like a normal token — but every number is hidden.

This contract combines everything you've learned into a production-relevant pattern:

```
Trivial encryption → Encrypted transfers → Silent-zero guard → Encrypted approvals → Double protection
```

## Weekly Milestones

Use this checklist to track your progress:

- [ ] **Lesson 1** — Understand the ConfidentialERC20 contract structure, trivial encryption with `FHE.asEuint64()`, the `mint` function, the silent-zero transfer pattern, and the `_transfer` internal function with its permission dance
- [ ] **Lesson 2** — Master encrypted approvals with multi-party permissions, `transferFrom` with double protection (allowance + balance), nested encrypted mappings, gas considerations, and run the full 8-test suite
- [ ] **Homework** — Extend `ConfidentialERC20.sol` with new features and pass all provided tests

## Lessons

### [Lesson 1: Building a Confidential ERC20 Token](/week-3/lesson-1-token) <span style="opacity: 0.6">~75 min</span>

Build a confidential token from the ground up. Learn why encrypted tokens matter, how `FHE.asEuint64()` bridges plaintext and ciphertext, how the silent-zero pattern prevents information leakage on transfers, and why the "permission dance" (`allowThis` + `allow`) must follow every balance update.

### [Lesson 2: Advanced Patterns — Approvals, Double Protection & Testing](/week-3/lesson-2-advanced) <span style="opacity: 0.6">~60 min</span>

Dive into encrypted `approve` with dual-party permissions, `transferFrom` with double protection (two layered silent-zero checks), nested encrypted mappings for allowances, gas considerations for FHE operations, and a full walkthrough of the 8-test suite.

### [Homework: Extended ConfidentialERC20](/week-3/homework) <span style="opacity: 0.6">~4-5 hours</span>

Extend the ConfidentialERC20 with additional features — encrypted total supply tracking, burn functionality, and more — then pass a comprehensive test suite.

---

## Key Concepts This Week

| Concept | Description |
|---------|-------------|
| `FHE.asEuint64(value)` | Trivial encryption — convert a plaintext value into an encrypted handle for mixed-mode arithmetic |
| Silent-zero transfer | If balance < amount, silently transfer 0 instead of reverting — no information leak |
| Double protection | Two layered encrypted checks (allowance + balance) in `transferFrom` — both silent-zero |
| `mapping(a => mapping(b => euint64))` | Nested encrypted mappings for per-owner-per-spender allowances |
| Permission dance | After every balance mutation: `FHE.allowThis()` (contract reuse) + `FHE.allow()` (user decrypt) |
| Encrypted approve | Allowance grant readable by both owner and spender — two `FHE.allow` calls |
| Gas cost: ~300-500k | FHE operations cost significantly more gas than plaintext (~50k) — plan accordingly |

---

**Ready?** Start with [Lesson 1: Building a Confidential ERC20 Token](/week-3/lesson-1-token).
