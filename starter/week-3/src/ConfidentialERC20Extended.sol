// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title ConfidentialERC20Extended
/// @notice An ERC20-like token with encrypted balances — extended with burn, encrypted total
///         supply tracking, and a per-transfer cap.
///
/// @dev    Week 3 Homework — The base mint/transfer/approve/transferFrom functions are provided
///         as working reference code. You must implement the TODO sections:
///           - burn()                  — burn tokens from the caller's encrypted balance
///           - encryptedTotalSupply()  — return the encrypted total supply
///           - setTransferCap()        — set a per-transfer maximum
///           - Modify _transfer()      — enforce the transfer cap alongside the balance check
///
///         Key FHE pattern for "double protection" in _transfer:
///           1. Check amount <= balance      (existing)
///           2. Check amount <= transferCap   (new — TODO)
///           3. Both must pass for the transfer to go through; otherwise amount → 0
contract ConfidentialERC20Extended is ZamaEthereumConfig {
    // ──────────────────────────────────────────────
    //  State (base)
    // ──────────────────────────────────────────────

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

    // ──────────────────────────────────────────────
    //  State (extended — Week 3)
    // ──────────────────────────────────────────────

    /// @notice Encrypted total supply tracker.
    ///         Updated on mint and burn so the total supply can be queried privately.
    euint64 private _encryptedTotalSupply;

    /// @notice Per-transfer cap. If non-zero, no single transfer can exceed this amount.
    ///         Transfers over the cap are silently zeroed (privacy-preserving).
    uint64 public transferCap;

    // ──────────────────────────────────────────────
    //  Events & Errors
    // ──────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to);
    event Approval(address indexed owner, address indexed spender);
    event Mint(address indexed to, uint64 amount);
    event Burn(address indexed from);

    error OnlyOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        owner = msg.sender;
    }

    // ══════════════════════════════════════════════
    //  REFERENCE CODE — These functions are complete
    // ══════════════════════════════════════════════

    /// @notice Mint tokens to an address. Only the owner can mint.
    /// @param to The recipient address.
    /// @param amount The plaintext amount to mint.
    function mint(address to, uint64 amount) external onlyOwner {
        euint64 encAmount = FHE.asEuint64(amount);

        _balances[to] = FHE.add(_balances[to], encAmount);
        FHE.allowThis(_balances[to]);
        FHE.allow(_balances[to], to);

        // Also update the encrypted total supply
        _encryptedTotalSupply = FHE.add(_encryptedTotalSupply, encAmount);
        FHE.allowThis(_encryptedTotalSupply);
        FHE.allow(_encryptedTotalSupply, owner);

        totalSupply += amount;

        emit Mint(to, amount);
    }

    /// @notice Transfer an encrypted amount to another address.
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

        ebool hasAllowance = FHE.le(amount, _allowances[from][msg.sender]);
        euint64 actualAmount = FHE.select(hasAllowance, amount, FHE.asEuint64(0));

        _allowances[from][msg.sender] = FHE.sub(_allowances[from][msg.sender], actualAmount);
        FHE.allowThis(_allowances[from][msg.sender]);
        FHE.allow(_allowances[from][msg.sender], from);
        FHE.allow(_allowances[from][msg.sender], msg.sender);

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

    // ══════════════════════════════════════════════
    //  TODO: Implement these new functions!
    // ══════════════════════════════════════════════

    /// @notice Burn tokens from the caller's encrypted balance.
    ///         If the burn amount exceeds the caller's balance, the burn is silently
    ///         zeroed (privacy-preserving — no revert to leak balance info).
    /// @param encAmount The encrypted amount to burn.
    /// @param inputProof The input proof.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Convert the external encrypted input:
    ///         euint64 amount = FHE.fromExternal(encAmount, inputProof);
    ///      2. Check if the burn amount <= caller's balance:
    ///         ebool hasFunds = FHE.le(amount, _balances[msg.sender]);
    ///      3. Use FHE.select() to zero the burn if insufficient balance:
    ///         euint64 actualBurn = FHE.select(hasFunds, amount, FHE.asEuint64(0));
    ///      4. Subtract from the caller's balance:
    ///         _balances[msg.sender] = FHE.sub(_balances[msg.sender], actualBurn);
    ///      5. Subtract from the encrypted total supply:
    ///         _encryptedTotalSupply = FHE.sub(_encryptedTotalSupply, actualBurn);
    ///      6. Set FHE permissions on both updated values.
    ///      7. Emit the Burn event.
    function burn(externalEuint64 encAmount, bytes calldata inputProof) external {
        // TODO: Implement burn logic with balance-cap silent fail
    }

    /// @notice Get the encrypted total supply.
    /// @return The encrypted total supply handle (only decryptable by the owner).
    ///
    /// @dev TODO: Return _encryptedTotalSupply.
    function encryptedTotalSupply() external view returns (euint64) {
        // TODO: Return the encrypted total supply
        return _encryptedTotalSupply;
    }

    /// @notice Set the per-transfer cap. Only the owner can set this.
    /// @param cap The maximum amount a single transfer can move. Set to 0 to disable.
    ///
    /// @dev TODO: Implement this function. You should:
    ///      1. Set the transferCap state variable to the given cap value.
    function setTransferCap(uint64 cap) external onlyOwner {
        // TODO: Set the transfer cap
    }

    // ──────────────────────────────────────────────
    //  Internal — TODO: Modify _transfer!
    // ──────────────────────────────────────────────

    /// @dev Internal transfer with balance check AND transfer cap enforcement.
    ///
    /// TODO: Add transfer cap enforcement BEFORE the balance check.
    ///       If transferCap > 0, check that amount <= transferCap.
    ///       If over the cap, zero the amount (silent fail).
    ///       The "double protection" means BOTH the cap check and the balance check
    ///       must pass for the transfer to go through.
    ///
    ///       Steps to add (before the existing balance check):
    ///       1. If transferCap > 0:
    ///          ebool isUnderCap = FHE.le(amount, FHE.asEuint64(transferCap));
    ///          amount = FHE.select(isUnderCap, amount, FHE.asEuint64(0));
    ///       2. Then proceed with the existing balance check below.
    function _transfer(address from, address to, euint64 amount) internal {
        // ┌─────────────────────────────────────────┐
        // │  TODO: Add transfer cap check here      │
        // │  (before the balance check below)       │
        // └─────────────────────────────────────────┘

        // Existing balance check (do NOT remove)
        ebool hasFunds = FHE.le(amount, _balances[from]);
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
