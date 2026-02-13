# Lesson 2: From Mock to Mainnet — Deployment & Frontend

**Duration:** ~60 minutes | **Prerequisites:** [Lesson 1: Sealed-Bid Auction](/week-4/lesson-1-auction) | **Script:** `script/Deploy.s.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Understand the **difference between mock mode and real mode** — what changes when encryption is real
- Write and execute a **Forge deployment script** to deploy FHE contracts to Sepolia
- Integrate **`fhevmjs`** for real client-side encryption and decryption
- Use **`createEncryptedInput`** to encrypt values client-side and submit them to contracts
- Use **off-chain decryption** to read encrypted values with proper permissions
- **Verify contracts** on Etherscan after deployment
- Complete a comprehensive **mainnet deployment checklist** covering security, privacy, and operations
- Know the **security considerations** specific to FHE contracts in production

---

## 1. Mock Mode vs Real Mode

Throughout this bootcamp, you've used **mock mode** — where encrypted values are just plaintext encoded as `bytes32`. This made development fast and deterministic, but provided no actual privacy. Now it's time to understand what changes when you deploy to a real FHEVM network.

| Aspect | Mock Mode | Real Mode |
|--------|-----------|-----------|
| Encryption | Plaintext in bytes32 | Actual FHE ciphertext |
| Coprocessor | MockFHEVMExecutor | Real FHEVM coprocessor |
| ACL | Always allows | Real permission checks |
| Decryption | Direct cast | KMS threshold decryption |
| Speed | Milliseconds | Seconds (FHE is expensive) |
| Privacy | None | Full confidentiality |
| Network | Local Foundry (31337) | Sepolia / Mainnet |

### What Stays the Same

The good news: **your Solidity code doesn't change**. The same `SealedBidAuction.sol` you tested locally deploys to Sepolia without modification. The `ZamaEthereumConfig` base contract automatically selects the correct coprocessor, ACL, and KMS addresses based on `block.chainid`.

For local testing (chain 31337), `FhevmTest.sol` deploys mocks at these addresses. For real networks, the real contracts are already deployed by the Zama team.

### What Changes

1. **Encryption is real** — `FHE.add`, `FHE.gt`, `FHE.select` perform actual homomorphic operations on ciphertexts
2. **ACL is enforced** — `FHE.allow` and `FHE.allowThis` are not just bookkeeping; they control real access
3. **Decryption requires KMS** — you can't just cast a `bytes32` to `uint64`; you need threshold decryption through the Key Management Service
4. **Operations are slower** — each FHE operation takes seconds instead of milliseconds
5. **Client-side encryption** — users must encrypt values using `fhevmjs` before submitting transactions

### Switching to Real Mode

```bash
# In .env
FHEVM_MOCK=false
RPC_URL=https://devnet.zama.ai   # Or Sepolia with FHEVM support
```

## 2. Deployment with Forge Script

Foundry's `forge script` command is the standard way to deploy contracts. It's reproducible, version-controlled, and can be dry-run before spending real gas.

### The Deploy Script

```solidity
// script/Deploy.s.sol
contract DeployScript is Script {
    function run() public {
        vm.startBroadcast();
        FHECounter counter = new FHECounter();
        console.log("FHECounter deployed at:", address(counter));
        vm.stopBroadcast();
    }
}
```

This follows the standard Forge scripting pattern:
1. `vm.startBroadcast()` — start recording transactions to broadcast
2. Deploy contracts — each `new` creates a deployment transaction
3. `vm.stopBroadcast()` — stop recording and (optionally) broadcast to the network

### Deploy to Testnet

```bash
# Load environment variables
source .env

# Deploy (dry run first — no --broadcast)
forge script script/Deploy.s.sol --rpc-url $RPC_URL -vvvv

# Deploy for real (with broadcast)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify -vvvv

# With a specific private key
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

**Tip**: Always dry-run first (without `--broadcast`) to verify everything works before spending gas.

### Deploy All Bootcamp Contracts

For deploying everything you've built across all four weeks:

