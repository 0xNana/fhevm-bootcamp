# Lesson 1: Building a Confidential ERC20 Token

**Duration:** ~75 minutes | **Prerequisites:** [Week 2](/week-2/) completed | **Contract:** `src/ConfidentialERC20.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Understand **why** confidential tokens matter and what privacy problems they solve
- Implement a full ERC20-like token with **encrypted balances** using `mapping(address => euint64)`
- Use **`FHE.asEuint64()`** (trivial encryption) to convert plaintext values into encrypted handles
- Handle encrypted transfers with the **silent-zero pattern** — never revert on insufficient balance
- Trace the `_transfer` internal function step by step
- Master the **"permission dance"** — why `allowThis` + `allow` must follow every balance update

---

## 1. Why Confidential Tokens?

On standard ERC20 tokens, everyone can see:
- How many tokens you hold
- Every transfer you make and receive
- Your approval allowances

This is a massive privacy issue. Imagine your salary being paid on-chain — your employer, coworkers, and the entire internet can see exactly how much you earn.

A **Confidential ERC20** encrypts all balances and transfer amounts. The token appears as a normal ERC20 from the outside, but the numbers are hidden.

### What Changes, What Stays the Same

The *interface* of a Confidential ERC20 looks familiar — `mint`, `transfer`, `approve`, `transferFrom`, `balanceOf`. But under the hood, every numeric value is an encrypted handle. Let's see the full picture:

| Feature | Standard ERC20 | Confidential ERC20 |
|---------|---------------|-------------------|
| Balance type | `uint256` (public) | `euint64` (encrypted) |
| Transfer amount | Public | Encrypted |
| Allowance | Public | Encrypted |
| Insufficient balance | `revert` | Silent zero transfer |
| `balanceOf(addr)` | Returns plaintext | Returns encrypted handle |
| Decryption | N/A | Off-chain, permission-based |
| Gas cost | ~50k | ~300-500k (FHE ops) |

The gas difference is significant. Each FHE operation (add, subtract, compare, select) costs roughly 5-10x more than its plaintext equivalent. This is the cost of privacy — and it's why FHEVM contracts are designed to minimize the number of encrypted operations.

## 2. The Contract: `ConfidentialERC20.sol`

Open `src/ConfidentialERC20.sol`. Here's the full interface:

```solidity
contract ConfidentialERC20 is ZamaEthereumConfig {
    string public name;
    string public symbol;
    uint8 public constant decimals = 6;
    address public owner;

    mapping(address => euint64) private _balances;
    mapping(address => mapping(address => euint64)) private _allowances;
    uint64 public totalSupply;    // Plaintext — mint amounts are public

    function mint(address to, uint64 amount) external onlyOwner { ... }
    function transfer(address to, externalEuint64 encAmount, bytes calldata inputProof) external { ... }
    function approve(address spender, externalEuint64 encAmount, bytes calldata inputProof) external { ... }
    function transferFrom(address from, address to, externalEuint64 encAmount, bytes calldata inputProof) external { ... }
    function balanceOf() external view returns (euint64) { ... }
}
```

Compare this to the `EncryptedVault` from Week 2:

| Week 2 (EncryptedVault) | Week 3 (ConfidentialERC20) |
|--------------------------|----------------------------|
| `mapping(address => euint64) _balances` | Same, plus `mapping(address => mapping(address => euint64)) _allowances` |
| `deposit` / `withdraw` | `mint` / `transfer` / `approve` / `transferFrom` |
| Single-user operations | Multi-party operations (sender, receiver, spender) |
| Withdraw caps at balance | Transfer silently sends zero |
| One permission per op | Permission dance on both parties |

The core ACL pattern from Week 2 — `allowThis` + `allow` after every mutation — carries forward. But now you're managing permissions across **multiple parties** in a single transaction.

## 3. Minting: Plaintext to Encrypted

Let's start with the simplest function — `mint`:

```solidity
function mint(address to, uint64 amount) external onlyOwner {
    euint64 encAmount = FHE.asEuint64(amount);
    _balances[to] = FHE.add(_balances[to], encAmount);

    FHE.allowThis(_balances[to]);
    FHE.allow(_balances[to], to);

    totalSupply += amount;
}
```

This function introduces a new FHE operation you haven't seen before.

### `FHE.asEuint64()` — Trivial Encryption

`FHE.asEuint64(amount)` converts a **plaintext** `uint64` value into an **encrypted** `euint64` handle. Under the hood, it calls `trivialEncrypt(value, FheType.Uint64)` on the coprocessor.

**Why do you need it?** You can't mix plaintext and encrypted values in FHE operations:

```solidity
// ❌ IMPOSSIBLE — type mismatch
_balances[to] = FHE.add(_balances[to], 5);

