# Capstone Homework: Vickrey (Second-Price) Auction

**Estimated time:** 6-8 hours | **Difficulty:** Advanced | **Points:** 100 (+ up to 30 bonus)

---

## Problem Statement

In a standard sealed-bid auction, the highest bidder wins and pays their bid. But this creates a problem: bidders are incentivized to **underbid** their true valuation, because paying your full valuation means zero surplus. The economic ideal is for bidders to reveal their **true willingness to pay** — and that's exactly what a **Vickrey auction** achieves.

In a **Vickrey (second-price) auction**:
- Bidders submit sealed bids (just like `SealedBidAuction`)
- The **highest** bidder wins
- But the winner pays the **second-highest** bid, not their own

This design is incentive-compatible — bidding your true value is a dominant strategy, because you'll never pay more than the second-highest bid. It's the mechanism behind Google's ad auctions, spectrum sales, and many real-world procurement systems.

Your task is to build `VickreyAuction.sol` — a sealed-bid auction contract where the winner pays the second-highest price. This is the capstone project that ties together **every FHE pattern** you've learned across the entire bootcamp:

| Week | Pattern | How You'll Use It |
|------|---------|------------------|
| Week 1 | `FHE.fromExternal`, `FHE.allowThis`, `FHE.allow` | Verify inputs, manage permissions |
| Week 2 | `FHE.le` → `FHE.select` (silent-zero) | Minimum bid enforcement |
| Week 3 | Trivial encryption, multi-party ACL | Convert plaintext thresholds, dual-party permissions |
| Week 4 | `FHE.gt`, `FHE.select`, `eaddress`, state machine | Encrypted ranking with dual tracking |

### Why This Is Hard

The `SealedBidAuction` from Lesson 1 tracked one encrypted value: the highest bid. Your Vickrey auction must track **two**: the highest bid AND the second-highest bid. Every time a new bid arrives, you need to determine where it fits in the ranking — and update both values accordingly. This requires careful conditional logic with `FHE.gt` and `FHE.select`, all operating on ciphertext.

---

## Requirements

### Contract: `VickreyAuction`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract VickreyAuction is ZamaEthereumConfig {
    // TODO: Implement
}
```

### State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `auctioneer` | `address` | The auction creator (set in constructor) |
| `itemDescription` | `string` | Description of the item being auctioned |
| `phase` | `Phase` (enum) | Current auction phase: `Bidding`, `Closed`, `Revealed` |
| `biddingEndTime` | `uint256` | Timestamp when bidding closes |
| `minimumBid` | `uint64` | Minimum bid amount (plaintext, public) |
| `_bids` | `mapping(address => euint64)` | Encrypted bid per bidder |
| `hasBid` | `mapping(address => bool)` | Whether an address has bid |
| `bidders` | `address[]` | List of all bidder addresses |
| `_highestBid` | `euint64` | Encrypted highest bid |
| `_secondHighestBid` | `euint64` | Encrypted second-highest bid |
| `_highestBidder` | `eaddress` | Encrypted address of the highest bidder |
| `winningBid` | `uint64` | Revealed second-highest price (the price the winner pays) |
| `winner` | `address` | Revealed winner address |

### Phase Enum

```solidity
enum Phase { Bidding, Closed, Revealed }
```

Same three-phase system as `SealedBidAuction`. Use the same `inPhase` modifier pattern.

### Constructor

```solidity
constructor(string memory description_, uint256 biddingDuration_, uint64 minimumBid_)
```

- Sets `auctioneer` to `msg.sender`
- Sets `itemDescription` to `description_`
- Sets `biddingEndTime` to `block.timestamp + biddingDuration_`
- Sets `minimumBid` to `minimumBid_`
- Sets `phase` to `Phase.Bidding`

### Functions

#### `placeBid`

```solidity
function placeBid(externalEuint64 encBid, bytes calldata inputProof)
    external
    inPhase(Phase.Bidding)
```

This is the core function and the hardest part of the project. It must:

1. Revert if the sender has already bid (plaintext check — safe to revert)
2. Verify the encrypted input with `FHE.fromExternal`
3. **Minimum bid enforcement** (silent-reject): if the bid is below `minimumBid`, silently replace it with zero so it has no effect on the ranking
4. Store the bid and grant ACL (`allowThis` + `allow(msg.sender)`)
5. **Dual tracking**: update both `_highestBid` and `_secondHighestBid`

**The dual tracking logic** is the key challenge. Here's the algorithm:

```
If this is the first bid:
    _highestBid = bid
    _highestBidder = encrypted(msg.sender)
    _secondHighestBid = 0

