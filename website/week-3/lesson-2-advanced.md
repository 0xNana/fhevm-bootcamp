# Lesson 2: Advanced Patterns — Approvals, Double Protection & Testing

**Duration:** ~60 minutes | **Prerequisites:** [Lesson 1: Confidential Token](/week-3/lesson-1-token) | **Contract:** `src/ConfidentialERC20.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Implement encrypted `approve` with **dual-party permissions** (owner and spender)
- Understand `transferFrom` with **double protection** — two layered silent-zero checks on allowance and balance
- Work with **nested encrypted mappings**: `mapping(address => mapping(address => euint64))`
- Reason about **gas costs** for FHE operations and how to minimize them
- Walk through the full **8-test suite** and understand what each test verifies
- Run the tests locally and interpret the output

---

## 1. Encrypted Approvals

In a standard ERC20, `approve(spender, amount)` sets a public allowance. Anyone can call `allowance(owner, spender)` and see the exact amount.

In our confidential token, the allowance is **encrypted**. But there's a key design question: who should be able to see the allowance?

### The `approve` Function

```solidity
function approve(address spender, externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    _allowances[msg.sender][spender] = amount;

    FHE.allowThis(_allowances[msg.sender][spender]);
    FHE.allow(_allowances[msg.sender][spender], msg.sender);  // Owner can see allowance
    FHE.allow(_allowances[msg.sender][spender], spender);      // Spender can see allowance
}
```

### Dual-Party Permissions

Notice the **three** permission calls:

| Call | Purpose |
|------|---------|
| `FHE.allowThis(...)` | Contract can use this allowance in future `transferFrom` calls |
| `FHE.allow(..., msg.sender)` | The **owner** can decrypt to see how much they've approved |
| `FHE.allow(..., spender)` | The **spender** can decrypt to know their spending limit |

This matches standard ERC20 semantics where `allowance(owner, spender)` is a public view function. In the confidential version, both parties can see it — but nobody else can.

### Why Two `allow` Calls?

In Week 2's vault, each balance had one owner. In the allowance case, the same value is meaningful to **two** parties:

```
  ┌──────────────────────────────────────────────────────────────┐
  │      _allowances[alice][bob] = Handle_X                      │
  │                                                              │
  │  FHE.allowThis(Handle_X)                                     │
  │    → Contract uses X in transferFrom                         │
  │                                                              │
  │  FHE.allow(Handle_X, alice)     [OWNER]                      │
  │    → Alice can see: "I approved Bob for 500 tokens"          │
  │                                                              │
  │  FHE.allow(Handle_X, bob)       [SPENDER]                    │
  │    → Bob can see: "Alice approved me for 500 tokens"         │
  │                                                              │
  │  Charlie cannot decrypt Handle_X                             │
  └──────────────────────────────────────────────────────────────┘
```

## 2. Nested Encrypted Mappings

The allowance storage uses a **nested mapping**:

```solidity
mapping(address => mapping(address => euint64)) private _allowances;
```

This maps `owner → spender → encrypted allowance`. Each unique (owner, spender) pair has its own independent encrypted value.

### Storage Layout

```
_allowances[alice][bob]     = euint64  (Alice approved Bob)
_allowances[alice][charlie] = euint64  (Alice approved Charlie)
_allowances[bob][alice]     = euint64  (Bob approved Alice)
```

Each of these is a separate encrypted handle with its own permissions. Approving Bob doesn't affect Charlie's allowance, and Alice's approval of Bob is independent of Bob's approval of Alice.

### Solidity Mechanics

Nested mappings with encrypted types work exactly like regular nested mappings — the outer key selects the inner mapping, the inner key selects the value. The only difference is that the stored value is an encrypted handle (`bytes32`) rather than a plaintext number.

## 3. `transferFrom` with Double Protection

Here's the most sophisticated function in the contract. It combines **two** silent-zero checks in sequence:

```solidity
function transferFrom(address from, address to, externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    // Check 1: Does spender have enough allowance?
    ebool hasAllowance = FHE.le(amount, _allowances[from][msg.sender]);
    euint64 actualAmount = FHE.select(hasAllowance, amount, FHE.asEuint64(0));

    // Deduct from allowance
    _allowances[from][msg.sender] = FHE.sub(_allowances[from][msg.sender], actualAmount);

    // Check 2: _transfer internally checks if sender has enough balance
    _transfer(from, to, actualAmount);
}
```

### The Double Protection Pattern

There are **two** silent-zero checks that fire in sequence:

```
  ┌──────────────────────────────────────────────────────────────┐
  │              transferFrom Double Protection                   │
  │                                                              │
  │  Check 1: Allowance Guard (in transferFrom)                  │
  │    amount <= allowance?                                      │
  │    YES → actualAmount = amount                               │
  │    NO  → actualAmount = 0  (silent zero)                     │
  │                                                              │
  │  Check 2: Balance Guard (inside _transfer)                   │
  │    actualAmount <= balance?                                   │
  │    YES → transfer actualAmount                               │
  │    NO  → transfer 0  (silent zero)                           │
  │                                                              │
  │  Both checks are ENCRYPTED                                   │
  │  Neither the spender nor any observer knows                  │
  │  which check (if any) blocked the transfer                   │
  └──────────────────────────────────────────────────────────────┘