```solidity
// script/DeployAll.s.sol
contract DeployAllScript is Script {
    function run() public {
        vm.startBroadcast();

        FHECounter counter = new FHECounter();
        console.log("FHECounter:", address(counter));

        EncryptedVault vault = new EncryptedVault();
        console.log("EncryptedVault:", address(vault));

        ConfidentialERC20 token = new ConfidentialERC20("Confidential Token", "CFHE");
        console.log("ConfidentialERC20:", address(token));

        SealedBidAuction auction = new SealedBidAuction("Bootcamp Demo Auction", 1 hours);
        console.log("SealedBidAuction:", address(auction));

        vm.stopBroadcast();
    }
}
```

## 3. Real Encryption with `fhevmjs`

In mock mode, you used `mockEncrypt64(value)` to create handles. In real mode, encryption happens **client-side** using the `fhevmjs` SDK. This is the bridge between your frontend (or script) and the on-chain FHE world.

### Install fhevmjs

```bash
npm install fhevmjs ethers
```

### Encryption Flow: `createEncryptedInput`

```javascript
import { createInstance } from "fhevmjs/node";
import { ethers } from "ethers";

// 1. Initialize fhevmjs instance
const provider = new ethers.JsonRpcProvider(RPC_URL);
const fhevm = await createInstance({ chainId: 11155111, networkUrl: RPC_URL });

// 2. Create encrypted input
const input = fhevm.createEncryptedInput(contractAddress, userAddress);
input.add64(1000); // Encrypt the value 1000 as euint64

const encrypted = await input.encrypt();
// encrypted.handles[0] → bytes32 handle (externalEuint64)
// encrypted.inputProof → bytes proof

// 3. Send transaction
const contract = new ethers.Contract(contractAddress, abi, signer);
const tx = await contract.deposit(encrypted.handles[0], encrypted.inputProof);
await tx.wait();
```

### Step-by-Step Breakdown

| Step | What Happens | Mock Equivalent |
|------|-------------|-----------------|
| `createInstance()` | Connects to the FHEVM network and fetches the public key | Not needed — mock uses plaintext |
| `createEncryptedInput(contract, user)` | Creates an encryption context bound to a specific contract and user | `mockEncrypt64(value)` |
| `input.add64(1000)` | Encrypts the value 1000 under the network's FHE public key | Encoded as `bytes32` in mock |
| `input.encrypt()` | Returns the encrypted handle and a ZK proof of valid encryption | Returns mock handle + empty proof |
| Send transaction | Submit handle + proof to the contract | Same — contract interface is identical |

**Key insight**: The contract's `FHE.fromExternal(encBid, inputProof)` works identically in both modes. It verifies the proof and converts to an internal handle. The only difference is whether the proof is real or mocked.

### Decryption Flow

```javascript
// Decrypt a euint64 value
const encryptedBalance = await contract.getBalance();

// Request decryption from KMS
const plaintext = await fhevm.userDecrypt64(
    encryptedBalance,  // The encrypted handle
    contractAddress,   // Contract that holds the value
    signer             // Must have FHE.allow permission
);

console.log("Balance:", plaintext); // e.g., 1000n (BigInt)
```

Decryption is **not** instant in real mode. The KMS (Key Management Service) uses threshold decryption — multiple key holders must cooperate to decrypt a value. This takes a few seconds but ensures no single party can decrypt unilaterally.

**Permission requirement**: The `signer` must have been granted `FHE.allow` on the value. If you try to decrypt a value you don't have permission for, the KMS will reject the request.

### FFI Integration for Foundry (Real Mode)

For running `forge test` against a real FHEVM network, you can use Foundry's FFI to call a Node.js script for real encryption:

```solidity
function realEncrypt64(uint64 value, address contractAddr, address userAddr)
    internal
    returns (bytes32 handle, bytes memory proof)
{
    string[] memory cmd = new string[](5);
    cmd[0] = "node";
    cmd[1] = "script/fhevmjs-encrypt.js";
    cmd[2] = vm.toString(value);
    cmd[3] = vm.toString(contractAddr);
    cmd[4] = vm.toString(userAddr);

    bytes memory result = vm.ffi(cmd);
    (handle, proof) = abi.decode(result, (bytes32, bytes));
}
```

This uses the `ffi = true` setting in `foundry.toml` — it allows Forge to shell out to Node.js for real encryption. This is only needed for integration testing against real networks; your local mock tests don't need it.

## 4. Network Configuration

### Supported Networks

