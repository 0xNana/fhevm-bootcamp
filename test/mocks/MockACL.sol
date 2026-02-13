// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockACL
/// @notice Mock Access Control List for local testing. All operations are permissive no-ops.
contract MockACL {
    function allowTransient(bytes32, address) external {}

    function allow(bytes32, address) external {}

    function isAllowed(bytes32, address) external pure returns (bool) {
        return true;
    }

    function cleanTransientStorage() external {}

    function allowForDecryption(bytes32[] memory) external {}

    function persistAllowed(bytes32, address) external pure returns (bool) {
        return true;
    }

    function isAllowedForDecryption(bytes32) external pure returns (bool) {
        return true;
    }

    function isAccountDenied(address) external pure returns (bool) {
        return false;
    }

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
    }

    function delegateForUserDecryption(address, address, uint64) external {}

    function revokeDelegationForUserDecryption(address, address) external {}

    function getUserDecryptionDelegationExpirationDate(address, address, address) external pure returns (uint64) {
        return 0;
    }

    function isHandleDelegatedForUserDecryption(address, address, address, bytes32) external pure returns (bool) {
        return false;
    }
}
