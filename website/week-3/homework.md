# Homework: ConfidentialERC20 Extended

**Estimated time:** 4-5 hours | **Difficulty:** Intermediate-Advanced | **Points:** 100 (+ up to 20 bonus)

---

## Problem Statement

The `ConfidentialERC20` you built in Lessons 1 and 2 is functional — it supports encrypted minting, transfers, approvals, and `transferFrom` with double protection. But a production token needs more. Real ERC20 tokens support burning, supply tracking, and transfer limits. Your job is to **extend** the base `ConfidentialERC20` with three new features:

1. **Burn** — Destroy tokens from the sender's encrypted balance
2. **Encrypted total supply** — Track the running supply as an encrypted value (unlike the plaintext `totalSupply` in the base contract)
3. **Transfer cap** — Enforce a maximum transfer amount per transaction

### Why This Matters

In traditional ERC20 tokens, burning and supply tracking are trivial — just subtract and update a counter. With encrypted balances, every one of these operations must preserve privacy. Burning can't reveal whether the sender had enough tokens. The transfer cap can't leak the transfer amount by reverting. You'll use the **silent-zero pattern** twice over — once for the burn underflow check and once for the cap enforcement — layering encrypted guards exactly like `transferFrom`'s double protection.

---

## Requirements

### Contract: `ConfidentialERC20Extended`

Your contract must extend the base `ConfidentialERC20` with these additions:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract ConfidentialERC20Extended is ZamaEthereumConfig {
    // All existing ConfidentialERC20 state + logic, PLUS:
    // - burn()
    // - _encryptedTotalSupply tracking
    // - transferCap enforcement in _transfer
}
```

### New State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_encryptedTotalSupply` | `euint64` | Encrypted running total of all minted tokens minus burned tokens |
| `transferCap` | `uint64` | Maximum allowed transfer amount per transaction (plaintext, set by owner) |

### New & Modified Functions

#### `burn`

```solidity
function burn(externalEuint64 encAmount, bytes calldata inputProof) external
```

- Verifies the encrypted input with `FHE.fromExternal`
- **Silent-zero pattern**: if the burn amount exceeds the sender's balance, burn zero instead of reverting
  1. Compare: `FHE.le(amount, _balances[msg.sender])` → `ebool`
  2. Select: `FHE.select(canBurn, amount, FHE.asEuint64(0))` → `euint64`
  3. Subtract: `FHE.sub(_balances[msg.sender], actualAmount)`
- Updates `_encryptedTotalSupply` by subtracting the actual burn amount
- Grants ACL: `FHE.allowThis()` + `FHE.allow(msg.sender)` on the updated balance
- Grants ACL: `FHE.allowThis()` + `FHE.allow(owner)` on the updated `_encryptedTotalSupply`
- Emits a `Burn(address indexed from)` event

::: warning Silent-Zero Is Critical
Just like `_transfer`, the `burn` function must **never revert** based on whether the amount exceeds the balance. If the sender tries to burn more than they have, silently burn zero. This prevents observers from binary-searching the sender's balance by watching which burn transactions revert.
:::

#### `encryptedTotalSupply`

```solidity
function encryptedTotalSupply() external view returns (euint64)
```

- Returns the encrypted total supply
- Only the **owner** has ACL permission to decrypt this value
- Updated automatically on `mint` (increase) and `burn` (decrease)

#### Modify `mint` — Update Encrypted Total Supply

The existing `mint` function must additionally update `_encryptedTotalSupply`:

```solidity
// After the existing mint logic:
_encryptedTotalSupply = FHE.add(_encryptedTotalSupply, encAmount);
FHE.allowThis(_encryptedTotalSupply);
FHE.allow(_encryptedTotalSupply, owner);
```

#### `setTransferCap`

```solidity
function setTransferCap(uint64 cap) external onlyOwner
```

- Sets the maximum transfer amount per transaction
- A value of `0` means **no cap** (transfers are uncapped by default)
- Only the owner can set this

#### Modify `_transfer` — Enforce Transfer Cap

The internal `_transfer` function must enforce the transfer cap **before** the existing balance check. This means `_transfer` now has **double protection** — just like `transferFrom` has double protection with the allowance check + balance check:

1. **Cap check** (new): if `transferCap > 0` and `amount > cap`, set amount to zero
2. **Balance check** (existing): if amount > balance, set amount to zero

```solidity
function _transfer(address from, address to, euint64 amount) internal {
    // --- NEW: Cap enforcement (silent-zero) ---
    if (transferCap > 0) {
        euint64 encCap = FHE.asEuint64(transferCap);
        ebool withinCap = FHE.le(amount, encCap);
        amount = FHE.select(withinCap, amount, FHE.asEuint64(0));
    }

    // --- EXISTING: Balance check (silent-zero) ---
    ebool hasFunds = FHE.le(amount, _balances[from]);
    euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));

    // ... rest of transfer logic unchanged
}
```

::: tip Double Protection
The modified `_transfer` now mirrors the pattern from `transferFrom`. In `transferFrom`, the two layers are **allowance check** + **balance check**. In the new `_transfer`, the two layers are **cap check** + **balance check**. Both use the same `FHE.le` → `FHE.select` → silent-zero pipeline.
:::

### ACL Summary

| Value Updated | `allowThis` | `allow` to |
|--------------|-------------|-----------|
| `_balances[msg.sender]` (burn) | Yes | `msg.sender` |
| `_encryptedTotalSupply` (mint/burn) | Yes | `owner` |
| All existing ACL from base contract | Unchanged | Unchanged |

---

## Starter Code

A starter template with the contract skeleton is available at:

```
starter/week-3/
```

The starter contains the full base `ConfidentialERC20` with imports, state variables, events, and the new function signatures. You need to implement the new function bodies and modify the existing ones.

## Test Suite

A pre-written test suite is provided. Run it with:

```bash
forge test --match-contract ConfidentialERC20ExtendedTest -vvv
```

The test suite covers:

| Test | What It Verifies |
|------|-----------------|
| All base ERC20 tests still pass | Existing functionality is preserved |
| Burn reduces sender balance | Basic burn with sufficient balance |
| Burn with insufficient balance burns zero | Silent-zero pattern for burn |
| Burn updates encrypted total supply | Supply tracking on burn |
| Mint updates encrypted total supply | Supply tracking on mint |
| Owner can view encrypted total supply | ACL on `_encryptedTotalSupply` |
| Transfer within cap succeeds | Normal transfer with cap set |
| Transfer exceeding cap sends zero | Silent-zero on cap violation |
| Transfer with no cap set (default) works | Uncapped transfers work normally |
| Double protection: cap + balance | Both checks layer correctly |

::: tip Goal
All tests in the provided test suite must pass. Use `forge test -vvv` to see detailed output when debugging failures.
:::

---

## Grading Rubric

| Category | Points | Criteria |
|----------|--------|----------|
| **Correctness** | 40 | All provided tests pass. Contract compiles without errors. Existing ERC20 functionality is preserved. |
| **FHE Patterns** | 25 | Silent-zero for burn (compare → select → subtract). Silent-zero for cap enforcement. Proper ACL on `_encryptedTotalSupply` (only owner can decrypt). |
| **Code Quality** | 15 | NatSpec documentation on all new functions, clean structure, no compiler warnings, consistent naming with the base contract. |
| **Double Protection** | 20 | The modified `_transfer` enforces **both** the cap check AND the balance check as two layered silent-zero guards. Neither check leaks information via revert. |
| **Total** | **100** | |

---

## Bonus Challenges

Earn up to **20 extra points** by implementing one or both of these extensions:

### Bonus A: Encrypted `totalBurned` Tracker (10 pts)

Track the cumulative amount of tokens burned across all users:

- Add `euint64 private _totalBurned` state variable
- On each `burn`, add the actual burn amount (post silent-zero) to `_totalBurned`
- Add `totalBurned() external view returns (euint64)` getter
- Grant ACL: `allowThis` + `allow(owner)` so only the owner can decrypt the burn total
- Verify that `_encryptedTotalSupply + _totalBurned` always equals the cumulative minted amount

::: tip Invariant Thinking
In a traditional ERC20: `totalSupply + totalBurned == totalMinted`. With encrypted types, this invariant still holds — but it can only be verified by the owner who has decrypt permission on both values.
:::

### Bonus B: `increaseAllowance` / `decreaseAllowance` (10 pts)

