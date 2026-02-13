# Lesson 1: Building a Sealed-Bid Auction

**Duration:** ~90 minutes | **Prerequisites:** [Week 3](/week-3/) completed | **Contract:** `src/SealedBidAuction.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Understand **why sealed-bid auctions** solve front-running, sniping, and shill bidding
- Build a complete **three-phase state machine** (Bidding → Closed → Revealed) to enforce auction lifecycle rules
- Use **`eaddress`** — an encrypted Ethereum address type — to hide the winner's identity until reveal
- Use **`FHE.gt()`** for encrypted greater-than comparison to determine the highest bidder
- Use **`FHE.select()`** with multiple encrypted types to conditionally update state
- Implement **incremental winner tracking** — updating the highest bid on each `placeBid` call
- Understand **selective revelation** — only the winning bid is ever decrypted
- Connect this to the **real-world application**: Zama Auction, the first app on Zama Protocol mainnet

---

## 1. Why Sealed-Bid Auctions?

In Weeks 1–3, you built contracts where encrypted values belonged to individual users — counters, vaults, token balances. Now you're building something different: a **multi-party competitive system** where encrypted values are compared against each other to determine a winner.

In traditional on-chain auctions, all bids are visible. This creates serious problems:

- **Front-running**: Bots see your bid in the mempool and outbid you
- **Strategic underbidding**: Bidders wait to see others' bids before committing
- **Shill bidding**: Auctioneers place fake bids to drive up prices
- **Bid sniping**: Last-second bids based on seeing current highest

A **sealed-bid auction** solves all of these. Bids are encrypted — nobody (not even the auctioneer) can see them until the reveal phase. The winner is determined by encrypted comparison, and only the winning bid is ever revealed.

### Traditional vs Sealed-Bid Comparison

| Problem | Traditional Auction | Sealed-Bid (FHE) Auction |
|---------|-------------------|-------------------------|
| Front-running | Bots outbid you after seeing your tx | Bids encrypted — nothing to front-run |
| Strategic underbidding | Wait and lowball | Can't see other bids |
| Shill bidding | Fake bids drive up price | Auctioneer can't see bids either |
| Bid sniping | Last-second bid based on current highest | No "current highest" is visible |
| Winner determination | Public comparison | Encrypted `FHE.gt()` comparison |
| Bid privacy after auction | All bids public forever | Only winning bid revealed |

### Real-World Context: Zama Auction

This lesson is directly inspired by **Zama Auction**, which was the very first application launched on the Zama Protocol mainnet. Building this project demonstrates mastery of the exact patterns Zama uses in production. By the end of this lesson, you'll have built the same core logic.

## 2. The State Machine

Every auction has a lifecycle. In a traditional auction, you can enforce timing with `block.timestamp`. In a sealed-bid auction, you also need to control **who can do what, when** — because decryption permissions change across phases.

We model this as a **state machine** with three phases:

```
  ┌──────────┐       closeAuction()      ┌──────────┐    revealWinner()    ┌──────────┐
  │ Bidding  │ ─────────────────────────► │  Closed  │ ──────────────────► │ Revealed │
  │          │   (after biddingEndTime)   │          │                     │          │
  └──────────┘                            └──────────┘                     └──────────┘
       │                                       │
   placeBid()                              Auctioneer
   (any user)                             decrypts winner
