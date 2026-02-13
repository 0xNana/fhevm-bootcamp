// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title VickreyAuction
/// @notice A sealed-bid, second-price (Vickrey) auction powered by FHE.
///         The winner pays the second-highest bid, not their own bid.
///         No one — not even the auctioneer — can see individual bids.
///
/// @dev    Week 4 Capstone — Implement the TODO sections below.
///         This contract tracks BOTH the highest and second-highest bids using
///         encrypted comparisons. Bids below the public minimumBid are silently
///         zeroed (privacy-preserving rejection).
///
///         Key FHE operations you will need:
///           - FHE.fromExternal()    — convert external encrypted input
///           - FHE.asEuint64()       — trivially encrypt a plaintext
///           - FHE.asEaddress()      — trivially encrypt an address
///           - FHE.gt()              — encrypted greater-than comparison → ebool
///           - FHE.ge()              — encrypted greater-than-or-equal → ebool
///           - FHE.select()          — conditional: select(cond, ifTrue, ifFalse)
///           - FHE.allowThis()       — grant contract permission
///           - FHE.allow()           — grant address permission
contract VickreyAuction is ZamaEthereumConfig {
    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    enum Phase {
        Bidding,
        Closed,
        Revealed
    }

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    /// @notice The auctioneer who controls phase transitions and reveals the winner.
    address public auctioneer;

    /// @notice Description of the item being auctioned.
    string public itemDescription;

    /// @notice Current phase of the auction.
    Phase public phase;

    /// @notice Timestamp after which bidding can be closed.
    uint256 public biddingEndTime;

    /// @notice Public minimum bid. Bids below this are silently zeroed.
    uint64 public minimumBid;

    /// @notice Encrypted bid per bidder (only the bidder can decrypt their own).
    mapping(address => euint64) private _bids;

    /// @notice Track which addresses have placed bids.
    mapping(address => bool) public hasBid;

    /// @notice Addresses of all bidders (for iteration/counting).
    address[] public bidders;

    /// @notice The encrypted highest bid (tracked incrementally as bids arrive).
    euint64 private _highestBid;

    /// @notice The encrypted second-highest bid (the price the winner pays).
    euint64 private _secondHighestBid;

    /// @notice The encrypted address of the highest bidder.
    eaddress private _highestBidder;

    /// @notice After reveal: the second-highest bid amount (plaintext).
    uint64 public winningPrice;

    /// @notice After reveal: the winning address (plaintext).
    address public winner;

    // ──────────────────────────────────────────────
    //  Events & Errors
    // ──────────────────────────────────────────────

    event BidPlaced(address indexed bidder);
    event AuctionClosed();
    event AuctionRevealed(address indexed winner, uint64 winningPrice);

    error OnlyAuctioneer();
    error WrongPhase(Phase expected, Phase actual);
    error BiddingNotEnded();
    error AlreadyBid();

    // ──────────────────────────────────────────────
    //  Modifiers (provided as reference — already implemented)
    // ──────────────────────────────────────────────

    modifier onlyAuctioneer() {
        if (msg.sender != auctioneer) revert OnlyAuctioneer();
        _;
    }

    modifier inPhase(Phase expected) {
        if (phase != expected) revert WrongPhase(expected, phase);
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    /// @param description_ A description of the item being auctioned.
    /// @param biddingDuration_ How long (in seconds) the bidding phase lasts.
    /// @param minimumBid_ The minimum bid amount (public — bids below this are zeroed).
    constructor(string memory description_, uint256 biddingDuration_, uint64 minimumBid_) {
        auctioneer = msg.sender;
        itemDescription = description_;
        biddingEndTime = block.timestamp + biddingDuration_;
        minimumBid = minimumBid_;
        phase = Phase.Bidding;
    }

    // ──────────────────────────────────────────────
    //  Core Functions — TODO: Implement these!
    // ──────────────────────────────────────────────

    /// @notice Place a sealed (encrypted) bid.
    /// @param encBid The encrypted bid amount.
    /// @param inputProof The input proof from the encryption client.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Check that the bidder hasn't already bid (revert with AlreadyBid if so).
    ///      2. Convert the external encrypted input:
    ///         euint64 bid = FHE.fromExternal(encBid, inputProof);
    ///      3. Enforce the minimum bid using encrypted comparison:
    ///         ebool isAboveMin = FHE.ge(bid, FHE.asEuint64(minimumBid));
    ///         bid = FHE.select(isAboveMin, bid, FHE.asEuint64(0));
    ///         (Bids below minimum are silently zeroed — privacy-preserving rejection.)
    ///      4. Store the bid and mark the bidder:
    ///         _bids[msg.sender] = bid;
    ///         hasBid[msg.sender] = true;
    ///         bidders.push(msg.sender);
    ///      5. Set FHE permissions on the stored bid:
    ///         FHE.allowThis(_bids[msg.sender]);
    ///         FHE.allow(_bids[msg.sender], msg.sender);
    ///      6. Update the highest and second-highest bid trackers:
    ///         - If this is the first bid (bidders.length == 1):
    ///             _highestBid = bid;
    ///             _secondHighestBid = FHE.asEuint64(0);
    ///             _highestBidder = FHE.asEaddress(msg.sender);
    ///         - Otherwise:
    ///             ebool isHigher = FHE.gt(bid, _highestBid);
    ///             // New second-highest = the smaller of (new bid, old highest)
    ///             _secondHighestBid = FHE.select(isHigher, _highestBid, FHE.select(FHE.gt(bid, _secondHighestBid), bid, _secondHighestBid));
    ///             _highestBid = FHE.select(isHigher, bid, _highestBid);
    ///             _highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
    ///      7. Set FHE permissions on highest/secondHighest/highestBidder:
    ///         FHE.allowThis(_highestBid);
    ///         FHE.allowThis(_secondHighestBid);
    ///         FHE.allowThis(_highestBidder);
    ///      8. Emit the BidPlaced event.
    function placeBid(externalEuint64 encBid, bytes calldata inputProof) external inPhase(Phase.Bidding) {
        // TODO: Implement bid placement with minimum enforcement and ranking
    }

    /// @notice Close the auction (auctioneer only, after bidding period ends).
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Check that the bidding period has ended:
    ///         if (block.timestamp < biddingEndTime) revert BiddingNotEnded();
    ///      2. Transition to the Closed phase:
    ///         phase = Phase.Closed;
    ///      3. Grant the auctioneer permission to decrypt the results:
    ///         FHE.allow(_highestBid, auctioneer);
    ///         FHE.allow(_secondHighestBid, auctioneer);
    ///         FHE.allow(_highestBidder, auctioneer);
    ///      4. Emit the AuctionClosed event.
    function closeAuction() external onlyAuctioneer inPhase(Phase.Bidding) {
        // TODO: Implement auction closing
    }

    /// @notice Reveal the auction results (auctioneer provides decrypted values).
    ///         In production, decryption happens off-chain via fhevmjs.
    ///         In mock mode, the test directly reads the plaintext handles.
    /// @param winningPrice_ The decrypted second-highest bid (the price the winner pays).
    /// @param winner_ The decrypted winner address.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Store the revealed values:
    ///         winningPrice = winningPrice_;
    ///         winner = winner_;
    ///      2. Transition to the Revealed phase:
    ///         phase = Phase.Revealed;
    ///      3. Emit the AuctionRevealed event.
    function revealWinner(uint64 winningPrice_, address winner_) external onlyAuctioneer inPhase(Phase.Closed) {
        // TODO: Implement winner reveal
    }

    // ──────────────────────────────────────────────
    //  View Functions — TODO: Implement these!
    // ──────────────────────────────────────────────

    /// @notice Get the caller's own encrypted bid.
    /// @return The caller's encrypted bid handle (only decryptable by the caller).
    ///
    /// @dev TODO: Return _bids[msg.sender].
    function getMyBid() external view returns (euint64) {
        // TODO: Return the caller's encrypted bid
        return _bids[msg.sender];
    }

    /// @notice Get the encrypted second-highest bid (readable by auctioneer after close).
    /// @return The encrypted second-highest bid handle.
    ///
    /// @dev TODO: Return _secondHighestBid.
    function getSecondHighestBid() external view returns (euint64) {
        // TODO: Return the encrypted second-highest bid
        return _secondHighestBid;
    }

    /// @notice Get the encrypted highest bid (readable by auctioneer after close).
    /// @return The encrypted highest bid handle.
    function getHighestBid() external view returns (euint64) {
        return _highestBid;
    }

    /// @notice Get the encrypted highest bidder (readable by auctioneer after close).
    /// @return The encrypted highest bidder address handle.
    function getHighestBidder() external view returns (eaddress) {
        return _highestBidder;
    }

    /// @notice Get the total number of bidders.
    /// @return The number of addresses that have placed bids.
    ///
    /// @dev TODO: Return bidders.length.
    function getBidderCount() external view returns (uint256) {
        // TODO: Return the number of bidders
        return bidders.length;
    }
}
