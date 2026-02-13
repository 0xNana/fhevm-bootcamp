# Lesson 2: FHE Patterns — Comparisons, Conditionals & Silent Failure

**Duration:** ~60 minutes | **Prerequisites:** [Lesson 1: Access Control](/week-2/lesson-1-access-control) | **Contract:** `src/EncryptedVault.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Use `FHE.select()` for encrypted conditionals (the encrypted ternary)
- Understand why FHE contracts "silent fail" instead of reverting — and why this preserves privacy
- Know the full set of encrypted comparison operations (`eq`, `ne`, `gt`, `ge`, `lt`, `le`, `min`, `max`)
- Apply the **"encrypted guard" pattern**: compare → select → operate
- Walk through the EncryptedVault tests and run them locally
- Reason about encrypted control flow without `if/else`

---

## 1. The Problem: No Branching on Ciphertext

In traditional Solidity, you'd write:

```solidity
require(amount <= balance, "Insufficient funds");
balance -= amount;
```

But with FHE, **you cannot branch on encrypted values**. The EVM sees only `bytes32` handles — it has no idea what the underlying plaintext is. Writing `if (encryptedA > encryptedB)` is impossible because:

1. The EVM cannot evaluate the condition (it doesn't have the plaintext)
2. Even if it could, branching would **leak information** — an observer could tell which branch was taken

FHEVM solves this with `FHE.select()` — an encrypted ternary that executes **both branches** and selects the result, revealing nothing about which was chosen.

## 2. `FHE.select()` Deep Dive

### Signature

```solidity
function select(ebool condition, euint64 ifTrue, euint64 ifFalse) returns (euint64)
```

### How It Works

`FHE.select()` is the encrypted equivalent of the ternary operator `condition ? a : b`. But unlike a normal ternary:

- **Both `ifTrue` and `ifFalse` are evaluated** — there is no short-circuit
- The coprocessor performs the selection **on ciphertext** — it never sees which value was chosen
- The result is a new encrypted handle with no information leakage

```
  ┌──────────────────────────────────────────────────────┐
  │              FHE.select(cond, a, b)                  │
  │                                                      │
  │  Traditional:   if (x <= y) use x; else use y;       │
  │                 ↑ leaks which branch was taken        │
  │                                                      │
  │  FHE:           result = select(le(x, y), x, y)      │
  │                 ↑ both paths computed, one selected   │
  │                   on ciphertext — zero leakage        │
  └──────────────────────────────────────────────────────┘
```

### Analogy

Think of `FHE.select()` like putting two sealed envelopes into a machine. The machine picks one and hands you a new sealed envelope. You never opened either input, and nobody watching knows which one was picked.

## 3. The `withdraw` Function Walkthrough

Now let's see `FHE.select()` in action. Open `src/EncryptedVault.sol` and look at the `withdraw` function:

```solidity
function withdraw(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    // Step 1: Encrypted comparison — is amount <= balance?
    ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);

    // Step 2: Encrypted ternary — if yes, use amount; if no, cap at balance
    euint64 actualAmount = FHE.select(canWithdraw, amount, _balances[msg.sender]);

    // Step 3: Subtract (guaranteed safe — actualAmount <= balance)
    _balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);

    // Step 4: Update aggregate
    _totalDeposits = FHE.sub(_totalDeposits, actualAmount);

    // Step 5: Re-authorize all updated handles
    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);
    FHE.allowThis(_totalDeposits);
    FHE.allow(_totalDeposits, owner);

    emit Withdraw(msg.sender);
}
```

Let's trace through two scenarios:

### Scenario A: User has 1000, withdraws 400

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(400, 1000)` | `ebool(true)` — 400 ≤ 1000 |
| 2 | `FHE.select(true, 400, 1000)` | `euint64(400)` — use requested amount |
| 3 | `FHE.sub(1000, 400)` | `euint64(600)` — new balance |

### Scenario B: User has 500, tries to withdraw 999

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(999, 500)` | `ebool(false)` — 999 > 500 |
| 2 | `FHE.select(false, 999, 500)` | `euint64(500)` — cap at balance |
| 3 | `FHE.sub(500, 500)` | `euint64(0)` — withdrew everything |

In Scenario B, the user tried to withdraw more than they had. Instead of reverting, the contract **silently capped** the withdrawal at their full balance. The transaction succeeded.

## 4. Why Silent-Fail Instead of Revert?

This is one of the most important patterns in FHE contract design.

### The Privacy Argument

In traditional Solidity:
```solidity
require(amount <= balance, "Insufficient funds"); // ← LEAKS INFORMATION
```

An observer watching the blockchain sees:
- Transaction **reverted** → the user's balance is **less than** `amount`
- Transaction **succeeded** → the user's balance is **at least** `amount`

By submitting transactions with different amounts and watching which revert, an attacker can **binary-search** for a user's exact balance — even though the balance is "encrypted."

### The FHE Solution

```solidity
// Transaction ALWAYS succeeds — no information leak
ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);
euint64 actualAmount = FHE.select(canWithdraw, amount, _balances[msg.sender]);
_balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);
```

Both cases (sufficient funds and insufficient funds) produce a successful transaction. An observer cannot tell which path was taken. The user's balance remains private.

```
  ┌─────────────────────────────────────────────────────────────┐
  │              Traditional vs FHE Error Handling               │
  │                                                             │
  │  Traditional:                                               │
  │    withdraw(999) with balance=500                           │
  │    → REVERT "Insufficient funds"                            │
  │    → Observer learns: balance < 999                         │
  │                                                             │
  │  FHE (silent-fail):                                         │
  │    withdraw(999) with balance=500                           │
  │    → SUCCESS (silently withdrew 500)                        │
  │    → Observer learns: nothing                               │
  └─────────────────────────────────────────────────────────────┘