| Network | Chain ID | Status |
|---------|----------|--------|
| Local Foundry/Hardhat | 31337 | Mock mode only |
| Zama Devnet | — | Full FHEVM support |
| Ethereum Sepolia | 11155111 | FHEVM coprocessor deployed |
| Ethereum Mainnet | 1 | Production FHEVM |

### Automatic Configuration

The `ZamaEthereumConfig` constructor automatically selects the correct coprocessor, ACL, and KMS addresses based on `block.chainid`. You don't need to configure these manually — just inherit from `ZamaEthereumConfig` (which you've been doing all bootcamp) and the right addresses are selected at deployment time.

## 5. Contract Verification

After deploying, verify your contracts on Etherscan so users can read the source code and interact through the Etherscan UI:

```bash
forge verify-contract \
  <DEPLOYED_ADDRESS> \
  src/FHECounter.sol:FHECounter \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

For contracts with constructor arguments:

```bash
forge verify-contract \
  <DEPLOYED_ADDRESS> \
  src/ConfidentialERC20.sol:ConfidentialERC20 \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(string,string)" "Confidential Token" "CFHE")
```

**Tip**: The `--verify` flag on `forge script` can do this automatically during deployment if you provide `$ETHERSCAN_API_KEY` in your environment.

## 6. Mainnet Deployment Checklist

Before deploying to mainnet, work through this comprehensive checklist. Each item addresses a real risk specific to FHE contracts.

### Code Quality

- [ ] All tests pass in mock mode (`forge test`)
- [ ] Tests pass on Sepolia testnet (real FHE)
- [ ] Code reviewed by at least one other developer
- [ ] No compiler warnings (except known linter notes)
- [ ] Optimizer enabled with appropriate runs

### Security

- [ ] `FHE.allowThis()` called after every operation that produces a new handle
- [ ] `FHE.allow()` is granular — only authorized users can decrypt specific values
- [ ] No encrypted values leaked through events (events are public!)
- [ ] No encrypted values used in `require` / `revert` messages
- [ ] State machine transitions are properly guarded
- [ ] Access control (onlyOwner, etc.) is correct
- [ ] No reentrancy vulnerabilities (standard Solidity concern)
- [ ] Integer overflow is handled (Solidity 0.8.x has built-in overflow checks for plaintext; FHE operations handle overflow internally)

### Privacy Considerations

- [ ] No side-channel leaks through gas usage patterns
- [ ] Reverts don't reveal encrypted information (use silent-zero pattern)
- [ ] Event parameters don't expose sensitive data
- [ ] `view` functions return encrypted handles, not plaintext
- [ ] Decryption is off-chain only (no on-chain Oracle pattern)

### Operational

- [ ] Private keys are stored securely (hardware wallet or key management service)
- [ ] Deployment script is tested on testnet first
- [ ] Contract addresses are documented
- [ ] Frontend is updated with correct contract addresses and ABI

## 7. Security Considerations for FHE Contracts

FHE contracts have unique security concerns beyond standard Solidity. These are the mistakes that can break your privacy guarantees even when the cryptography is sound.

### Side-Channel Attacks

Even though values are encrypted, some information can leak:

1. **Gas metering**: Different FHE operations may use different gas amounts depending on the operands. Monitor and account for this.

2. **Access patterns**: Which functions are called and when can reveal information. For example, if a user calls `withdraw` frequently after `deposit`, an observer knows they're managing funds.

3. **Timing**: Transaction timing can correlate with real-world events.

### Common Mistakes

**1. Logging encrypted values in events:**

```solidity
// BAD: amount is encrypted but events are public!
event Transfer(address from, address to, euint64 amount);

// GOOD: only log addresses (which are public anyway)
event Transfer(address indexed from, address indexed to);
```

Events are stored in the transaction receipt and are publicly visible. If you emit an encrypted handle in an event, the handle itself is visible (though not the plaintext). But the *presence* and *timing* of the event still leaks information.

**2. Reverting based on encrypted conditions:**

```solidity
// BAD: leaks that balance < amount
require(FHE.gt(balance, amount), "Insufficient");

