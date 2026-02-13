# Homework: EncryptedTipJar

**Estimated time:** 3-4 hours | **Difficulty:** Intermediate | **Points:** 100 (+ up to 20 bonus)

---

## Problem Statement

A content platform wants to let users **tip creators privately**. Tips should be fully encrypted — nobody can see how much any individual tipped, and only the creator can see their aggregate balance. The creator can withdraw accumulated tips, but withdrawals are capped at the available balance using the **silent-fail pattern** to prevent information leakage.

Your task is to build `EncryptedTipJar.sol` — a contract that manages encrypted tips using the per-user state, comparison, and conditional patterns you learned in Week 2 (EncryptedVault).

### Why This Matters

Transparent tipping creates perverse incentives: people tip more to be seen, or don't tip at all to avoid judgment. Large tips can signal insider knowledge or create social pressure. With FHE, tips are **genuinely private** — the creator knows their total, each tipper knows their own contribution, but nobody else sees anything.

---

## Requirements

### Contract: `EncryptedTipJar`

Your contract must implement the following interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedTipJar is ZamaEthereumConfig {
    // TODO: Implement
}
```

### State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `creator` | `address` | The tip recipient (set in constructor) |
| `_creatorBalance` | `euint64` | Encrypted aggregate of all tips received |
| `_tipperTotals` | `mapping(address => euint64)` | Per-tipper encrypted running total of tips given |

### Constructor

```solidity
constructor(address _creator)
```

- Sets `creator` to `_creator`

### Functions

#### `tip`

```solidity
function tip(externalEuint64 encAmount, bytes calldata inputProof) external
```

- Verifies the encrypted input with `FHE.fromExternal`
- Adds the encrypted amount to the caller's tip total (`_tipperTotals[msg.sender]`)
- Adds the encrypted amount to the creator's aggregate balance (`_creatorBalance`)
- Grants ACL permissions:
  - `FHE.allowThis()` + `FHE.allow(msg.sender)` on the tipper's total
  - `FHE.allowThis()` + `FHE.allow(creator)` on the creator's balance
- Emits a `Tip(address indexed tipper)` event

#### `getMyTotalTips`

```solidity
function getMyTotalTips() external view returns (euint64)
```

- Returns the caller's encrypted total tips given
- Only the caller has ACL permission to decrypt this value

#### `getCreatorBalance`

```solidity
function getCreatorBalance() external view returns (euint64)
```

- Returns the creator's encrypted aggregate balance
- Only the creator has ACL permission to decrypt this value

#### `withdraw`

```solidity
function withdraw(externalEuint64 encAmount, bytes calldata inputProof) external
```

- Reverts if `msg.sender != creator` (plaintext check — safe to revert)
- Verifies the encrypted input with `FHE.fromExternal`
- **Silent-fail pattern**: caps the withdrawal at the creator's balance
  1. Compare: `FHE.le(amount, _creatorBalance)` → `ebool`
  2. Select: `FHE.select(canWithdraw, amount, _creatorBalance)` → `euint64`
  3. Subtract: `FHE.sub(_creatorBalance, actualAmount)`
- Grants ACL: `FHE.allowThis()` + `FHE.allow(creator)` on the updated balance
- Emits a `Withdraw(uint64 amount)` event (the amount here is opaque — just emit for indexing)

::: warning The Silent-Fail Pattern
The `withdraw` function must **never revert** based on whether the requested amount exceeds the balance. If the creator requests more than they have, the contract silently withdraws their full balance. This prevents observers from binary-searching the creator's balance by watching which transactions revert.
:::

### ACL Summary

Every time an encrypted value is updated, you must re-grant permissions because FHE operations produce **new handles**:

| Value Updated | `allowThis` | `allow` to |
|--------------|-------------|-----------|
| `_tipperTotals[msg.sender]` | Yes | `msg.sender` (the tipper) |
| `_creatorBalance` | Yes | `creator` |

---

## Starter Code

A starter template with the contract skeleton is available at:

```
starter/week-2/
```

The starter contains imports, state variables, events, and function signatures. You need to implement the function bodies.

## Test Suite

A pre-written test suite is provided. Run it with:

```bash
forge test --match-contract EncryptedTipJarTest -vvv
```

The test suite covers:

| Test | What It Verifies |
|------|-----------------|
| Single tip updates creator balance | Basic `tip` functionality |
| Multiple tips accumulate | `FHE.add` with repeated calls |
| Tipper can see their own total | Per-tipper ACL and state |
| Different tippers have separate totals | State isolation via mapping |
| Creator can withdraw | Normal withdrawal flow |
| Over-withdrawal caps at balance | Silent-fail pattern |
| Non-creator cannot withdraw | Plaintext access control |

::: tip Goal
All tests in the provided test suite must pass. The silent-fail test is the most important — it verifies that over-withdrawals succeed (not revert) and cap at the available balance.
:::

---

## Grading Rubric

| Category | Points | Criteria |
|----------|--------|----------|
| **Correctness** | 40 | All provided tests pass. Contract compiles without errors. |
| **FHE Patterns** | 25 | Proper use of `FHE.le` / `FHE.select` for the withdrawal cap. Correct `FHE.fromExternal` on all inputs. Proper `FHE.allowThis` and `FHE.allow` on every state update. |
| **Code Quality** | 15 | NatSpec documentation on contract and functions, clean structure, no compiler warnings, meaningful event emissions. |
| **Silent-Fail Pattern** | 20 | The `withdraw` function never reverts on insufficient balance. Uses compare → select → subtract correctly. Over-withdrawal results in a zero balance, not a revert. |
| **Total** | **100** | |

---

## Bonus Challenges

Earn up to **20 extra points** by implementing one or both of these extensions:

### Bonus A: Minimum Tip Threshold (10 pts)

Add a minimum tip amount that is enforced via encrypted comparison:

- Add a `euint64 private _minTip` state variable, set via `setMinTip(externalEuint64, bytes calldata)` by the creator
- In `tip`, compare the incoming amount against `_minTip` using `FHE.le`
- If the tip is below the minimum, use `FHE.select` to set the effective tip to zero (silent-fail — don't revert!)
- The tipper's total and creator balance should only increase if the tip meets the threshold

::: details Implementation Hint
```solidity
ebool meetsMin = FHE.ge(amount, _minTip);
euint64 effectiveAmount = FHE.select(meetsMin, amount, FHE.asEuint64(0));
// Now use effectiveAmount instead of amount for the rest of the function
```
:::

### Bonus B: Tip Count Per User (10 pts)

Track how many times each user has tipped (not just the total amount):

- Add `mapping(address => euint32) private _tipCounts`
- On each `tip` call, increment the tipper's count: `FHE.add(_tipCounts[msg.sender], FHE.asEuint32(1))`
- Add a `getMyTipCount() external view returns (euint32)` getter
- Grant ACL: `allowThis` + `allow(msg.sender)` on the count

::: tip Why Encrypt the Count?
Even the number of tips reveals information — a user who tipped 50 times is clearly a superfan. Encrypting the count keeps this private.
:::

---

## Hints

::: details Hint 1: EncryptedVault Is Your Blueprint
The `withdraw` function in `EncryptedTipJar` follows the **exact same pattern** as `EncryptedVault.withdraw`. Review it: compare with `FHE.le`, select with `FHE.select`, subtract with `FHE.sub`. The only difference is the variable names.
:::

::: details Hint 2: Two Things Update on Every Tip
Each call to `tip` modifies **two** encrypted values: the tipper's running total and the creator's aggregate balance. Both need `FHE.add`, and both need fresh `allowThis` + `allow` calls. Don't forget either one.
:::

::: details Hint 3: Uninitialized euint64 Is Zero
Just like Week 1, an uninitialized `euint64` in a mapping is `bytes32(0)`. The FHE library treats it as zero in arithmetic. The first tip to a new tipper "just works" — no special initialization needed.
:::

::: details Hint 4: Separate Plaintext and Encrypted Guards
Use `require(msg.sender == creator)` for the creator-only check (plaintext — safe). Use `FHE.le` + `FHE.select` for the balance cap (encrypted — must not revert). Mixing these up is a common mistake.
:::

---

## Concepts You'll Practice

This homework reinforces the core Week 2 patterns:

| Pattern | How You'll Use It |
|---------|------------------|
| `mapping(address => euint64)` | Per-tipper encrypted state tracking |
| `FHE.fromExternal()` | Verify encrypted tip amounts and withdrawal amounts |
| `FHE.add()` | Accumulate tips for both tipper totals and creator balance |
| `FHE.le()` | Compare withdrawal amount against balance |
| `FHE.select()` | Cap withdrawal at available balance (silent-fail) |
| `FHE.sub()` | Deduct withdrawal from creator balance |
| `FHE.allowThis()` | Let the contract reuse encrypted values across transactions |
| `FHE.allow()` | Grant tippers and creator permission to decrypt their own values |
| Silent-fail pattern | Withdraw never reverts on insufficient balance |

---

## Submission Checklist

Before submitting, verify:

- [ ] `forge build` compiles without warnings
- [ ] `forge test --match-contract EncryptedTipJarTest -vvv` — all tests pass
- [ ] `tip` updates both `_tipperTotals[msg.sender]` and `_creatorBalance`
- [ ] `tip` grants `allowThis` + `allow` on **both** updated values
- [ ] `withdraw` uses the silent-fail pattern (compare → select → subtract)
- [ ] `withdraw` does **not** revert when amount exceeds balance
- [ ] Only the creator can call `withdraw`
- [ ] NatSpec comments on the contract, constructor, and each function

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-2/">← Week 2 Overview</a>
  <a href="/week-2/instructor">Instructor Notes →</a>
</div>
