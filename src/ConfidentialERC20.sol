// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title ConfidentialERC20
/// @notice An ERC20-like token with encrypted balances and encrypted transfer amounts.
///         Balances are private — only the holder can decrypt their own balance.
/// @dev    Demonstrates encrypted balances, transfers with underflow protection,
///         approve/transferFrom with encrypted allowances, and scalar operations.
contract ConfidentialERC20 is ZamaEthereumConfig {
    string public name;
    string public symbol;
    uint8 public constant DECIMALS = 6;
    address public owner;

    /// @notice Encrypted balances per address.
    mapping(address => euint64) private _balances;

    /// @notice Encrypted allowances: owner => spender => encrypted amount.
    mapping(address => mapping(address => euint64)) private _allowances;

    /// @notice Plaintext total supply (minted amounts are public; balances after transfers are not).
    uint64 public totalSupply;

    event Transfer(address indexed from, address indexed to);
    event Approval(address indexed owner, address indexed spender);
    event Mint(address indexed to, uint64 amount);

    error OnlyOwner();

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        if (msg.sender != owner) revert OnlyOwner();
    }

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        owner = msg.sender;
    }

    /// @notice Mint tokens to an address. Only the owner can mint.
    ///         The minted amount is public, but the recipient's total balance remains encrypted.
    /// @param to The recipient address.
    /// @param amount The plaintext amount to mint.
    function mint(address to, uint64 amount) external onlyOwner {
        // Trivially encrypt the mint amount
        euint64 encAmount = FHE.asEuint64(amount);

        // Add to recipient's encrypted balance
        _balances[to] = FHE.add(_balances[to], encAmount);

        // Grant permissions
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);

        totalSupply += amount;

        emit Mint(to, amount);
    }

    /// @notice Transfer an encrypted amount to another address.
    ///         If the sender doesn't have enough balance, the transfer amount is silently set to zero
    ///         (no revert, preserving privacy about whether the transfer succeeded).
    /// @param to The recipient.
    /// @param encAmount The encrypted transfer amount.
    /// @param inputProof The input proof.
    function transfer(address to, externalEuint64 encAmount, bytes calldata inputProof) external {
        euint64 amount = FHE.fromExternal(encAmount, inputProof);
        _transfer(msg.sender, to, amount);
    }

    /// @notice Approve a spender for an encrypted allowance.
    /// @param spender The spender address.
    /// @param encAmount The encrypted allowance amount.
    /// @param inputProof The input proof.
    function approve(address spender, externalEuint64 encAmount, bytes calldata inputProof) external {
        euint64 amount = FHE.fromExternal(encAmount, inputProof);

        _allowances[msg.sender][spender] = amount;

        FHE.allowThis(_allowances[msg.sender][spender]);
        FHE.allow(_allowances[msg.sender][spender], msg.sender);
        FHE.allow(_allowances[msg.sender][spender], spender);

        emit Approval(msg.sender, spender);
    }

    /// @notice Transfer tokens from one address to another using an allowance.
    ///         Both the transfer amount and the allowance check are encrypted.
    /// @param from The sender.
    /// @param to The recipient.
    /// @param encAmount The encrypted transfer amount.
    /// @param inputProof The input proof.
    function transferFrom(
        address from,
        address to,
        externalEuint64 encAmount,
        bytes calldata inputProof
    ) external {
        euint64 amount = FHE.fromExternal(encAmount, inputProof);

        // Check: is amount <= allowance?
        ebool hasAllowance = FHE.le(amount, _allowances[from][msg.sender]);

        // If not enough allowance, set amount to zero (silent fail for privacy)
        euint64 actualAmount = FHE.select(hasAllowance, amount, FHE.asEuint64(0));

        // Deduct from allowance
        _allowances[from][msg.sender] = FHE.sub(_allowances[from][msg.sender], actualAmount);
        FHE.allowThis(_allowances[from][msg.sender]);
        FHE.allow(_allowances[from][msg.sender], from);
        FHE.allow(_allowances[from][msg.sender], msg.sender);

        // Execute the transfer
        _transfer(from, to, actualAmount);
    }

    /// @notice Get the caller's encrypted balance.
    function balanceOf() external view returns (euint64) {
        return _balances[msg.sender];
    }

    /// @notice Get a specific address's encrypted balance handle.
    /// @param account The account to query.
    function balanceOf(address account) external view returns (euint64) {
        return _balances[account];
    }

    /// @notice Get the encrypted allowance for owner -> spender.
    function allowance(address tokenOwner, address spender) external view returns (euint64) {
        return _allowances[tokenOwner][spender];
    }

    // ──────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────

    function _transfer(address from, address to, euint64 amount) internal {
        // Check: is amount <= sender's balance?
        ebool hasFunds = FHE.le(amount, _balances[from]);

        // If insufficient balance, set transfer to zero (silent fail for privacy)
        euint64 actualAmount = FHE.select(hasFunds, amount, FHE.asEuint64(0));

        // Deduct from sender
        _balances[from] = FHE.sub(_balances[from], actualAmount);
        FHE.allowThis(_balances[from]);
        FHE.allow(_balances[from], from);

        // Add to recipient
        _balances[to] = FHE.add(_balances[to], actualAmount);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);

        emit Transfer(from, to);
    }
}
