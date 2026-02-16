// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockKMSVerifier
/// @notice Mock KMS Verifier for local testing. Always returns true for decryption verification.
contract MockKMSVerifier {
    function verifyDecryptionEIP712KMSSignatures(bytes32[] memory, bytes memory, bytes memory)
        external
        pure
        returns (bool)
    {
        return true;
    }
}