```

### Design Principle

> In FHE contracts, **never revert based on encrypted state**. If the condition depends on a ciphertext, use `FHE.select()` to handle both outcomes silently.

You *can* still revert on **plaintext** conditions (e.g., `require(msg.sender == owner)`) because those don't reveal encrypted data.

## 5. Comparison Operations

FHEVM provides a full set of encrypted comparison operators. All comparisons return `ebool` — an encrypted boolean.

| Operation | Function | Returns |
|-----------|----------|---------|
| Equal | `FHE.eq(a, b)` | `ebool` — encrypted true if a == b |
| Not equal | `FHE.ne(a, b)` | `ebool` — encrypted true if a != b |
| Greater than | `FHE.gt(a, b)` | `ebool` — encrypted true if a > b |
| Greater or equal | `FHE.ge(a, b)` | `ebool` — encrypted true if a >= b |
| Less than | `FHE.lt(a, b)` | `ebool` — encrypted true if a < b |
| Less or equal | `FHE.le(a, b)` | `ebool` — encrypted true if a <= b |
| Min | `FHE.min(a, b)` | Same type — encrypted minimum of a and b |
| Max | `FHE.max(a, b)` | Same type — encrypted maximum of a and b |

### Critical Rule

You **cannot** use an `ebool` in a Solidity `if` statement:

```solidity
// ❌ IMPOSSIBLE — EVM cannot evaluate encrypted boolean
ebool isGreater = FHE.gt(a, b);
if (isGreater) { ... }  // Compilation error or meaningless

// ✅ CORRECT — use FHE.select()
ebool isGreater = FHE.gt(a, b);
euint64 result = FHE.select(isGreater, valueIfTrue, valueIfFalse);
```

### `min` and `max` — Shorthand Patterns

`FHE.min` and `FHE.max` are convenience functions. They're equivalent to:

```solidity
// FHE.min(a, b) is equivalent to:
FHE.select(FHE.le(a, b), a, b);

// FHE.max(a, b) is equivalent to:
FHE.select(FHE.ge(a, b), a, b);
```

In fact, the withdraw function could use `min` as a shorthand:

```solidity
// These are equivalent:
euint64 actualAmount = FHE.select(FHE.le(amount, balance), amount, balance);
euint64 actualAmount = FHE.min(amount, balance);
```

## 6. The "Encrypted Guard" Pattern

Many FHE functions follow a three-step pattern we call the **encrypted guard**:

```
Compare → Select → Operate
```

### The Pattern

```solidity
// 1. COMPARE — produce an encrypted boolean
ebool condition = FHE.le(requestedAmount, balance);

// 2. SELECT — choose the safe value based on the condition
euint64 safeAmount = FHE.select(condition, requestedAmount, balance);

