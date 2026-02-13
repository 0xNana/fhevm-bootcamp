# Week 2: Encrypted State & Access Control

**Time estimate:** ~8-10 hours (including homework) | **Difficulty:** Intermediate | **Prerequisites:** [Week 1](/week-1/) completed

---

## What You'll Learn

This week you move from a single shared counter to **per-user private state**. You'll master the FHEVM access control system and learn encrypted comparison and conditional patterns that every confidential contract relies on:

- Per-user encrypted state with `mapping(address => euint64)`
- Granular access control: `FHE.allow`, `FHE.allowThis`, `FHE.allowTransient`
- Encrypted comparisons with `FHE.le` (and the full comparison operator family)
- Encrypted conditionals with `FHE.select` — the encrypted ternary
- The `ebool` type — encrypted booleans returned by comparisons
- The **silent-fail pattern** — why FHE contracts don't revert on insufficient funds

## What You'll Build

**`EncryptedVault.sol`** — A vault contract where users deposit and withdraw encrypted amounts. Each user's balance is private (only they can decrypt it), the contract owner can see the aggregate total, and withdrawals silently cap at the available balance to avoid leaking information.

This contract teaches you the patterns that power every confidential DeFi application:

```
Per-user state → Granular ACL → Encrypted comparison → Silent conditional → No info leak
```

## Weekly Milestones

Use this checklist to track your progress:

- [ ] **Lesson 1** — Understand per-user encrypted state, the deposit function, and the full ACL permission model (`allowThis`, `allow`, `allowTransient`)
- [ ] **Lesson 2** — Master `FHE.select`, encrypted comparisons, the silent-fail pattern, and the "encrypted guard" pattern; run all EncryptedVault tests
- [ ] **Homework** — Build `EncryptedTipJar.sol` from the starter template and pass all provided tests

## Lessons

### [Lesson 1: Encrypted Access Control — The Vault](/week-2/lesson-1-access-control) <span style="opacity: 0.6">~60 min</span>

Build a vault with per-user encrypted balances. Learn why every FHE operation creates a new handle, why you must re-authorize after every operation, and how the three ACL functions (`allowThis`, `allow`, `allowTransient`) control who can compute on and decrypt encrypted values.

### [Lesson 2: FHE Patterns — Comparisons, Conditionals & Silent Failure](/week-2/lesson-2-patterns) <span style="opacity: 0.6">~60 min</span>

Deep dive into `FHE.select()`, the full comparison operations table, the withdraw function, and why FHE contracts "silent fail" instead of reverting. Learn the "encrypted guard" pattern (compare → select → operate) and walk through the EncryptedVault test suite.

### [Homework: EncryptedTipJar](/week-2/homework) <span style="opacity: 0.6">~4-5 hours</span>

Build an encrypted tip jar contract from scratch. Users send encrypted tips, the contract tracks per-user totals, and the recipient can claim accumulated tips — all without revealing individual amounts.

---

## Key Concepts This Week

| Concept | Description |
|---------|-------------|
| `mapping(address => euint64)` | Per-user encrypted state — each address maps to its own encrypted balance |
| `FHE.allowThis(value)` | Grant the contract permission to reuse an encrypted value in future transactions |
| `FHE.allow(value, addr)` | Grant a specific address permission to decrypt a value off-chain |
| `FHE.allowTransient(value, addr)` | Temporary permission — valid only within the current transaction |
| `FHE.le(a, b)` | Encrypted less-than-or-equal comparison, returns `ebool` |
| `FHE.select(cond, a, b)` | Encrypted ternary — choose `a` or `b` based on encrypted boolean, no branching |
| `ebool` | Encrypted boolean — result of comparison operations, usable only in `FHE.select()` |
| Silent failure | Transactions succeed regardless of balance — no information leak via reverts |
| New-handle rule | Every FHE operation produces a new handle; permissions don't carry over |

---

**Ready?** Start with [Lesson 1: Encrypted Access Control](/week-2/lesson-1-access-control).
