// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title EncryptedPoll
/// @notice A private voting contract where votes are encrypted.
///         Each voter submits an encrypted vote per question, and the tally
///         remains encrypted until the owner decrypts the results.
/// @dev    Week 1 Homework — Implement the TODO sections below.
///         Key FHE operations you will need:
///           - FHE.fromExternal()  — convert an external encrypted input to an internal handle
///           - FHE.add()           — add two encrypted values
///           - FHE.allowThis()     — grant the contract permission to use a handle
///           - FHE.allow()         — grant a specific address permission to decrypt a handle
contract EncryptedPoll is ZamaEthereumConfig {
    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    /// @notice The owner who deployed the poll (can read encrypted tallies).
    address public owner;

    /// @notice Total number of questions in this poll.
    uint8 public questionCount;

    /// @notice Encrypted vote tally per question.
    ///         questionId => encrypted total votes
    mapping(uint8 => euint32) private _voteCounts;

    /// @notice Tracks whether a voter has voted on a given question.
    ///         voter => questionId => has voted
    mapping(address => mapping(uint8 => bool)) private _hasVoted;

    // ──────────────────────────────────────────────
    //  Events & Errors
    // ──────────────────────────────────────────────

    event VoteCast(address indexed voter, uint8 indexed questionId);

    error InvalidQuestion();
    error AlreadyVoted();
    error OnlyOwner();

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier validQuestion(uint8 questionId) {
        if (questionId >= questionCount) revert InvalidQuestion();
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    /// @param questionCount_ The number of questions in this poll (0-indexed).
    /// @param owner_ The address that can decrypt and read vote tallies.
    constructor(uint8 questionCount_, address owner_) {
        questionCount = questionCount_;
        owner = owner_;
    }

    // ──────────────────────────────────────────────
    //  Core Functions — TODO: Implement these!
    // ──────────────────────────────────────────────

    /// @notice Cast an encrypted vote on a specific question.
    /// @param questionId The question to vote on (0-indexed).
    /// @param encVote The encrypted vote value (e.g., 1 for "yes").
    /// @param inputProof The input proof from the encryption client.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Check that the voter hasn't already voted on this question.
    ///         - If they have, revert with AlreadyVoted().
    ///      2. Convert the external encrypted input to an internal euint32:
    ///         euint32 voteValue = FHE.fromExternal(encVote, inputProof);
    ///      3. Add the encrypted vote to the running tally for this question:
    ///         _voteCounts[questionId] = FHE.add(_voteCounts[questionId], voteValue);
    ///      4. Mark the voter as having voted on this question.
    ///      5. Set FHE permissions so the contract and owner can use the tally:
    ///         FHE.allowThis(_voteCounts[questionId]);
    ///         FHE.allow(_voteCounts[questionId], owner);
    ///      6. Emit the VoteCast event.
    function vote(
        uint8 questionId,
        externalEuint32 encVote,
        bytes calldata inputProof
    ) external validQuestion(questionId) {
        // TODO: Implement vote logic here
    }

    /// @notice Get the encrypted vote count for a question.
    /// @param questionId The question to query.
    /// @return The encrypted vote tally (only decryptable by the owner).
    ///
    /// @dev TODO: Return the encrypted vote count stored in _voteCounts for the given questionId.
    function getVoteCount(uint8 questionId) external view validQuestion(questionId) returns (euint32) {
        // TODO: Return the encrypted vote count for the given question
        return _voteCounts[questionId];
    }

    /// @notice Check if a voter has already voted on a specific question.
    /// @param voter The voter address to check.
    /// @param questionId The question to check.
    /// @return True if the voter has already voted on this question.
    ///
    /// @dev TODO: Return the boolean from the _hasVoted mapping for the given voter and questionId.
    function hasVoted(address voter, uint8 questionId) external view validQuestion(questionId) returns (bool) {
        // TODO: Return whether the voter has voted on this question
        return _hasVoted[voter][questionId];
    }
}