```

### Three Phases

1. **Bidding** — Users place encrypted bids. Nobody can see any bid — not other bidders, not the auctioneer, not validators.
2. **Closed** — Bidding ends. The auctioneer receives permission to decrypt the winner and winning bid.
3. **Revealed** — The auctioneer publishes the winner and winning bid amount on-chain for all to see.

### Why This Matters

The state machine isn't just organizational — it's a **security boundary**. During the Bidding phase, not even the auctioneer can see the highest bid. Only after `closeAuction()` does the auctioneer get `FHE.allow` on the winner data. This is enforced by the ACL, not by trust.

Compare this to Week 2's vault pattern where permissions were granted immediately. Here, permissions are **deferred** — granted only when the state machine transitions to the appropriate phase.

## 3. Key FHE Concepts Introduced

Before we walk through the code, let's understand the three new FHE operations this contract introduces.

### `eaddress` — Encrypted Address

```solidity
eaddress private _highestBidder;
```

Just like `euint64` is an encrypted integer, `eaddress` is an encrypted Ethereum address. It's stored as a `bytes32` handle, and the plaintext address is hidden until decrypted.

**Why do we need it?** In a sealed-bid auction, we're tracking not just the highest *bid* but also the highest *bidder*. If we stored the bidder as a plaintext `address`, anyone watching the contract's state could see who's winning — defeating the purpose of sealed bids.

### `FHE.asEaddress(msg.sender)` — Trivial Address Encryption

Converts a plaintext address into an encrypted handle, similar to `FHE.asEuint64()` for integers. You saw trivial encryption in Week 3's `mint` function — this is the same concept applied to addresses:

```solidity
// Week 3: Trivially encrypt an integer
euint64 encAmount = FHE.asEuint64(amount);

// Week 4: Trivially encrypt an address
eaddress encBidder = FHE.asEaddress(msg.sender);
```

### `FHE.gt()` — Encrypted Greater-Than

```solidity
ebool isHigher = FHE.gt(bid, _highestBid);
```

Compares two encrypted values **without revealing either**. The result is an `ebool` — an encrypted boolean that can only be used in `FHE.select()`. You cannot `if (isHigher)` — the result is encrypted.

This is the key operation that makes sealed auctions possible. In Week 3 you used `FHE.le()` for balance checks. `FHE.gt()` is the mirror operation:

| Operation | Returns | Used For |
|-----------|---------|----------|
| `FHE.le(a, b)` | `ebool`: a ≤ b | Balance sufficiency checks |
| `FHE.gt(a, b)` | `ebool`: a > b | Ranking / highest-value tracking |
| `FHE.ge(a, b)` | `ebool`: a ≥ b | Minimum threshold checks |

### `FHE.select()` with Multiple Types

You already know `FHE.select()` from Week 2 and Week 3. What's new here is using it with **multiple encrypted types in the same logic**:

```solidity
_highestBid = FHE.select(isHigher, bid, _highestBid);
_highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
```

`FHE.select` works with any encrypted type — `euint64`, `eaddress`, `ebool`, etc. The condition is always an `ebool`, and the two branches must be the same type. Here we use the **same condition** (`isHigher`) to atomically update both the bid amount and the bidder address.

## 4. Code Walkthrough: `placeBid`

Now let's walk through the core function — `placeBid`. This is where the new patterns come together:

```solidity
function placeBid(externalEuint64 encBid, bytes calldata inputProof)
    external
    inPhase(Phase.Bidding)
{
    if (hasBid[msg.sender]) revert AlreadyBid();

    euint64 bid = FHE.fromExternal(encBid, inputProof);

    // Store the bid
    _bids[msg.sender] = bid;
    hasBid[msg.sender] = true;
    bidders.push(msg.sender);

    // Permissions: bidder sees their own bid, contract can use it
    FHE.allowThis(_bids[msg.sender]);
    FHE.allow(_bids[msg.sender], msg.sender);

    // Update highest bid tracker
    if (bidders.length == 1) {
        _highestBid = bid;
        _highestBidder = FHE.asEaddress(msg.sender);
    } else {
        ebool isHigher = FHE.gt(bid, _highestBid);
        _highestBid = FHE.select(isHigher, bid, _highestBid);
        _highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
    }

    FHE.allowThis(_highestBid);
    FHE.allowThis(_highestBidder);
}
```

### Step-by-Step Breakdown

Let's trace this function when three bidders place bids:

**Alice bids 100 (first bidder):**

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.fromExternal(encBid, proof)` | Verify input → `euint64 bid = enc(100)` |
| 2 | `_bids[alice] = bid` | Store Alice's encrypted bid |
| 3 | `FHE.allowThis` + `FHE.allow` | Alice can see her bid, contract can use it |
| 4 | `bidders.length == 1` → first bidder path | Skip comparison |
| 5 | `_highestBid = bid` | First bid is automatically highest |
| 6 | `_highestBidder = FHE.asEaddress(alice)` | Trivially encrypt Alice's address |
| 7 | `FHE.allowThis` on both | Contract can use these in future comparisons |

