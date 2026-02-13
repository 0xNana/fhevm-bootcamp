// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "../../../test/FhevmTest.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {VickreyAuction} from "../src/VickreyAuction.sol";

/// @title VickreyAuctionTest
/// @notice Tests for the Week 4 capstone — Vickrey (second-price) sealed-bid auction.
///         Your implementation must pass all of these tests.
///
///         Run with:  forge test --match-contract VickreyAuctionTest -vvv
contract VickreyAuctionTest is FhevmTest {
    VickreyAuction public auction;

    address public auctioneerAddr;
    address public alice;
    address public bob;
    address public charlie;

    uint256 constant BIDDING_DURATION = 1 hours;
    uint64 constant MINIMUM_BID = 100;

    function setUp() public override {
        super.setUp();

        auctioneerAddr = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        auction = new VickreyAuction("Rare NFT #42", BIDDING_DURATION, MINIMUM_BID);
    }

    // ──────────────────────────────────────────────
    //  Test: Bidding
    // ──────────────────────────────────────────────

    /// @notice Placing a bid should store it and be readable by the bidder.
    function test_placeBidStoresBid() public {
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(500);
        vm.prank(alice);
        auction.placeBid(handle, proof);

        assertEq(auction.getBidderCount(), 1, "Should have 1 bidder");
        assertTrue(auction.hasBid(alice), "Alice should be marked as having bid");

        // Alice can read her own bid
        vm.prank(alice);
        uint64 myBid = mockDecrypt64(auction.getMyBid());
        assertEq(myBid, 500, "Alice's bid should be 500");
    }

    /// @notice Bids below the minimum should be silently zeroed (privacy-preserving rejection).
    function test_bidBelowMinimumIsRejected() public {
        // Place a bid of 50, which is below the minimum of 100
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(50);
        vm.prank(alice);
        auction.placeBid(handle, proof);

        // The bid should be stored as zero (silently rejected)
        vm.prank(alice);
        uint64 myBid = mockDecrypt64(auction.getMyBid());
        assertEq(myBid, 0, "Below-minimum bid should be silently zeroed");
    }

    /// @notice The highest bid should be tracked correctly with two bidders.
    function test_highestBidTracked() public {
        // Alice bids 200
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(200);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        // Bob bids 500 (highest)
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(500);
        vm.prank(bob);
        auction.placeBid(h2, p2);

        uint64 highest = mockDecrypt64(auction.getHighestBid());
        assertEq(highest, 500, "Highest bid should be 500");
    }

    /// @notice The second-highest bid should be tracked correctly.
    function test_secondHighestBidTracked() public {
        // Alice bids 200
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(200);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        // Bob bids 500 (highest)
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(500);
        vm.prank(bob);
        auction.placeBid(h2, p2);

        uint64 secondHighest = mockDecrypt64(auction.getSecondHighestBid());
        assertEq(secondHighest, 200, "Second-highest bid should be 200");
    }

    /// @notice With three bidders, both highest and second-highest should be correct.
    function test_threeBiddersCorrectRanking() public {
        // Alice bids 200
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(200);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        // Bob bids 500 (highest)
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(500);
        vm.prank(bob);
        auction.placeBid(h2, p2);

        // Charlie bids 350 (second highest)
        (externalEuint64 h3, bytes memory p3) = mockEncrypt64(350);
        vm.prank(charlie);
        auction.placeBid(h3, p3);

        assertEq(auction.getBidderCount(), 3, "Should have 3 bidders");

        uint64 highest = mockDecrypt64(auction.getHighestBid());
        uint64 secondHighest = mockDecrypt64(auction.getSecondHighestBid());

        assertEq(highest, 500, "Highest bid should be 500 (Bob)");
        assertEq(secondHighest, 350, "Second-highest bid should be 350 (Charlie)");
    }

    /// @notice A bidder cannot bid twice.
    function test_cannotBidTwice() public {
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(200);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(300);
        vm.prank(alice);
        vm.expectRevert(VickreyAuction.AlreadyBid.selector);
        auction.placeBid(h2, p2);
    }

    // ──────────────────────────────────────────────
    //  Test: Closing
    // ──────────────────────────────────────────────

    /// @notice Only the auctioneer can close the auction.
    function test_closeAuctionOnlyAuctioneer() public {
        _placeBids();
        vm.warp(block.timestamp + BIDDING_DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(VickreyAuction.OnlyAuctioneer.selector);
        auction.closeAuction();
    }

    /// @notice The auction cannot be closed before the bidding period ends.
    function test_closeAuctionOnlyAfterDeadline() public {
        _placeBids();

        // Try to close before the deadline — should revert
        vm.expectRevert(VickreyAuction.BiddingNotEnded.selector);
        auction.closeAuction();
    }

    // ──────────────────────────────────────────────
    //  Test: Reveal
    // ──────────────────────────────────────────────

    /// @notice After reveal, the winner pays the second-highest price.
    function test_revealShowsSecondPrice() public {
        _placeBids();
        vm.warp(block.timestamp + BIDDING_DURATION + 1);
        auction.closeAuction();

        // Auctioneer decrypts the results
        uint64 secondPrice = mockDecrypt64(auction.getSecondHighestBid());
        address highestBidder = mockDecryptAddress(auction.getHighestBidder());

        auction.revealWinner(secondPrice, highestBidder);

        assertEq(
            uint256(auction.phase()),
            uint256(VickreyAuction.Phase.Revealed),
            "Phase should be Revealed"
        );
        assertEq(auction.winner(), bob, "Winner should be Bob (highest bidder)");
        assertEq(auction.winningPrice(), 350, "Winning price should be 350 (second-highest bid)");
    }

    // ──────────────────────────────────────────────
    //  Test: Phase Enforcement
    // ──────────────────────────────────────────────

    /// @notice Cannot bid after the auction is closed.
    function test_phaseEnforcement() public {
        _placeBids();
        vm.warp(block.timestamp + BIDDING_DURATION + 1);
        auction.closeAuction();

        // Try to bid after closing — should revert with WrongPhase
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(999);
        vm.prank(makeAddr("lateBidder"));
        vm.expectRevert(
            abi.encodeWithSelector(
                VickreyAuction.WrongPhase.selector,
                VickreyAuction.Phase.Bidding,
                VickreyAuction.Phase.Closed
            )
        );
        auction.placeBid(handle, proof);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    /// @dev Places three bids: Alice=200, Bob=500, Charlie=350
    function _placeBids() internal {
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(200);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(500);
        vm.prank(bob);
        auction.placeBid(h2, p2);

        (externalEuint64 h3, bytes memory p3) = mockEncrypt64(350);
        vm.prank(charlie);
        auction.placeBid(h3, p3);
    }
}
