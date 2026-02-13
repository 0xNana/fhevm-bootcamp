# FHE Operations Cheat Sheet

A comprehensive quick-reference for every FHE operation, type, and pattern used in this bootcamp. Bookmark this page — you'll come back to it constantly.

---

## Encrypted Types

Every encrypted type is stored on-chain as a `bytes32` handle. The actual ciphertext lives in the coprocessor.

| Encrypted Type | Solidity Type | External Input Type | Bit Width | Plaintext Equivalent | Introduced |
|---------------|---------------|--------------------:|----------:|---------------------|------------|
| Boolean | `ebool` | `externalEbool` | 1 | `bool` | [Week 2](/week-2/lesson-2-patterns) |
| Unsigned 8-bit | `euint8` | `externalEuint8` | 8 | `uint8` | [Week 1](/week-1/lesson-1-fhe-theory) |
| Unsigned 16-bit | `euint16` | `externalEuint16` | 16 | `uint16` | [Week 1](/week-1/lesson-1-fhe-theory) |
| Unsigned 32-bit | `euint32` | `externalEuint32` | 32 | `uint32` | [Week 1](/week-1/lesson-3-hello-fhe) |
| Unsigned 64-bit | `euint64` | `externalEuint64` | 64 | `uint64` | [Week 2](/week-2/lesson-1-access-control) |
| Unsigned 128-bit | `euint128` | `externalEuint128` | 128 | `uint128` | [Week 1](/week-1/lesson-1-fhe-theory) |
| Unsigned 256-bit | `euint256` | `externalEuint256` | 256 | `uint256` | [Week 1](/week-1/lesson-1-fhe-theory) |
| Address | `eaddress` | `externalEaddress` | 160 | `address` | [Week 4](/week-4/lesson-1-auction) |

### Import Paths

```solidity
// Internal encrypted types (for state variables and computations)
import {ebool, euint8, euint16, euint32, euint64, euint128, euint256, eaddress}
    from "encrypted-types/EncryptedTypes.sol";

// External encrypted types (for function parameters — user inputs)
import {externalEbool, externalEuint8, externalEuint16, externalEuint32,
        externalEuint64, externalEuint128, externalEuint256, externalEaddress}
    from "encrypted-types/EncryptedTypes.sol";

// FHE library (all operations)
import {FHE} from "@fhevm/solidity/lib/FHE.sol";

// Config (inheritable — sets coprocessor/ACL/KMS addresses)
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
```

---

## Arithmetic Operations

All arithmetic operations take two encrypted operands of the same type and return the same type.

### `FHE.add(a, b)` — Encrypted Addition

```solidity
function add(euint64 a, euint64 b) returns (euint64)
```

Adds two encrypted values. Returns an encrypted result.

| Property | Value |
|----------|-------|
| **Operands** | Same encrypted type (e.g., both `euint64`) |
| **Returns** | Same encrypted type |
| **Gas estimate** | ~50–80k |
| **Overflow** | Wraps silently (no revert) |

```solidity
// Example: accumulate a deposit into an encrypted balance
_balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
```

### `FHE.sub(a, b)` — Encrypted Subtraction

```solidity
function sub(euint64 a, euint64 b) returns (euint64)
```

Subtracts `b` from `a`. Returns an encrypted result.

| Property | Value |
|----------|-------|
| **Operands** | Same encrypted type |
| **Returns** | Same encrypted type |
| **Gas estimate** | ~50–80k |
| **Underflow** | Wraps silently — always guard with compare+select |

```solidity
// Example: deduct withdrawal from balance (after guard)
_balances[msg.sender] = FHE.sub(_balances[msg.sender], safeAmount);
```