**Bob bids 250 (second bidder):**

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.fromExternal(encBid, proof)` | Verify input → `euint64 bid = enc(250)` |
| 2 | Store bid, permissions | Same as Alice |
| 3 | `FHE.gt(enc(250), enc(100))` | `ebool(true)` — Bob's bid is higher |
| 4 | `FHE.select(true, enc(250), enc(100))` | `_highestBid = enc(250)` |
| 5 | `FHE.select(true, enc(bob), enc(alice))` | `_highestBidder = enc(bob)` |
| 6 | `FHE.allowThis` on both | Contract can use updated values |

**Charlie bids 150 (third bidder):**

| Step | Operation | Result |
|------|-----------|--------|
| 1 | `FHE.fromExternal(encBid, proof)` | Verify input → `euint64 bid = enc(150)` |
| 2 | Store bid, permissions | Same as above |
| 3 | `FHE.gt(enc(150), enc(250))` | `ebool(false)` — Charlie's bid is lower |
| 4 | `FHE.select(false, enc(150), enc(250))` | `_highestBid = enc(250)` (unchanged) |
| 5 | `FHE.select(false, enc(charlie), enc(bob))` | `_highestBidder = enc(bob)` (unchanged) |
| 6 | `FHE.allowThis` on both | New handles, same values |

After all three bids: `_highestBid = enc(250)`, `_highestBidder = enc(bob)`. But nobody knows this yet — not Alice, not Charlie, not even the auctioneer.

### The Bid Flow

```
  User encrypts bid client-side
          │
          ▼
  placeBid(encBid, proof)
          │
          ▼
  FHE.fromExternal() ──► Verify ZK proof
          │
          ▼
  Store bid ──► FHE.allowThis + FHE.allow
          │
          ▼
  First bidder? ──YES──► _highestBid = bid
          │
          NO
          │
          ▼
  FHE.gt(bid, _highestBid) ──► ebool isHigher
          │
          ▼
  FHE.select(isHigher, ...) ──► Update _highestBid + _highestBidder
          │
          ▼
  FHE.allowThis on both trackers