// ✅ CORRECT — both operands are euint64
_balances[to] = FHE.add(_balances[to], FHE.asEuint64(5));
```

**When to use it:** Whenever you need to operate on a mix of plaintext and encrypted values. Common scenarios:
- Minting (plaintext amount + encrypted balance)
- Comparing against zero: `FHE.asEuint64(0)`
- Setting thresholds or caps with known values

### The Mint Flow

Let's trace `mint(alice, 1_000_000)`:

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.asEuint64(1_000_000)` | New encrypted handle `enc(1000000)` |
| 2 | `FHE.add(_balances[alice], enc(1000000))` | New handle = old balance + 1000000 |
| 3 | `FHE.allowThis(newHandle)` | Contract can use this handle in future txns |
| 4 | `FHE.allow(newHandle, alice)` | Alice can decrypt her balance off-chain |
| 5 | `totalSupply += 1_000_000` | Plaintext increment (public) |

### Design Decision: Public vs Private Minting

In our design, `totalSupply` is public and `mint` amounts are visible. This is intentional — the initial distribution is transparent, but subsequent transfers are private.

An alternative design could encrypt `totalSupply` too, making even the total supply private. You'll explore this in the homework exercise.

## 4. Encrypted Transfers and the Silent-Zero Pattern

Now for the heart of the contract — the `_transfer` internal function. This is where Week 2's silent-fail pattern evolves into the **silent-zero pattern**:

```solidity
function _transfer(address from, address to, euint64 amount) internal {
    // Step 1: Check balance (encrypted comparison)
    ebool hasFunds = FHE.le(amount, _balances[from]);

    // Step 2: If insufficient, set amount to zero (no revert!)
    euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));

    // Step 3: Update balances
    _balances[from] = FHE.sub(_balances[from], actualAmount);
    FHE.allowThis(_balances[from]);
    FHE.allow(_balances[from], from);

    _balances[to] = FHE.add(_balances[to], actualAmount);
    FHE.allowThis(_balances[to]);
    FHE.allow(_balances[to], to);
}
```

### Comparing Silent-Zero vs Silent-Fail (Week 2 Recap)

In Week 2's vault, the withdraw function **capped** the amount at the balance:

```solidity
// Week 2: Cap at balance (withdraw everything)
euint64 actualAmount = FHE.select(canWithdraw, amount, _balances[msg.sender]);
```

In the confidential token, we use a different approach — **zero out** the transfer:

```solidity
// Week 3: Zero out (transfer nothing)
euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));
```

**Why the difference?** In a vault withdrawal, the user is asking for their own money. Giving them as much as possible is reasonable. In a token transfer, silently sending a different amount than requested would be confusing — better to send **nothing** and let both parties check their balances.

```
Traditional ERC20:  if (amount > balance) revert("Insufficient balance");
Confidential ERC20: actualAmount = hasFunds ? amount : 0;  // encrypted select
```

**Why?** If the transaction reverts on insufficient balance, an observer knows the sender's balance is below the transfer amount. By always succeeding (just transferring 0 when insufficient), no balance information leaks.

Both sender and receiver can check whether the transfer "worked" by decrypting their balances after the transaction.

### Step-by-Step: `_transfer(alice, bob, 400_000)` with Balance = 1_000_000

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(400_000, 1_000_000)` | `ebool(true)` — Alice has enough |
| 2 | `FHE.select(true, 400_000, 0)` | `euint64(400_000)` — use requested amount |
| 3 | `FHE.sub(1_000_000, 400_000)` | Alice's new balance: `600_000` |
| 4 | `FHE.add(bob_balance, 400_000)` | Bob's new balance: `400_000` |
| 5 | Permission dance on both balances | Both users can decrypt, contract can reuse |

### Step-by-Step: `_transfer(alice, bob, 999)` with Balance = 100

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.le(999, 100)` | `ebool(false)` — Alice doesn't have enough |
| 2 | `FHE.select(false, 999, 0)` | `euint64(0)` — zero out the transfer |
| 3 | `FHE.sub(100, 0)` | Alice's balance unchanged: `100` |
| 4 | `FHE.add(bob_balance, 0)` | Bob's balance unchanged: `0` |
| 5 | Permission dance on both balances | Handles still updated (new handles!) |

