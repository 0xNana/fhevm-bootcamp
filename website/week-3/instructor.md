# Instructor Notes: Week 3

**Audience:** Instructors running cohort-based workshops **or** self-paced learners checking their own understanding.

---

## Teaching Tips & Pacing

### Recommended Session Structure (~3 hours live)

| Block | Duration | Content |
|-------|----------|---------|
| Week 2 Review | 15 min | Recap silent-fail, le → select → sub, per-user state |
| ERC20 Side-by-Side | 20 min | Compare standard ERC20 vs ConfidentialERC20 structure |
| Trivial Encryption | 15 min | `FHE.asEuint64` and why `mint` needs it |
| Live-Coding \_transfer | 35 min | Build the transfer with silent-zero, step by step |
| Break | 10 min | |
| Encrypted Approvals | 25 min | The three-party permission problem in `approve` |
| transferFrom Double Protection | 20 min | Layered silent-zero guards — allowance + balance |
| Gas Discussion | 10 min | Real-world cost implications of FHE operations |
| Homework Kickoff | 15 min | Extended ERC20 requirements, burn and cap patterns |
| Q&A Buffer | 5 min | |

### Key Teaching Moments

**Compare ERC20 and ConfidentialERC20 side by side.** Put the standard `_transfer` next to the encrypted `_transfer` on the board or a split screen. The shape is the same — the "business logic" is identical. The difference is *how* each step is implemented:

| Standard ERC20 | ConfidentialERC20 |
|----------------|-------------------|
| `require(amount <= balance)` | `FHE.le(amount, balance)` |
| `if (condition)` | `FHE.select(condition, ...)` |
| `balance -= amount` | `FHE.sub(balance, amount)` |
| `balances[to] += amount` | `FHE.add(balances[to], amount)` |

This makes the encrypted version feel less alien — it's the same contract with encrypted primitives.

**Trivial encryption (`FHE.asEuint64`) is a key concept.** In `mint`, the owner specifies a plaintext amount. But `_balances[to]` is encrypted. To add them, you need both operands in the encrypted domain. `FHE.asEuint64(amount)` converts the plaintext into an encrypted handle. The analogy: "You're putting a known value into a sealed envelope so it can ride the encrypted pipeline."

**The `_transfer` function is the heart of the contract.** Everything else feeds into it. Spend real time on it — the silent-zero pattern here is the exact same `le → select → sub` from Week 2, but now there are *two* balance updates (sender decreases, receiver increases) and *four* ACL calls. Walk through it methodically.

**Double protection in `transferFrom` is the culmination of everything learned.** It's two layered `le → select` guards — first checking the allowance, then checking the balance. Both produce silent-zero outcomes. If the allowance is insufficient, the actual amount becomes zero. If the balance is insufficient, the actual amount becomes zero. The subtraction then operates on zero, which is a harmless no-op.

**Gas considerations become real here.** A single `transfer` in a standard ERC20 costs ~50k gas. A ConfidentialERC20 `transfer` costs ~300-500k gas because of the FHE operations. `transferFrom` with its double protection costs even more. This isn't a bug — it's the cost of privacy. Discuss how this affects DeFi UX: batch operations, gas sponsorship, L2 considerations.

---

## Common Student Mistakes

### 1. Using `require(balance >= amount)` to check encrypted balances

**Symptom:** Compilation fails with a type error — `euint64` can't be compared with `>=`.

**Why it happens:** Students are so used to the ERC20 pattern that they instinctively write plaintext comparisons. The Solidity compiler catches this, but the error message isn't always clear.

**How to fix:** Remind students of the fundamental rule: **you cannot use Solidity comparison operators on encrypted types.** The only way to compare encrypted values is through `FHE.le`, `FHE.gt`, etc. These return `ebool`, which can only be consumed by `FHE.select`.

### 2. Not understanding that `FHE.asEuint64(0)` creates an encrypted zero

**Symptom:** Students write `euint64(0)` or just `0` where they need an encrypted zero for the `select` fallback.

**Why it happens:** `FHE.asEuint64(0)` looks verbose for "just zero." Students try to shortcut it.

**How to fix:** Explain that `FHE.select(cond, amount, 0)` won't compile — the third argument must be `euint64`, not `uint64`. `FHE.asEuint64(0)` is the trivial encryption of zero. It produces a proper encrypted handle containing zero, which the coprocessor can use in select operations. There's no shortcut.

### 3. Allowance permissions needing THREE parties

**Symptom:** The `approve` function works, but either the owner or the spender can't decrypt the allowance value.

**Why it happens:** In `approve`, the allowance needs to be readable by both the owner (`msg.sender`) and the spender. Plus the contract needs `allowThis` to use it in `transferFrom`. That's three `FHE.allow*` calls:

```solidity
FHE.allowThis(_allowances[msg.sender][spender]);   // Contract can use it
FHE.allow(_allowances[msg.sender][spender], msg.sender);  // Owner can decrypt
FHE.allow(_allowances[msg.sender][spender], spender);     // Spender can decrypt
```

Students often forget the spender's permission or the owner's permission.

**How to fix:** Draw the three-party diagram. Ask: "Who needs to *compute* on this value?" (The contract — `allowThis`.) "Who needs to *see* this value?" (Both owner and spender — two `allow` calls.)

### 4. Forgetting to handle the burn case where totalSupply needs updating

**Symptom:** Burn reduces the user's balance but `_encryptedTotalSupply` stays unchanged (or vice versa for mint).

**Why it happens:** Students focus on the per-user balance logic and forget the aggregate. Especially in the extended homework, where `_encryptedTotalSupply` is new state that wasn't in the base contract.

**How to fix:** Suggest a mental checklist for any state-mutating function: "What *all* state variables does this function touch?" For `burn`: `_balances[msg.sender]` AND `_encryptedTotalSupply`. For `mint`: `_balances[to]` AND `_encryptedTotalSupply`. Both need full ACL treatment.

---

## Discussion Questions

1. **"How would you build a DEX with encrypted order amounts?"**
   *Target answer:* An order book DEX needs to match buy and sell orders by price. With encrypted amounts, you'd need to compare encrypted prices using `FHE.le/gt` and match orders using `FHE.select`. The challenge is that order matching is O(n) comparisons — each one is an expensive FHE operation. An AMM (constant-product) model might be more practical since it only needs a few FHE operations per swap.

2. **"What's the tradeoff between privacy and gas costs in a high-volume token?"**
   *Target answer:* Every transfer costs 5-10x more gas than a standard ERC20. For a stablecoin with millions of daily transfers, this could be prohibitive. Possible mitigations: L2/rollup deployment (lower base gas), batching operations, hybrid models where only large transfers are encrypted, or waiting for FHE hardware acceleration. The discussion naturally previews Week 4's deployment considerations.

3. **"Could you combine this with a standard ERC20 wrapper for interoperability?"**
   *Target answer:* Yes — you could build a "wrapper" contract where users deposit standard ERC20 tokens and receive confidential ERC20 tokens. When they want to exit, they burn confidential tokens and receive standard tokens. The wrapper itself needs to be trusted (it sees the amounts at wrap/unwrap time), but all intermediate transfers are private. This is analogous to WETH wrapping ETH.

4. **"In `transferFrom`, why do we check the allowance *before* the balance?"**
   *Target answer:* Order matters for the double protection pattern. If you check the balance first and it passes, but the allowance check fails, the `actualAmount` becomes zero. You'd then subtract zero from both the balance and allowance — harmless. But if you check the balance first, you've already computed `FHE.sub(balance, amount)` *before* learning the allowance was insufficient. The allowance-first order lets you zero out the amount early, avoiding unnecessary FHE operations. Both orderings are *correct* privacy-wise, but allowance-first is more gas-efficient.

---

## Cohort Mode: Live-Coding Segments

### Build the `_transfer` Function (~35 min)

Start with an empty `_transfer` and let students drive:

**Step 1 — Function signature (3 min):**
```solidity
function _transfer(address from, address to, euint64 amount) internal {
    // What's the first thing we need to check?
}
```

**Step 2 — Silent-zero guard (10 min):**
```solidity
    // Can the sender afford this transfer?
    ebool hasFunds = FHE.le(amount, _balances[from]);
    euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));
```
Pause. Ask: "If `hasFunds` is false, what is `actualAmount`?" (Encrypted zero.) "So what happens when we subtract zero?" (Nothing — the balance is unchanged.) "Does the transaction revert?" (No — this is the silent-zero pattern.)

**Step 3 — Balance updates (10 min):**
```solidity
    // Debit sender
    _balances[from] = FHE.sub(_balances[from], actualAmount);
    FHE.allowThis(_balances[from]);
    FHE.allow(_balances[from], from);

    // Credit receiver
    _balances[to] = FHE.add(_balances[to], actualAmount);
    FHE.allowThis(_balances[to]);
    FHE.allow(_balances[to], to);
```
Ask: "Why does the receiver also need `allowThis`?" (Because they might transfer these tokens later — the contract needs permission to compute on their balance in a future transaction.)

**Step 4 — Compile and test (10 min):**
Run the transfer tests. Show the test that transfers more than the balance — it succeeds with a zero transfer. Show `-vvv` output to prove the balance didn't change.

### Encrypted Approvals Walk-Through (~25 min)

Instead of live-coding `approve` from scratch, project the finished code and walk through it. Focus on the three-party permission problem — it's unique to `approve` and hasn't appeared before:

```solidity
function approve(address spender, externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
    _allowances[msg.sender][spender] = amount;

    // THREE permissions needed:
    FHE.allowThis(_allowances[msg.sender][spender]);    // Contract reads it in transferFrom
    FHE.allow(_allowances[msg.sender][spender], msg.sender); // Owner can see their own allowance
    FHE.allow(_allowances[msg.sender][spender], spender);    // Spender can see what they're allowed
}
```

---

## Self-Paced Mode: Checkpoint Milestones

### CP1: ConfidentialERC20 Structure
- [ ] Can map each ConfidentialERC20 function to its standard ERC20 equivalent
- [ ] Understand why `mint` uses `FHE.asEuint64(amount)` — trivial encryption
- [ ] Can explain the silent-zero transfer pattern in one sentence
- **Self-check:** What would happen if `_transfer` used `require` instead of `FHE.select`?

### CP2: Transfer Logic Understood
- [ ] Can trace through `_transfer` for a successful transfer (amount <= balance)
- [ ] Can trace through `_transfer` for a failed transfer (amount > balance) — no revert
- [ ] Understand why both sender's and receiver's balances need `allowThis` + `allow`
- **Self-check:** After a silent-zero transfer, does the sender's balance change? Does the receiver's?

### CP3: Approvals and transferFrom
- [ ] Understand the three-party permission model in `approve`
- [ ] Can explain the double protection in `transferFrom` (allowance check + balance check)
- [ ] All ConfidentialERC20 tests pass
- **Self-check:** In `transferFrom`, if the allowance is sufficient but the balance isn't, what happens?

### CP4: Extended ERC20 Started
- [ ] Opened `starter/week-3/src/ConfidentialERC20Extended.sol`
- [ ] Can identify which existing functions need modification (mint, _transfer)
- [ ] The `burn` function at minimum compiles
- **Self-check:** How many `FHE.le → FHE.select` guards does the modified `_transfer` have? (Answer: two — cap check and balance check.)

---

## Homework Answer Key Notes

### ConfidentialERC20Extended — Key Implementation Details

**The `burn` function is EncryptedVault.withdraw in disguise.** The `le → select → sub` chain is identical. Students who completed Week 2 should recognize the pattern immediately:

```solidity
function burn(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    // Silent-zero: don't revert if amount > balance
    ebool canBurn = FHE.le(amount, _balances[msg.sender]);
    euint64 actualAmount = FHE.select(canBurn, amount, FHE.asEuint64(0));

    // Update user balance
    _balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);
    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);

    // Update encrypted total supply
    _encryptedTotalSupply = FHE.sub(_encryptedTotalSupply, actualAmount);
    FHE.allowThis(_encryptedTotalSupply);
    FHE.allow(_encryptedTotalSupply, owner);

    emit Burn(msg.sender);
}
```

**The cap check in `_transfer` goes BEFORE the balance check.** This is the most common ordering mistake. The cap check zeros out the amount if it exceeds the cap. The balance check then sees either the original amount (within cap) or zero (exceeded cap). If students reverse the order, a transfer that exceeds the cap but is within the balance slips through.

```solidity
// CORRECT order: cap first, then balance
if (transferCap > 0) {
    euint64 encCap = FHE.asEuint64(transferCap);
    ebool withinCap = FHE.le(amount, encCap);
    amount = FHE.select(withinCap, amount, FHE.asEuint64(0));
}
ebool hasFunds = FHE.le(amount, _balances[from]);
euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));
```

**Edge case — `transferCap == 0` means no cap.** Students sometimes implement the cap check unconditionally, which means `FHE.asEuint64(0)` becomes the cap — effectively blocking all transfers. The `if (transferCap > 0)` guard is a plaintext check that's critical.

**Edge case — `_encryptedTotalSupply` initialization.** Before the first `mint`, this is `bytes32(0)`. `FHE.add(bytes32(0), amount)` works correctly — the FHE library treats uninitialized handles as zero. Students don't need to initialize it in the constructor.

**Bonus A (totalBurned tracker):** Straightforward — it mirrors `_encryptedTotalSupply` but only increases on burn. The invariant `_encryptedTotalSupply + _totalBurned == cumulative_minted` holds but can only be verified by the owner who has decrypt permission on both values.

**Bonus B (increaseAllowance/decreaseAllowance):** `decreaseAllowance` uses the silent-zero pattern — if the decrease exceeds the current allowance, set the allowance to zero rather than reverting. The triple ACL (`allowThis` + `allow(owner)` + `allow(spender)`) must be applied to the result.

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-3/homework">← Homework: Extended ERC20</a>
  <a href="/week-4/">Week 4 →</a>
</div>
