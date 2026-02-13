// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "../../../test/FhevmTest.sol";
import {externalEuint32} from "encrypted-types/EncryptedTypes.sol";
import {EncryptedPoll} from "../src/EncryptedPoll.sol";

/// @title EncryptedPollTest
/// @notice Tests for the Week 1 homework — Encrypted Poll.
///         Your implementation must pass all of these tests.
///
///         Run with:  forge test --match-contract EncryptedPollTest -vvv
contract EncryptedPollTest is FhevmTest {
    EncryptedPoll public poll;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    function setUp() public override {
        super.setUp();

        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Deploy a poll with 3 questions, owned by this test contract
        poll = new EncryptedPoll(3, owner);
    }

    // ──────────────────────────────────────────────
    //  Test: Initial State
    // ──────────────────────────────────────────────

    /// @notice All vote counts should start at zero.
    function test_initialVoteCountsAreZero() public {
        for (uint8 i = 0; i < 3; i++) {
            uint32 count = mockDecrypt32(poll.getVoteCount(i));
            assertEq(count, 0, "Initial vote count should be zero");
        }
    }

    // ──────────────────────────────────────────────
    //  Test: Voting
    // ──────────────────────────────────────────────

    /// @notice A single vote should increment the encrypted count by the vote value.
    function test_voteIncrementsCount() public {
        (externalEuint32 handle, bytes memory proof) = mockEncrypt32(1);
        vm.prank(alice);
        poll.vote(0, handle, proof);

        uint32 count = mockDecrypt32(poll.getVoteCount(0));
        assertEq(count, 1, "Vote count should be 1 after one vote");
    }

    /// @notice Multiple voters on the same question should accumulate.
    function test_multipleVotersOnSameQuestion() public {
        // Alice votes on question 0
        (externalEuint32 h1, bytes memory p1) = mockEncrypt32(1);
        vm.prank(alice);
        poll.vote(0, h1, p1);

        // Bob votes on question 0
        (externalEuint32 h2, bytes memory p2) = mockEncrypt32(1);
        vm.prank(bob);
        poll.vote(0, h2, p2);

        // Charlie votes on question 0
        (externalEuint32 h3, bytes memory p3) = mockEncrypt32(1);
        vm.prank(charlie);
        poll.vote(0, h3, p3);

        uint32 count = mockDecrypt32(poll.getVoteCount(0));
        assertEq(count, 3, "Vote count should be 3 after three voters");
    }

    /// @notice A voter can vote on different questions independently.
    function test_voteOnDifferentQuestions() public {
        // Alice votes on question 0
        (externalEuint32 h1, bytes memory p1) = mockEncrypt32(1);
        vm.prank(alice);
        poll.vote(0, h1, p1);

        // Alice also votes on question 1 (different question — allowed)
        (externalEuint32 h2, bytes memory p2) = mockEncrypt32(1);
        vm.prank(alice);
        poll.vote(1, h2, p2);

        uint32 count0 = mockDecrypt32(poll.getVoteCount(0));
        uint32 count1 = mockDecrypt32(poll.getVoteCount(1));
        uint32 count2 = mockDecrypt32(poll.getVoteCount(2));

        assertEq(count0, 1, "Question 0 should have 1 vote");
        assertEq(count1, 1, "Question 1 should have 1 vote");
        assertEq(count2, 0, "Question 2 should have 0 votes");
    }

    // ──────────────────────────────────────────────
    //  Test: Double-Vote Prevention
    // ──────────────────────────────────────────────

    /// @notice A voter cannot vote twice on the same question.
    function test_cannotVoteTwiceOnSameQuestion() public {
        (externalEuint32 h1, bytes memory p1) = mockEncrypt32(1);
        vm.prank(alice);
        poll.vote(0, h1, p1);

        // Alice tries to vote again on question 0 — should revert
        (externalEuint32 h2, bytes memory p2) = mockEncrypt32(1);
        vm.prank(alice);
        vm.expectRevert(EncryptedPoll.AlreadyVoted.selector);
        poll.vote(0, h2, p2);
    }

    // ──────────────────────────────────────────────
    //  Test: Owner Access
    // ──────────────────────────────────────────────

    /// @notice The owner should be able to decrypt and read vote counts.
    function test_ownerCanReadVoteCounts() public {
        // Place several votes on question 0
        (externalEuint32 h1, bytes memory p1) = mockEncrypt32(1);
        vm.prank(alice);
        poll.vote(0, h1, p1);

        (externalEuint32 h2, bytes memory p2) = mockEncrypt32(1);
        vm.prank(bob);
        poll.vote(0, h2, p2);

        // Owner can decrypt the vote count
        uint32 count = mockDecrypt32(poll.getVoteCount(0));
        assertEq(count, 2, "Owner should read accumulated vote count of 2");

        // Verify hasVoted tracking is correct
        assertTrue(poll.hasVoted(alice, 0), "Alice should be marked as voted");
        assertTrue(poll.hasVoted(bob, 0), "Bob should be marked as voted");
        assertFalse(poll.hasVoted(charlie, 0), "Charlie should not be marked as voted");
    }
}
