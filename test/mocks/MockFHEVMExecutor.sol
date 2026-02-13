// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FheType} from "@fhevm/solidity/lib/FheType.sol";

/// @title MockFHEVMExecutor
/// @notice Mock coprocessor for local testing. "Encrypted" handles are simply bytes32-encoded
///         plaintext values, so all FHE operations reduce to their plaintext equivalents.
contract MockFHEVMExecutor {
    /// @dev Fixed address where MockInputVerifier is expected to be etched.
    address public constant MOCK_INPUT_VERIFIER = 0x0000000000000000000000000000000000000069;

    /// @dev Counter for deterministic mock random values.
    uint256 private _randCounter;

    // ──────────────────────────────────────────────
    //  Arithmetic
    // ──────────────────────────────────────────────

    function fheAdd(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return bytes32(uint256(lhs) + uint256(rhs));
    }

    function fheSub(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return bytes32(uint256(lhs) - uint256(rhs));
    }

    function fheMul(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return bytes32(uint256(lhs) * uint256(rhs));
    }

    function fheDiv(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        uint256 r = uint256(rhs);
        if (r == 0) return bytes32(0);
        return bytes32(uint256(lhs) / r);
    }

    function fheRem(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        uint256 r = uint256(rhs);
        if (r == 0) return bytes32(0);
        return bytes32(uint256(lhs) % r);
    }

    // ──────────────────────────────────────────────
    //  Bitwise
    // ──────────────────────────────────────────────

    function fheBitAnd(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return lhs & rhs;
    }

    function fheBitOr(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return lhs | rhs;
    }

    function fheBitXor(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return lhs ^ rhs;
    }

    function fheShl(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return bytes32(uint256(lhs) << uint256(rhs));
    }

    function fheShr(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return bytes32(uint256(lhs) >> uint256(rhs));
    }

    function fheRotl(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        // Simplified: treat as shift left (rotation not meaningful for 256-bit in mock)
        return bytes32(uint256(lhs) << uint256(rhs));
    }

    function fheRotr(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        // Simplified: treat as shift right
        return bytes32(uint256(lhs) >> uint256(rhs));
    }

    // ──────────────────────────────────────────────
    //  Comparison  (returns 1 for true, 0 for false)
    // ──────────────────────────────────────────────

    function fheEq(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) == uint256(rhs) ? bytes32(uint256(1)) : bytes32(uint256(0));
    }

    function fheNe(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) != uint256(rhs) ? bytes32(uint256(1)) : bytes32(uint256(0));
    }

    function fheGe(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) >= uint256(rhs) ? bytes32(uint256(1)) : bytes32(uint256(0));
    }

    function fheGt(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) > uint256(rhs) ? bytes32(uint256(1)) : bytes32(uint256(0));
    }

    function fheLe(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) <= uint256(rhs) ? bytes32(uint256(1)) : bytes32(uint256(0));
    }

    function fheLt(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) < uint256(rhs) ? bytes32(uint256(1)) : bytes32(uint256(0));
    }

    function fheMin(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) <= uint256(rhs) ? lhs : rhs;
    }

    function fheMax(bytes32 lhs, bytes32 rhs, bytes1) external pure returns (bytes32) {
        return uint256(lhs) >= uint256(rhs) ? lhs : rhs;
    }

    // ──────────────────────────────────────────────
    //  Unary
    // ──────────────────────────────────────────────

    function fheNeg(bytes32 ct) external pure returns (bytes32) {
        return bytes32(uint256(0) - uint256(ct));
    }

    function fheNot(bytes32 ct) external pure returns (bytes32) {
        return ~ct;
    }

    // ──────────────────────────────────────────────
    //  Input / Encrypt / Cast / Select
    // ──────────────────────────────────────────────

    /// @notice In mock mode, verification is a pass-through — the handle IS the plaintext.
    function verifyInput(bytes32 inputHandle, address, bytes memory, FheType) external pure returns (bytes32) {
        return inputHandle;
    }

    /// @notice Cast is a no-op in mock mode (no type metadata in handles).
    function cast(bytes32 ct, FheType) external pure returns (bytes32) {
        return ct;
    }

    /// @notice Trivial encrypt: encode the plaintext value directly as a bytes32 handle.
    function trivialEncrypt(uint256 ct, FheType) external pure returns (bytes32) {
        return bytes32(ct);
    }

    /// @notice Ternary select: if control != 0 return ifTrue, else ifFalse.
    function fheIfThenElse(bytes32 control, bytes32 ifTrue, bytes32 ifFalse) external pure returns (bytes32) {
        return uint256(control) != 0 ? ifTrue : ifFalse;
    }

    // ──────────────────────────────────────────────
    //  Random (deterministic for reproducible tests)
    // ──────────────────────────────────────────────

    function fheRand(FheType) external returns (bytes32) {
        return bytes32(++_randCounter);
    }

    function fheRandBounded(uint256 upperBound, FheType) external returns (bytes32) {
        if (upperBound == 0) return bytes32(0);
        return bytes32((++_randCounter) % upperBound);
    }

    // ──────────────────────────────────────────────
    //  Metadata
    // ──────────────────────────────────────────────

    function getInputVerifierAddress() external pure returns (address) {
        return MOCK_INPUT_VERIFIER;
    }
}
