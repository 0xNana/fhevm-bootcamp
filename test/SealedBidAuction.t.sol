// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "./FhevmTest.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {SealedBidAuction} from "../src/SealedBidAuction.sol";

/// @title SealedBidAuctionTest
/// @notice Tests for the sealed-bid auction — the capstone project mirroring Zama Auction.
contract SealedBidAuctionTest is FhevmTest {
    SealedBidAuction public auction;

    address public auctioneer;
    address public alice;
    address public bob;
    address public charlie;

    uint256 constant BIDDING_DURATION = 1 hours;

    function setUp() public override {
        super.setUp();

        auctioneer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        auction = new SealedBidAuction("Rare NFT #42", BIDDING_DURATION);
    }

    // ──────────────────────────────────────────────
    //  Bidding Phase
    // ──────────────────────────────────────────────

    function test_placeBid() public {
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(100);
        vm.prank(alice);
        auction.placeBid(handle, proof);

        assertEq(auction.getBidderCount(), 1);
        assertTrue(auction.hasBid(alice));
    }

    function test_cannotBidTwice() public {
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(200);
        vm.prank(alice);
        vm.expectRevert(SealedBidAuction.AlreadyBid.selector);
        auction.placeBid(h2, p2);
    }

    function test_bidderCanReadOwnBid() public {
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(42);
        vm.prank(alice);
        auction.placeBid(handle, proof);

        vm.prank(alice);
        uint64 myBid = mockDecrypt64(auction.getMyBid());
        assertEq(myBid, 42);
    }

    function test_multipleBiddersTrackHighest() public {
        // Alice bids 100
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        // Bob bids 250 (highest)
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(250);
        vm.prank(bob);
        auction.placeBid(h2, p2);

        // Charlie bids 150
        (externalEuint64 h3, bytes memory p3) = mockEncrypt64(150);
        vm.prank(charlie);
        auction.placeBid(h3, p3);

        assertEq(auction.getBidderCount(), 3);

        // The encrypted highest bid should be 250
        uint64 highest = mockDecrypt64(auction.getHighestBid());
        assertEq(highest, 250);
    }

    // ──────────────────────────────────────────────
    //  Close Phase
    // ──────────────────────────────────────────────

    function test_closeAuctionAfterBidding() public {
        _placeBids();

        // Fast-forward past bidding period
        vm.warp(block.timestamp + BIDDING_DURATION + 1);

        auction.closeAuction();
        assertEq(uint256(auction.phase()), uint256(SealedBidAuction.Phase.Closed));
    }

    function test_cannotCloseBeforeBiddingEnds() public {
        _placeBids();

        vm.expectRevert(SealedBidAuction.BiddingNotEnded.selector);
        auction.closeAuction();
    }

    function test_onlyAuctioneerCanClose() public {
        _placeBids();
        vm.warp(block.timestamp + BIDDING_DURATION + 1);

        vm.prank(alice);
        vm.expectRevert(SealedBidAuction.OnlyAuctioneer.selector);
        auction.closeAuction();
    }

    function test_cannotBidAfterClose() public {
        _placeBids();
        vm.warp(block.timestamp + BIDDING_DURATION + 1);
        auction.closeAuction();

        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(999);
        vm.prank(makeAddr("lateBidder"));
        vm.expectRevert(
            abi.encodeWithSelector(
                SealedBidAuction.WrongPhase.selector, SealedBidAuction.Phase.Bidding, SealedBidAuction.Phase.Closed
            )
        );
        auction.placeBid(handle, proof);
    }

    // ──────────────────────────────────────────────
    //  Reveal Phase
    // ──────────────────────────────────────────────

    function test_revealWinner() public {
        _placeBids();
        vm.warp(block.timestamp + BIDDING_DURATION + 1);
        auction.closeAuction();

        // Auctioneer decrypts and reveals
        uint64 highestBid = mockDecrypt64(auction.getHighestBid());
        address highestBidder = mockDecryptAddress(auction.getHighestBidder());

        auction.revealWinner(highestBid, highestBidder);

        assertEq(uint256(auction.phase()), uint256(SealedBidAuction.Phase.Revealed));
        assertEq(auction.winner(), bob); // Bob bid 250 (highest)
        assertEq(auction.winningBid(), 250);
    }

    function test_fullAuctionFlow() public {
        // Phase 1: Bidding
        assertEq(uint256(auction.phase()), uint256(SealedBidAuction.Phase.Bidding));

        // Alice: 100, Bob: 250, Charlie: 150
        _placeBids();

        // Each bidder can see their own bid
        vm.prank(alice);
        assertEq(mockDecrypt64(auction.getMyBid()), 100);
        vm.prank(bob);
        assertEq(mockDecrypt64(auction.getMyBid()), 250);
        vm.prank(charlie);
        assertEq(mockDecrypt64(auction.getMyBid()), 150);

        // Phase 2: Close
        vm.warp(block.timestamp + BIDDING_DURATION + 1);
        auction.closeAuction();

        // Phase 3: Reveal
        uint64 highestBid = mockDecrypt64(auction.getHighestBid());
        address highestBidder = mockDecryptAddress(auction.getHighestBidder());
        auction.revealWinner(highestBid, highestBidder);

        // Verify
        assertEq(auction.winner(), bob);
        assertEq(auction.winningBid(), 250);
        assertEq(auction.itemDescription(), "Rare NFT #42");
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _placeBids() internal {
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        auction.placeBid(h1, p1);

        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(250);
        vm.prank(bob);
        auction.placeBid(h2, p2);

        (externalEuint64 h3, bytes memory p3) = mockEncrypt64(150);
        vm.prank(charlie);
        auction.placeBid(h3, p3);
    }
}
