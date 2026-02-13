// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

// Re-export commonly used encrypted types for convenience
import {
    ebool,
    euint8,
    euint16,
    euint32,
    euint64,
    euint128,
    euint256,
    eaddress,
    externalEbool,
    externalEuint8,
    externalEuint16,
    externalEuint32,
    externalEuint64,
    externalEuint128,
    externalEuint256,
    externalEaddress
} from "encrypted-types/EncryptedTypes.sol";

import {MockFHEVMExecutor} from "./mocks/MockFHEVMExecutor.sol";
import {MockACL} from "./mocks/MockACL.sol";
import {MockInputVerifier} from "./mocks/MockInputVerifier.sol";
import {MockKMSVerifier} from "./mocks/MockKMSVerifier.sol";

/// @title FhevmTest
/// @notice Base test contract for FHEVM Foundry tests.
///         Deploys mock FHE infrastructure (coprocessor, ACL, KMS, InputVerifier) to the
///         well-known local addresses defined in ZamaConfig for chainId 31337.
///
/// @dev    In mock mode, "encrypted" handles are simply bytes32-encoded plaintext values.
///         This gives fast, deterministic tests without real FHE computation.
///
///         Inherit from this contract instead of forge-std Test:
///         ```
///         contract MyTest is FhevmTest { ... }
///         ```
abstract contract FhevmTest is Test {
    // ──────────────────────────────────────────────
    //  Well-known local addresses (from ZamaConfig.sol, chainId == 31337)
    // ──────────────────────────────────────────────

    address internal constant ACL_ADDRESS = 0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D;
    address internal constant COPROCESSOR_ADDRESS = 0xe3a9105a3a932253A70F126eb1E3b589C643dD24;
    address internal constant KMS_VERIFIER_ADDRESS = 0x901F8942346f7AB3a01F6D7613119Bca447Bb030;
    address internal constant INPUT_VERIFIER_ADDRESS = 0x0000000000000000000000000000000000000069;

    /// @notice Whether tests are running in mock mode.
    bool public isMock;

    // ──────────────────────────────────────────────
    //  Setup
    // ──────────────────────────────────────────────

    function setUp() public virtual {
        isMock = vm.envOr("FHEVM_MOCK", true);

        if (isMock) {
            _deployMocks();
        }
    }

    /// @dev Deploys mock contracts and etches their bytecode to the well-known addresses
    ///      that ZamaConfig expects on chainId 31337.
    function _deployMocks() internal {
        // Deploy mock implementations (they get temporary addresses)
        MockFHEVMExecutor executor = new MockFHEVMExecutor();
        MockACL acl = new MockACL();
        MockInputVerifier inputVerifier = new MockInputVerifier();
        MockKMSVerifier kmsVerifier = new MockKMSVerifier();

        // Etch runtime bytecode to the addresses that the FHEVM contracts expect
        vm.etch(COPROCESSOR_ADDRESS, address(executor).code);
        vm.etch(ACL_ADDRESS, address(acl).code);
        vm.etch(INPUT_VERIFIER_ADDRESS, address(inputVerifier).code);
        vm.etch(KMS_VERIFIER_ADDRESS, address(kmsVerifier).code);
    }

    // ──────────────────────────────────────────────
    //  Mock Encryption Helpers
    //
    //  Usage mirrors the Hardhat fhevmjs pattern:
    //    const encrypted = fhevm.createEncryptedInput(addr, user).add32(val).encrypt();
    //    contract.increment(encrypted.handles[0], encrypted.inputProof);
    //
    //  Foundry equivalent:
    //    (externalEuint32 handle, bytes memory proof) = mockEncrypt32(val);
    //    counter.increment(handle, proof);
    // ──────────────────────────────────────────────

    function mockEncryptBool(bool value) internal pure returns (externalEbool, bytes memory) {
        bytes32 handle = bytes32(uint256(value ? 1 : 0));
        bytes memory inputProof = new bytes(1); // non-empty → goes through verifyInput path
        return (externalEbool.wrap(handle), inputProof);
    }

    function mockEncrypt8(uint8 value) internal pure returns (externalEuint8, bytes memory) {
        bytes32 handle = bytes32(uint256(value));
        bytes memory inputProof = new bytes(1);
        return (externalEuint8.wrap(handle), inputProof);
    }

    function mockEncrypt16(uint16 value) internal pure returns (externalEuint16, bytes memory) {
        bytes32 handle = bytes32(uint256(value));
        bytes memory inputProof = new bytes(1);
        return (externalEuint16.wrap(handle), inputProof);
    }

    function mockEncrypt32(uint32 value) internal pure returns (externalEuint32, bytes memory) {
        bytes32 handle = bytes32(uint256(value));
        bytes memory inputProof = new bytes(1);
        return (externalEuint32.wrap(handle), inputProof);
    }

    function mockEncrypt64(uint64 value) internal pure returns (externalEuint64, bytes memory) {
        bytes32 handle = bytes32(uint256(value));
        bytes memory inputProof = new bytes(1);
        return (externalEuint64.wrap(handle), inputProof);
    }

    function mockEncrypt128(uint128 value) internal pure returns (externalEuint128, bytes memory) {
        bytes32 handle = bytes32(uint256(value));
        bytes memory inputProof = new bytes(1);
        return (externalEuint128.wrap(handle), inputProof);
    }

    function mockEncrypt256(uint256 value) internal pure returns (externalEuint256, bytes memory) {
        bytes32 handle = bytes32(value);
        bytes memory inputProof = new bytes(1);
        return (externalEuint256.wrap(handle), inputProof);
    }

    function mockEncryptAddress(address value) internal pure returns (externalEaddress, bytes memory) {
        bytes32 handle = bytes32(uint256(uint160(value)));
        bytes memory inputProof = new bytes(1);
        return (externalEaddress.wrap(handle), inputProof);
    }

    // ──────────────────────────────────────────────
    //  Mock Decryption Helpers
    //
    //  Usage mirrors: fhevm.userDecryptEuint(type, ciphertext, contractAddr, signer)
    //
    //  Foundry equivalent:
    //    uint32 clear = mockDecrypt32(counter.getCount());
    // ──────────────────────────────────────────────

    function mockDecryptBool(ebool value) internal pure returns (bool) {
        return uint256(ebool.unwrap(value)) != 0;
    }

    function mockDecrypt8(euint8 value) internal pure returns (uint8) {
        return uint8(uint256(euint8.unwrap(value)));
    }

    function mockDecrypt16(euint16 value) internal pure returns (uint16) {
        return uint16(uint256(euint16.unwrap(value)));
    }

    function mockDecrypt32(euint32 value) internal pure returns (uint32) {
        return uint32(uint256(euint32.unwrap(value)));
    }

    function mockDecrypt64(euint64 value) internal pure returns (uint64) {
        return uint64(uint256(euint64.unwrap(value)));
    }

    function mockDecrypt128(euint128 value) internal pure returns (uint128) {
        return uint128(uint256(euint128.unwrap(value)));
    }

    function mockDecrypt256(euint256 value) internal pure returns (uint256) {
        return uint256(euint256.unwrap(value));
    }

    function mockDecryptAddress(eaddress value) internal pure returns (address) {
        return address(uint160(uint256(eaddress.unwrap(value))));
    }
}