// GOOD: silent zero pattern
euint64 actual = FHE.select(FHE.le(amount, balance), amount, FHE.asEuint64(0));
```

If a transaction reverts, observers know the encrypted condition was false. This lets attackers binary-search for the hidden value. The silent-zero pattern (which you've used throughout this bootcamp) prevents this.

**3. Forgetting permissions after operation:**

```solidity
// BAD: _balance is unusable after this
_balance = FHE.add(_balance, amount);
// Missing FHE.allowThis(_balance) !

// GOOD:
_balance = FHE.add(_balance, amount);
FHE.allowThis(_balance);
FHE.allow(_balance, msg.sender);
```

Every FHE operation produces a new handle. The old handle's permissions are gone. This is the **new-handle rule** you learned in Week 2 — forgetting it in production means your contract silently breaks after the first state mutation.

## 8. What's Next?

Congratulations — you've completed the FHEVM Bootcamp! Over four weeks, you've progressed from "what is FHE?" to deploying production-grade confidential contracts:

```
Week 1: FHE Theory → FHECounter
Week 2: Access Control → EncryptedVault
Week 3: Confidential DeFi → ConfidentialERC20
Week 4: Capstone → SealedBidAuction → Deployment
```

You now have the skills to build production-grade confidential smart contracts using Fully Homomorphic Encryption.

### Build

- Extend the ConfidentialERC20 into a full DeFi protocol
- Build a confidential DAO with encrypted voting
- Create a privacy-preserving DEX with encrypted order books
- Implement a confidential lottery or prediction market
- Build a Vickrey (second-price) auction — that's your capstone homework!

### Learn More

- [Zama Documentation](https://docs.zama.ai/fhevm)
- [fhevmjs SDK Reference](https://docs.zama.ai/fhevm/fhevmjs)
- [Zama Blog](https://www.zama.ai/blog)
- [FHEVM Solidity Library](https://github.com/zama-ai/fhevm)

### Contribute

- Submit improvements to this bootcamp
- Build templates for other FHE patterns
- Join the Zama Developer Program

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| Mock vs Real mode | Mock uses plaintext in `bytes32`; Real uses actual FHE ciphertexts with KMS decryption |
| `fhevmjs` | Client-side SDK for real encryption (`createEncryptedInput`) and decryption (`userDecrypt64`) |
| `createEncryptedInput` | Encrypts values client-side under the network's FHE public key — returns handle + proof |
| FFI | Foundry calls Node.js for real-mode encryption in integration tests |
| `forge script` | Deployment automation — dry-run first, then `--broadcast` to deploy |
| Contract verification | Etherscan source code verification with `forge verify-contract` |
| Silent-zero pattern | Privacy-preserving error handling — never revert on encrypted conditions |
| Side-channel awareness | Gas patterns, access patterns, and timing can leak information even with encryption |
| Mainnet checklist | Comprehensive production readiness audit: code quality, security, privacy, operations |

---

## Key Takeaways

1. **Your Solidity code doesn't change** between mock and real mode — `ZamaEthereumConfig` handles network-specific addresses automatically
2. **`fhevmjs` is the client-side bridge** — it encrypts values before submission and decrypts values after permission is granted
3. **`createEncryptedInput`** binds encryption to a specific contract and user — this prevents handle reuse attacks
4. **Always dry-run deployments** with `forge script` (without `--broadcast`) before spending real gas
5. **Events are public** — never emit encrypted handles or values that could leak information
6. **The silent-zero pattern is mandatory** for production — reverting on encrypted conditions leaks information through binary search
7. **Every FHE operation creates a new handle** — always re-grant `allowThis` and `allow` after mutations
8. **Side channels exist even with perfect encryption** — gas usage, access patterns, and timing can all leak information
9. **Test on Sepolia before mainnet** — real FHE operations behave differently (slower, real ACL enforcement, real KMS)
10. **You've completed the bootcamp** — you now have the skills to build and deploy production-grade confidential smart contracts

---

**Congratulations, you've graduated from the FHEVM Bootcamp!** You started with zero FHE knowledge and can now build, test, and deploy confidential smart contracts on mainnet. The patterns you've learned — encrypted state, ACL permissions, silent-zero, incremental tracking, state machines, and deferred revelation — are the building blocks of every confidential application on FHEVM.

**Final challenge:** [Capstone Homework: Vickrey Auction](/week-4/homework) — extend the sealed-bid auction into a second-price auction and prove your mastery of the full stack.
