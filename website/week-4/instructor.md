# Instructor Notes: Week 4

**Audience:** Instructors running cohort-based workshops **or** self-paced learners checking their own understanding.

---

## Teaching Tips & Pacing

### Recommended Session Structure (~3.5 hours live)

| Block | Duration | Content |
|-------|----------|---------|
| Week 3 Review | 10 min | Recap ConfidentialERC20 patterns, double protection |
| Real-World Context | 10 min | Zama Auction as the first mainnet FHEVM app |
| State Machine Design | 20 min | Draw the three-phase diagram, discuss phase transitions |
| `eaddress` Introduction | 10 min | Encrypted addresses — new type, same patterns |
| Live-Coding placeBid | 30 min | Incremental winner tracking with `FHE.gt` + `FHE.select` |
| Break | 10 min | |
| Deployment Walkthrough | 30 min | `forge script`, mock vs real, live deploy to Anvil |
| fhevmjs Overview | 15 min | Client-side encryption — how the frontend talks to FHE contracts |
| Security Checklist | 15 min | Production readiness audit for FHE contracts |
| Capstone Kickoff | 20 min | Vickrey auction requirements, dual tracking challenge |
| Q&A Buffer | 10 min | |

### Key Teaching Moments

**Start with the real-world context.** Zama Auction was the first application deployed on the Zama Protocol mainnet. This isn't a toy exercise — students are building the same core logic used in production. This context motivates the complexity of the state machine and the careful ACL management.

**The state machine is the key architectural pattern.** Draw it on the board with clear transitions:

```
  Bidding ──[closeAuction()]-→ Closed ──[revealWinner()]-→ Revealed
     ↑                           ↑                            ↑
  placeBid()              FHE.allow to              winner & price
  allowed here            auctioneer here           become public
```

Emphasize that `FHE.allow` to the auctioneer is *only* granted at `closeAuction`. During bidding, nobody — not even the auctioneer — can decrypt any bids. This is what makes it a sealed-bid auction.

**`eaddress` is new — but the pattern is familiar.** `FHE.asEaddress(msg.sender)` works exactly like `FHE.asEuint64(amount)` — it trivially encrypts a plaintext value. The only difference is the type. Students who understood trivial encryption in Week 3 will grasp `eaddress` immediately.

**The incremental tracking pattern is more gas-efficient than batch comparison.** Some students will ask: "Why not store all bids and compare them at close time?" The answer: that would require O(n) comparisons at close time, where n is the number of bidders. Each comparison is an expensive FHE operation. Instead, we compare each new bid against the current highest *when it arrives*. This amortizes the cost across all `placeBid` calls — O(1) per bid.

**Deployment section: emphasize that mock ≠ production.** The Solidity code is identical, but everything around it changes:
- Real encryption (not plaintext-in-bytes32)
- Real ACL enforcement (not always-allow)
- Real gas costs (FHE operations are expensive)
- Client-side encryption with `fhevmjs` (not test helpers)
- KMS-based decryption (not direct cast)

Show the `.env` switch from `FHEVM_MOCK=true` to `FHEVM_MOCK=false` and walk through what changes under the hood.

---

## Common Student Mistakes

### 1. Second-highest tracking — only updating when a new highest is found

**Symptom:** When three bids arrive in descending order (100, 80, 60), the second-highest correctly becomes 80. But when three bids arrive in ascending order (60, 80, 100), the second-highest incorrectly stays at 60 instead of becoming 80.

**Why it happens:** Students write the update logic as:

```solidity
// WRONG: only updates second when new highest found
if (bid > highest) {
    second = highest;  // old first becomes second
    highest = bid;
}
// Missing: what if bid > second but bid <= highest?
```

The bid of 80 isn't higher than 100, so the `if` block is skipped — but 80 *is* higher than the current second (60). Without the `FHE.max` trick, this case is missed.

**How to fix:** The correct FHE pattern handles both cases in one expression:

```solidity
ebool isHigher = FHE.gt(bid, _highestBid);

// If bid is new highest: old highest becomes second
// If bid is NOT highest: take max(bid, currentSecond)
_secondHighestBid = FHE.select(isHigher, _highestBid, FHE.max(bid, _secondHighestBid));

_highestBid = FHE.select(isHigher, bid, _highestBid);
_highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
```

The `FHE.max(bid, _secondHighestBid)` is the key insight — it handles the "bid falls between first and second" case automatically.

### 2. Using `FHE.max` instead of `FHE.select` for the highest bid update

**Symptom:** The highest bid tracks correctly, but the `_highestBidder` address doesn't update in sync.

**Why it happens:** Students write `_highestBid = FHE.max(bid, _highestBid)` — which correctly gives the higher value but doesn't produce an `ebool` for branching. Without the `isHigher` boolean, they can't conditionally update `_highestBidder`.

**How to fix:** You need `FHE.gt` to get the comparison result as an `ebool`, then use `FHE.select` three times — once each for `_highestBid`, `_secondHighestBid`, and `_highestBidder`. All three must branch on the same `isHigher` value:

```solidity
ebool isHigher = FHE.gt(bid, _highestBid);
// Use isHigher for ALL three select operations
```

### 3. Not handling the first-bid edge case

**Symptom:** The first bid triggers an `FHE.gt` against an uninitialized `_highestBid` (which is `bytes32(0)`), producing undefined behavior or unexpected results.

**Why it happens:** Before any bids, `_highestBid` is zero. The comparison `FHE.gt(bid, 0)` should return true for any positive bid, but students don't always reason through the initialization path.

**How to fix:** Handle the first bid separately with a `bidders.length == 0` check (a plaintext check — safe):

```solidity
if (bidders.length == 0) {
    _highestBid = bid;
    _highestBidder = FHE.asEaddress(msg.sender);
    _secondHighestBid = FHE.asEuint64(0);
} else {
    // Normal dual-tracking logic
}
```

This is a plaintext branch (based on array length, not ciphertext) — perfectly safe and much clearer than relying on uninitialized handle behavior.

### 4. Phase enforcement bugs in `revealWinner`

**Symptom:** `revealWinner` can be called during the bidding phase, or `placeBid` works after the auction is closed.

**Why it happens:** Students implement the `inPhase` modifier but forget to apply it to one or more functions. Or they apply it to `closeAuction` but not `revealWinner`.

**How to fix:** Use a checklist approach — every public function should explicitly document which phase it requires:

```solidity
function placeBid(...)     external inPhase(Phase.Bidding)   { ... }
function closeAuction()    external inPhase(Phase.Bidding)   { ... }
function revealWinner(...)  external inPhase(Phase.Closed)    { ... }
function getMyBid()        external view                      { ... } // Any phase
```

---

## Discussion Questions

1. **"What happens in a Vickrey auction if all bids are equal?"**
   *Target answer:* `_highestBid` and `_secondHighestBid` both equal the common bid amount. The "winner" is whichever bidder happened to be tracked as highest (likely the first bidder, due to `FHE.gt` returning false for equal values). They pay the second-highest price, which equals their own bid. This is mathematically correct Vickrey behavior — with no competition advantage, the winner pays their bid.

2. **"How would you add a reserve price without revealing it?"**
   *Target answer:* Store the reserve as `euint64 private _reservePrice = FHE.asEuint64(reservePrice_)` in the constructor. At `closeAuction`, use `FHE.ge(_highestBid, _reservePrice)` to produce an `ebool`. Use `FHE.select` to conditionally set the winner to the zero address if the reserve isn't met. The reserve price is never revealed — the only information leaked is whether the auction succeeded or failed (which is a public event anyway). This is Bonus C in the homework.

