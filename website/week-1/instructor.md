# Instructor Notes: Week 1

**Audience:** Instructors running cohort-based workshops **or** self-paced learners checking their own understanding.

---

## Teaching Tips & Pacing

### Recommended Session Structure (~3 hours live)

| Block | Duration | Content |
|-------|----------|---------|
| Opening | 15 min | The "why" — privacy leaks in standard Ethereum |
| FHE Theory | 30 min | Lesson 1 concepts, HTTPS analogy, coprocessor model |
| Setup & First Test | 20 min | Foundry install, `forge build`, `forge test` |
| Live-Coding FHECounter | 45 min | Build from scratch (see live-coding section below) |
| Break | 10 min | |
| ACL Deep Dive | 20 min | `allowThis` vs `allow`, the new-handle rule |
| Homework Kickoff | 15 min | Walk through EncryptedPoll requirements, show starter code |
| Q&A Buffer | 15 min | Address confusion, revisit coprocessor model if needed |

### Key Teaching Moments

**Start with the "why."** Students who understand *why* FHE matters will push through the learning curve. Open with a concrete example: go to Etherscan, show a token transfer — the sender, receiver, and exact amount are all visible. Ask: "Would you use this to pay your salary?" This motivates everything that follows.

**The HTTPS analogy is your best friend.** HTTPS encrypts data *in transit* but the server sees plaintext. FHE encrypts data *in compute* — the server (EVM) never sees plaintext. Students immediately grasp why this is a bigger deal.

**The coprocessor model is the key "aha" moment.** Draw this on the board:

```
User encrypts → EVM stores handle (bytes32) → Coprocessor does math on ciphertext → New handle returned
```

Emphasize: the EVM is just a *routing layer*. It never touches the plaintext. Encrypted values are opaque `bytes32` handles — like a claim ticket for your encrypted data.

**Don't rush ACL.** It's the most misunderstood concept in Week 1. Students think `FHE.allow` is like a getter — it's not. It grants *off-chain decrypt permission*. The contract still needs `allowThis` separately to *compute* on the value in future transactions. Dedicate at least 15 minutes to walking through what happens when you forget each call.

**Show `forge test` verbosity levels.** Run the same test three times: default, `-v`, and `-vvv`. Students are often surprised by how much information `-vvv` reveals — call traces, gas usage, and revert reasons. This is their primary debugging tool for the rest of the bootcamp.

---

## Common Student Mistakes

### 1. Forgetting `FHE.allowThis()` after arithmetic

**Symptom:** Contract compiles, first operation works, second operation fails with a cryptic "not allowed" error.

**Why it happens:** `FHE.add` produces a *new* handle. The old handle had `allowThis` permission, but the new one doesn't. Students assume permissions "carry over."

**How to fix:** Emphasize the **new-handle rule** — draw it out:

```
_count (handle 0x1) → FHE.add → new_count (handle 0x2)
                                  ↑ has NO permissions yet!
```

### 2. Confusing `euint32` (internal) vs `externalEuint32` (user input)

**Symptom:** Students use `euint32` as a function parameter for user input, or skip `FHE.fromExternal` entirely.

**Why it happens:** Both types "look like encrypted integers." Students don't realize `externalEuint32` is an *unverified* ciphertext that must pass through `FHE.fromExternal` before the coprocessor will accept it.

**How to fix:** Use the analogy: `externalEuint32` is an unopened envelope with no postmark. `FHE.fromExternal` is the post office verifying and stamping it. Only stamped mail (`euint32`) can enter the system.

### 3. Not calling `FHE.allow(result, msg.sender)`

**Symptom:** The contract updates state correctly, but when the user tries to decrypt their value off-chain, they get a permission error.

**Why it happens:** Students confuse *contract* access (`allowThis`) with *user* access (`allow`). The contract can compute on the value, but no one can read it.

**How to fix:** Remind students: `allowThis` = "the contract can use this value in future calls." `allow(addr)` = "this address can decrypt it off-chain." Both are almost always needed together.

### 4. Trying to read encrypted values directly

**Symptom:** Students try `uint32(counter.getCount())` or expect `console.log` to print the encrypted value.

**Why it happens:** `euint32` looks like it should be a number. In mock mode, it even *is* a number under the hood, which deepens the confusion.

**How to fix:** In mock mode, show them `FHE.decrypt32(handle)` from the test helper. Then explain: in production, this doesn't exist — decryption is an off-chain operation requiring ACL permission. The test helper is a convenience, not a representation of how real contracts work.

---

## Discussion Questions

Use these to gauge understanding and spark deeper thinking:

1. **"If the EVM never sees the actual data, how can the contract compute on it?"**
   *Target answer:* The EVM delegates computation to the coprocessor, which operates on ciphertexts. The EVM only routes handles back and forth. This naturally leads into discussing the trust model of the coprocessor.

2. **"What would happen if you forgot `allowThis`? When would you discover the bug?"**
   *Target answer:* The first operation works (because the initial value is created by the contract). The *second* operation fails — the contract no longer has permission to read its own state. In mock mode you'd see a revert; in real mode it could be more subtle.

3. **"How is the coprocessor model different from zero-knowledge proofs?"**
   *Target answer:* ZK proves a statement is true without revealing the data. FHE computes on encrypted data and returns an encrypted result. ZK = "I can prove I'm over 18 without showing my ID." FHE = "You can compute my age + your age without either of us revealing our age."