// 3. OPERATE — use the safe value (guaranteed no underflow/overflow)
balance = FHE.sub(balance, safeAmount);
```

### Why This Pattern Matters

It's the FHE equivalent of `require` + `operation`. Every time you would write:

```solidity
require(someCondition, "Error");
doSomething();
```

In FHE, you write:

```solidity
ebool condition = FHE.someComparison(...);
euint64 safeValue = FHE.select(condition, valueA, valueB);
doSomethingWith(safeValue);
```

### More Examples

**Capped transfer** (don't send more than balance):
```solidity
ebool hasEnough = FHE.le(amount, senderBalance);
euint64 transferAmount = FHE.select(hasEnough, amount, senderBalance);
senderBalance = FHE.sub(senderBalance, transferAmount);
receiverBalance = FHE.add(receiverBalance, transferAmount);
```

**Conditional bonus** (double reward if balance > threshold):
```solidity
ebool isHighBalance = FHE.gt(balance, threshold);
euint64 bonus = FHE.select(isHighBalance, doubleReward, singleReward);
balance = FHE.add(balance, bonus);
```

You'll see this pattern again in Week 3 when we build ConfidentialERC20 transfers.

## 7. Testing Patterns: The EncryptedVault Tests

Open `test/EncryptedVault.t.sol`. Let's walk through the key tests.

### Test: `test_withdrawCapsAtBalance`

This is the most important test — it verifies the silent-fail pattern:

```solidity
function test_withdrawCapsAtBalance() public {
    // Deposit 500
    (externalEuint64 h1, bytes memory p1) = mockEncrypt64(500);
    vm.prank(alice);
    vault.deposit(h1, p1);

    // Try to withdraw 999 (more than balance) — should cap at 500
    (externalEuint64 h2, bytes memory p2) = mockEncrypt64(999);
    vm.prank(alice);
    vault.withdraw(h2, p2);

    // Balance is 0 (withdrew everything, silently capped)
    vm.prank(alice);
    assertEq(mockDecrypt64(vault.getBalance()), 0);
}
```

**What this verifies:**
1. Alice deposits 500
2. Alice tries to withdraw 999 (more than she has)
3. The transaction **does not revert** — it succeeds silently
4. Alice's balance is 0 — the withdrawal was capped at her full balance of 500

### Test: `test_differentUsersHaveSeparateBalances`

This verifies the per-user state isolation:

```solidity
function test_differentUsersHaveSeparateBalances() public {
    // Alice deposits 1000
    (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
    vm.prank(alice);
    vault.deposit(h1, p1);

    // Bob deposits 2000
    (externalEuint64 h2, bytes memory p2) = mockEncrypt64(2000);
    vm.prank(bob);
    vault.deposit(h2, p2);

    // Check Alice's balance
    vm.prank(alice);
    assertEq(mockDecrypt64(vault.getBalance()), 1000);

    // Check Bob's balance
    vm.prank(bob);
    assertEq(mockDecrypt64(vault.getBalance()), 2000);
}
```

**What this verifies:**
1. Alice and Bob each have their own encrypted balance
2. Alice's deposit doesn't affect Bob's balance (and vice versa)
3. Each user can only read their own balance via `getBalance()` (which uses `msg.sender`)

### Test: `test_totalDepositsAggregates`

This verifies the aggregate tracking:

```solidity
function test_totalDepositsAggregates() public {
    // Alice deposits 1000
    (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
    vm.prank(alice);
    vault.deposit(h1, p1);

    // Bob deposits 2000
    (externalEuint64 h2, bytes memory p2) = mockEncrypt64(2000);
    vm.prank(bob);
    vault.deposit(h2, p2);

    // Owner (deployer) can see aggregate total
    uint64 total = mockDecrypt64(vault.getTotalDeposits());
    assertEq(total, 3000);
}
```

**What this verifies:**
1. The aggregate total tracks the sum of all deposits
2. The owner (deployer) can decrypt the total
3. Individual balances remain private — only the sum is available to the owner

## 8. Running the EncryptedVault Tests

Run the full test suite:

```bash
forge test --match-contract EncryptedVaultTest -vvv
```

Expected output: **7 tests pass**, covering:

| Test | What It Verifies |
|------|-----------------|
| `test_depositUpdatesBalance` | Single deposit updates user balance |
| `test_multipleDepositsAccumulate` | Multiple deposits add up correctly |
| `test_differentUsersHaveSeparateBalances` | Per-user state isolation |
| `test_withdrawReducesBalance` | Normal withdrawal reduces balance |
| `test_withdrawCapsAtBalance` | Over-withdrawal is silently capped |
| `test_totalDepositsAggregates` | Aggregate total is correct |
| `test_totalDepositsDecreasesOnWithdraw` | Withdrawals reduce the aggregate |

### The Test Pattern (Recap)

Every FHE test follows the same rhythm from Week 1:

```
1. Encrypt    →  mockEncrypt64(value)
2. Call       →  vm.prank(user); contract.function(handle, proof)
3. Decrypt    →  mockDecrypt64(contract.getter())
4. Assert     →  assertEq(decrypted, expected)
```

The only new element this week is that you need `vm.prank` to set `msg.sender` correctly, because the vault uses `msg.sender` to determine which balance to read/write.

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| `FHE.le(a, b)` | Encrypted less-than-or-equal comparison, returns `ebool` |
| `FHE.select(cond, a, b)` | Encrypted ternary — if/then/else without branching |
| `ebool` | Encrypted boolean from comparisons, usable only in `FHE.select()` |
| Silent failure | Transactions succeed regardless — no info leak via reverts |
| Encrypted guard pattern | Compare → Select → Operate: the FHE replacement for `require` |
| `FHE.min(a, b)` / `FHE.max(a, b)` | Shorthand for compare+select on min/max |

---

## Key Takeaways

1. **`FHE.select()`** is the encrypted ternary — both branches execute, one is chosen on ciphertext, zero leakage
2. **Never revert on encrypted state** — use `select` to handle both outcomes silently (the silent-fail pattern)
3. The **"encrypted guard" pattern** (compare → select → operate) replaces `require` + `operation` in FHE
4. **All comparisons return `ebool`** — you cannot use `ebool` in `if` statements, only in `FHE.select()`
5. **`FHE.min`/`FHE.max`** are shorthand for common compare+select patterns
6. The silent-fail pattern **preserves privacy** — observers cannot binary-search balances by watching reverts

---

**Next:** [Homework: EncryptedTipJar](/week-2/homework) — Build an encrypted tip jar that tracks per-user totals and lets recipients claim tips privately.