3. **"What are the security implications of the auctioneer being able to decrypt?"**
   *Target answer:* After `closeAuction`, the auctioneer can decrypt `_highestBid`, `_secondHighestBid`, and `_highestBidder`. They must honestly report these values to `revealWinner`. A malicious auctioneer could lie — but since the encrypted values are on-chain, any party with decrypt access can verify. In a production system, you'd use a multi-party decryption committee or a threshold KMS to eliminate single-party trust.

4. **"Why do we deploy with `forge script` instead of just `forge create`?"**
   *Target answer:* Scripts are reproducible, version-controlled, and can be dry-run before spending gas. They can also handle multi-contract deployments, constructor arguments, and post-deployment setup. For FHE contracts specifically, scripts let you automate the initial ACL setup that's needed after deployment.

---

## Cohort Mode: Live-Coding Segments

### Deploy FHECounter to Local Anvil (~30 min)

This is the deployment walkthrough. Use FHECounter (not the auction) — it's simpler and lets students focus on the deployment mechanics rather than the contract logic.

**Step 1 — Show the deployment script (5 min):**
```solidity
// script/Deploy.s.sol
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/FHECounter.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        FHECounter counter = new FHECounter();
        console.log("FHECounter deployed at:", address(counter));
        vm.stopBroadcast();
    }
}
```

**Step 2 — Start a local Anvil node (3 min):**
```bash
# In a separate terminal
anvil
```
Point out: Anvil gives you 10 pre-funded accounts. Copy the first private key.

**Step 3 — Dry run (5 min):**
```bash
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY
```
Show the simulation output — gas estimates, contract address preview.

**Step 4 — Broadcast (5 min):**
```bash
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```
Show the transaction hash, contract address, and the broadcast JSON artifact.

**Step 5 — Interact with the deployed contract (10 min):**
```bash
# Call getCount (should return 0x00...00)
cast call $CONTRACT_ADDRESS "getCount()" --rpc-url http://localhost:8545

# Note: In mock mode, we can't easily increment from CLI
# because we need to encrypt the input — this is where fhevmjs comes in
```
Use this moment to explain why client-side encryption matters — you can't just pass `5` to `increment`. You need to encrypt it first.

### Auction State Machine Walk-Through (~20 min)