```

## 5. Code Walkthrough: `closeAuction` and `revealWinner`

### Closing the Auction

```solidity
function closeAuction() external onlyAuctioneer inPhase(Phase.Bidding) {
    if (block.timestamp < biddingEndTime) revert BiddingNotEnded();
    phase = Phase.Closed;

    FHE.allow(_highestBid, auctioneer);
    FHE.allow(_highestBidder, auctioneer);
}
```

This is where the state machine's security role becomes clear. Notice what happens:

1. **Phase transition**: `Phase.Bidding → Phase.Closed` — no more bids accepted
2. **Permission grant**: The auctioneer gets `FHE.allow` on the winner data — this is the first time **anyone** can decrypt these values
3. **Timing enforcement**: `block.timestamp < biddingEndTime` prevents early closing

During the Bidding phase, `_highestBid` and `_highestBidder` only had `FHE.allowThis` (contract can use them). Now the auctioneer can decrypt them off-chain.

### Revealing the Winner

```solidity
function revealWinner(uint64 winningBid_, address winner_) external onlyAuctioneer inPhase(Phase.Closed) {
    winningBid = winningBid_;
    winner = winner_;
    phase = Phase.Revealed;
}
```

In production, the auctioneer:
1. Calls `fhevmjs` to decrypt `_highestBid` → gets the plaintext `uint64`
2. Calls `fhevmjs` to decrypt `_highestBidder` → gets the plaintext `address`
3. Submits both to `revealWinner()` — making the results publicly visible on-chain

**Important privacy property**: Only the **winning** bid is revealed. Losing bidders' bids remain encrypted forever. Alice and Charlie can see their own bids (via `FHE.allow` granted during `placeBid`), but nobody else ever learns what they bid.

## 6. Architecture Deep Dive: Incremental vs Batch

### Why Not Compare All Bids at Close Time?

A naive implementation would compare all bids when the auction closes:

```solidity
// DON'T DO THIS — O(n) comparisons at close time
function closeAuction() external {
    for (uint i = 0; i < bidders.length; i++) {
        if (FHE.gt(_bids[bidders[i]], _highestBid)) {
            _highestBid = _bids[bidders[i]];
            _highestBidder = bidders[i];
        }
    }
}
```

Our implementation tracks the highest bid **incrementally** as each bid arrives. This is a critical design choice for two reasons:

1. **Gas distribution** — FHE comparisons are expensive. The incremental approach distributes the cost across all `placeBid` transactions instead of concentrating it in one massive `closeAuction` call.
2. **Scalability** — With 100 bidders, the batch approach would need 100 FHE comparisons in a single transaction. That could exceed the block gas limit.

### Per-Transaction FHE Cost

Each `placeBid` after the first performs:
- 1× `FHE.fromExternal` — verify input
- 1× `FHE.gt` — compare with current highest
- 2× `FHE.select` — update highest bid and bidder
- 4× `FHE.allow/allowThis` — permissions

On a real FHEVM chain, FHE operations are significantly more expensive than plaintext. The incremental approach keeps per-transaction gas manageable.

## 7. Test Walkthrough

### Full Auction Flow

```solidity
function test_fullAuctionFlow() public {
    // Phase 1: Bidding
    // Alice: 100, Bob: 250, Charlie: 150
    _placeBids();

    // Each bidder can see their own bid (but not others')
    vm.prank(alice);
    assertEq(mockDecrypt64(auction.getMyBid()), 100);
    vm.prank(bob);
    assertEq(mockDecrypt64(auction.getMyBid()), 250);

    // Phase 2: Close
    vm.warp(block.timestamp + BIDDING_DURATION + 1);
    auction.closeAuction();

    // Phase 3: Reveal
    uint64 highestBid = mockDecrypt64(auction.getHighestBid());
    address highestBidder = mockDecryptAddress(auction.getHighestBidder());
    auction.revealWinner(highestBid, highestBidder);

    // Bob wins with 250
    assertEq(auction.winner(), bob);
    assertEq(auction.winningBid(), 250);
}
```

This test validates the complete three-phase lifecycle:
1. **Bidding** — Three users place encrypted bids, each can only see their own
2. **Close** — Time advances past deadline, auctioneer closes bidding
3. **Reveal** — Auctioneer decrypts winner data and publishes it

Notice the test pattern follows the same rhythm you've used all bootcamp:
```
Setup → Encrypt → Call → Decrypt → Assert
```

### Phase Enforcement

```solidity
function test_cannotBidAfterClose() public {
    _placeBids();
    vm.warp(block.timestamp + BIDDING_DURATION + 1);
    auction.closeAuction();

    // Late bid rejected
    vm.expectRevert(abi.encodeWithSelector(
        SealedBidAuction.WrongPhase.selector,
        SealedBidAuction.Phase.Bidding,
        SealedBidAuction.Phase.Closed
    ));
    auction.placeBid(handle, proof);
}
```

The state machine enforces strict phase boundaries. Once the auction is closed, `placeBid` reverts with a `WrongPhase` error. This isn't a privacy concern (the phase is public), so a normal `revert` is appropriate here — unlike the silent-zero pattern used for encrypted balance checks.

### Running the Tests

```bash
forge test --match-contract SealedBidAuctionTest -vvv
```

Expected: **10 tests pass**.

## 8. Production Considerations

The core contract teaches the essential patterns. Here are extensions you'd add for a production auction:

### Bid Deposits

In a real auction, bidders should lock up ETH/tokens as collateral:

```solidity
function placeBid(externalEuint64 encBid, bytes calldata inputProof) external payable {
    require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");
    // ... store bid, refund losing bidders after reveal
}
```

### Multi-Item Auctions

Extend to auction multiple items simultaneously:

```solidity
mapping(uint256 => mapping(address => euint64)) private _bids; // itemId => bidder => bid
mapping(uint256 => euint64) private _highestBids;
mapping(uint256 => eaddress) private _highestBidders;
```

### Vickrey (Second-Price) Auctions

In a Vickrey auction, the winner pays the **second-highest** bid. This requires tracking one more encrypted value:

```solidity
euint64 private _secondHighestBid;

