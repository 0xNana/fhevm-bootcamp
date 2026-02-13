# Lesson 2: Environment Setup

**Duration:** ~30 minutes | **Prerequisites:** [Lesson 1: FHE Theory](/week-1/lesson-1-fhe-theory) | **Code:** Configuration only

---

## Learning Objectives

By the end of this lesson, you will:

- Have Foundry installed and configured for FHEVM development
- Understand the project structure and how remappings work
- Know how mock mode works and why it enables fast testing
- Successfully run `forge build` and `forge test`

---

## 1. Install Foundry

If you don't have Foundry installed:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify:

```bash
forge --version
```

You need Foundry with Solidity 0.8.27+ support.

## 2. Clone and Build

```bash
git clone --recurse-submodules https://github.com/0xNana/fhevm-bootcamp.git
cd fhevm-bootcamp
forge build
```

You should see a successful compilation with zero errors.

## 3. Project Structure

```
fhevm-bootcamp/
│
├── foundry.toml              # Foundry configuration
├── .env.example              # Environment variables template
│
├── src/                      # Smart contract source files
│   └── FHECounter.sol        # Example: encrypted counter
│
├── test/                     # Forge tests
│   ├── FhevmTest.sol         # Base test contract (mock FHE infrastructure)
│   ├── FHECounter.t.sol      # Tests for FHECounter
│   └── mocks/                # Mock contracts for local testing
│       ├── MockFHEVMExecutor.sol
│       ├── MockACL.sol
│       ├── MockInputVerifier.sol
│       └── MockKMSVerifier.sol
│
├── script/
│   └── Deploy.s.sol          # Deployment script
│
└── lib/                      # Dependencies (git submodules + copied packages)
    ├── forge-std/             # Forge standard library
    ├── fhevm-solidity/        # @fhevm/solidity (FHE library, types, config)
    │   ├── lib/
    │   │   ├── FHE.sol        # Main FHE library
    │   │   ├── Impl.sol       # Coprocessor call implementations
    │   │   └── FheType.sol    # FHE type enum
    │   └── config/
    │       └── ZamaConfig.sol # Network-specific addresses
    └── encrypted-types/
        └── EncryptedTypes.sol # Type definitions (euint32, externalEuint32, etc.)
```

## 4. Key Configuration: `foundry.toml`

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
ffi = true                    # Required for real-mode FFI to fhevmjs
evm_version = "cancun"        # Must match FHEVM target
solc = "0.8.27"               # Solidity version
optimizer = true
optimizer_runs = 800

remappings = [
    "@fhevm/solidity/=lib/fhevm-solidity/",
    "encrypted-types/=lib/encrypted-types/",
    "forge-std/=lib/forge-std/src/",
]
```

### Key settings explained:

- **`ffi = true`** — Enables Foreign Function Interface. In real mode, Forge calls a Node.js script to interact with fhevmjs for encryption/decryption.
- **`evm_version = "cancun"`** — Matches the Hardhat template's EVM target.
- **`remappings`** — Maps import paths so that `import "@fhevm/solidity/lib/FHE.sol"` resolves to `lib/fhevm-solidity/lib/FHE.sol`. This is how Foundry replicates npm-style imports.

## 5. How Mock Mode Works

This is the most important concept for local development. On a real FHEVM chain, the FHE library calls external contracts (coprocessor, ACL, KMS) that perform actual homomorphic encryption. Locally, those contracts don't exist.

**Solution: We deploy mock contracts at the expected addresses.**

### The ZamaConfig addresses

When your contract inherits `ZamaEthereumConfig`, its constructor calls `FHE.setCoprocessor()` which configures three addresses based on chain ID. For local testing (chain ID 31337):

| Contract | Address | Mock Behavior |
|----------|---------|---------------|
| Coprocessor | `0xe3a9105a3a932253A70F126eb1E3b589C643dD24` | Plaintext arithmetic |
| ACL | `0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D` | Always allows |
| KMS Verifier | `0x901F8942346f7AB3a01F6D7613119Bca447Bb030` | Always returns true |

### How `FhevmTest.sol` sets this up

```solidity
function _deployMocks() internal {
    // Deploy mock implementations
    MockFHEVMExecutor executor = new MockFHEVMExecutor();
    MockACL acl = new MockACL();
    // ... etc

    // Etch runtime bytecode to the addresses ZamaConfig expects
    vm.etch(COPROCESSOR_ADDRESS, address(executor).code);
    vm.etch(ACL_ADDRESS, address(acl).code);
    // ... etc
}
```

`vm.etch()` is a Foundry cheatcode that places bytecode at any address. After this, when your contract calls `FHE.add(a, b)`, the call flows:

```
FHE.add(a, b)
  → Impl.add(a_unwrapped, b_unwrapped, false)
    → IFHEVMExecutor(COPROCESSOR_ADDRESS).fheAdd(a, b, 0x00)
      → MockFHEVMExecutor.fheAdd(a, b, 0x00)
        → returns bytes32(uint256(a) + uint256(b))   // plaintext!