```

### Trace: Successful `transferFrom`

Alice approved Bob for 500. Alice has 1000 tokens. Bob calls `transferFrom(alice, charlie, 300)`:

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(300, 500)` | `ebool(true)` — allowance sufficient |
| 2 | `FHE.select(true, 300, 0)` | `euint64(300)` — use full amount |
| 3 | `FHE.sub(500, 300)` | Allowance updated: `200` remaining |
| 4 | `_transfer(alice, charlie, 300)` | |
| 4a | `FHE.le(300, 1000)` | `ebool(true)` — balance sufficient |
| 4b | `FHE.select(true, 300, 0)` | `euint64(300)` — transfer proceeds |
| 4c | Alice: `1000 - 300 = 700` | |
| 4d | Charlie: `0 + 300 = 300` | |

### Trace: Insufficient Allowance

Alice approved Bob for 100. Alice has 1000 tokens. Bob calls `transferFrom(alice, charlie, 500)`:

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(500, 100)` | `ebool(false)` — allowance insufficient |
| 2 | `FHE.select(false, 500, 0)` | `euint64(0)` — zeroed out |
| 3 | `FHE.sub(100, 0)` | Allowance unchanged: `100` |
| 4 | `_transfer(alice, charlie, 0)` | |
| 4a | `FHE.le(0, 1000)` | `ebool(true)` — 0 ≤ anything |
| 4b | `FHE.select(true, 0, 0)` | `euint64(0)` — nothing to transfer |
| 4c | Alice: `1000 - 0 = 1000` | Unchanged |
| 4d | Charlie: `0 + 0 = 0` | Unchanged |

### Trace: Sufficient Allowance, Insufficient Balance

Alice approved Bob for 5000. Alice has 100 tokens. Bob calls `transferFrom(alice, charlie, 3000)`:

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(3000, 5000)` | `ebool(true)` — allowance sufficient |
| 2 | `FHE.select(true, 3000, 0)` | `euint64(3000)` — passes allowance check |
| 3 | `FHE.sub(5000, 3000)` | Allowance updated: `2000` |
| 4 | `_transfer(alice, charlie, 3000)` | |
| 4a | `FHE.le(3000, 100)` | `ebool(false)` — balance insufficient |
| 4b | `FHE.select(false, 3000, 0)` | `euint64(0)` — zeroed out by balance check |
| 4c | Alice: `100 - 0 = 100` | Unchanged |
| 4d | Charlie: `0 + 0 = 0` | Unchanged |

> **Important:** In this scenario the allowance **was** deducted (5000 → 2000) even though the transfer didn't happen. This is a design tradeoff — reverting based on the balance check would leak information about Alice's balance. The allowance deduction is a privacy cost.

### Why Not Just One Check?

You might wonder: why not check both conditions in a single `select`? Because the two checks serve different purposes and operate on different data:

1. **Allowance check** — protects the **owner** from unauthorized spending
2. **Balance check** — protects against **underflow** in the owner's balance

Both must be encrypted and both must silent-zero to avoid leaking whether it was the allowance or the balance that blocked the transfer.

### Allowance Permission Update

After deducting the allowance, `transferFrom` needs to update permissions. In the current implementation, the allowance permission dance happens implicitly because the allowance mapping is updated and the `_transfer` function handles balance permissions. A production implementation would also re-grant allowance permissions:

```solidity
// After allowance deduction
FHE.allowThis(_allowances[from][msg.sender]);
FHE.allow(_allowances[from][msg.sender], from);       // Owner can still see
FHE.allow(_allowances[from][msg.sender], msg.sender);  // Spender can still see
```

## 4. Gas Considerations for FHE Operations

FHE operations are computationally expensive. Understanding gas costs helps you design efficient contracts:

| Operation Type | Approximate Gas Cost | Notes |
|---------------|---------------------|-------|
| Plaintext ERC20 transfer | ~50k gas | Standard Solidity |
| Confidential `_transfer` | ~300-500k gas | 4-6 FHE operations |
| Confidential `transferFrom` | ~500-800k gas | 7-10 FHE operations (double protection) |
| Single `FHE.add` / `FHE.sub` | ~50-80k gas | Basic arithmetic |
| `FHE.le` (comparison) | ~80-100k gas | Returns `ebool` |
| `FHE.select` | ~80-100k gas | Encrypted ternary |
| `FHE.asEuint64` | ~30-50k gas | Trivial encryption |
| `FHE.allowThis` / `FHE.allow` | ~20-30k gas | ACL updates |

### Optimization Tips

1. **Minimize FHE operations** — Each encrypted operation adds significant gas. Batch where possible.
2. **Keep public what can be public** — `totalSupply` is public because minting is a transparent event. Don't encrypt values that don't need privacy.
3. **Use `FHE.asEuint64(0)` instead of storing zero** — Trivial encryption of 0 is cheaper than maintaining a stored encrypted zero.
4. **Consider batch operations** — If you need to perform multiple transfers, a batch function can amortize some overhead.

## 5. The Test Suite Walkthrough

The ConfidentialERC20 contract comes with a comprehensive 8-test suite. Let's walk through the key tests.

### Running the Tests

```bash
forge test --match-contract ConfidentialERC20Test -vvv
```

### Test 1: Mint and Check Balance

```solidity
function test_mintUpdatesBalance() public {
    token.mint(alice, 1_000_000);
    vm.prank(alice);
    assertEq(mockDecrypt64(token.balanceOf()), 1_000_000);
}
```

**What it verifies:** Minting creates encrypted balances correctly. After minting 1,000,000 tokens to Alice, she can decrypt her balance and see the correct amount. This validates:
- `FHE.asEuint64()` (trivial encryption)
- `FHE.add()` on encrypted balances
- Correct `FHE.allow` grants (Alice can decrypt)

### Test 2: Transfer with Sufficient Balance

```solidity
function test_transferMovesBalance() public {
    token.mint(alice, 1_000_000);
    (externalEuint64 handle, bytes memory proof) = mockEncrypt64(400_000);
    vm.prank(alice);
    token.transfer(bob, handle, proof);

    vm.prank(alice);
    assertEq(mockDecrypt64(token.balanceOf()), 600_000);
    vm.prank(bob);
    assertEq(mockDecrypt64(token.balanceOf()), 400_000);
}
```

**What it verifies:** A normal transfer works correctly. Alice sends 400,000 to Bob, ending up with 600,000. Both parties' balances are correctly updated and decryptable. This validates:
- The full `_transfer` flow
- `FHE.sub` on sender, `FHE.add` on receiver
- Permission dance on both parties

### Test 3: Transfer with Insufficient Balance (Silent Fail)

```solidity
function test_transferInsufficientBalanceSilentFails() public {
    token.mint(alice, 100);
    (externalEuint64 handle, bytes memory proof) = mockEncrypt64(999);
    vm.prank(alice);
    token.transfer(bob, handle, proof);

    vm.prank(alice);
    assertEq(mockDecrypt64(token.balanceOf()), 100);  // Unchanged!
    vm.prank(bob);
    assertEq(mockDecrypt64(token.balanceOf()), 0);     // Nothing transferred
}
```

**What it verifies:** The silent-zero pattern works — the transaction **does not revert**, Alice's balance is unchanged, and Bob receives nothing. This is the most important privacy property: an observer cannot tell whether the transfer had sufficient funds.

### Test 4: Approve and TransferFrom

This test validates the full approval + delegated transfer flow:

```solidity
function test_approveAndTransferFrom() public {
    // Setup: Mint tokens to Alice
    token.mint(alice, 1_000_000);

    // Alice approves Bob for some amount
    (externalEuint64 approveHandle, bytes memory approveProof) = mockEncrypt64(500_000);
    vm.prank(alice);
    token.approve(bob, approveHandle, approveProof);

    // Bob transfers from Alice to Charlie
    (externalEuint64 transferHandle, bytes memory transferProof) = mockEncrypt64(300_000);
    vm.prank(bob);
    token.transferFrom(alice, charlie, transferHandle, transferProof);

    // Verify balances
    vm.prank(alice);
    assertEq(mockDecrypt64(token.balanceOf()), 700_000);  // 1M - 300k
    vm.prank(charlie);
    assertEq(mockDecrypt64(token.balanceOf()), 300_000);   // Received 300k
}
```

**What it verifies:** The complete delegated transfer cycle:
1. Alice approves Bob (encrypted allowance)
2. Bob calls `transferFrom` (double protection: allowance + balance)
3. Alice's balance decreases, Charlie receives tokens
4. Both the allowance check and balance check passed

