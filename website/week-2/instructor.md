# Instructor Notes: Week 2

**Audience:** Instructors running cohort-based workshops **or** self-paced learners checking their own understanding.

---

## Teaching Tips & Pacing

### Recommended Session Structure (~3 hours live)

| Block | Duration | Content |
|-------|----------|---------|
| Week 1 Review | 15 min | Quick recap: handles, ACL, FHECounter pattern |
| Per-User State Intro | 20 min | Why `mapping(address => euint64)` is the natural next step |
| Live-Coding Deposit | 30 min | Build EncryptedVault.deposit together (see live-coding section) |
| Break | 10 min | |
| Silent-Fail Deep Dive | 25 min | The poker analogy, why reverts leak information |
| Live-Coding Withdraw | 30 min | The le → select → sub chain, step by step |
| Testing Walkthrough | 15 min | Run tests, show -vvv output for the silent-fail case |
| Homework Kickoff | 15 min | EncryptedTipJar requirements, mapping to Vault patterns |
| Q&A Buffer | 10 min | |

### Key Teaching Moments

**Start by reviewing Week 1 patterns, then show why they're not enough.** FHECounter has a single shared state variable. Ask: "What if two users each want their own private counter?" This naturally leads to `mapping(address => euint64)` — the bridge from Week 1 to Week 2.

**Walk through the deposit function step by step.** The deposit is the simpler function — it's just `FHE.add` on a per-user mapping. Use it to reinforce Week 1 patterns in a new context before introducing the harder withdraw logic.

**Use the "sealed envelope" analogy for `FHE.select`.** Imagine you have two sealed envelopes (A and B) and a sealed coin flip result. `FHE.select` hands you one envelope without anyone seeing the coin flip or opening either envelope. Both envelopes are "processed" — but you only get one.

**The "silent-fail" concept is counterintuitive — use the poker analogy.** You're playing poker. You push all your chips in. If the casino said "insufficient funds — bet rejected" out loud, everyone at the table learns your chip count is below your bet. In FHE: if `withdraw(1000)` reverts, an observer knows your balance is below 1000. So instead, the contract silently withdraws whatever you have (possibly zero). The transaction always succeeds — no information leaked.

**The `le → select → sub` chain is the core pattern of the whole bootcamp.** Students will use this exact chain in Week 2 (vault), Week 3 (token transfers, burns), and Week 4 (minimum bids). Spend real time on it:

```solidity
// 1. Can we afford this?
ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);

// 2. If yes, use the requested amount. If no, use zero.
euint64 actualAmount = FHE.select(canWithdraw, amount, FHE.asEuint64(0));

// 3. Subtract the actual amount (possibly zero — a no-op).
_balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);
```

Ask students to trace through both scenarios (sufficient and insufficient balance) on paper.

---

## Common Student Mistakes

### 1. Not re-permissioning after arithmetic

**Symptom:** Deposit works once. Second deposit to the same user fails with an ACL error.

**Why it happens:** `FHE.add(_balances[user], amount)` creates a NEW handle. The old `_balances[user]` had `allowThis` + `allow(user)`, but the new result doesn't.

**How to fix:** This is the same "new-handle rule" from Week 1, but students need to re-learn it in the mapping context. Show the trace:

```
_balances[alice] = handle_0x1 (has permissions)
FHE.add(handle_0x1, amount) → handle_0x2 (NO permissions!)
_balances[alice] = handle_0x2
FHE.allowThis(handle_0x2)    // ← contract can use it
FHE.allow(handle_0x2, alice) // ← alice can decrypt it
```

### 2. Using `FHE.gt` instead of `FHE.le` for the withdrawal check

**Symptom:** Withdrawals with sufficient balance silently withdraw zero. Withdrawals with insufficient balance withdraw the full amount.

**Why it happens:** Students write `FHE.gt(amount, balance)` and use it in the `select` with the arguments in the "wrong" order — getting the logic inverted.

**How to fix:** Encourage students to think in terms of the *question* they're asking: "Is the amount *less than or equal to* my balance?" → `FHE.le(amount, balance)`. If true, proceed. If false, use zero. Write the English sentence first, then the code.

### 3. Forgetting to update `_totalDeposits` in both deposit and withdraw