4. **"Why does FHECounter use `euint32` instead of `euint64` or `euint256`?"**
   *Target answer:* Gas costs scale with bit width. A 32-bit encrypted operation costs less than 64-bit. For a counter that won't exceed ~4 billion, 32 bits is sufficient. This previews Week 3's gas discussion.

---

## Cohort Mode: Live-Coding Segments

### Build FHECounter from Scratch (~45 minutes)

Start with an empty file. Write each piece incrementally, pausing to explain and take questions.

**Step 1 — Skeleton (5 min):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract FHECounter {
    // What goes here?
}
```
Ask students: "What do we need to import?" Guide them to the FHE library and config.

**Step 2 — Imports & Config (5 min):**
```solidity
import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract FHECounter is ZamaEthereumConfig {
    euint32 private _count;
}
```
Pause and ask: "Why is `_count` typed as `euint32`, not `uint32`?"

**Step 3 — The getter (3 min):**
```solidity
function getCount() external view returns (euint32) {
    return _count;
}
```
Explain: this returns a *handle*, not a number. The caller needs ACL permission to decrypt.

**Step 4 — Increment, one operation at a time (15 min):**

Write `FHE.fromExternal` first. Compile. Then add `FHE.add`. Compile. Then `FHE.allowThis`. Compile. Finally `FHE.allow`. Compile. Run `forge test` after each addition — show that earlier versions fail and explain *why*.

**Step 5 — Decrement (5 min):**
Let a student dictate the code. It's identical to increment but with `FHE.sub`.

**Step 6 — Run the full test suite (10 min):**
```bash
forge test --match-contract FHECounterTest -vvv
```
Walk through the test output. Highlight the encrypt → call → decrypt test pattern.

---

## Self-Paced Mode: Checkpoint Milestones

Use these checkpoints to verify understanding at each stage. If a checkpoint feels unclear, re-read the referenced lesson before moving on.

### CP1: Environment Ready
- [ ] Foundry installed (`forge --version` outputs a version)
- [ ] Repo cloned and `forge build` succeeds with no errors
- [ ] `forge test` runs and all pre-existing tests pass
- **Self-check:** Can you explain what `foundry.toml` and the `remappings` entry do?

### CP2: FHE Conceptual Understanding
- [ ] Can explain what a `euint32` handle is (it's a `bytes32` reference, not a number)
- [ ] Can describe the coprocessor model in one sentence
- [ ] Can explain the difference between `allowThis` and `allow`
- **Self-check:** Draw the lifecycle of an encrypted value from user input to decrypted output.

### CP3: FHECounter Tests Pass
- [ ] Read through `FHECounter.sol` line by line — no line is confusing
- [ ] `forge test --match-contract FHECounterTest -vvv` — all green
- [ ] Completed the `multiply` exercise from Lesson 3
- **Self-check:** Can you add a `resetCount` function that sets `_count` to an encrypted zero?

### CP4: EncryptedPoll Compiles
- [ ] Opened `starter/week-1/src/EncryptedPoll.sol` and read the skeleton
- [ ] Implemented at least the `vote` function body
- [ ] `forge build` compiles without errors
- **Self-check:** Does your `vote` function include *both* `allowThis` and `allow(owner)`?

---

## Homework Answer Key Notes

### EncryptedPoll — Key Implementation Details

**The one-vote-per-address check must come *before* the FHE operations.** This is the most common mistake. Students who check `_hasVoted` after `FHE.add` waste gas on encrypted computation that gets reverted anyway. The correct order is:

```solidity
function vote(uint8 questionId, externalEuint32 encVote, bytes calldata inputProof) external {
    require(questionId < questionCount, "Invalid question");
    require(!_hasVoted[msg.sender][questionId], "Already voted");  // ← plaintext check FIRST

    euint32 verified = FHE.fromExternal(encVote, inputProof);
    _voteCounts[questionId] = FHE.add(_voteCounts[questionId], verified);

    FHE.allowThis(_voteCounts[questionId]);
    FHE.allow(_voteCounts[questionId], owner);

    _hasVoted[msg.sender][questionId] = true;
}
```

**Edge case — uninitialized vote counts:** The first vote on any question calls `FHE.add` on an uninitialized `euint32` (which is `bytes32(0)`). The FHE library treats this as zero, so it "just works." Some students try to pre-initialize the mappings in the constructor — this isn't wrong, but it's unnecessary and wastes gas.

**Edge case — ACL on every update:** Every call to `vote` produces a new handle for `_voteCounts[questionId]`. Students who only set ACL permissions in the constructor (or only on the first vote) will see failures on the second vote for the same question.

**Bonus A (revealResults):** The tricky part is that if students defer `FHE.allow(owner)` until `revealResults()`, they need to loop through all questions and grant permission on each `_voteCounts[questionId]`. This means storing `questionCount` and iterating — a pattern they haven't seen yet. Some students will store the handles in an array instead; either approach is valid.

**Bonus B (weighted voting):** The zero-check for unregistered voters requires `FHE.ne(_weights[voter], FHE.asEuint32(0))` and then `FHE.select` to default to 1. Some students will try a plaintext `if` check on the mapping value — this doesn't work because an uninitialized `euint32` is `bytes32(0)`, not the number 0, and you can't branch on it.

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-1/homework">← Homework: EncryptedPoll</a>
  <a href="/week-2/">Week 2 →</a>
</div>