// In placeBid:
ebool isHigher = FHE.gt(bid, _highestBid);
_secondHighestBid = FHE.select(isHigher, _highestBid, FHE.max(bid, _secondHighestBid));
_highestBid = FHE.select(isHigher, bid, _highestBid);
```

You'll implement this in the capstone homework.

## 9. Exercise: Minimum Bid Enforcement

Before moving on, try adding a minimum bid requirement. This reinforces the silent-zero pattern from Week 3 in a new context:

```solidity
euint64 public minimumBid;

constructor(string memory description_, uint256 duration_, uint64 minBid_) {
    minimumBid = FHE.asEuint64(minBid_);
    FHE.allowThis(minimumBid);
}

function placeBid(externalEuint64 encBid, bytes calldata inputProof) external {
    euint64 bid = FHE.fromExternal(encBid, inputProof);

    // Enforce minimum (silent: if below minimum, treat as minimum)
    ebool meetsMinimum = FHE.ge(bid, minimumBid);
    euint64 effectiveBid = FHE.select(meetsMinimum, bid, minimumBid);
    // ... rest of logic with effectiveBid
}
```

**Why silent instead of revert?** If the contract reverts on bids below the minimum, an observer could binary-search to discover the minimum bid threshold (if it were encrypted). Using `FHE.select` to silently clamp the bid preserves privacy. Since the minimum is public in this design, a revert would also be acceptable — but the silent pattern is the safer default.

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| `eaddress` | Encrypted Ethereum address — hides the winner's identity |
| `FHE.asEaddress()` | Trivially encrypt an address into an encrypted handle |
| `FHE.gt()` | Encrypted greater-than comparison — returns `ebool` |
| State machines | Phase-based flow control (Bidding → Closed → Revealed) |
| Incremental tracking | Update winner on each bid (vs batch at close) — distributes FHE gas cost |
| Selective revelation | Only the winning bid is ever revealed — losers' bids stay encrypted forever |
| Deferred permissions | `FHE.allow` granted only when state machine reaches the appropriate phase |

---

## Key Takeaways

1. **Sealed-bid auctions solve front-running, sniping, and shill bidding** — encrypted bids mean nobody can see or react to others' bids
2. **State machines enforce security boundaries** — `FHE.allow` on the winner is only granted after `closeAuction()`, not during bidding
3. **`eaddress` hides the winner's identity** — combined with `euint64` for the bid amount, the entire winner record is encrypted
4. **`FHE.gt()` + `FHE.select()` enable encrypted ranking** — compare and conditionally update without revealing any values
5. **Incremental tracking distributes gas cost** — each `placeBid` does O(1) FHE work instead of O(n) at close time
6. **Only the winning bid is revealed** — losing bidders' bids remain encrypted forever, preserving their privacy
7. **This is a production pattern** — Zama Auction uses these same techniques on mainnet

---

**Next:** [Lesson 2: From Mock to Mainnet — Deployment & Frontend](/week-4/lesson-2-deployment) — Take your contracts from mock mode to real FHE on Sepolia, integrate `fhevmjs` for client-side encryption, and complete the mainnet deployment checklist.