Instead of building the full auction live (it's too long), walk through the SealedBidAuction code on screen:

1. Show the Phase enum and `inPhase` modifier
2. Show `placeBid` — focus on `FHE.gt` and `FHE.select`
3. Show `closeAuction` — emphasize the `FHE.allow` grants happening here
4. Show `revealWinner` — the auctioneer submits decrypted values
5. Ask: "How would you add a *second* price?" — this bridges into the capstone homework

---

## Self-Paced Mode: Checkpoint Milestones

### CP1: State Machine Understood
- [ ] Can draw the three-phase lifecycle and label which functions are available in each phase
- [ ] Understand why `FHE.allow` to the auctioneer is deferred until `closeAuction`
- [ ] Can explain what `eaddress` is and how `FHE.asEaddress` works
- **Self-check:** What prevents the auctioneer from peeking at bids during the bidding phase?

### CP2: SealedBidAuction Code Understood
- [ ] Read through `SealedBidAuction.sol` — can explain every function
- [ ] Understand the incremental tracking pattern in `placeBid`
- [ ] All SealedBidAuction tests pass
- **Self-check:** Trace through three bids (50, 100, 75) and show `_highestBid` after each.

### CP3: Deployment Mechanics
- [ ] Understand the difference between mock mode and real mode (table from Lesson 2)
- [ ] Can explain what `forge script` does vs `forge create`
- [ ] Read through `script/Deploy.s.sol` and understand each step
- **Self-check:** What changes in the Solidity code when deploying to a real FHEVM network? (Answer: nothing — the config auto-detects based on chain ID.)

### CP4: Vickrey Auction Started
- [ ] Opened `starter/week-4/src/VickreyAuction.sol` and identified the dual-tracking challenge
- [ ] Can explain the algorithm for updating `_secondHighestBid` on each new bid
- [ ] The `placeBid` function at minimum compiles
- **Self-check:** Trace through three bids (60, 100, 80). What are `_highestBid` and `_secondHighestBid` after each?

---

## Homework Answer Key Notes

### Vickrey Auction — Key Implementation Details

**The dual-tracking logic is the core challenge.** Here's the complete `placeBid` pattern for subsequent bids (after the first):

```solidity
ebool isHigher = FHE.gt(bid, _highestBid);

// Second-highest update:
// - If new bid is the highest → old highest becomes second
// - If new bid is NOT highest → take max(bid, currentSecond)
_secondHighestBid = FHE.select(isHigher, _highestBid, FHE.max(bid, _secondHighestBid));

// Highest bid update: take the higher of the two
_highestBid = FHE.select(isHigher, bid, _highestBid);

// Bidder update: track who has the highest bid
_highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);

// ACL on all three values
FHE.allowThis(_highestBid);
FHE.allowThis(_secondHighestBid);
FHE.allowThis(_highestBidder);
```

**The `FHE.max` trick is essential.** Without it, students need a second comparison (`FHE.gt(bid, _secondHighestBid)`) and a nested `FHE.select`. This works but costs more gas. `FHE.max` handles both sub-cases (bid between first and second, bid below second) in one operation.

**Trace through the three-bid test case.** Students should verify their logic against this sequence:

| After Bid | `_highestBid` | `_secondHighestBid` | `_highestBidder` |
|-----------|---------------|---------------------|------------------|
| Alice: 50 | 50 | 0 | Alice |
| Bob: 100 | 100 | 50 | Bob |
| Carol: 75 | 100 | 75 | Bob |

The critical case is Carol's bid: 75 is NOT higher than 100, so `isHigher` is false. The `FHE.select` for `_secondHighestBid` takes the `else` branch: `FHE.max(75, 50) = 75`. The second-highest correctly updates from 50 to 75.

**Minimum bid enforcement uses `FHE.ge`, not a revert.** The minimum bid is public (plaintext), but the bid amount is encrypted. To compare, trivially encrypt the minimum: `FHE.asEuint64(minimumBid)`. Then use `FHE.ge(bid, encMinimum)` to check. If below minimum, replace with zero via `FHE.select`. A zero bid will never beat any real bid in the ranking.

**Edge case — single bidder Vickrey.** With one bidder, `_secondHighestBid` is zero. The winner pays zero. This is correct Vickrey behavior: with no competition, there's no second price. In a production system, you'd enforce a reserve price (Bonus C) to prevent this.

**Edge case — equal bids.** If Alice bids 100 and Bob bids 100, `FHE.gt(100, 100)` returns false. Alice remains the highest bidder. `FHE.max(100, secondHighest)` updates the second-highest to 100 (or keeps it at 100). Both tracked values are 100, and the winner (Alice) pays 100 — her own bid. This is correct: equal bids mean no surplus.

**Bonus A (deposits):** The deposit is in plaintext ETH and doesn't reveal the encrypted bid amount. Use a fixed deposit (e.g., 1 ETH) for all bidders to avoid leaking bid-size information. The `claimRefund` function is straightforward once `winner` is public.

**Bonus B (multi-item):** The state variables become item-indexed mappings. The `placeBid` logic is identical per item — just add an `itemId` parameter. The main complexity is managing ACL across multiple items in `closeAuction`.

**Bonus C (encrypted reserve):** Store as `_reservePrice = FHE.asEuint64(reservePrice_)`. At close time, `FHE.ge(_highestBid, _reservePrice)` produces an `ebool`. The auctioneer decrypts this boolean to learn whether the reserve was met. If not, the auction has no winner. The reserve amount stays encrypted forever.

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-4/homework">← Capstone: Vickrey Auction</a>
  <a href="/getting-started">Getting Started →</a>
</div>
