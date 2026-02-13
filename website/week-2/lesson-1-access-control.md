# Lesson 1: Encrypted Access Control — The Vault

**Duration:** ~60 minutes | **Prerequisites:** [Week 1](/week-1/) completed | **Contract:** `src/EncryptedVault.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Implement per-user encrypted state with `mapping(address => euint64)`
- Master granular access control with `FHE.allow`, `FHE.allowThis`, and `FHE.allowTransient`
- Understand why every FHE operation produces a **new handle** that must be re-authorized
- Know the difference between contract-level and user-level permissions
- Be able to build deposit functionality with proper ACL grants

---

## 1. The Problem

In Week 1, we built a single counter that anyone could modify. Real applications need **per-user private state** — each user should have their own encrypted balance that only they can see.

Consider a vault contract:
- Users deposit encrypted amounts
- Each user's balance is private (only they can decrypt it)
- The contract owner can see the aggregate total (but not individual balances)
- Withdrawals must check balances without revealing them

This requires mastering the FHEVM access control system.

## 2. The Contract: `EncryptedVault.sol`

Open `src/EncryptedVault.sol`. Here's the interface:

```solidity
contract EncryptedVault is ZamaEthereumConfig {
    address public owner;
    mapping(address => euint64) private _balances;
    euint64 private _totalDeposits;

    function deposit(externalEuint64 encAmount, bytes calldata inputProof) external { ... }
    function withdraw(externalEuint64 encAmount, bytes calldata inputProof) external { ... }
    function getBalance() external view returns (euint64) { ... }
    function getTotalDeposits() external view returns (euint64) { ... }
}
```

Compared to `FHECounter` from Week 1, this contract introduces:
- **Per-user state** — a mapping instead of a single variable
- **Multiple permission grants** — different users get access to different values
- **Encrypted conditionals** — the withdraw function uses `FHE.le` and `FHE.select` (covered in Lesson 2)

Let's walk through the key patterns.

## 3. Per-User Encrypted State

```solidity
mapping(address => euint64) private _balances;
```

This is the core pattern. Each address maps to its own encrypted 64-bit unsigned integer. On-chain, these are `bytes32` handles. Nobody can see the plaintext values by reading storage — the handles are meaningless without decryption permission.

Compare this to Week 1's single state variable:

| Week 1 (Counter) | Week 2 (Vault) |
|-------------------|-----------------|
| `euint32 private _count` | `mapping(address => euint64) private _balances` |
| One value, shared by all | One value per user, each private |
| Any caller gets `allow` | Only the depositor gets `allow` |

### The `deposit` Function

```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    // Add to user's encrypted balance
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);

    // Update aggregate total
    _totalDeposits = FHE.add(_totalDeposits, amount);

    // Grant permissions
    FHE.allowThis(_balances[msg.sender]);        // Contract can use it
    FHE.allow(_balances[msg.sender], msg.sender); // User can decrypt
    FHE.allowThis(_totalDeposits);                // Contract can use it
    FHE.allow(_totalDeposits, owner);             // Owner can decrypt aggregate
}
```

This function follows the same verify → compute → authorize pattern from Week 1, but with two crucial additions:

1. **Two separate state updates** — the user's balance and the aggregate total are both encrypted and updated independently
2. **Targeted permissions** — the user can only decrypt their own balance; only the owner can decrypt the total

**Key insight:** Every `FHE.add()` produces a **new handle**. The old handle's permissions don't transfer. You must re-authorize after every operation.

### Why Re-Authorization Matters

Consider what happens without it:

```solidity
// Transaction 1: Alice deposits 100
_balances[alice] = FHE.add(_balances[alice], amount);  // New handle = H1
FHE.allowThis(H1);  // Contract can use H1
FHE.allow(H1, alice);  // Alice can decrypt H1

// Transaction 2: Alice deposits 200
// FHE.add needs to READ _balances[alice] (which is H1)
// The contract must have permission on H1 — that's why allowThis was critical!
_balances[alice] = FHE.add(_balances[alice], amount);  // New handle = H2
// H2 is a DIFFERENT handle than H1
// Nobody has permission on H2 yet!
FHE.allowThis(H2);  // Now contract can use H2 next time
FHE.allow(H2, alice);  // Now Alice can decrypt H2
```

If you forget `allowThis` in Transaction 1, Transaction 2 **reverts** because the contract can't read its own state.

## 4. Deep Dive: Access Control

The ACL is the most important concept in FHEVM. Here's the full picture:

### `FHE.allowThis(value)`

Grants the **contract itself** permission to use the encrypted value in future transactions. Without this:

```
// Transaction 1: deposit
_balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
FHE.allowThis(_balances[msg.sender]); // ← MUST do this