::: warning Underflow Danger
`FHE.sub` does **not** revert on underflow — it wraps. Always use the [encrypted guard pattern](#encrypted-guard-compare-select-operate) before subtraction.
:::

### `FHE.mul(a, b)` — Encrypted Multiplication

```solidity
function mul(euint32 a, euint32 b) returns (euint32)
```

Multiplies two encrypted values. Returns an encrypted result.

| Property | Value |
|----------|-------|
| **Operands** | Same encrypted type |
| **Returns** | Same encrypted type |
| **Gas estimate** | ~80–150k |
| **Overflow** | Wraps silently |

```solidity
// Example: double an encrypted counter
_count = FHE.mul(_count, FHE.asEuint32(2));
```

---

## Comparison Operations

All comparisons take two encrypted operands and return `ebool` — an encrypted boolean. You **cannot** use `ebool` in Solidity `if` statements. Use `FHE.select()` instead.

### `FHE.eq(a, b)` — Equal

```solidity
function eq(euint64 a, euint64 b) returns (ebool)
```

Returns encrypted `true` if `a == b`.

```solidity
ebool isZero = FHE.eq(balance, FHE.asEuint64(0));
```

### `FHE.ne(a, b)` — Not Equal

```solidity
function ne(euint64 a, euint64 b) returns (ebool)
```

Returns encrypted `true` if `a != b`.

```solidity
ebool hasBalance = FHE.ne(balance, FHE.asEuint64(0));
```

### `FHE.gt(a, b)` — Greater Than

```solidity
function gt(euint64 a, euint64 b) returns (ebool)
```

Returns encrypted `true` if `a > b`. Used in ranking and highest-value tracking.

```solidity
// Example: check if new bid exceeds current highest
ebool isHigher = FHE.gt(bid, _highestBid);
```

### `FHE.ge(a, b)` — Greater Than or Equal

```solidity
function ge(euint64 a, euint64 b) returns (ebool)
```

Returns encrypted `true` if `a >= b`.

```solidity
ebool meetsMinimum = FHE.ge(bid, minimumBid);
```

### `FHE.lt(a, b)` — Less Than

```solidity
function lt(euint64 a, euint64 b) returns (ebool)
```

Returns encrypted `true` if `a < b`.

```solidity
ebool isBelow = FHE.lt(amount, threshold);
```

### `FHE.le(a, b)` — Less Than or Equal

```solidity
function le(euint64 a, euint64 b) returns (ebool)
```

Returns encrypted `true` if `a <= b`. The most common comparison — used in every balance sufficiency check.

```solidity
// Example: check if withdrawal amount <= balance
ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);
```

### `FHE.min(a, b)` — Encrypted Minimum

```solidity
function min(euint64 a, euint64 b) returns (euint64)
```

Returns the smaller of `a` and `b` as an encrypted value. **Not** an `ebool` — returns the same encrypted type as the inputs.

Equivalent to:

```solidity
FHE.select(FHE.le(a, b), a, b)
```

```solidity
// Example: cap withdrawal at balance
euint64 actualAmount = FHE.min(requestedAmount, balance);
```

### `FHE.max(a, b)` — Encrypted Maximum

```solidity
function max(euint64 a, euint64 b) returns (euint64)
```

Returns the larger of `a` and `b` as an encrypted value.

Equivalent to:

```solidity
FHE.select(FHE.ge(a, b), a, b)
```

```solidity
// Example: enforce minimum bid
euint64 effectiveBid = FHE.max(bid, minimumBid);
```

### Comparison Summary Table

| Operation | Function | Returns | Gas Estimate |
|-----------|----------|---------|-------------|
| Equal | `FHE.eq(a, b)` | `ebool` | ~80–100k |
| Not Equal | `FHE.ne(a, b)` | `ebool` | ~80–100k |
| Greater Than | `FHE.gt(a, b)` | `ebool` | ~80–100k |
| Greater or Equal | `FHE.ge(a, b)` | `ebool` | ~80–100k |
| Less Than | `FHE.lt(a, b)` | `ebool` | ~80–100k |
| Less or Equal | `FHE.le(a, b)` | `ebool` | ~80–100k |
| Minimum | `FHE.min(a, b)` | Same type | ~150–200k |
| Maximum | `FHE.max(a, b)` | Same type | ~150–200k |

::: danger Cannot Branch on ebool
```solidity
// ❌ IMPOSSIBLE — EVM cannot evaluate encrypted boolean
ebool isGreater = FHE.gt(a, b);
if (isGreater) { ... }  // Compilation error or meaningless

// ✅ CORRECT — use FHE.select()
ebool isGreater = FHE.gt(a, b);
euint64 result = FHE.select(isGreater, valueIfTrue, valueIfFalse);
```
:::

---

## Conditional Operation

### `FHE.select(condition, ifTrue, ifFalse)` — Encrypted Ternary

```solidity
function select(ebool condition, euint64 ifTrue, euint64 ifFalse) returns (euint64)
```

The encrypted equivalent of `condition ? a : b`. This is the **most important** FHE operation — it replaces all `if/else` logic on encrypted data.

| Property | Value |
|----------|-------|
| **Condition** | `ebool` (from any comparison) |
| **Branches** | Must be the same encrypted type |
| **Returns** | Same encrypted type as branches |
| **Gas estimate** | ~80–100k |
| **Evaluation** | **Both** branches are always evaluated (no short-circuit) |
| **Privacy** | Zero leakage — observer cannot tell which branch was selected |

Works with **all** encrypted types — `euint64`, `eaddress`, `ebool`, etc.:

```solidity
// With euint64
euint64 safeAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));

// With eaddress
_highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
```

---

## Type Conversions

### `FHE.asEuint*(plaintext)` — Trivial Encryption

Converts a plaintext value into an encrypted handle. Required when mixing plaintext and encrypted values in FHE operations.

```solidity
// Integer types
euint8  enc8  = FHE.asEuint8(42);
euint16 enc16 = FHE.asEuint16(1000);
euint32 enc32 = FHE.asEuint32(123456);
euint64 enc64 = FHE.asEuint64(1_000_000);
euint128 enc128 = FHE.asEuint128(value128);
euint256 enc256 = FHE.asEuint256(value256);

// Boolean
ebool encBool = FHE.asEbool(true);
```

| Property | Value |
|----------|-------|
| **Gas estimate** | ~30–50k |
| **Common uses** | Minting (plaintext amount), comparing to zero, setting caps/thresholds |
| **First seen** | [Week 3: Confidential Token](/week-3/lesson-1-token) |

```solidity
// Example: mint converts plaintext amount to encrypted for addition
euint64 encAmount = FHE.asEuint64(amount);
_balances[to] = FHE.add(_balances[to], encAmount);
```

### `FHE.asEaddress(address)` — Address Encryption

```solidity
eaddress encAddr = FHE.asEaddress(msg.sender);
```

Converts a plaintext `address` into an encrypted `eaddress` handle. Used to hide addresses on-chain (e.g., auction winners).

| Property | Value |
|----------|-------|
| **Gas estimate** | ~30–50k |
| **First seen** | [Week 4: Sealed Auction](/week-4/lesson-1-auction) |

### `FHE.fromExternal(external, proof)` — Verify User Input

```solidity
function fromExternal(externalEuint64 handle, bytes calldata proof) returns (euint64)
```

Verifies a user-submitted encrypted input and converts it from an `external*` type to the corresponding internal type. This is the entry point for all user-submitted encrypted data.

| Property | Value |
|----------|-------|
| **Gas estimate** | ~50–100k |
| **Must call** | Before any FHE operation on user input |
| **What it does** | Asks InputVerifier to validate the ciphertext + proof |
| **First seen** | [Week 1: Hello FHE](/week-1/lesson-3-hello-fhe) |

```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
    // Now `amount` is a verified encrypted value
}
```

---

## ACL Operations

The Access Control List determines who can read (decrypt) encrypted values. Every FHE operation produces a **new handle** — the old handle's permissions are gone.

### `FHE.allowThis(handle)` — Contract Self-Permission

```solidity
FHE.allowThis(_balances[msg.sender]);
```

Grants the **current contract** permission to use this handle in future transactions. Without this, the contract cannot read or operate on the value in a later call.

### `FHE.allow(handle, address)` — Grant Decryption Permission

```solidity
FHE.allow(_balances[msg.sender], msg.sender);
```

Grants a specific address permission to decrypt this value off-chain via `fhevmjs` and the KMS.

### `FHE.allowTransient(handle, address)` — Temporary Permission

```solidity
FHE.allowTransient(result, msg.sender);
```

Grants permission only for the current transaction. Useful for intermediate values that don't need to persist.

### The Permission Dance

After **every** FHE operation that produces a new handle you intend to store, you **must** call:

1. `FHE.allowThis(handle)` — so the contract can use it later
2. `FHE.allow(handle, user)` — so the relevant user(s) can decrypt it

```solidity
// The complete permission dance (after every balance update)
_balances[user] = FHE.add(_balances[user], amount);
FHE.allowThis(_balances[user]);     // Contract can use in future txns
FHE.allow(_balances[user], user);   // User can decrypt off-chain
```

::: tip Dual-Party Permissions
For allowances (approve/transferFrom), grant to **both** owner and spender:
```solidity
FHE.allow(_allowances[owner][spender], owner);   // Owner sees allowance
FHE.allow(_allowances[owner][spender], spender);  // Spender sees allowance
```
First seen in [Week 3: Advanced Patterns](/week-3/lesson-2-advanced).
:::

| ACL Operation | Gas Estimate | Use Case |
|---------------|-------------|----------|
| `FHE.allowThis(handle)` | ~20–30k | Contract can reuse handle |
| `FHE.allow(handle, addr)` | ~20–30k | User can decrypt off-chain |
| `FHE.allowTransient(handle, addr)` | ~15–25k | Temporary within-tx permission |

---

## Common Patterns

These are the recurring design patterns that appear throughout the bootcamp. Master these and you can build any FHE contract.

### The FHE Pattern (Core Lifecycle)

Every FHE function follows this four-step pattern:

```
fromExternal → Operate → allowThis → allow
```

```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    // 1. Verify input
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    // 2. Operate
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);

    // 3. Self-permit
    FHE.allowThis(_balances[msg.sender]);

    // 4. User-permit
    FHE.allow(_balances[msg.sender], msg.sender);
}
```

**First seen:** [Week 1: Hello FHE](/week-1/lesson-3-hello-fhe)

---

### Encrypted Guard (Compare → Select → Operate)

The FHE replacement for `require()` + operation. Use whenever you would check a condition before mutating state.

```solidity
// 1. COMPARE — produce an encrypted boolean
ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);

// 2. SELECT — choose the safe value
euint64 safeAmount = FHE.select(canWithdraw, amount, _balances[msg.sender]);

// 3. OPERATE — guaranteed safe (no underflow)
_balances[msg.sender] = FHE.sub(_balances[msg.sender], safeAmount);
```

**First seen:** [Week 2: FHE Patterns](/week-2/lesson-2-patterns)

---

### Silent-Zero Pattern

Transfer 0 instead of reverting on insufficient balance. Preserves privacy — an observer cannot tell whether the transfer had sufficient funds.

```solidity
ebool hasFunds = FHE.le(amount, _balances[from]);
euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));

_balances[from] = FHE.sub(_balances[from], actualAmount);
_balances[to] = FHE.add(_balances[to], actualAmount);
```

**Use when:** Transferring between parties — better to send nothing than a different amount.

**First seen:** [Week 3: Confidential Token](/week-3/lesson-1-token)

---

### Silent-Fail / Cap Pattern

Cap the amount at the maximum available instead of reverting. The operation always "succeeds" — just with a potentially reduced amount.

```solidity
ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);
euint64 actualAmount = FHE.select(canWithdraw, amount, _balances[msg.sender]);

_balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);
```

**Use when:** User is withdrawing their own funds — give them as much as possible.

**First seen:** [Week 2: FHE Patterns](/week-2/lesson-2-patterns)

---

### Double Protection Pattern

Two sequential silent-zero checks — first on allowance, then on balance. Used in delegated transfers (`transferFrom`).

```solidity
// Check 1: Allowance guard
ebool hasAllowance = FHE.le(amount, _allowances[from][msg.sender]);
euint64 actualAmount = FHE.select(hasAllowance, amount, FHE.asEuint64(0));

// Deduct allowance
_allowances[from][msg.sender] = FHE.sub(_allowances[from][msg.sender], actualAmount);

// Check 2: Balance guard (inside _transfer)
ebool hasFunds = FHE.le(actualAmount, _balances[from]);
euint64 transferAmount = FHE.select(hasFunds, actualAmount, FHE.asEuint64(0));
```

**Why two checks?** Neither check leaks information about *which one* failed. An observer cannot distinguish "insufficient allowance" from "insufficient balance."

**First seen:** [Week 3: Advanced Patterns](/week-3/lesson-2-advanced)

---

### Deferred Permissions Pattern

Grant `FHE.allow` only when the state machine reaches the appropriate phase — not at creation time.

```solidity
// During bidding: only contract can access winner data
FHE.allowThis(_highestBid);
FHE.allowThis(_highestBidder);

// After close: auctioneer gets permission to decrypt
function closeAuction() external onlyAuctioneer {
    FHE.allow(_highestBid, auctioneer);
    FHE.allow(_highestBidder, auctioneer);
}
```

**First seen:** [Week 4: Sealed Auction](/week-4/lesson-1-auction)

---

## Mock Testing Quick Reference

These helpers are provided by `FhevmTest.sol` — the base test contract that replaces `@fhevm/hardhat-plugin`.

### Encryption Helpers

| Helper | Returns | Example |
|--------|---------|---------|
| `mockEncryptBool(value)` | `(externalEbool, bytes memory)` | `mockEncryptBool(true)` |
| `mockEncrypt8(value)` | `(externalEuint8, bytes memory)` | `mockEncrypt8(42)` |
| `mockEncrypt16(value)` | `(externalEuint16, bytes memory)` | `mockEncrypt16(1000)` |
| `mockEncrypt32(value)` | `(externalEuint32, bytes memory)` | `mockEncrypt32(123456)` |
| `mockEncrypt64(value)` | `(externalEuint64, bytes memory)` | `mockEncrypt64(1_000_000)` |
| `mockEncrypt128(value)` | `(externalEuint128, bytes memory)` | `mockEncrypt128(val)` |
| `mockEncrypt256(value)` | `(externalEuint256, bytes memory)` | `mockEncrypt256(val)` |
| `mockEncryptAddress(value)` | `(externalEaddress, bytes memory)` | `mockEncryptAddress(alice)` |

### Decryption Helpers

| Helper | Returns | Example |
|--------|---------|---------|
| `mockDecryptBool(enc)` | `bool` | `mockDecryptBool(result)` |
| `mockDecrypt8(enc)` | `uint8` | `mockDecrypt8(counter.get())` |
| `mockDecrypt16(enc)` | `uint16` | `mockDecrypt16(value)` |
| `mockDecrypt32(enc)` | `uint32` | `mockDecrypt32(counter.getCount())` |
| `mockDecrypt64(enc)` | `uint64` | `mockDecrypt64(token.balanceOf())` |
| `mockDecrypt128(enc)` | `uint128` | `mockDecrypt128(value)` |
| `mockDecrypt256(enc)` | `uint256` | `mockDecrypt256(value)` |
| `mockDecryptAddress(enc)` | `address` | `mockDecryptAddress(auction.getHighestBidder())` |

### The Test Pattern

Every FHE test follows this rhythm:

```solidity
function test_example() public {
    // 1. Encrypt — create mock encrypted input
    (externalEuint64 handle, bytes memory proof) = mockEncrypt64(500);

    // 2. Call — execute contract function as a specific user
    vm.prank(alice);
    contract.someFunction(handle, proof);

    // 3. Decrypt — read and decrypt the result
    uint64 result = mockDecrypt64(contract.getValue());

    // 4. Assert — verify the plaintext result
    assertEq(result, 500);
}
```

### Test Setup

Every test contract **must** call `super.setUp()` to deploy mock FHE infrastructure:

```solidity
contract MyTest is FhevmTest {
    function setUp() public override {
        super.setUp();    // ← Deploys MockFHEVMExecutor, MockACL, etc.
        // ... deploy your contract
    }
}
```

---

## Gas Cost Reference

Approximate gas costs for FHE operations. These are estimates for the FHEVM coprocessor — mock mode costs are significantly lower.

| Operation | Gas Estimate | Category |
|-----------|-------------|----------|
| `FHE.add` / `FHE.sub` | ~50–80k | Arithmetic |
| `FHE.mul` | ~80–150k | Arithmetic |
| `FHE.eq` / `FHE.ne` | ~80–100k | Comparison |
| `FHE.gt` / `FHE.ge` / `FHE.lt` / `FHE.le` | ~80–100k | Comparison |
| `FHE.min` / `FHE.max` | ~150–200k | Comparison (compound) |
| `FHE.select` | ~80–100k | Conditional |
| `FHE.asEuint*` / `FHE.asEaddress` | ~30–50k | Trivial encryption |
| `FHE.fromExternal` | ~50–100k | Input verification |
| `FHE.allowThis` / `FHE.allow` | ~20–30k | ACL |
| Plaintext ERC20 transfer | ~50k | (baseline) |
| Confidential `_transfer` | ~300–500k | 4–6 FHE operations |
| Confidential `transferFrom` | ~500–800k | 7–10 FHE operations |

---

## Quick Decision Guide

| I need to... | Use... | Pattern |
|--------------|--------|---------|
| Accept encrypted user input | `FHE.fromExternal(handle, proof)` | Core lifecycle |
| Add encrypted values | `FHE.add(a, b)` | — |
| Subtract encrypted values | `FHE.sub(a, b)` + guard | Encrypted guard |
| Check if value is sufficient | `FHE.le(amount, balance)` | Compare → select |
| Handle insufficient balance (own funds) | `FHE.select(cond, amount, balance)` | Silent-fail/cap |
| Handle insufficient balance (transfer) | `FHE.select(cond, amount, FHE.asEuint64(0))` | Silent-zero |
| Mix plaintext with encrypted | `FHE.asEuint64(plaintext)` | Trivial encryption |
| Hide an address | `FHE.asEaddress(addr)` | — |
| Find higher of two values | `FHE.gt(a, b)` + `FHE.select` | Ranking |
| Store encrypted result | `FHE.allowThis(handle)` | Permission dance |
| Let user decrypt | `FHE.allow(handle, user)` | Permission dance |
| Grant temp permission | `FHE.allowTransient(handle, user)` | — |
| Delegate spending | Double silent-zero | Double protection |
