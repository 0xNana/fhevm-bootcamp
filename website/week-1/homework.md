# Homework: EncryptedPoll

**Estimated time:** 3-4 hours | **Difficulty:** Beginner+ | **Points:** 100 (+ up to 20 bonus)

---

## Problem Statement

An organization wants to run a **private poll** among its members. The poll has multiple questions (e.g., "Should we fund Project A?", "Should we hire a new developer?"). Members vote on each question by submitting an encrypted value — nobody can see the current tally or how anyone else voted. Only the **poll owner** can reveal the final results after the poll closes.

Your task is to build `EncryptedPoll.sol` — a smart contract that manages encrypted vote tallies using the FHE patterns you learned in Lesson 3 (FHECounter).

### Why This Matters

On-chain governance votes today are fully transparent. Anyone can see who voted and how, which creates social pressure and enables vote-buying. With FHE, votes remain **encrypted throughout the entire process** — providing genuine ballot privacy on a public blockchain.

---

## Requirements

### Contract: `EncryptedPoll`

Your contract must implement the following interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedPoll is ZamaEthereumConfig {
    // TODO: Implement
}
```

### State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `owner` | `address` | The poll creator (set in constructor, only they can reveal results) |
| `questionCount` | `uint8` | Number of questions in the poll (set in constructor) |
| `_voteCounts` | `mapping(uint8 => euint32)` | Encrypted vote tally per question |
| `_hasVoted` | `mapping(address => mapping(uint8 => bool))` | Tracks whether an address has voted on a given question |

### Constructor

```solidity
constructor(uint8 _questionCount)
```

- Sets `owner` to `msg.sender`
- Sets `questionCount` to `_questionCount`

### Functions

#### `vote`

```solidity
function vote(uint8 questionId, externalEuint32 encVote, bytes calldata inputProof) external
```

- Reverts if `questionId >= questionCount` (plaintext check — safe to revert)
- Reverts if `msg.sender` has already voted on this question
- Verifies the encrypted input with `FHE.fromExternal`
- Adds the encrypted vote to the question's tally using `FHE.add`
- Grants ACL permissions:
  - `FHE.allowThis()` — so the contract can accumulate future votes
  - `FHE.allow(owner)` — so the owner can eventually decrypt results
- Marks the sender as having voted on this question

#### `getVoteCount`

```solidity
function getVoteCount(uint8 questionId) external view returns (euint32)
```

- Returns the encrypted vote count for the given question
- The caller receives a `bytes32` handle — they can only decrypt it if they have ACL permission (i.e., the owner)

### ACL Pattern

Every time `_voteCounts[questionId]` is updated, you must call:

```solidity
FHE.allowThis(_voteCounts[questionId]);   // Contract can use the value in future ops
FHE.allow(_voteCounts[questionId], owner); // Owner can decrypt the final result
```

This is the same pattern from `FHECounter.increment` — every FHE operation produces a **new handle**, so permissions must be re-granted.

### One Vote Per Address

Each address can vote on each question **exactly once**. Use a nested mapping to track this:

```solidity
mapping(address => mapping(uint8 => bool)) private _hasVoted;
```

This is a **plaintext** check, so it is safe to `require(!_hasVoted[msg.sender][questionId])` — no encrypted information is leaked by reverting here.

---

## Starter Code

A starter template is available at:

```
starter/week-1/src/EncryptedPoll.sol
```

The starter file contains the contract skeleton with imports, state variables, and function signatures. You need to fill in the function bodies.

## Test Suite

A pre-written test suite is available at:

```
starter/week-1/test/EncryptedPoll.t.sol
```

Run the tests with:

```bash
forge test --match-contract EncryptedPollTest -vvv
```

::: tip Goal
All tests in the provided test suite must pass. Use `forge test -vvv` to see detailed output when debugging failures.
:::

---

## Grading Rubric

| Category | Points | Criteria |
|----------|--------|----------|
| **Correctness** | 40 | All provided tests pass. Contract compiles without errors. |
| **FHE Patterns** | 25 | Proper use of `FHE.fromExternal` for input verification, `FHE.add` for encrypted accumulation, `FHE.allowThis` and `FHE.allow` on every state update. |
| **Code Quality** | 15 | NatSpec documentation on contract and functions, clean structure, no compiler warnings, meaningful variable names. |
| **Edge Cases** | 20 | One-vote-per-address enforcement works correctly. Invalid `questionId` is rejected. Double-vote attempts revert with clear error messages. |
| **Total** | **100** | |

---

## Bonus Challenges

Earn up to **20 extra points** by implementing one or both of these extensions:

### Bonus A: `revealResults()` (10 pts)

Add a `revealResults` function that can only be called by the owner after a deadline:

- Add a `uint256 public deadline` parameter to the constructor (a block timestamp)
- `revealResults()` requires `block.timestamp >= deadline` and `msg.sender == owner`
- The function should emit an event with the question IDs (the actual decryption happens off-chain — the owner already has ACL permission)
- Before the deadline, nobody — not even the owner — should be able to see intermediate results (don't grant `allow` to anyone until `revealResults` is called)

::: warning Think About It
If you defer `FHE.allow(owner)` until `revealResults()`, how do you handle the ACL for intermediate vote counts? The contract still needs `allowThis` to accumulate votes, but the owner shouldn't be able to decrypt until the deadline.
:::

### Bonus B: Weighted Voting (10 pts)

Support weighted voting where different voters have different vote multipliers:

- Add a `setWeight(address voter, euint32 weight)` function (owner only)
- In `vote`, multiply the encrypted input by the voter's encrypted weight before adding to the tally
- Use `FHE.mul` for the encrypted multiplication
- Default weight for unregistered voters should be treated as 1 (use `FHE.select` with a zero check)

---

## Hints

::: details Hint 1: The Pattern Is FHECounter, Repeated
Look at `FHECounter.increment`. Your `vote` function follows the **exact same pattern** — verify input, add to state, re-authorize. The only additions are the `questionId` index and the one-vote check.
:::

::: details Hint 2: Plaintext Guards Are OK
You can safely use `require` for checks on **plaintext** values. `questionId` is plaintext (it's a function parameter, not encrypted). `_hasVoted` is a plaintext boolean. Only revert based on encrypted values is forbidden.
:::

::: details Hint 3: Uninitialized euint32 Is Zero
An uninitialized `euint32` in a mapping is `bytes32(0)`. The FHE library handles this gracefully — `FHE.add(uninitialized, x)` treats the uninitialized value as zero. So the first vote on a question "just works" without special initialization.
:::

::: details Hint 4: Test Your ACL
If your tests fail with a "not allowed" error, you probably forgot `FHE.allowThis` or `FHE.allow`. Remember: every `FHE.add` produces a **new** handle. The old permissions don't carry over.
:::

---

## Concepts You'll Practice

This homework reinforces the core Week 1 patterns:

| Pattern | How You'll Use It |
|---------|------------------|
| `FHE.fromExternal()` | Verify each voter's encrypted input |
| `FHE.add()` | Accumulate encrypted votes per question |
| `FHE.allowThis()` | Let the contract reuse vote tallies across transactions |
| `FHE.allow()` | Let the owner eventually decrypt results |
| Plaintext guards | `require` on `questionId` bounds and double-vote checks |
| `ZamaEthereumConfig` | Contract inherits the coprocessor config |

---

## Submission Checklist

Before submitting, verify:

- [ ] `forge build` compiles without warnings
- [ ] `forge test --match-contract EncryptedPollTest -vvv` — all tests pass
- [ ] Every `vote` call grants `allowThis` and `allow(owner)` on the updated tally
- [ ] Double voting on the same question reverts
- [ ] Invalid `questionId` reverts
- [ ] NatSpec comments on the contract, constructor, and each function

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-1/">← Week 1 Overview</a>
  <a href="/week-1/instructor">Instructor Notes →</a>
</div>
