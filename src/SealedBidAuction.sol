// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool, eaddress} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title SealedBidAuction
/// @notice A sealed-bid auction where bids are encrypted. Nobody (not even the auctioneer)
///         can see individual bids. The winner is determined by FHE comparison without
///         revealing any losing bids.
/// @dev    Inspired by Zama Auction — the first application launched on Zama Protocol mainnet.
///         Demonstrates: state machines with FHE, encrypted comparisons (FHE.gt),
///         encrypted conditionals (FHE.select), and multi-party encrypted state.
contract SealedBidAuction is ZamaEthereumConfig {
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

    address public auctioneer;
    string public itemDescription;

    Phase public phase;
    uint256 public biddingEndTime;

    /// @notice Encrypted bid per bidder (only the bidder can decrypt their own).
    mapping(address => euint64) private _bids;

    /// @notice Track which addresses have placed bids.
    mapping(address => bool) public hasBid;

    /// @notice Addresses of all bidders (for iteration during reveal).
    address[] public bidders;

    /// @notice The encrypted highest bid (tracked incrementally).
    euint64 private _highestBid;

    /// @notice The encrypted highest bidder address.
    eaddress private _highestBidder;

    /// @notice After reveal: the winning bid amount (plaintext, set by auctioneer).
    uint64 public winningBid;

    /// @notice After reveal: the winning address (plaintext, set by auctioneer).
    address public winner;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event BidPlaced(address indexed bidder);
    event AuctionClosed();
    event AuctionRevealed(address indexed winner, uint64 winningBid);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error OnlyAuctioneer();
    error WrongPhase(Phase expected, Phase actual);
    error BiddingNotEnded();
    error AlreadyBid();

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyAuctioneer() {
        _onlyAuctioneer();
        _;
    }

    function _onlyAuctioneer() internal view {
        if (msg.sender != auctioneer) revert OnlyAuctioneer();
    }

    modifier inPhase(Phase expected) {
        _inPhase(expected);
        _;
    }

    function _inPhase(Phase expected) internal view {
        if (phase != expected) revert WrongPhase(expected, phase);
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    /// @param description_ A description of the item being auctioned.
    /// @param biddingDuration_ How long (in seconds) the bidding phase lasts.
    constructor(string memory description_, uint256 biddingDuration_) {
        auctioneer = msg.sender;
        itemDescription = description_;
        biddingEndTime = block.timestamp + biddingDuration_;
        phase = Phase.Bidding;
    }

    // ──────────────────────────────────────────────
    //  Bidding Phase
    // ──────────────────────────────────────────────

    /// @notice Place a sealed (encrypted) bid.
    /// @param encBid The encrypted bid amount.
    /// @param inputProof The input proof.
    function placeBid(externalEuint64 encBid, bytes calldata inputProof) external inPhase(Phase.Bidding) {
        if (hasBid[msg.sender]) revert AlreadyBid();

        euint64 bid = FHE.fromExternal(encBid, inputProof);

        // Store the bid
        _bids[msg.sender] = bid;
        hasBid[msg.sender] = true;
        bidders.push(msg.sender);

        // Grant permissions: bidder can decrypt their own bid, contract can use it
        FHE.allowThis(_bids[msg.sender]);
        FHE.allow(_bids[msg.sender], msg.sender);

        // Update highest bid tracker
        if (bidders.length == 1) {
            // First bid — it's automatically the highest
            _highestBid = bid;
            _highestBidder = FHE.asEaddress(msg.sender);
        } else {
            // Compare with current highest (encrypted comparison!)
            ebool isHigher = FHE.gt(bid, _highestBid);

            // Select new highest bid and bidder
            _highestBid = FHE.select(isHigher, bid, _highestBid);
            _highestBidder = FHE.select(isHigher, FHE.asEaddress(msg.sender), _highestBidder);
        }

        FHE.allowThis(_highestBid);
        FHE.allowThis(_highestBidder);

        emit BidPlaced(msg.sender);
    }

    // ──────────────────────────────────────────────
    //  Close Phase
    // ──────────────────────────────────────────────

    /// @notice Close the auction (auctioneer only, after bidding period ends).
    function closeAuction() external onlyAuctioneer inPhase(Phase.Bidding) {
        if (block.timestamp < biddingEndTime) revert BiddingNotEnded();
        phase = Phase.Closed;

        // Allow auctioneer to decrypt the winner
        FHE.allow(_highestBid, auctioneer);
        FHE.allow(_highestBidder, auctioneer);

        emit AuctionClosed();
    }

    // ──────────────────────────────────────────────
    //  Reveal Phase
    // ──────────────────────────────────────────────

    /// @notice Reveal the auction results (auctioneer provides decrypted values).
    ///         In production, decryption happens off-chain via fhevmjs.
    ///         In mock mode, the test directly reads the plaintext.
    /// @param winningBid_ The decrypted winning bid amount.
    /// @param winner_ The decrypted winner address.
    function revealWinner(uint64 winningBid_, address winner_) external onlyAuctioneer inPhase(Phase.Closed) {
        winningBid = winningBid_;
        winner = winner_;
        phase = Phase.Revealed;

        emit AuctionRevealed(winner_, winningBid_);
    }

    // ──────────────────────────────────────────────
    //  View Functions
    // ──────────────────────────────────────────────

    /// @notice Get the caller's own encrypted bid.
    function getMyBid() external view returns (euint64) {
        return _bids[msg.sender];
    }

    /// @notice Get the encrypted highest bid (only readable by auctioneer after close).
    function getHighestBid() external view returns (euint64) {
        return _highestBid;
    }

    /// @notice Get the encrypted highest bidder (only readable by auctioneer after close).
    function getHighestBidder() external view returns (eaddress) {
        return _highestBidder;
    }

    /// @notice Get the number of bidders.
    function getBidderCount() external view returns (uint256) {
        return bidders.length;
    }
}