```

In mock mode, encrypted handles are just `bytes32`-encoded plaintext values. `fheAdd(3, 5)` returns `8`. This is fast, deterministic, and requires no real FHE infrastructure.

## 6. Writing Your First Test

Every test contract inherits from `FhevmTest`:

```solidity
import {FhevmTest, euint32, externalEuint32} from "./FhevmTest.sol";

contract MyTest is FhevmTest {
    function setUp() public override {
        super.setUp();    // <-- Deploys mock FHE infrastructure
        // Deploy your contracts here
    }
}
```

The base `setUp()` checks `FHEVM_MOCK` (defaults to `true`) and deploys mocks if needed.

### Encrypt and Decrypt Helpers

```solidity
// Encrypt a uint32 value (mock mode: just wraps in bytes32)
(externalEuint32 handle, bytes memory proof) = mockEncrypt32(42);

// Pass to a contract function
myContract.doSomething(handle, proof);

// Decrypt an encrypted result
uint32 result = mockDecrypt32(myContract.getEncryptedValue());
```

## 7. Run the Tests

```bash
forge test -vvv
```

Expected output:

```
Ran 5 tests for test/FHECounter.t.sol:FHECounterTest
[PASS] test_decrementByOne() (gas: 43672)
[PASS] test_differentUsersCanIncrement() (gas: 59600)
[PASS] test_incrementByOne() (gas: 50798)
[PASS] test_initialCountIsZero() (gas: 7622)
[PASS] test_multipleIncrements() (gas: 57621)
Suite result: ok. 5 passed; 0 failed; 0 skipped
```

All 5 tests pass. The mock infrastructure is working.

## 8. Coming from Hardhat?

If you're familiar with the Hardhat FHEVM template, here's how concepts map:

| Hardhat | Foundry |
|---------|---------|
| `npm install` | `forge install` / git submodules |
| `hardhat.config.ts` | `foundry.toml` |
| `@fhevm/hardhat-plugin` | `FhevmTest.sol` + mocks |
| `fhevm.isMock` | `vm.envOr("FHEVM_MOCK", true)` |
| `fhevm.createEncryptedInput(...).add32(v).encrypt()` | `mockEncrypt32(v)` |
| `fhevm.userDecryptEuint(euint32, ct, addr, signer)` | `mockDecrypt32(ct)` |
| `npx hardhat test` | `forge test` |
| `npx hardhat deploy` | `forge script` |

The contract code is **identical** — `FHECounter.sol` is the same file in both templates.

---

## Key Takeaways

1. **Foundry configuration** is straightforward — `foundry.toml` with remappings handles import resolution
2. **Mock mode** replaces real FHE infrastructure with plaintext stand-ins deployed via `vm.etch()`
3. **`FhevmTest.sol`** is the base test contract — always call `super.setUp()` to deploy mocks
4. **`mockEncrypt32` / `mockDecrypt32`** are your testing workhorses for the encrypt/decrypt cycle

---

**Next:** [Lesson 3: Hello FHE — Your First Encrypted Contract](/week-1/lesson-3-hello-fhe) — Walk through `FHECounter.sol` line by line.
