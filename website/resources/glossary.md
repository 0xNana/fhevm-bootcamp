# FHEVM Glossary

An A–Z reference of every FHE, FHEVM, and tooling term used in this bootcamp. Each entry includes a concise definition and a reference to where it first appears in the curriculum.

---

## A

### ACL (Access Control List)

The on-chain contract that tracks which addresses have permission to decrypt specific encrypted handles. Every encrypted value is useless unless the ACL grants you access. Managed via `FHE.allowThis()`, `FHE.allow()`, and `FHE.allowTransient()`.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### `allowThis` / `allow` / `allowTransient`

See [Permission Dance](#permission-dance).

---

### Anvil

Foundry's local Ethereum node (similar to Hardhat Network or Ganache). Used for local development and testing. When running `forge test`, Foundry spins up an in-memory Anvil instance automatically.

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

## C

### Cast

Foundry's command-line tool for interacting with deployed contracts and performing Ethereum RPC calls. Used to send transactions, read contract state, convert values, and more. Analogous to `ethers.js` scripting in Hardhat.

**First seen in:** [Week 4, Lesson 2](/week-4/lesson-2-deployment)

---

### Ciphertext

Encrypted data produced by FHE encryption. On the FHEVM, ciphertexts live in the coprocessor and are referenced on-chain by `bytes32` handles. The plaintext value inside a ciphertext can only be recovered by decryption through the KMS with proper ACL permissions.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### Coprocessor

The off-chain FHE execution engine (formally called the **FHEVMExecutor**). When a contract calls `FHE.add(a, b)`, the EVM delegates to the coprocessor, which performs the actual homomorphic computation on ciphertexts and returns an encrypted result. The coprocessor lives at a well-known on-chain address.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

## D

### Decryption

The process of converting an encrypted ciphertext back to its plaintext value. In FHEVM, decryption is always **off-chain** — it never happens inside a smart contract. The user requests decryption via `fhevmjs`, which coordinates with the KMS threshold network. Only addresses granted permission via the ACL can decrypt.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### Deferred Permissions

A pattern where `FHE.allow()` is intentionally withheld until the system reaches an appropriate state. For example, in a sealed-bid auction, the auctioneer only gets permission to decrypt the winning bid after `closeAuction()` — not during bidding.

**First seen in:** [Week 4, Lesson 1](/week-4/lesson-1-auction)

---

### Double Protection

A pattern using two sequential silent-zero checks in `transferFrom`: first checking allowance, then checking balance. Neither check leaks information about which one (if either) blocked the transfer.

**First seen in:** [Week 3, Lesson 2](/week-3/lesson-2-advanced)

---

## E

### `eaddress`

An encrypted Ethereum address. Stored as a `bytes32` handle on-chain; the actual address is hidden in the coprocessor. Used to hide identities — e.g., the winning bidder in a sealed auction.

**First seen in:** [Week 4, Lesson 1](/week-4/lesson-1-auction)

---

### `ebool`

An encrypted boolean. Produced by all FHE comparison operations (`FHE.eq`, `FHE.gt`, `FHE.le`, etc.). Cannot be used in Solidity `if` statements — must be consumed by `FHE.select()`.

**First seen in:** [Week 2, Lesson 2](/week-2/lesson-2-patterns)

---

### Encrypted Guard Pattern

The FHE replacement for `require()` + operation. A three-step pattern: **compare** (produce `ebool`) → **select** (choose safe value) → **operate** (execute with guaranteed safety). Prevents underflow/overflow without revealing which branch was taken.

```solidity
ebool ok = FHE.le(amount, balance);                      // Compare
euint64 safe = FHE.select(ok, amount, balance);          // Select
balance = FHE.sub(balance, safe);                        // Operate
```

**First seen in:** [Week 2, Lesson 2](/week-2/lesson-2-patterns)

---

### Encrypted Handle

A `bytes32` value that acts as a pointer to an encrypted ciphertext stored in the coprocessor. Contracts operate on handles; the EVM never sees the underlying plaintext. Every FHE operation takes handles as input and returns a new handle.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### `euint8` / `euint16` / `euint32` / `euint64` / `euint128` / `euint256`

Encrypted unsigned integer types of various bit widths. These are the core building blocks of confidential smart contracts. Each is a user-defined type wrapping `bytes32` in Solidity.

| Type | Bit Width | Typical Use |
|------|-----------|-------------|
| `euint8` | 8 | Small counters, enums |
| `euint16` | 16 | Medium values |
| `euint32` | 32 | Counters, IDs, votes |
| `euint64` | 64 | Token amounts, balances |
| `euint128` | 128 | Large values |
| `euint256` | 256 | Very large values |

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### `externalEuint*` (External Encrypted Types)

Unverified encrypted input types submitted by users. They must be validated with `FHE.fromExternal()` before use. Each encrypted type has a corresponding external type: `externalEbool`, `externalEuint8`, `externalEuint16`, `externalEuint32`, `externalEuint64`, `externalEuint128`, `externalEuint256`, `externalEaddress`.

```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
}
```

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

## F

### FHE (Fully Homomorphic Encryption)

A cryptographic technique that allows computation on encrypted data without decrypting it. The result, when decrypted, matches the result of performing the same computation on the plaintext. First proposed by Craig Gentry in 2009, made practical for blockchain by Zama.

```
Encrypted(3) + Encrypted(5) = Encrypted(8)
```

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### FHEVM (Fully Homomorphic Encryption Virtual Machine)

Zama's confidential computing layer for the EVM. It adds encrypted types, a coprocessor for FHE operations, an ACL for access control, and a KMS for key management. Smart contracts look like normal Solidity but operate on encrypted data.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### `FHE.sol`

The core Solidity library providing all FHE operations (`add`, `sub`, `mul`, `eq`, `gt`, `le`, `select`, etc.) and ACL management (`allowThis`, `allow`, `allowTransient`). Imported as:

```solidity
import {FHE} from "@fhevm/solidity/lib/FHE.sol";
```

**First seen in:** [Week 1, Lesson 3](/week-1/lesson-3-hello-fhe)

---

### `fhevmjs`

Zama's client-side JavaScript/TypeScript SDK for encrypting inputs and decrypting outputs. In the Hardhat workflow, it's used extensively in tests. In this Foundry bootcamp, it's replaced by mock helpers (`mockEncrypt*` / `mockDecrypt*`) for testing, but would still be used in production frontends.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### `FhevmTest.sol`

The base test contract in this bootcamp that replaces `@fhevm/hardhat-plugin`. It deploys mock FHE infrastructure (coprocessor, ACL, KMS, InputVerifier) to well-known addresses and provides `mockEncrypt*` / `mockDecrypt*` helper functions. All test contracts inherit from it.

```solidity
contract MyTest is FhevmTest {
    function setUp() public override {
        super.setUp();
    }
}
```

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

### Forge

Foundry's test runner and build tool. Compiles Solidity, runs tests, generates gas reports, and more. The primary command you'll use throughout this bootcamp.

| Command | Purpose |
|---------|---------|
| `forge build` | Compile contracts |
| `forge test` | Run tests |
| `forge test -vvv` | Verbose test output |
| `forge test --match-test "name"` | Filter tests |
| `forge script` | Run deployment scripts |
| `forge fmt` | Format Solidity code |

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

### Foundry

A fast, portable, and modular Ethereum development toolkit written in Rust. Consists of `forge` (build/test), `cast` (CLI interaction), `anvil` (local node), and `chisel` (REPL). This bootcamp uses Foundry instead of the officially supported Hardhat.

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

### `fromExternal`

See [`FHE.fromExternal`](#externaleuint-external-encrypted-types). The function that verifies and converts user-submitted encrypted inputs into internal encrypted types.

---

## H

### Handle

See [Encrypted Handle](#encrypted-handle). A `bytes32` reference to a ciphertext in the coprocessor.

---

### Homomorphic

Describing the property that allows operations to be performed on encrypted data such that the result, when decrypted, equals the result of the same operations on the plaintext. "Homo" (same) + "morphic" (form) — the structure of the computation is preserved through encryption.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

## I

### Incremental Winner Tracking

A design pattern where the highest bid is updated on each `placeBid` call (O(1) per bid) rather than computing it in a batch at auction close (O(n)). This distributes FHE gas costs across all bidders instead of concentrating them in one expensive transaction.

**First seen in:** [Week 4, Lesson 1](/week-4/lesson-1-auction)

---

### InputVerifier

The on-chain contract that validates encrypted inputs submitted by users. When a user sends an `externalEuint64` with a proof, `FHE.fromExternal()` delegates to the InputVerifier to confirm the ciphertext is well-formed. Prevents malicious ciphertext injection.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

## K

### KMS (Key Management Service)

A threshold network that manages the global FHE encryption key. No single party holds the full key — decryption requires cooperation from multiple KMS nodes. This prevents any single entity from decrypting all on-chain data.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### KMSVerifier

The on-chain contract that verifies KMS signatures and coordinates decryption requests. It ensures that decryption responses genuinely came from the threshold KMS network.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

## M

### Mock Mode

A testing configuration where encrypted operations are simulated using plaintext values. Instead of real FHE computation, handles are just `bytes32`-encoded plaintext numbers. This enables fast, deterministic tests without FHE infrastructure.

Controlled by the `FHEVM_MOCK` environment variable:

```solidity
bool isMock = vm.envOr("FHEVM_MOCK", true);  // default: true (mock mode)
```

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

### Mock Contracts

Four mock implementations deployed by `FhevmTest.sol` for local testing:

| Mock Contract | Replaces | Behavior |
|---------------|----------|----------|
| `MockFHEVMExecutor` | Coprocessor | Plaintext arithmetic on `bytes32` handles |
| `MockACL` | ACL | Always permits (no real access control) |
| `MockInputVerifier` | InputVerifier | No-op verification (accepts all inputs) |
| `MockKMSVerifier` | KMSVerifier | Always returns true |

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

## N

### New-Handle Rule

Every FHE operation produces a **new** `bytes32` handle. The old handle's ACL permissions are orphaned. This means you must call `FHE.allowThis()` and `FHE.allow()` after every operation that produces a value you intend to store or expose.

**First seen in:** [Week 2, Lesson 1](/week-2/lesson-1-access-control)

---

## P

### Permission Dance

The required sequence of ACL calls after every FHE operation that stores a new handle:

1. `FHE.allowThis(handle)` — contract can use the handle in future transactions
2. `FHE.allow(handle, user)` — user can decrypt the handle off-chain

Forgetting either call causes failures: missing `allowThis` means the contract can't read the value later; missing `allow` means the user can't decrypt.

**First seen in:** [Week 1, Lesson 3](/week-1/lesson-3-hello-fhe)

---

### Plaintext

An unencrypted value. In the context of FHEVM, plaintext values are visible to anyone inspecting the blockchain. The goal of FHE is to keep values as ciphertext during computation, only revealing plaintext to authorized parties off-chain.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### Proof (Input Proof)

A cryptographic proof submitted alongside an encrypted input (`externalEuint*`). It proves that the ciphertext is well-formed and was encrypted with the correct public key. Validated by the InputVerifier.

```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
}
```

In mock mode, the proof is a dummy non-empty `bytes` value.

**First seen in:** [Week 1, Lesson 3](/week-1/lesson-3-hello-fhe)

---

## R

### Remappings

Foundry's mechanism for resolving Solidity import paths. Defined in `foundry.toml`, they map import prefixes to local directories:

```toml
remappings = [
    "@fhevm/solidity/=lib/fhevm-solidity/",
    "encrypted-types/=lib/encrypted-types/",
    "forge-std/=lib/forge-std/src/",
]
```

This allows `import "@fhevm/solidity/lib/FHE.sol"` to resolve to `lib/fhevm-solidity/lib/FHE.sol`.

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

## S

### Selective Revelation

A privacy pattern where only specific results are ever decrypted — not all data. In a sealed-bid auction, only the winning bid is revealed; losing bids remain encrypted forever.

**First seen in:** [Week 4, Lesson 1](/week-4/lesson-1-auction)

---

### Silent-Fail / Silent-Zero Pattern

A design principle where FHE contracts never revert based on encrypted state. Instead of `require(balance >= amount)`, the contract uses `FHE.select()` to either cap the amount (silent-fail) or zero it out (silent-zero). This prevents observers from learning about encrypted state by watching which transactions revert.

Two variants:
- **Silent-fail (cap):** `FHE.select(ok, amount, balance)` — use the max available. Used for self-withdrawals.
- **Silent-zero:** `FHE.select(ok, amount, FHE.asEuint64(0))` — transfer nothing. Used for party-to-party transfers.

**First seen in:** [Week 2, Lesson 2](/week-2/lesson-2-patterns) (silent-fail), [Week 3, Lesson 1](/week-3/lesson-1-token) (silent-zero)

---

### State Machine

A design pattern that enforces lifecycle phases with strict transition rules. Used in the sealed-bid auction with three phases: **Bidding** → **Closed** → **Revealed**. State machines control when `FHE.allow()` is granted and what operations are permitted.

```solidity
enum Phase { Bidding, Closed, Revealed }
modifier inPhase(Phase expected) {
    if (phase != expected) revert WrongPhase(expected, phase);
    _;
}
```

**First seen in:** [Week 4, Lesson 1](/week-4/lesson-1-auction)

---

## T

### Trivial Encryption

Converting a known plaintext value into an encrypted handle using `FHE.asEuint*()` or `FHE.asEaddress()`. Called "trivial" because the value is known at encryption time (as opposed to user-submitted inputs that are encrypted client-side). Necessary when mixing plaintext and encrypted values in FHE operations.

```solidity
euint64 zero = FHE.asEuint64(0);      // trivially encrypt 0
eaddress encAddr = FHE.asEaddress(msg.sender);  // trivially encrypt an address
```

**First seen in:** [Week 3, Lesson 1](/week-3/lesson-1-token)

---

## V

### `vm.etch`

A Foundry cheatcode that replaces the bytecode at a specific address. Used in `FhevmTest.sol` to deploy mock contracts to the well-known addresses that `ZamaConfig` expects:

```solidity
MockFHEVMExecutor executor = new MockFHEVMExecutor();
vm.etch(COPROCESSOR_ADDRESS, address(executor).code);
```

This is how the mock framework "tricks" the FHE library into using mock implementations instead of real coprocessor contracts.

**First seen in:** [Week 1, Lesson 2](/week-1/lesson-2-setup)

---

### `vm.prank`

A Foundry cheatcode that sets `msg.sender` for the **next** external call only. Used extensively in tests to simulate different users interacting with contracts.

```solidity
vm.prank(alice);
contract.deposit(handle, proof);  // msg.sender == alice

contract.deposit(handle, proof);  // msg.sender == test contract (NOT alice)
```

For multiple calls, use `vm.startPrank(addr)` / `vm.stopPrank()`.

**First seen in:** [Week 1, Lesson 3](/week-1/lesson-3-hello-fhe)

---

## Z

### Zama

The company behind FHEVM and the `tfhe-rs` library. Zama develops FHE technology for blockchain and AI, making encrypted computation practical. They maintain `@fhevm/solidity`, `fhevmjs`, and the FHEVM coprocessor infrastructure.

**First seen in:** [Week 1, Lesson 1](/week-1/lesson-1-fhe-theory)

---

### `ZamaConfig` / `ZamaEthereumConfig`

Configuration contracts that define the well-known addresses for FHE infrastructure (coprocessor, ACL, KMS, InputVerifier) on each chain. Contracts inherit from `ZamaEthereumConfig` to automatically configure themselves for the correct network:

```solidity
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract MyContract is ZamaEthereumConfig {
    // Automatically knows where the coprocessor, ACL, and KMS live
}
```

On `chainId 31337` (Anvil/Hardhat), the config uses local addresses that `FhevmTest.sol` deploys mock contracts to.

**First seen in:** [Week 1, Lesson 3](/week-1/lesson-3-hello-fhe)

---

## Symbol Index

Quick lookup for all special types and functions referenced in the bootcamp:

| Symbol | Category | Definition |
|--------|----------|------------|
| `ebool` | Type | [ebool](#ebool) |
| `euint8`–`euint256` | Type | [euint*](#euint8--euint16--euint32--euint64--euint128--euint256) |
| `eaddress` | Type | [eaddress](#eaddress) |
| `externalEuint*` | Type | [External Encrypted Types](#externaleuint-external-encrypted-types) |
| `FHE.add` | Operation | [Cheat Sheet: Arithmetic](/resources/cheatsheet#arithmetic-operations) |
| `FHE.sub` | Operation | [Cheat Sheet: Arithmetic](/resources/cheatsheet#arithmetic-operations) |
| `FHE.mul` | Operation | [Cheat Sheet: Arithmetic](/resources/cheatsheet#arithmetic-operations) |
| `FHE.eq` / `FHE.ne` | Operation | [Cheat Sheet: Comparison](/resources/cheatsheet#comparison-operations) |
| `FHE.gt` / `FHE.ge` / `FHE.lt` / `FHE.le` | Operation | [Cheat Sheet: Comparison](/resources/cheatsheet#comparison-operations) |
| `FHE.min` / `FHE.max` | Operation | [Cheat Sheet: Comparison](/resources/cheatsheet#comparison-operations) |
| `FHE.select` | Operation | [Cheat Sheet: Conditional](/resources/cheatsheet#conditional-operation) |
| `FHE.asEuint*` | Conversion | [Cheat Sheet: Conversions](/resources/cheatsheet#type-conversions) |
| `FHE.asEaddress` | Conversion | [Cheat Sheet: Conversions](/resources/cheatsheet#type-conversions) |
| `FHE.fromExternal` | Conversion | [Cheat Sheet: Conversions](/resources/cheatsheet#type-conversions) |
| `FHE.allowThis` | ACL | [Cheat Sheet: ACL](/resources/cheatsheet#acl-operations) |
| `FHE.allow` | ACL | [Cheat Sheet: ACL](/resources/cheatsheet#acl-operations) |
| `FHE.allowTransient` | ACL | [Cheat Sheet: ACL](/resources/cheatsheet#acl-operations) |
| `mockEncrypt*` | Testing | [Cheat Sheet: Mock Testing](/resources/cheatsheet#mock-testing-quick-reference) |
| `mockDecrypt*` | Testing | [Cheat Sheet: Mock Testing](/resources/cheatsheet#mock-testing-quick-reference) |
| `vm.etch` | Foundry | [vm.etch](#vm-etch) |
| `vm.prank` | Foundry | [vm.prank](#vm-prank) |