Else:
    isHigher = bid > _highestBid?

    If bid > _highestBid:
        _secondHighestBid = old _highestBid     (old first becomes second)
        _highestBid = bid
        _highestBidder = encrypted(msg.sender)

    Else (bid <= _highestBid):
        isSecond = bid > _secondHighestBid?
        _secondHighestBid = max(bid, _secondHighestBid)
```

In FHE, this translates to:

```solidity
ebool isHigher = FHE.gt(bid, _highestBid);

// Update second-highest: if new bid is highest, old highest becomes second
// If new bid is NOT highest, it might still beat the current second
euint64 newSecond = FHE.select(isHigher, _highestBid, FHE.max(bid, _secondHighestBid));
_secondHighestBid = newSecond;

// Update highest bid and bidder
_highestBid = FHE.select(isHigher, bid, _highestBid);
_highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
```

::: warning The FHE.max Trick
`FHE.max(bid, _secondHighestBid)` handles the case where the new bid isn't highest but might be second-highest. If the bid is between second and first, it becomes the new second. If it's below the current second, the second stays unchanged. `FHE.max` handles both cases in a single operation — no branching needed.
:::

6. Grant ACL on all three tracked values: `FHE.allowThis` on `_highestBid`, `_secondHighestBid`, and `_highestBidder`
7. Emit `BidPlaced(address indexed bidder)`

#### `closeAuction`

```solidity
function closeAuction() external onlyAuctioneer inPhase(Phase.Bidding)
```

- Reverts if `block.timestamp < biddingEndTime`
- Transitions to `Phase.Closed`
- Grants `FHE.allow` to the auctioneer on `_highestBid`, `_secondHighestBid`, and `_highestBidder`
- Emits `AuctionClosed()`

#### `revealWinner`

```solidity
function revealWinner(uint64 secondPrice_, address winner_)
    external
    onlyAuctioneer
    inPhase(Phase.Closed)
