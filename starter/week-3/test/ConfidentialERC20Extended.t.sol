// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "../../../test/FhevmTest.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {ConfidentialERC20Extended} from "../src/ConfidentialERC20Extended.sol";

/// @title ConfidentialERC20ExtendedTest
/// @notice Tests for the Week 3 homework — Confidential ERC20 with burn, encrypted supply, and transfer cap.
///         Your implementation must pass all of these tests.
///
///         Run with:  forge test --match-contract ConfidentialERC20ExtendedTest -vvv
contract ConfidentialERC20ExtendedTest is FhevmTest {
    ConfidentialERC20Extended public token;

    address public deployer;
    address public alice;
    address public bob;

    function setUp() public override {
        super.setUp();

        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new ConfidentialERC20Extended("Extended Token", "XFHE");
    }

    // ──────────────────────────────────────────────
    //  Test: Burn
    // ──────────────────────────────────────────────

    /// @notice Minting then burning should reduce the balance correctly.
    function test_mintAndBurn() public {
        token.mint(alice, 1_000_000);

        // Alice burns 300,000
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(300_000);
        vm.prank(alice);
        token.burn(handle, proof);

        // Alice should have 700,000
        vm.prank(alice);
        uint64 balance = mockDecrypt64(token.balanceOf());
        assertEq(balance, 700_000, "Balance should be 700,000 after burning 300,000");
    }

    /// @notice Burning more than the balance should silently burn zero (no revert).
    function test_burnCapsAtBalance() public {
        token.mint(alice, 500);

        // Alice tries to burn 999 (more than her balance)
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(999);
        vm.prank(alice);
        token.burn(handle, proof);

        // Balance should be unchanged — burn was silently zeroed
        vm.prank(alice);
        uint64 balance = mockDecrypt64(token.balanceOf());
        assertEq(balance, 500, "Balance should be unchanged after over-burn");
    }

    // ──────────────────────────────────────────────
    //  Test: Encrypted Total Supply
    // ──────────────────────────────────────────────

    /// @notice Minting should update the encrypted total supply.
    function test_encryptedTotalSupplyUpdatesOnMint() public {
        token.mint(alice, 1_000);
        token.mint(bob, 2_000);

        uint64 encSupply = mockDecrypt64(token.encryptedTotalSupply());
        assertEq(encSupply, 3_000, "Encrypted total supply should be 3,000");
    }

    /// @notice Burning should decrease the encrypted total supply.
    function test_encryptedTotalSupplyUpdatesOnBurn() public {
        token.mint(alice, 5_000);

        // Alice burns 2,000
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(2_000);
        vm.prank(alice);
        token.burn(handle, proof);

        uint64 encSupply = mockDecrypt64(token.encryptedTotalSupply());
        assertEq(encSupply, 3_000, "Encrypted total supply should be 3,000 after burn");
    }

    // ──────────────────────────────────────────────
    //  Test: Transfer Cap
    // ──────────────────────────────────────────────

    /// @notice Transfers exceeding the cap should be silently zeroed.
    function test_transferCapEnforced() public {
        token.mint(alice, 1_000_000);

        // Set a transfer cap of 100
        token.setTransferCap(100);

        // Alice tries to transfer 500 (over the cap)
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(500);
        vm.prank(alice);
        token.transfer(bob, handle, proof);

        // Alice should still have 1,000,000 (transfer was silently zeroed due to cap)
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 1_000_000, "Sender balance unchanged - over cap");

        // Bob should have 0
        vm.prank(bob);
        assertEq(mockDecrypt64(token.balanceOf()), 0, "Receiver got nothing - over cap");
    }

    /// @notice Transfers under the cap should succeed normally.
    function test_transferUnderCapSucceeds() public {
        token.mint(alice, 1_000_000);

        // Set a transfer cap of 1000
        token.setTransferCap(1000);

        // Alice transfers 500 (under the cap)
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(500);
        vm.prank(alice);
        token.transfer(bob, handle, proof);

        // Alice: 1,000,000 - 500 = 999,500
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 999_500, "Sender should have 999,500");

        // Bob: 500
        vm.prank(bob);
        assertEq(mockDecrypt64(token.balanceOf()), 500, "Receiver should have 500");
    }

    /// @notice Double protection: transfer must pass BOTH the cap check AND the balance check.
    ///         A transfer under the cap but over the balance should also be zeroed.
    function test_doubleProtection() public {
        token.mint(alice, 50);

        // Set a transfer cap of 1000 (high cap)
        token.setTransferCap(1000);

        // Alice tries to transfer 100 (under cap, but OVER her balance of 50)
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(100);
        vm.prank(alice);
        token.transfer(bob, handle, proof);

        // Alice should still have 50 (transfer zeroed due to insufficient balance)
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 50, "Sender balance unchanged - over balance");

        // Bob should have 0
        vm.prank(bob);
        assertEq(mockDecrypt64(token.balanceOf()), 0, "Receiver got nothing - sender had insufficient balance");
    }

    // ──────────────────────────────────────────────
    //  Test: Access Control
    // ──────────────────────────────────────────────

    /// @notice Only the owner can set the transfer cap.
    function test_onlyOwnerCanSetCap() public {
        vm.prank(alice);
        vm.expectRevert(ConfidentialERC20Extended.OnlyOwner.selector);
        token.setTransferCap(100);
    }
}