Add convenience functions for adjusting allowances without replacing them:

```solidity
function increaseAllowance(
    address spender,
    externalEuint64 encAddedValue,
    bytes calldata inputProof
) external
```

- Verifies input with `FHE.fromExternal`
- Adds the encrypted value to the existing allowance: `FHE.add(_allowances[msg.sender][spender], addedValue)`
- Grants ACL: `allowThis` + `allow(msg.sender)` + `allow(spender)` on the updated allowance

```solidity
function decreaseAllowance(
    address spender,
    externalEuint64 encSubValue,
    bytes calldata inputProof
) external
```

- Verifies input with `FHE.fromExternal`
- Uses silent-zero: if the decrease exceeds the current allowance, set the allowance to zero (don't revert)
- `FHE.le(subValue, _allowances[...])` → `FHE.select` → `FHE.sub`
- Grants the same triple ACL as `increaseAllowance`

::: warning Why Silent-Zero for Decrease?
If `decreaseAllowance` reverted on underflow, an attacker could binary-search the allowance amount by observing which transactions revert. The silent-zero pattern sets the allowance to zero instead, leaking no information.
:::

---

## Hints

::: details Hint 1: Burn Is Withdraw in Disguise
Look at `EncryptedTipJar.withdraw` from Week 2. Your `burn` function follows the **exact same pattern** — compare → select → subtract. The only addition is updating `_encryptedTotalSupply` after the burn. If your Week 2 withdrawal works, your burn will too.
:::

::: details Hint 2: Cap Check Goes Before Balance Check
The transfer cap must be checked **before** the balance check in `_transfer`. If you check the cap after the balance check, a transfer that exceeds the cap but is within the balance would still go through. The order matters: cap → balance, just like `transferFrom` does allowance → balance.
:::

::: details Hint 3: Trivial Encryption for the Cap
The `transferCap` is stored as a plaintext `uint64` (because it's a public setting). To compare it against the encrypted transfer amount, you need to trivially encrypt it first with `FHE.asEuint64(transferCap)`. This is the same pattern as `mint` converting a plaintext amount to an encrypted handle.
:::

::: details Hint 4: Uninitialized `_encryptedTotalSupply`
Before the first `mint`, `_encryptedTotalSupply` is uninitialized (`bytes32(0)`). The FHE library handles this gracefully — `FHE.add(uninitialized, x)` treats it as zero. So the first mint "just works" without special initialization, exactly like the vote counters in Week 1.
:::

---

## Concepts You'll Practice

This homework reinforces and extends the Week 3 patterns:

| Pattern | How You'll Use It |
|---------|------------------|
| `FHE.asEuint64()` | Trivially encrypt the transfer cap for comparison |
| Silent-zero (burn) | If burn amount > balance, silently burn zero |
| Silent-zero (cap) | If transfer amount > cap, silently transfer zero |
| Double protection | Two layered silent-zero checks in `_transfer` (cap + balance) |
| `FHE.add()` / `FHE.sub()` | Update encrypted total supply on mint and burn |
| `FHE.allowThis()` + `FHE.allow()` | Permission dance on every mutated encrypted value |
| ACL for sensitive state | Only the owner can decrypt `_encryptedTotalSupply` |
| `FHE.le()` → `FHE.select()` | The compare-and-branch pattern, used three times (burn, cap, balance) |

---

## Submission Checklist

Before submitting, verify:

- [ ] `forge build` compiles without warnings
- [ ] `forge test --match-contract ConfidentialERC20ExtendedTest -vvv` — all tests pass
- [ ] `burn` uses the silent-zero pattern (never reverts on insufficient balance)
- [ ] `_encryptedTotalSupply` updates on both `mint` and `burn`
- [ ] Only the owner can decrypt `_encryptedTotalSupply` (ACL check)
- [ ] `setTransferCap` is owner-only
- [ ] `_transfer` enforces both cap check AND balance check (double protection)
- [ ] Neither the cap check nor the balance check reverts on encrypted conditions
- [ ] All existing ERC20 tests still pass (you haven't broken anything)
- [ ] NatSpec comments on all new and modified functions

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-3/">← Week 3 Overview</a>
  <a href="/week-3/instructor">Instructor Notes →</a>
</div>
