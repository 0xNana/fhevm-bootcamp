// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "./FhevmTest.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {ConfidentialERC20} from "../src/ConfidentialERC20.sol";

/// @title ConfidentialERC20Test
/// @notice Tests for the confidential ERC20 token with encrypted balances.
contract ConfidentialERC20Test is FhevmTest {
    ConfidentialERC20 public token;

    address public deployer;
    address public alice;
    address public bob;
    address public charlie;

    function setUp() public override {
        super.setUp();

        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        token = new ConfidentialERC20("Confidential Token", "CFHE");
    }

    // ──────────────────────────────────────────────
    //  Mint Tests
    // ──────────────────────────────────────────────

    function test_mintUpdatesBalance() public {
        token.mint(alice, 1_000_000);

        vm.prank(alice);
        uint64 balance = mockDecrypt64(token.balanceOf());
        assertEq(balance, 1_000_000);
    }

    function test_mintUpdatesTotalSupply() public {
        token.mint(alice, 500_000);
        token.mint(bob, 300_000);

        assertEq(token.totalSupply(), 800_000);
    }

    function test_mintOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(ConfidentialERC20.OnlyOwner.selector);
        token.mint(alice, 1000);
    }

    // ──────────────────────────────────────────────
    //  Transfer Tests
    // ──────────────────────────────────────────────

    function test_transferMovesBalance() public {
        token.mint(alice, 1_000_000);

        // Alice transfers 400,000 to Bob
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(400_000);
        vm.prank(alice);
        token.transfer(bob, handle, proof);

        // Alice should have 600,000
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 600_000);

        // Bob should have 400,000
        vm.prank(bob);
        assertEq(mockDecrypt64(token.balanceOf()), 400_000);
    }

    function test_transferInsufficientBalanceSilentFails() public {
        token.mint(alice, 100);

        // Alice tries to transfer 999 (more than she has)
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(999);
        vm.prank(alice);
        token.transfer(bob, handle, proof);

        // Alice still has 100 (transfer was silently zeroed)
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 100);

        // Bob has 0
        vm.prank(bob);
        assertEq(mockDecrypt64(token.balanceOf()), 0);
    }

    // ──────────────────────────────────────────────
    //  Approve + TransferFrom Tests
    // ──────────────────────────────────────────────

    function test_approveAndTransferFrom() public {
        token.mint(alice, 1_000_000);

        // Alice approves Bob for 500,000
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(500_000);
        vm.prank(alice);
        token.approve(bob, h1, p1);

        // Bob transfers 200,000 from Alice to Charlie
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(200_000);
        vm.prank(bob);
        token.transferFrom(alice, charlie, h2, p2);

        // Alice: 1,000,000 - 200,000 = 800,000
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 800_000);

        // Charlie: 200,000
        vm.prank(charlie);
        assertEq(mockDecrypt64(token.balanceOf()), 200_000);
    }

    function test_transferFromExceedsAllowanceSilentFails() public {
        token.mint(alice, 1_000_000);

        // Alice approves Bob for 100
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(100);
        vm.prank(alice);
        token.approve(bob, h1, p1);

        // Bob tries to transferFrom 500 (exceeds allowance)
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(500);
        vm.prank(bob);
        token.transferFrom(alice, charlie, h2, p2);

        // Alice still has 1,000,000 (transfer was silently zeroed due to allowance check)
        vm.prank(alice);
        assertEq(mockDecrypt64(token.balanceOf()), 1_000_000);

        // Charlie has 0
        vm.prank(charlie);
        assertEq(mockDecrypt64(token.balanceOf()), 0);
    }

    // ──────────────────────────────────────────────
    //  Metadata Tests
    // ──────────────────────────────────────────────

    function test_tokenMetadata() public view {
        assertEq(token.name(), "Confidential Token");
        assertEq(token.symbol(), "CFHE");
        assertEq(token.DECIMALS(), 6);
    }
}