```

- Sets `winningBid` to `secondPrice_` (the **second-highest** bid — this is what the winner pays)
- Sets `winner` to `winner_`
- Transitions to `Phase.Revealed`
- Emits `AuctionRevealed(address indexed winner, uint64 secondPrice)`

::: tip Vickrey Reveal
Notice that `revealWinner` takes the **second** price, not the first. The winner's actual bid remains private — they only pay the second-highest amount. This is the defining feature of a Vickrey auction.
:::

#### `getMyBid`

```solidity
function getMyBid() external view returns (euint64)
```

- Returns the caller's own encrypted bid
- Only the caller has ACL permission to decrypt

#### `getSecondHighestBid`

```solidity
function getSecondHighestBid() external view returns (euint64)
```

- Returns the encrypted second-highest bid
- Only the auctioneer can decrypt (after `closeAuction`)

#### `getBidderCount`

```solidity
function getBidderCount() external view returns (uint256)
```

- Returns the number of bidders (plaintext — this is public information)

---

## Starter Code

A starter template with the contract skeleton is available at:

```
starter/week-4/
```

The starter contains imports, state variables, the phase enum, modifiers, events, errors, and function signatures. You need to implement the function bodies — especially the dual-tracking logic in `placeBid`.

## Test Suite

A pre-written test suite is provided. Run it with:

```bash
forge test --match-contract VickreyAuctionTest -vvv
```

The test suite covers:

| Test | What It Verifies |
|------|-----------------|
| Single bid sets highest and second = 0 | First bidder initialization |
| Two bids: higher bid wins, second tracks correctly | Basic dual tracking |
| Three bids: highest, second, and non-contending | Full ranking with three bidders |
| Winner pays second price, not their own | The Vickrey property |
| Bid below minimum is silently rejected | Minimum bid enforcement |
| Phase enforcement: no bids after close | State machine works correctly |
| Bidder can see own bid only | Per-bidder ACL |
| Only auctioneer can close/reveal | Access control |
| Cannot close before deadline | Timing enforcement |
| Duplicate bid from same address reverts | One-bid-per-address rule |
| Second-highest bid accessible after close | ACL on `_secondHighestBid` |

::: tip Goal
All tests in the provided test suite must pass. The dual-tracking tests are the most important — they verify that both `_highestBid` and `_secondHighestBid` update correctly across multiple bid sequences.
:::

---

## Grading Rubric

| Category | Points | Criteria |
|----------|--------|----------|
| **Correctness** | 40 | All provided tests pass. Contract compiles without errors. The winner pays the second-highest price. |
| **FHE Patterns** | 25 | Correct use of `FHE.gt` / `FHE.select` for dual tracking. `FHE.max` or equivalent for second-highest update. `FHE.ge` for minimum bid enforcement. Proper `allowThis` / `allow` on all three tracked values. |
| **State Machine** | 15 | Proper three-phase enforcement. `FHE.allow` on winner data only granted at close. Timing enforcement on `closeAuction`. |
| **Code Quality** | 20 | NatSpec documentation on contract and all functions. Clean structure with section comments. No compiler warnings. Consistent naming with `SealedBidAuction`. |
| **Total** | **100** | |

---

## Bonus Challenges

Earn up to **30 extra points** by implementing one or more of these extensions:

### Bonus A: Deposit & Refund Mechanism (10 pts)

Require bidders to stake ETH as collateral alongside their encrypted bid:

- `placeBid` becomes `payable`, requiring `msg.value >= DEPOSIT_AMOUNT`
- Add a `mapping(address => uint256) public deposits` to track deposited ETH
- After reveal, losers can call `claimRefund()` to get their deposit back
- The winner's deposit is transferred to the auctioneer (or held as partial payment)
- Use the public `winner` address to determine eligibility — only non-winners can claim refunds

```solidity
function claimRefund() external {
    require(phase == Phase.Revealed, "Not revealed yet");
    require(msg.sender != winner, "Winner cannot claim refund");
    uint256 amount = deposits[msg.sender];
    require(amount > 0, "Nothing to refund");
    deposits[msg.sender] = 0;
    payable(msg.sender).transfer(amount);
}
```

::: tip Why Plaintext Deposits?
The deposit is in plaintext ETH — it doesn't reveal the bid amount. You could require a fixed deposit for all bidders (e.g., 1 ETH) regardless of bid size. This way the deposit leaks no information about the encrypted bid.
:::

### Bonus B: Multi-Item Auctions (10 pts)

Support auctioning multiple items simultaneously with a single contract:

- Accept `uint8 itemCount_` in the constructor
- Convert all bid storage to item-indexed mappings:
  ```solidity
  mapping(uint8 => mapping(address => euint64)) private _bids;
  mapping(uint8 => euint64) private _highestBids;
  mapping(uint8 => euint64) private _secondHighestBids;
  mapping(uint8 => eaddress) private _highestBidders;
  ```
- `placeBid(uint8 itemId, externalEuint64 encBid, bytes calldata inputProof)` — bid on a specific item
- Allow bidders to bid on multiple items (but only once per item)
- `revealWinner` takes an `itemId` parameter

### Bonus C: Encrypted Reserve Price (10 pts)

Allow the auctioneer to set a secret minimum acceptable price:

- Add `euint64 private _reservePrice` set in the constructor via `FHE.asEuint64(reservePrice_)`
- In `closeAuction`, check if `_highestBid >= _reservePrice` using `FHE.ge`
- If the reserve isn't met, the auction resolves with no winner
- The reserve price is **never** publicly revealed — not even after the auction ends
- Add a `bool public reserveMet` flag set during close

::: warning Privacy of the Reserve
The reserve price must stay encrypted even after the auction. If the auction fails (reserve not met), observers know the highest bid was below the reserve — but they don't know by how much. This is acceptable information leakage because the auction failure itself is a public event.
:::

---

## Hints

::: details Hint 1: Start from SealedBidAuction
Copy `SealedBidAuction.sol` as your starting point. The structure is nearly identical — same phases, same modifiers, same events. The key additions are: `_secondHighestBid`, the dual-tracking logic in `placeBid`, and the minimum bid check.
:::

::: details Hint 2: The Dual Tracking Is Two Select Calls + One Max
Don't overcomplicate the dual tracking. You need exactly:
- `FHE.gt(bid, _highestBid)` — one comparison
- `FHE.select(isHigher, _highestBid, FHE.max(bid, _secondHighestBid))` — update second
- `FHE.select(isHigher, bid, _highestBid)` — update first
- `FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder)` — update bidder

The `FHE.max` call handles the "is this bid the new second-highest?" case automatically. No additional comparisons needed.
:::

::: details Hint 3: Initialize _secondHighestBid to Zero
On the first bid, set `_secondHighestBid = FHE.asEuint64(0)`. This means if there's only one bidder, the second-highest bid is zero — and the winner pays zero. This is actually correct Vickrey behavior: with no competition, the winner pays nothing (or the minimum bid, if you enforce it on the payment as well).
:::

::: details Hint 4: Minimum Bid Uses FHE.ge, Not a Revert
The minimum bid check must be **silent** — don't revert if the bid is too low. Use `FHE.ge(bid, FHE.asEuint64(minimumBid))` to check, then `FHE.select` to replace the bid with zero if it fails. A zero bid will never beat any real bid in the ranking, so it's effectively ignored.
:::

::: details Hint 5: Order of Operations in placeBid
Follow this exact order:
1. Check `hasBid` (revert if duplicate — plaintext, safe)
2. `FHE.fromExternal` (verify input)
3. Minimum bid check (silent-zero)
4. Store bid + ACL
5. Dual tracking update (first bidder vs subsequent)
6. `FHE.allowThis` on all three tracked values
7. Emit event

Getting the order wrong — especially storing the bid before the minimum check — will cause test failures.
:::

---

## Concepts You'll Practice

This capstone project uses patterns from every week of the bootcamp:

| Pattern | Source | How You'll Use It |
|---------|--------|------------------|
| `FHE.fromExternal()` | Week 1 | Verify every encrypted bid input |
| `FHE.allowThis()` + `FHE.allow()` | Week 1 | Permission dance on bids, highest, second, bidder |
| `FHE.le()` / `FHE.ge()` → `FHE.select()` | Week 2 | Minimum bid enforcement (silent-zero) |
| `FHE.asEuint64()` | Week 3 | Trivially encrypt minimum bid for comparison |
| `FHE.gt()` + `FHE.select()` | Week 4 | Encrypted ranking — dual tracking |
| `eaddress` + `FHE.asEaddress()` | Week 4 | Encrypted winner identity |
| State machine (Phase enum) | Week 4 | Three-phase auction lifecycle |
| Deferred permissions | Week 4 | `FHE.allow` to auctioneer only at close |
| `FHE.max()` | New | Efficiently update second-highest bid |

---

## Submission Checklist

Before submitting, verify:

- [ ] `forge build` compiles without warnings
- [ ] `forge test --match-contract VickreyAuctionTest -vvv` — all tests pass
- [ ] `placeBid` enforces minimum bid via silent-zero (not revert)
- [ ] `placeBid` correctly updates both `_highestBid` and `_secondHighestBid`
- [ ] Duplicate bids from the same address revert
- [ ] `closeAuction` grants `FHE.allow` on all three tracked values to the auctioneer
- [ ] `revealWinner` publishes the **second-highest** price (not the highest)
- [ ] Phase enforcement works: no bids after close, no close before deadline
- [ ] Each bidder can only see their own bid
- [ ] NatSpec comments on the contract, constructor, and every function

---

## Congratulations! :tada:

If you've made it here and all your tests pass — **you've completed the FHEVM Bootcamp**.

Over four weeks, you've gone from zero FHE knowledge to building a production-grade Vickrey auction with:

- **Encrypted state management** — balances, bids, and addresses hidden on a public blockchain
- **Silent-zero patterns** — privacy-preserving error handling that never leaks information via reverts
- **Encrypted comparisons and conditionals** — `FHE.gt`, `FHE.le`, `FHE.select`, `FHE.max` operating entirely on ciphertext
- **Multi-party ACL** — fine-grained permission control over who can decrypt what, and when
- **State machine design** — phase-based flow control with deferred permission grants
- **Dual encrypted tracking** — maintaining two ranked encrypted values simultaneously

These are the exact same patterns used in **Zama Auction** (the first app on Zama Protocol mainnet), in confidential DeFi protocols, in private governance systems, and in every production FHEVM application.

### What's Next?

You now have the skills to build confidential smart contracts for real-world deployment. Here are some ideas to keep building:

- **Confidential AMM** — A constant-product market maker with encrypted reserves and swap amounts
- **Private Governance** — Encrypted voting with delegation, quorum thresholds, and time-locked execution
- **Sealed-Bid NFT Marketplace** — Combine your auction skills with NFT transfers
- **Confidential Lending** — Encrypted collateral ratios, liquidation thresholds, and interest calculations
- **Dark Pool Exchange** — An order-matching engine where orders and fills are fully encrypted

The FHEVM ecosystem is young, and the builders who understand these patterns today will shape the confidential blockchain of tomorrow.

**Welcome to the future of on-chain privacy. Go build something amazing.**

---

<div style="display: flex; justify-content: space-between; margin-top: 2rem;">
  <a href="/week-4/">← Week 4 Overview</a>
  <a href="/week-4/instructor">Instructor Notes →</a>
</div>
