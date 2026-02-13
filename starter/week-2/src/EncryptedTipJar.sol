// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title EncryptedTipJar
/// @notice A tip jar where tip amounts are kept confidential using FHE.
///         Tippers can send encrypted tips to a creator. The creator accumulates
///         an encrypted balance that only they can decrypt and withdraw from.
///         Each tipper can also see their own encrypted running total.
///
/// @dev    Week 2 Homework — Implement the TODO sections below.
///         Key FHE operations you will need:
///           - FHE.fromExternal()  — convert external encrypted input to internal handle
///           - FHE.add()           — add two encrypted values
///           - FHE.sub()           — subtract two encrypted values
///           - FHE.le()            — encrypted less-than-or-equal comparison → ebool
///           - FHE.select()        — conditional select: select(cond, ifTrue, ifFalse)
///           - FHE.asEuint64()     — trivially encrypt a plaintext value
///           - FHE.allowThis()     — grant the contract permission to use a handle
///           - FHE.allow()         — grant a specific address permission to decrypt a handle
contract EncryptedTipJar is ZamaEthereumConfig {
    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    /// @notice The creator who receives tips and can withdraw.
    address public creator;

    /// @notice Encrypted total balance available to the creator.
    ///         Only the creator can decrypt this value.
    euint64 private _creatorBalance;

    /// @notice Encrypted running total of tips per tipper.
    ///         Each tipper can only decrypt their own total.
    ///         tipper address => encrypted running total
    mapping(address => euint64) private _tipperTotals;

    // ──────────────────────────────────────────────
    //  Events & Errors
    // ──────────────────────────────────────────────

    event TipSent(address indexed tipper);
    event Withdrawal(address indexed creator);

    error OnlyCreator();

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyCreator() {
        if (msg.sender != creator) revert OnlyCreator();
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    /// @param creator_ The address of the content creator receiving tips.
    constructor(address creator_) {
        creator = creator_;
    }

    // ──────────────────────────────────────────────
    //  Core Functions — TODO: Implement these!
    // ──────────────────────────────────────────────

    /// @notice Send an encrypted tip to the creator.
    /// @param encAmount The encrypted tip amount.
    /// @param inputProof The input proof from the encryption client.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Convert the external encrypted input to an internal euint64:
    ///         euint64 amount = FHE.fromExternal(encAmount, inputProof);
    ///      2. Add the tip to the creator's encrypted balance:
    ///         _creatorBalance = FHE.add(_creatorBalance, amount);
    ///      3. Add the tip to the tipper's encrypted running total:
    ///         _tipperTotals[msg.sender] = FHE.add(_tipperTotals[msg.sender], amount);
    ///      4. Set FHE permissions on the creator balance:
    ///         FHE.allowThis(_creatorBalance);
    ///         FHE.allow(_creatorBalance, creator);
    ///      5. Set FHE permissions on the tipper's total:
    ///         FHE.allowThis(_tipperTotals[msg.sender]);
    ///         FHE.allow(_tipperTotals[msg.sender], msg.sender);
    ///      6. Emit the TipSent event.
    function tip(externalEuint64 encAmount, bytes calldata inputProof) external {
        // TODO: Implement tip logic here
    }

    /// @notice Get the caller's own encrypted total tips sent.
    /// @return The caller's encrypted running total (only decryptable by the caller).
    ///
    /// @dev TODO: Return the encrypted total stored in _tipperTotals for msg.sender.
    function getMyTotalTips() external view returns (euint64) {
        // TODO: Return the caller's encrypted tip total
        return _tipperTotals[msg.sender];
    }

    /// @notice Get the creator's encrypted balance.
    /// @return The encrypted total balance (only decryptable by the creator).
    ///
    /// @dev TODO: Return the encrypted _creatorBalance.
    function getCreatorBalance() external view returns (euint64) {
        // TODO: Return the creator's encrypted balance
        return _creatorBalance;
    }

    /// @notice Withdraw an encrypted amount from the tip jar (creator only).
    /// @param encAmount The encrypted withdrawal amount.
    /// @param inputProof The input proof from the encryption client.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Convert the external encrypted input to an internal euint64:
    ///         euint64 amount = FHE.fromExternal(encAmount, inputProof);
    ///      2. Check if the withdrawal amount is within the creator's balance:
    ///         ebool hasFunds = FHE.le(amount, _creatorBalance);
    ///      3. Use FHE.select() to set actual withdrawal to zero if insufficient balance.
    ///         This is a "silent fail" that preserves privacy — no revert to leak info:
    ///         euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));
    ///      4. Subtract the actual amount from the creator's balance:
    ///         _creatorBalance = FHE.sub(_creatorBalance, actualAmount);
    ///      5. Set FHE permissions on the updated balance:
    ///         FHE.allowThis(_creatorBalance);
    ///         FHE.allow(_creatorBalance, creator);
    ///      6. Emit the Withdrawal event.
    function withdraw(externalEuint64 encAmount, bytes calldata inputProof) external onlyCreator {
        // TODO: Implement withdraw logic with balance-cap silent fail
    }
}