// Transaction 2: another deposit
// FHE.add reads _balances[msg.sender] — this requires the contract to have permission!
_balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
```

If you forget `allowThis`, the second transaction reverts because the contract can't read its own state.

### `FHE.allow(value, account)`

Grants a specific address permission to **decrypt** the value off-chain. This is how you control who can see what:

```solidity
FHE.allow(_balances[msg.sender], msg.sender); // Only the depositor can see their balance
FHE.allow(_totalDeposits, owner);              // Only the owner can see the total
```

This is where FHEVM's privacy model shines. In the vault:
- Alice deposits 1000 → only Alice can decrypt her balance
- Bob deposits 2000 → only Bob can decrypt his balance
- The owner can decrypt the aggregate (3000) but **cannot** see individual balances
- Nobody else can see anything

### `FHE.allowTransient(value, account)`

Grants **temporary** permission that expires at the end of the current transaction. Useful for cross-contract calls where you need to pass an encrypted value to another contract, but don't want to leave a permanent permission.

### Permission Model Summary

```
  ┌─────────────────────────────────────────────┐
  │             After FHE.add(a, b)              │
  │                                             │
  │  New handle = X                             │
  │                                             │
  │  Who can use X?                              │
  │  ├── Nobody (by default!)                    │
  │  │                                          │
  │  ├── FHE.allowThis(X)                       │
  │  │   → Contract can use X in future ops     │
  │  │                                          │
  │  ├── FHE.allow(X, alice)                    │
  │  │   → Alice can decrypt X off-chain        │
  │  │                                          │
  │  └── FHE.allowTransient(X, addr)            │
  │      → Temporary: only within this tx       │
  └─────────────────────────────────────────────┘
```

### When to Use Each

| Function | Use Case | Lifetime |
|----------|----------|----------|
| `FHE.allowThis(X)` | Contract needs to read/operate on X in a future transaction | Permanent (until overwritten) |
| `FHE.allow(X, addr)` | A user needs to decrypt X off-chain | Permanent (until overwritten) |
| `FHE.allowTransient(X, addr)` | Passing X to another contract within the same transaction | Current transaction only |

### The ACL Checklist

Every time you write a function that produces a new encrypted value, ask yourself:

1. **Will the contract use this value later?** → Call `FHE.allowThis(value)`
2. **Should a user be able to decrypt this?** → Call `FHE.allow(value, user)`
3. **Am I passing this to another contract in the same tx?** → Call `FHE.allowTransient(value, contract)`

## 5. Reading Encrypted State

The vault provides two view functions:

```solidity
function getBalance() external view returns (euint64) {
    return _balances[msg.sender];
}

function getTotalDeposits() external view returns (euint64) {
    return _totalDeposits;
}
```

Both return **encrypted handles**, not plaintext values. The caller receives a `bytes32` handle that they can only decrypt if they have been granted permission via `FHE.allow`.

- When Alice calls `getBalance()`, she gets her handle. She was granted `allow` during deposit, so she can decrypt it.
- When Bob calls `getBalance()`, he gets his own handle. He cannot decrypt Alice's.
- When anyone calls `getTotalDeposits()`, they get the aggregate handle. Only the owner was granted `allow`, so only the owner can decrypt it.

## 6. Visualizing the Permission Graph

After Alice deposits 1000 and Bob deposits 2000:

```
  ┌─────────────────────────────────────────────────────────────┐
  │                     EncryptedVault                          │
  │                                                             │
  │  _balances[alice] = Handle_A                                │
  │    ├── allowThis → Vault contract can use Handle_A          │
  │    └── allow(alice) → Alice can decrypt Handle_A            │
  │                                                             │
  │  _balances[bob] = Handle_B                                  │
  │    ├── allowThis → Vault contract can use Handle_B          │
  │    └── allow(bob) → Bob can decrypt Handle_B                │
  │                                                             │
  │  _totalDeposits = Handle_T                                  │
  │    ├── allowThis → Vault contract can use Handle_T          │
  │    └── allow(owner) → Owner can decrypt Handle_T            │
  │                                                             │
  │  Alice CANNOT decrypt Handle_B or Handle_T                  │
  │  Bob CANNOT decrypt Handle_A or Handle_T                    │
  │  Owner CANNOT decrypt Handle_A or Handle_B                  │
  └─────────────────────────────────────────────────────────────┘
```

## 7. Common Mistakes

### 1. Forgetting `allowThis` After an Operation

```solidity
// ❌ BROKEN — contract can't use balance next time
_balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
// Missing: FHE.allowThis(_balances[msg.sender]);
```

Next transaction that reads `_balances[msg.sender]` will revert.

### 2. Granting Too-Broad Permissions

```solidity
// ❌ BAD — anyone can decrypt the user's balance
FHE.allow(_balances[msg.sender], someOtherAddress);
```

Only grant decrypt permission to the user who owns the data.

### 3. Forgetting to Re-Authorize After Each Operation

```solidity
// ❌ BROKEN — only authorizes after the last operation
_balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
_totalDeposits = FHE.add(_totalDeposits, amount);
FHE.allowThis(_balances[msg.sender]);  // ✅
// Missing: FHE.allowThis(_totalDeposits);  ← OOPS
```

Each state variable that gets a new handle needs its own `allowThis`.

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| `mapping(address => euint64)` | Per-user encrypted state |
| `FHE.allowThis(value)` | Contract can reuse value in future transactions |
| `FHE.allow(value, addr)` | Specific address can decrypt value off-chain |
| `FHE.allowTransient(value, addr)` | Temporary permission within one transaction |
| New-handle rule | Every FHE operation produces a new handle — must re-authorize |

---

## Key Takeaways

1. **Per-user encrypted state** uses `mapping(address => euint64)` — each user gets their own private value
2. Every FHE operation produces a **new handle** — permissions from the old handle don't carry over
3. Always call **`allowThis`** so the contract can use the value in future transactions
4. Use **`allow`** to let specific users decrypt — this is how you control who sees what
5. The ACL is the **privacy enforcement layer** — without it, encrypted values are useless handles

---

**Next:** [Lesson 2: FHE Patterns — Comparisons, Conditionals & Silent Failure](/week-2/lesson-2-patterns) — Learn `FHE.select()`, the full comparison table, and why FHE contracts don't revert.