**Symptom:** The aggregate total drifts from reality. The owner sees an incorrect total.

**Why it happens:** Students update `_totalDeposits` in `deposit` but forget to subtract from it in `withdraw` (or vice versa). It's easy to focus on the per-user balance and neglect the aggregate.

**How to fix:** Suggest students add a comment block at the top of each function listing *every* state variable that should be modified:

```solidity
function withdraw(...) external {
    // STATE CHANGES: _balances[msg.sender] (decrease), _totalDeposits (decrease)
    ...
}
```

### 4. Trying to use `require()` with encrypted conditions

**Symptom:** Students write `require(FHE.le(amount, balance))` expecting it to work like a boolean check.

**Why it happens:** `FHE.le` returns an `ebool` — an encrypted boolean. It's a handle, not a `bool`. You can't branch on it, and passing it to `require` makes no sense (the EVM can't evaluate it).

**How to fix:** Reinforce the fundamental rule: **you can never branch on ciphertext.** The `ebool` from `FHE.le` can *only* be consumed by `FHE.select`. That's it. If you find yourself writing `if (eboolValue)` or `require(eboolValue)`, you're breaking the FHE model.

---

## Discussion Questions

1. **"Why can't we just revert if the withdrawal amount is too large?"**
   *Target answer:* Reverting leaks a bit of information — the observer learns that `amount > balance`. An attacker could binary-search your balance by submitting withdraw transactions with different amounts and watching which ones revert. The silent-fail pattern ensures every withdrawal succeeds, leaking nothing.

2. **"How does this privacy model compare to Tornado Cash's approach?"**
   *Target answer:* Tornado Cash provides *transaction unlinkability* (can't connect depositor to withdrawer) but uses fixed denominations and reveals the amounts. FHEVM provides *amount confidentiality* (amounts are hidden) but transactions are linked to addresses. They solve different privacy problems and are complementary.

3. **"What attack could an observer mount if they could see whether a withdraw succeeded or failed?"**
   *Target answer:* Binary search. Withdraw 1000 — fails? Balance < 1000. Withdraw 500 — succeeds? Balance >= 500. Withdraw 750 — fails? Balance < 750. In ~20 transactions, you can narrow down any balance to within a few units. This is why silent-fail is non-negotiable.

4. **"Could a user learn *anything* about another user's balance from the contract's behavior?"**
   *Target answer:* Not from the contract directly — all operations succeed regardless of balance. However, gas costs could theoretically differ between the `select(true)` and `select(false)` paths. In practice, FHE operations have uniform gas costs by design, but this is worth discussing as a side-channel consideration.

---

## Cohort Mode: Live-Coding Segments

### Build EncryptedVault Deposit (~30 min)

Start with the contract skeleton. Build the deposit function collaboratively:

**Step 1 — State variables and constructor (5 min):**
```solidity
mapping(address => euint64) private _balances;
euint64 private _totalDeposits;
address public owner;

constructor() {
    owner = msg.sender;
}
```
Ask: "Why do we need `_totalDeposits`? Who should be able to see it?"

**Step 2 — Deposit function, input verification (5 min):**
```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
    // What next?
}
```
Let students suggest the next line. Guide them to `FHE.add`.

**Step 3 — Balance update and ACL (10 min):**
```solidity
    _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);
    FHE.allowThis(_balances[msg.sender]);
    FHE.allow(_balances[msg.sender], msg.sender);
```
Ask: "Who needs to decrypt this balance? Just the user, or the owner too?" Answer: just the user — the owner has `_totalDeposits` for aggregate visibility.

**Step 4 — Total deposits update (10 min):**
```solidity
    _totalDeposits = FHE.add(_totalDeposits, amount);
    FHE.allowThis(_totalDeposits);
    FHE.allow(_totalDeposits, owner);
```
Compile. Run the deposit test. Celebrate the green checkmark.

### Live-Code the Withdraw Function (~30 min)

This is the main event. Have students suggest each step:

1. "What do we need to check first?" → `FHE.le(amount, _balances[msg.sender])`
2. "What do we do with the `ebool`?" → `FHE.select`
3. "What are the two branches?" → `amount` if true, `FHE.asEuint64(0)` if false
4. "Now what?" → `FHE.sub` with the `actualAmount`
5. "What about ACL?" → `allowThis` + `allow` on the new balance

Run the silent-fail test and show that a withdrawal of 9999 against a balance of 100 succeeds (withdrawing 100, not reverting).

---

## Self-Paced Mode: Checkpoint Milestones

### CP1: Conceptual Understanding
- [ ] Can explain the difference between `FHE.le` and a Solidity `<=` comparison
- [ ] Can describe the silent-fail pattern in one sentence
- [ ] Can explain why `FHE.select` executes *both* branches
- **Self-check:** In your own words, why is `require(amount <= balance)` a privacy leak?

### CP2: EncryptedVault Deposit Works
- [ ] Read through the deposit function — no line is confusing
- [ ] The deposit test passes with `forge test -vvv`
- [ ] Can explain the ACL difference between `_balances` (user can decrypt) and `_totalDeposits` (owner can decrypt)
- **Self-check:** What happens if you call `deposit` twice for the same user?

### CP3: EncryptedVault Withdraw Works
- [ ] Can trace through the `le → select → sub` chain for both sufficient and insufficient balances
- [ ] All EncryptedVault tests pass, including the over-withdrawal test
- [ ] Can explain why the over-withdrawal test *succeeds* instead of reverting
- **Self-check:** What value does `actualAmount` hold when the user tries to withdraw more than they have?

### CP4: EncryptedTipJar Started
- [ ] Opened `starter/week-2/src/EncryptedTipJar.sol` and identified which functions need implementing
- [ ] The `tip` function compiles (even if not fully correct yet)
- [ ] Can map each TipJar function to its EncryptedVault equivalent
- **Self-check:** In `tip`, how many encrypted state variables need updating? (Answer: two — `_tipperTotals` and `_creatorBalance`)

---

## Homework Answer Key Notes

### EncryptedTipJar — Key Implementation Details

**The `tip` function updates TWO encrypted values.** This is the most common source of partial implementations. Students get the creator balance update right but forget the tipper total, or vice versa:

```solidity
function tip(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);

    // Update tipper's running total
    _tipperTotals[msg.sender] = FHE.add(_tipperTotals[msg.sender], amount);
    FHE.allowThis(_tipperTotals[msg.sender]);
    FHE.allow(_tipperTotals[msg.sender], msg.sender);

    // Update creator's aggregate balance
    _creatorBalance = FHE.add(_creatorBalance, amount);
    FHE.allowThis(_creatorBalance);
    FHE.allow(_creatorBalance, creator);

    emit Tip(msg.sender);
}
```

**The `withdraw` function is a copy of EncryptedVault's withdraw.** The `le → select → sub` chain is identical. The only difference: the balance variable is `_creatorBalance` instead of `_balances[msg.sender]`, and the ACL grants to `creator` instead of `msg.sender`. Students who completed the vault should find this straightforward.

**Edge case — the `msg.sender != creator` check.** This is a plaintext check and *should* revert. Students sometimes confuse this with the "no revert on encrypted conditions" rule. Clarify: you can always `require` on plaintext values. The rule is specifically about encrypted conditions — don't revert when the decision depends on ciphertext.

**Edge case — tipper total visibility.** Each tipper should only see their own total. The creator should NOT be able to decrypt individual tipper amounts (only the aggregate). If students grant `FHE.allow(_tipperTotals[tipper], creator)`, they're leaking per-tipper information — only `FHE.allow(_tipperTotals[tipper], tipper)` is correct.

**Bonus A (minimum tip):** The key insight is that `FHE.select(meetsMin, amount, FHE.asEuint64(0))` produces a value that's either the real amount or zero. If it's zero, the subsequent `FHE.add` is a no-op. The tipper's total and creator balance only meaningfully increase when the tip meets the threshold — without any party learning whether it did.

**Bonus B (tip count):** Students often try to use `uint32` for the count since "it's just a number." But the count reveals information — if someone can see they tipped 50 times, that's meaningful data. Using `euint32` keeps it private. The increment pattern is `FHE.add(_tipCounts[msg.sender], FHE.asEuint32(1))` — trivially encrypting the literal `1`.

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-2/homework">← Homework: EncryptedTipJar</a>
  <a href="/week-3/">Week 3 →</a>
</div>
