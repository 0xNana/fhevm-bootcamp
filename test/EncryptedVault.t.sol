// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "./FhevmTest.sol";
import {externalEuint64} from "encrypted-types/EncryptedTypes.sol";
import {EncryptedVault} from "../src/EncryptedVault.sol";

/// @title EncryptedVaultTest
/// @notice Tests for the EncryptedVault demonstrating per-user encrypted balances and ACL.
contract EncryptedVaultTest is FhevmTest {
    EncryptedVault public vault;

    address public deployer;
    address public alice;
    address public bob;

    function setUp() public override {
        super.setUp();

        deployer = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vault = new EncryptedVault();
    }

    // ──────────────────────────────────────────────
    //  Deposit Tests
    // ──────────────────────────────────────────────

    function test_depositUpdatesBalance() public {
        (externalEuint64 handle, bytes memory proof) = mockEncrypt64(1000);

        vm.prank(alice);
        vault.deposit(handle, proof);

        // Alice can read her own balance
        vm.prank(alice);
        uint64 balance = mockDecrypt64(vault.getBalance());
        assertEq(balance, 1000);
    }

    function test_multipleDepositsAccumulate() public {
        // First deposit: 500
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(500);
        vm.prank(alice);
        vault.deposit(h1, p1);

        // Second deposit: 300
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(300);
        vm.prank(alice);
        vault.deposit(h2, p2);

        vm.prank(alice);
        uint64 balance = mockDecrypt64(vault.getBalance());
        assertEq(balance, 800);
    }

    function test_differentUsersHaveSeparateBalances() public {
        // Alice deposits 1000
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
        vm.prank(alice);
        vault.deposit(h1, p1);

        // Bob deposits 2000
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(2000);
        vm.prank(bob);
        vault.deposit(h2, p2);

        // Check Alice's balance
        vm.prank(alice);
        assertEq(mockDecrypt64(vault.getBalance()), 1000);

        // Check Bob's balance
        vm.prank(bob);
        assertEq(mockDecrypt64(vault.getBalance()), 2000);
    }

    // ──────────────────────────────────────────────
    //  Withdraw Tests
    // ──────────────────────────────────────────────

    function test_withdrawReducesBalance() public {
        // Deposit 1000
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
        vm.prank(alice);
        vault.deposit(h1, p1);

        // Withdraw 400
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(400);
        vm.prank(alice);
        vault.withdraw(h2, p2);

        vm.prank(alice);
        assertEq(mockDecrypt64(vault.getBalance()), 600);
    }

    function test_withdrawCapsAtBalance() public {
        // Deposit 500
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(500);
        vm.prank(alice);
        vault.deposit(h1, p1);

        // Try to withdraw 999 (more than balance) — should cap at 500
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(999);
        vm.prank(alice);
        vault.withdraw(h2, p2);

        vm.prank(alice);
        assertEq(mockDecrypt64(vault.getBalance()), 0);
    }

    // ──────────────────────────────────────────────
    //  Total Deposits Tests
    // ──────────────────────────────────────────────

    function test_totalDepositsAggregates() public {
        // Alice deposits 1000
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
        vm.prank(alice);
        vault.deposit(h1, p1);

        // Bob deposits 2000
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(2000);
        vm.prank(bob);
        vault.deposit(h2, p2);

        // Owner (deployer) can see aggregate total
        uint64 total = mockDecrypt64(vault.getTotalDeposits());
        assertEq(total, 3000);
    }

    function test_totalDepositsDecreasesOnWithdraw() public {
        // Alice deposits 1000
        (externalEuint64 h1, bytes memory p1) = mockEncrypt64(1000);
        vm.prank(alice);
        vault.deposit(h1, p1);

        // Alice withdraws 400
        (externalEuint64 h2, bytes memory p2) = mockEncrypt64(400);
        vm.prank(alice);
        vault.withdraw(h2, p2);

        uint64 total = mockDecrypt64(vault.getTotalDeposits());
        assertEq(total, 600);
    }
}