Notice that in the insufficient-balance case, the transaction still **succeeds**. Both balances get new handles (even though the values didn't change), and permissions are re-granted. An observer watching the blockchain sees an identical-looking transaction in both cases.

## 5. The Public `transfer` Function

The public `transfer` function wraps `_transfer` with input verification:

```solidity
function transfer(address to, externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
    _transfer(msg.sender, to, amount);
}
```

This follows the same pattern from Weeks 1 and 2:
1. **Verify** — `FHE.fromExternal()` validates the encrypted input and proof
2. **Compute** — `_transfer()` performs the encrypted balance update
3. **Authorize** — permissions are granted inside `_transfer()`

The caller encrypts the transfer amount client-side and submits it along with a ZK proof. The contract never sees the plaintext amount.

## 6. The "Permission Dance" — A Deep Dive

You've seen `allowThis` + `allow` in Week 2, but the confidential token makes it especially clear why **both** calls are essential on **both** parties:

```solidity
// Inside _transfer — sender's balance update
_balances[from] = FHE.sub(_balances[from], actualAmount);
FHE.allowThis(_balances[from]);   // ← Contract can use sender's new balance
FHE.allow(_balances[from], from); // ← Sender can decrypt their new balance

// Inside _transfer — receiver's balance update
_balances[to] = FHE.add(_balances[to], actualAmount);
FHE.allowThis(_balances[to]);     // ← Contract can use receiver's new balance
FHE.allow(_balances[to], to);     // ← Receiver can decrypt their new balance
```

### Why Both Calls on Both Parties?

Remember the **new-handle rule** from Week 2: every FHE operation produces a new handle. The old handle's permissions are gone.

```
  ┌──────────────────────────────────────────────────────────────┐
  │          After _transfer(alice, bob, 400_000)                │
  │                                                              │
  │  _balances[alice] = new Handle_A2  (was Handle_A1)           │
  │    ├── FHE.allowThis(Handle_A2)  → Contract can operate      │
  │    └── FHE.allow(Handle_A2, alice) → Alice can decrypt       │
  │                                                              │
  │  _balances[bob] = new Handle_B2  (was Handle_B1)             │
  │    ├── FHE.allowThis(Handle_B2)  → Contract can operate      │
  │    └── FHE.allow(Handle_B2, bob) → Bob can decrypt           │
  │                                                              │
  │  Handle_A1 and Handle_B1 are now ORPHANED — unusable         │
  └──────────────────────────────────────────────────────────────┘
```

### What Happens If You Forget?

| Missing Call | Consequence |
|-------------|-------------|
| `allowThis` on sender | Next transfer **from** this sender reverts — contract can't read balance |
| `allow` on sender | Sender can't decrypt their own balance after transfer |
| `allowThis` on receiver | Next transfer **from** this receiver reverts — contract can't read balance |
| `allow` on receiver | Receiver can't decrypt to confirm they received tokens |

This is verbose but essential. Every balance-mutating function in the contract **must** include the full permission dance for every balance it touches.

## 7. Reading Balances

The `balanceOf` function is elegantly simple:

```solidity
function balanceOf() external view returns (euint64) {
    return _balances[msg.sender];
}
```

Note the difference from standard ERC20:
- **Standard ERC20:** `balanceOf(address owner)` — anyone can query anyone's balance
- **Confidential ERC20:** `balanceOf()` — returns the caller's own encrypted handle (no address parameter)

The caller gets back an encrypted handle. They can only decrypt it if they were granted `FHE.allow` — which happens automatically during `mint` and `_transfer`.

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| `FHE.asEuint64(value)` | Trivial encrypt: convert plaintext to encrypted for mixed-mode operations |
| Silent-zero transfer | Never revert on insufficient balance — silently transfer 0 to preserve privacy |
| `_transfer` internal function | Encrypted compare → select → subtract/add with full permission dance |
| Permission dance (both parties) | `allowThis` + `allow` on **sender** and **receiver** after every transfer |
| Public `totalSupply`, private balances | Transparent distribution, private subsequent activity |

---

## Key Takeaways

1. **Confidential tokens encrypt balances, amounts, and allowances** — from the outside, the token looks normal but every number is hidden
2. **`FHE.asEuint64()`** bridges plaintext and ciphertext — use it whenever you need to mix known values with encrypted ones
3. The **silent-zero pattern** transfers 0 instead of reverting on insufficient balance — this prevents observers from binary-searching balances
4. The **permission dance** (`allowThis` + `allow`) must happen on **every** balance touched by every operation — forgetting either one breaks future transactions or prevents decryption
5. **Gas costs are 5-10x higher** than plaintext ERC20 — each FHE operation costs ~300-500k gas vs ~50k for standard operations
6. **New handles mean new permissions** — the old handle is orphaned after every FHE operation; always re-authorize

---

**Next:** [Lesson 2: Advanced Patterns — Approvals, Double Protection & Testing](/week-3/lesson-2-advanced) — Learn encrypted `approve`, `transferFrom` with double protection, and walk through the full test suite.
