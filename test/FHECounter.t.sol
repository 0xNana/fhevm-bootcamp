// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest, euint32, externalEuint32} from "./FhevmTest.sol";
import {FHECounter} from "../src/FHECounter.sol";

/// @title FHECounterTest
/// @notice Forge tests for FHECounter, mirroring the Hardhat template test suite.
///         Runs in mock mode by default (FHEVM_MOCK=true).
contract FHECounterTest is FhevmTest {
    FHECounter public counter;

    address public alice;
    address public bob;

    function setUp() public override {
        // Deploy mock FHE infrastructure first
        super.setUp();

        // Create test accounts
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy the FHECounter (constructor calls FHE.setCoprocessor via ZamaEthereumConfig)
        counter = new FHECounter();
    }

    /// @notice Encrypted count should be uninitialized (zero) after deployment.
    function test_initialCountIsZero() public view {
        euint32 encryptedCount = counter.getCount();
        // bytes32(0) means uninitialized, same as ethers.ZeroHash in Hardhat tests
        assertEq(euint32.unwrap(encryptedCount), bytes32(0));
    }

    /// @notice Increment the counter by 1 and verify the decrypted result.
    function test_incrementByOne() public {
        // Verify initial state
        assertEq(euint32.unwrap(counter.getCount()), bytes32(0));

        // Encrypt the value 1 (mirrors: fhevm.createEncryptedInput(...).add32(1).encrypt())
        (externalEuint32 handle, bytes memory inputProof) = mockEncrypt32(1);

        // Call increment as alice
        vm.prank(alice);
        counter.increment(handle, inputProof);

        // Decrypt and verify (mirrors: fhevm.userDecryptEuint(euint32, ciphertext, addr, signer))
        euint32 encryptedCount = counter.getCount();
        uint32 clearCount = mockDecrypt32(encryptedCount);
        assertEq(clearCount, 1);
    }

    /// @notice Increment then decrement, verifying count returns to zero.
    function test_decrementByOne() public {
        // Encrypt constant 1
        (externalEuint32 handle, bytes memory inputProof) = mockEncrypt32(1);

        // Increment by 1 → count becomes 1
        vm.prank(alice);
        counter.increment(handle, inputProof);

        // Decrement by 1 → count goes back to 0
        (externalEuint32 handle2, bytes memory inputProof2) = mockEncrypt32(1);
        vm.prank(alice);
        counter.decrement(handle2, inputProof2);

        // Verify decrypted count is 0
        uint32 clearCount = mockDecrypt32(counter.getCount());
        assertEq(clearCount, 0);
    }

    /// @notice Multiple increments accumulate correctly.
    function test_multipleIncrements() public {
        // Increment by 5
        (externalEuint32 h1, bytes memory p1) = mockEncrypt32(5);
        vm.prank(alice);
        counter.increment(h1, p1);

        // Increment by 3
        (externalEuint32 h2, bytes memory p2) = mockEncrypt32(3);
        vm.prank(alice);
        counter.increment(h2, p2);

        // Should be 8
        uint32 clearCount = mockDecrypt32(counter.getCount());
        assertEq(clearCount, 8);
    }

    /// @notice Different users can increment the counter.
    function test_differentUsersCanIncrement() public {
        // Alice increments by 10
        (externalEuint32 h1, bytes memory p1) = mockEncrypt32(10);
        vm.prank(alice);
        counter.increment(h1, p1);

        // Bob increments by 20
        (externalEuint32 h2, bytes memory p2) = mockEncrypt32(20);
        vm.prank(bob);
        counter.increment(h2, p2);

        // Should be 30
        uint32 clearCount = mockDecrypt32(counter.getCount());
        assertEq(clearCount, 30);
    }
}
