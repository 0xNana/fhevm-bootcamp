// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title EncryptedVault
/// @notice A vault where users deposit and withdraw encrypted amounts.
///         Each user's balance is private — only the depositor can decrypt their own balance.
///         The contract owner can see the aggregate encrypted total.
/// @dev    Demonstrates per-user encrypted state, granular ACL, and FHE.select for conditionals.
contract EncryptedVault is ZamaEthereumConfig {
    address public owner;

    /// @notice Per-user encrypted balance.
    mapping(address => euint64) private _balances;

    /// @notice Aggregate encrypted total across all users.
    euint64 private _totalDeposits;

    /// @notice Emitted when a user deposits.
    event Deposit(address indexed user);

    /// @notice Emitted when a user withdraws.
    event Withdraw(address indexed user);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Deposit an encrypted amount.
    /// @param encAmount The encrypted deposit amount.
    /// @param inputProof The input proof.
    function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
        euint64 amount = FHE.fromExternal(encAmount, inputProof);

        // Add to user's encrypted balance
        _balances[msg.sender] = FHE.add(_balances[msg.sender], amount);

        // Update aggregate total
        _totalDeposits = FHE.add(_totalDeposits, amount);

        // Grant permissions
        FHE.allowThis(_balances[msg.sender]);
        FHE.allow(_balances[msg.sender], msg.sender);

        FHE.allowThis(_totalDeposits);
        FHE.allow(_totalDeposits, owner);

        emit Deposit(msg.sender);
    }

    /// @notice Withdraw an encrypted amount. Silently caps at the user's balance
    ///         (if the requested amount exceeds balance, withdraws the full balance).
    /// @param encAmount The encrypted withdrawal amount.
    /// @param inputProof The input proof.
    function withdraw(externalEuint64 encAmount, bytes calldata inputProof) external {
        euint64 amount = FHE.fromExternal(encAmount, inputProof);

        // Check: is amount <= balance?
        ebool canWithdraw = FHE.le(amount, _balances[msg.sender]);

        // If amount > balance, cap at balance (withdraw everything)
        euint64 actualAmount = FHE.select(canWithdraw, amount, _balances[msg.sender]);

        // Subtract from user's balance
        _balances[msg.sender] = FHE.sub(_balances[msg.sender], actualAmount);

        // Subtract from aggregate total
        _totalDeposits = FHE.sub(_totalDeposits, actualAmount);

        // Grant permissions on updated values
        FHE.allowThis(_balances[msg.sender]);
        FHE.allow(_balances[msg.sender], msg.sender);

        FHE.allowThis(_totalDeposits);
        FHE.allow(_totalDeposits, owner);

        emit Withdraw(msg.sender);
    }

    /// @notice Get the caller's encrypted balance.
    /// @return The caller's encrypted balance (only they can decrypt it).
    function getBalance() external view returns (euint64) {
        return _balances[msg.sender];
    }

    /// @notice Get any user's encrypted balance handle.
    ///         Only the user themselves or the contract can meaningfully use this.
    /// @param user The user whose balance to query.
    /// @return The encrypted balance.
    function getBalanceOf(address user) external view returns (euint64) {
        return _balances[user];
    }

    /// @notice Get the aggregate encrypted total deposits.
    ///         Only the owner has permission to decrypt this.
    /// @return The encrypted total deposits.
    function getTotalDeposits() external view returns (euint64) {
        return _totalDeposits;
    }
}