### The Full 8-Test Suite

| # | Test | What It Verifies |
|---|------|-----------------|
| 1 | `test_mintUpdatesBalance` | Minting creates correct encrypted balances |
| 2 | `test_mintUpdatesTotalSupply` | Public `totalSupply` tracks minted amounts |
| 3 | `test_transferMovesBalance` | Normal transfer updates both sender and receiver |
| 4 | `test_transferInsufficientBalanceSilentFails` | Silent-zero on insufficient balance (no revert) |
| 5 | `test_approveAndTransferFrom` | Full approve → transferFrom cycle works |
| 6 | `test_transferFromInsufficientAllowance` | Silent-zero when allowance is too low |
| 7 | `test_transferFromInsufficientBalance` | Silent-zero when balance is too low (even if allowance is high) |
| 8 | `test_multipleTransfersAccumulate` | Sequential transfers correctly accumulate |

### The Test Pattern (Recap)

Every test follows the same rhythm established in Weeks 1 and 2:

```
1. Setup      →  token.mint(user, amount)
2. Encrypt    →  mockEncrypt64(value)
3. Call       →  vm.prank(user); token.function(args)
4. Decrypt    →  mockDecrypt64(token.balanceOf())
5. Assert     →  assertEq(decrypted, expected)
```

The `vm.prank(user)` calls are essential — they set `msg.sender` so the contract knows which balance to read/write and which permissions apply.

## 6. Running the Full Suite

Run the complete test suite:

```bash
forge test --match-contract ConfidentialERC20Test -vvv
```

Expected output: **8 tests pass**. If any test fails, check:

1. **Permission errors** — Did you forget `allowThis` or `allow` somewhere?
2. **Wrong balance** — Is the silent-zero logic selecting the right branch?
3. **Revert on transfer** — Are you accidentally reverting instead of silent-zeroing?

### What `-vvv` Shows You

The verbose flag shows you the FHE operations being executed:
- Each `FHE.add`, `FHE.sub`, `FHE.le`, `FHE.select` call and its arguments
- The `FHE.allowThis` and `FHE.allow` ACL grants
- Gas used per test (helpful for understanding FHE costs)

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| Encrypted approve | Set allowances readable by both owner and spender — dual `FHE.allow` |
| Double protection | Two layered silent-zero checks (allowance + balance) in `transferFrom` |
| `mapping(a => mapping(b => euint64))` | Nested encrypted mappings for per-owner-per-spender allowances |
| Gas: ~300-500k per transfer | FHE operations cost 5-10x more than plaintext — design accordingly |
| Allowance deduction tradeoff | Allowance may be consumed even if balance check fails — privacy cost |

---

## Key Takeaways

1. **Encrypted approvals need dual-party permissions** — both the owner and spender must be able to decrypt the allowance, requiring two `FHE.allow` calls
2. **`transferFrom` uses double protection** — two sequential silent-zero checks (allowance, then balance) ensure neither check leaks information about which one failed
3. **Nested encrypted mappings** (`mapping(a => mapping(b => euint64))`) work just like regular nested mappings — but each stored value is an encrypted handle
4. **FHE gas costs are 5-10x higher** than plaintext — plan your contract design to minimize encrypted operations
5. **The allowance deduction tradeoff** means allowance may be consumed even when balance is insufficient — this is intentional for privacy
6. **The 8-test suite** covers: minting, transfers, silent-zero on insufficient balance, approvals, transferFrom with double protection, and accumulation across multiple operations

---

## Exercise: Encrypted Total Supply

Before moving to the homework, try this extension. Modify `ConfidentialERC20` to track `totalSupply` as an **encrypted** value:

```solidity
euint64 private _encryptedTotalSupply;

function mint(address to, uint64 amount) external onlyOwner {
    euint64 encAmount = FHE.asEuint64(amount);
    _balances[to] = FHE.add(_balances[to], encAmount);
    _encryptedTotalSupply = FHE.add(_encryptedTotalSupply, encAmount);

    // Allow anyone to see total supply (or restrict to owner)
    FHE.allowThis(_encryptedTotalSupply);
    FHE.allow(_encryptedTotalSupply, owner);
    // ... rest of permissions
}
```

Think about:
- Should `_encryptedTotalSupply` be visible to everyone or just the owner?
- How does encrypting the total supply change the gas cost of `mint`?
- What privacy does this add? (Hint: observers can no longer see how many tokens exist)

---

**Next:** [Homework: Extended ConfidentialERC20](/week-3/homework) — Extend the token with encrypted total supply, burn functionality, and more advanced features.
