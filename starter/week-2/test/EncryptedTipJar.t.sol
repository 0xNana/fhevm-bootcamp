// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "../../../test/FhevmTest.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {EncryptedTipJar} from "../src/EncryptedTipJar.sol";

/// @title EncryptedTipJarTest
/// @notice Tests for the Week 2 homework — Encrypted Tip Jar.
///         Your implementation must pass all of these tests.
///
///         Run with:  forge test --match-contract EncryptedTipJarTest -vvv
contract EncryptedTipJarTest is FhevmTest {
    EncryptedTipJar public jar;

    address public creatorAddr;
    address public alice;
    address public bob;

    function setUp() public override {
        super.setUp();

        creatorAddr = makeAddr("creator");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        jar = new EncryptedTipJar(creatorAddr);
    }

    // ──────────────────────────────────────────────
    //  Test: Tipping
    // ──────────────────────────────────────────────

    /// @notice A single tip should increase the creator's encrypted balance.
    function test_tipIncreasesCreatorBalance() public {
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(500);
        vm.prank(alice);
        jar.tip(handle, proof);

        uint64 balance = mockDecrypt64(jar.getCreatorBalance());
        assertEq(balance, 500, "Creator balance should be 500 after one tip");
    }

    /// @notice Multiple tips from the same tipper should accumulate in their total.
    function test_tipTracksPerTipper() public {
        // Alice tips twice
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        jar.tip(h1, p1);

        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(250);
        vm.prank(alice);
        jar.tip(h2, p2);

        // Alice's total should be 350
        vm.prank(alice);
        uint64 total = mockDecrypt64(jar.getMyTotalTips());
        assertEq(total, 350, "Alice's total tips should be 350");
    }

    /// @notice Tips from multiple tippers should all accumulate in the creator's balance.
    function test_multipleTippersAccumulate() public {
        // Alice tips 100
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        jar.tip(h1, p1);

        // Bob tips 200
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(200);
        vm.prank(bob);
        jar.tip(h2, p2);

        // Creator balance should be 300
        uint64 balance = mockDecrypt64(jar.getCreatorBalance());
        assertEq(balance, 300, "Creator balance should be 300 from both tippers");
    }

    // ──────────────────────────────────────────────
    //  Test: Withdrawal
    // ──────────────────────────────────────────────

    /// @notice The creator should be able to withdraw part of their balance.
    function test_creatorCanWithdraw() public {
        // Alice tips 1000
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
        vm.prank(alice);
        jar.tip(h1, p1);

        // Creator withdraws 400
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(400);
        vm.prank(creatorAddr);
        jar.withdraw(h2, p2);

        // Remaining balance should be 600
        uint64 balance = mockDecrypt64(jar.getCreatorBalance());
        assertEq(balance, 600, "Creator balance should be 600 after withdrawing 400");
    }

    /// @notice Withdrawing more than the balance should silently fail (withdraw zero).
    ///         This is the privacy-preserving pattern — no revert to leak balance info.
    function test_withdrawCapsAtBalance() public {
        // Alice tips 100
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        jar.tip(h1, p1);

        // Creator tries to withdraw 999 (more than balance)
        // Should silently set withdrawal to zero — no revert
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(999);
        vm.prank(creatorAddr);
        jar.withdraw(h2, p2);

        // Balance should remain 100 — withdrawal was silently zeroed
        uint64 balance = mockDecrypt64(jar.getCreatorBalance());
        assertEq(balance, 100, "Balance should be unchanged after over-withdrawal");
    }

    /// @notice Only the creator can withdraw.
    function test_nonCreatorCannotWithdraw() public {
        // Alice tips 100
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        jar.tip(h1, p1);

        // Alice (not the creator) tries to withdraw — should revert
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(50);
        vm.prank(alice);
        vm.expectRevert(EncryptedTipJar.OnlyCreator.selector);
        jar.withdraw(h2, p2);
    }

    // ──────────────────────────────────────────────
    //  Test: Privacy
    // ──────────────────────────────────────────────

    /// @notice Each tipper can see their own total, but not others'.
    function test_tipperCanSeeOwnTotal() public {
        // Alice tips 200
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(200);
        vm.prank(alice);
        jar.tip(h1, p1);

        // Bob tips 300
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(300);
        vm.prank(bob);
        jar.tip(h2, p2);

        // Alice can see her own total
        vm.prank(alice);
        uint64 aliceTotal = mockDecrypt64(jar.getMyTotalTips());
        assertEq(aliceTotal, 200, "Alice should see her own total of 200");

        // Bob can see his own total
        vm.prank(bob);
        uint64 bobTotal = mockDecrypt64(jar.getMyTotalTips());
        assertEq(bobTotal, 300, "Bob should see his own total of 300");
    }
}
