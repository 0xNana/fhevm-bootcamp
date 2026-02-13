# Hardhat → Foundry Migration Guide

This guide walks you through migrating an existing Hardhat-based FHEVM project to Foundry. If you're coming from the [fhevm-hardhat-template](https://github.com/zama-ai/fhevm-hardhat-template), this is your roadmap. Every side-by-side comparison shows you exactly what changes and what stays the same.

::: tip Good News
**Your smart contracts don't need any changes.** `FHECounter.sol`, `ConfidentialERC20.sol`, and every other FHE contract compiles identically in both toolchains. The migration is entirely about the tooling around your contracts — tests, scripts, and configuration.
:::

---

[[toc]]

---

## Overview

### What Changes

| Concern | Hardhat | Foundry |
|---------|---------|---------|
| Language | TypeScript / JavaScript | Solidity (tests & scripts) |
| Package manager | npm / yarn | git submodules + copied libs |
| Config file | `hardhat.config.ts` | `foundry.toml` |
| FHE plugin | `@fhevm/hardhat-plugin` | [`FhevmTest.sol`](/week-1/lesson-2-setup) + mock contracts |
| Test runner | Mocha + Chai | `forge test` |
| Deployment | `hardhat deploy` / scripts | `forge script` |
| Mock mode flag | `fhevm.isMock` | `vm.envOr("FHEVM_MOCK", true)` |
| Encryption (test) | `fhevm.createEncryptedInput(...)` | `mockEncrypt32(v)` / `mockEncrypt64(v)` |
| Decryption (test) | `fhevm.userDecryptEuint(...)` | `mockDecrypt32(ct)` / `mockDecrypt64(ct)` |

### What Stays the Same

- **Smart contract code is identical.** Your `.sol` files compile without changes in both toolchains. No import modifications needed — Foundry resolves the same `@fhevm/solidity/` paths via remappings.
- **FHE library imports** (`@fhevm/solidity/lib/FHE.sol`, `ZamaConfig.sol`) resolve the same way.
- **Encrypted types** (`euint32`, `externalEuint64`, `ebool`, etc.) are the same Solidity types.

---

## When to Use Each

Not sure which toolchain to pick? Here's a guide:

### Choose Foundry When

- You prefer **writing tests in Solidity** (same language as your contracts)
- You want **faster compilation and test execution** (Foundry is significantly faster)
- You need **fuzz testing** built in (`forge test --fuzz`)
- You want **zero JavaScript dependencies** in your project
- You're already using Foundry for non-FHE projects
- You want to contribute to or use this bootcamp's curriculum

### Choose Hardhat When

- You need **official Zama support** (`@fhevm/hardhat-plugin` is maintained by Zama)
- Your team is more comfortable with **TypeScript/JavaScript**
- You need **extensive plugin ecosystem** (Hardhat has more third-party plugins)
- You're integrating with **existing TypeScript tooling** (like a frontend build pipeline)
- You need **real-mode FHE** out of the box (Hardhat plugin handles the setup)

### Use Both When

- You want **Foundry's fast tests** during development but **Hardhat's plugin** for production deployment
- Your contracts are the same — only the test/deploy tooling differs
- You're migrating gradually and want to run both test suites in parallel

---

## Dependency Migration

### Hardhat Dependencies (Remove)

```json
// package.json — these are no longer needed
{
  "devDependencies": {
    "@fhevm/hardhat-plugin": "...",
    "hardhat": "...",
    "ethers": "...",
    "@nomicfoundation/hardhat-toolbox": "..."
  },
  "dependencies": {
    "@fhevm/solidity": "...",
    "encrypted-types": "..."
  }
}
```

### Foundry Dependencies (Add)

```bash
# Initialize Foundry (if starting fresh)
forge init --no-git

# Add forge-std (standard library)
forge install foundry-rs/forge-std --no-commit

# Copy @fhevm/solidity into lib/
mkdir -p lib/fhevm-solidity/lib lib/fhevm-solidity/config
cp node_modules/@fhevm/solidity/lib/FHE.sol     lib/fhevm-solidity/lib/
cp node_modules/@fhevm/solidity/lib/Impl.sol     lib/fhevm-solidity/lib/
cp node_modules/@fhevm/solidity/lib/FheType.sol  lib/fhevm-solidity/lib/
cp node_modules/@fhevm/solidity/config/ZamaConfig.sol lib/fhevm-solidity/config/

# Copy encrypted-types into lib/
mkdir -p lib/encrypted-types
cp node_modules/encrypted-types/EncryptedTypes.sol lib/encrypted-types/
```

::: info Why Copy Instead of Submodule?
The `@fhevm/solidity` npm package doesn't have a standalone git repo suitable for `forge install`. Copying the specific files needed is the cleanest approach. See the [Getting Started](/getting-started) guide for the exact files included in this bootcamp.
:::

---

## Configuration

### Hardhat → Foundry Config Mapping

::: code-group

```typescript [hardhat.config.ts]
import { HardhatUserConfig } from "hardhat/config";
import "@fhevm/hardhat-plugin";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.27",
    settings: { optimizer: { enabled: true, runs: 800 } }
  },
  networks: {
    localDev: { url: "http://localhost:8545" },
    sepolia: {
      url: process.env.RPC_URL,
      accounts: [process.env.PRIVATE_KEY!]
    }
  }
};
export default config;
```

```toml [foundry.toml]
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
ffi = true
evm_version = "cancun"
solc = "0.8.27"
optimizer = true
optimizer_runs = 800

remappings = [
    "@fhevm/solidity/=lib/fhevm-solidity/",
    "encrypted-types/=lib/encrypted-types/",
    "forge-std/=lib/forge-std/src/",
]
```

:::

### Key Differences

| Setting | Hardhat | Foundry |
|---------|---------|---------|
| Solidity version | `solidity.version` | `solc = "0.8.27"` |
| Optimizer | `settings.optimizer` | `optimizer = true`, `optimizer_runs = 800` |
| Import resolution | npm `node_modules` | `remappings` in foundry.toml |
| FFI (shell calls) | Not needed (plugin handles it) | `ffi = true` (for real-mode fhevmjs) |
| EVM version | Automatic | `evm_version = "cancun"` |
| Network config | `networks: {}` | `.env` + `--rpc-url` flag |

---

## Contract Migration

**No changes required.** Move contract files from `contracts/` (Hardhat convention) to `src/` (Foundry convention):

```bash
# Hardhat layout          →  Foundry layout
# contracts/FHECounter.sol → src/FHECounter.sol
mv contracts/*.sol src/
```

Imports like `import "@fhevm/solidity/lib/FHE.sol"` resolve via the remapping in `foundry.toml`:

```
@fhevm/solidity/ → lib/fhevm-solidity/
```

So `@fhevm/solidity/lib/FHE.sol` resolves to `lib/fhevm-solidity/lib/FHE.sol`. No import changes needed.

---

## Test Migration

This is where the biggest changes happen. Hardhat tests are TypeScript with Mocha/Chai. Foundry tests are Solidity with `forge-std`.

### Step 1: Set Up the Mock Infrastructure

Copy `FhevmTest.sol` and the mock contracts into your `test/` directory. This replaces the `@fhevm/hardhat-plugin`:

```
test/
├── FhevmTest.sol              # Base test (replaces hardhat-plugin)
├── mocks/
│   ├── MockFHEVMExecutor.sol  # Plaintext FHE operations
│   ├── MockACL.sol            # Permissive ACL
│   ├── MockInputVerifier.sol  # No-op verifier
│   └── MockKMSVerifier.sol    # Always-true KMS
└── FHECounter.t.sol           # Your converted tests
```

Learn more about the mock framework in [Week 1, Lesson 2: Environment Setup](/week-1/lesson-2-setup).

### Step 2: Rewrite Tests from TypeScript to Solidity

Here's a complete test migration side by side:

::: code-group

```typescript [Hardhat (TypeScript)]
import { expect } from "chai";
import { ethers } from "hardhat";
import { initFhevm, createInstance } from "./utils";

describe("FHECounter", function () {
  let counter: any;
  let alice: any;
  let fhevm: any;

  before(async () => {
    fhevm = await createInstance();
    [, alice] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("FHECounter");
    counter = await Factory.deploy();
    await counter.waitForDeployment();
  });

  it("should increment by one", async () => {
    const input = fhevm.createEncryptedInput(
      await counter.getAddress(),
      alice.address
    );
    input.add32(1);
    const encrypted = await input.encrypt();

    await counter.connect(alice).increment(
      encrypted.handles[0],
      encrypted.inputProof
    );

    const countHandle = await counter.getCount();
    const clearCount = await fhevm.userDecryptEuint(
      "euint32",
      countHandle,
      await counter.getAddress(),
      alice
    );
    expect(clearCount).to.equal(1n);
  });
});
```

```solidity [Foundry (Solidity)]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FhevmTest} from "./FhevmTest.sol";
import {externalEuint32} from "encrypted-types/EncryptedTypes.sol";
import {FHECounter} from "../src/FHECounter.sol";

contract FHECounterTest is FhevmTest {
    FHECounter public counter;
    address public alice;

    function setUp() public override {
        super.setUp();                  // Deploys mock FHE infrastructure
        alice = makeAddr("alice");
        counter = new FHECounter();     // Deploy contract
    }

    function test_incrementByOne() public {
        // Encrypt
        (externalEuint32 handle, bytes memory inputProof) = mockEncrypt32(1);

        // Call
        vm.prank(alice);
        counter.increment(handle, inputProof);

        // Decrypt and assert
        uint32 clearCount = mockDecrypt32(counter.getCount());
        assertEq(clearCount, 1);
    }
}
```

:::

Learn the full test pattern in [Week 1, Lesson 3: Hello FHE](/week-1/lesson-3-hello-fhe).

### Step 3: Convert Each Pattern

#### Contract Deployment

::: code-group

```typescript [Hardhat]
const Factory = await ethers.getContractFactory("MyContract");
const contract = await Factory.deploy(arg1, arg2);
await contract.waitForDeployment();
```

```solidity [Foundry]
MyContract myContract = new MyContract(arg1, arg2);
```

:::

#### Impersonating Users

::: code-group

```typescript [Hardhat]
await contract.connect(alice).someFunction(args);
```

```solidity [Foundry]
vm.prank(alice);
myContract.someFunction(args);
```

:::

::: warning `vm.prank` Is Single-Use
In Hardhat, `contract.connect(alice)` persists for all calls on that instance. In Foundry, `vm.prank(alice)` only applies to the **next** call. Use `vm.startPrank(alice)` / `vm.stopPrank()` for multiple calls.
:::

#### Encrypting Values

::: code-group

```typescript [Hardhat]
const input = fhevm.createEncryptedInput(contractAddr, userAddr);
input.add32(value);            // euint32
input.add64(value);            // euint64
const encrypted = await input.encrypt();
// encrypted.handles[0], encrypted.inputProof
```

```solidity [Foundry]
(externalEuint32 handle, bytes memory proof) = mockEncrypt32(value);
(externalEuint64 handle, bytes memory proof) = mockEncrypt64(value);
// No async, no SDK instance — pure Solidity
```

:::

#### Decrypting Values

::: code-group

```typescript [Hardhat]
const clearValue = await fhevm.userDecryptEuint(
  "euint32", ciphertext, contractAddr, signer
);
```

```solidity [Foundry]
uint32 clearValue = mockDecrypt32(encryptedValue);
uint64 clearValue = mockDecrypt64(encryptedValue);
address clearAddr = mockDecryptAddress(encryptedAddr);
```

:::

#### Assertions

::: code-group

```typescript [Hardhat (Chai)]
expect(value).to.equal(42);
expect(value).to.be.gt(0);
expect(fn()).to.be.revertedWith("message");
expect(fn()).to.be.revertedWithCustomError(contract, "ErrorName");
```

```solidity [Foundry (forge-std)]
assertEq(value, 42);
assertGt(value, 0);
vm.expectRevert("message");
vm.expectRevert(MyContract.ErrorName.selector);
myContract.someFunction();    // must come AFTER expectRevert
```

:::

::: warning `expectRevert` Comes BEFORE the Call
In Chai, `expect(fn()).to.be.reverted` wraps the call. In Foundry, `vm.expectRevert` is set up **before** the call that's expected to revert.
:::

#### Time Manipulation

::: code-group

```typescript [Hardhat]
await ethers.provider.send("evm_increaseTime", [3600]);
await ethers.provider.send("evm_mine");
```

```solidity [Foundry]
vm.warp(block.timestamp + 3600);
```

:::

#### Event Checking

::: code-group

```typescript [Hardhat]
await expect(contract.doThing())
  .to.emit(contract, "ThingDone")
  .withArgs(alice.address, 42);
```

```solidity [Foundry]
vm.expectEmit(true, true, false, true);
emit ThingDone(alice, 42);
myContract.doThing();
```

:::

#### Mock Mode Check

::: code-group

```typescript [Hardhat]
if (fhevm.isMock) {
  // skip test in mock mode
}
```

```solidity [Foundry]
if (isMock) {
  // skip test in mock mode
}
```

:::

---

## Deployment Script Migration

::: code-group

```typescript [Hardhat (TypeScript)]
import { ethers } from "hardhat";

async function main() {
  const Factory = await ethers.getContractFactory("FHECounter");
  const counter = await Factory.deploy();
  await counter.waitForDeployment();
  console.log("FHECounter deployed to:", await counter.getAddress());
}

main().catch(console.error);
```

```solidity [Foundry (Solidity)]
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {FHECounter} from "../src/FHECounter.sol";

contract DeployScript is Script {
    function run() public {
        vm.startBroadcast();
        FHECounter counter = new FHECounter();
        console.log("FHECounter deployed at:", address(counter));
        vm.stopBroadcast();
    }
}
```

:::

### Running Deployment Scripts

```bash
# Hardhat
npx hardhat run scripts/deploy.ts --network sepolia

# Foundry
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

Learn more about deployment in [Week 4, Lesson 2: Deployment](/week-4/lesson-2-deployment).

---

## Command Cheat Sheet

| Task | Hardhat | Foundry |
|------|---------|---------|
| Compile | `npx hardhat compile` | `forge build` |
| Test (all) | `npx hardhat test` | `forge test` |
| Test (verbose) | `npx hardhat test --verbose` | `forge test -vvv` |
| Test (filter) | `npx hardhat test --grep "increment"` | `forge test --match-test "increment"` |
| Deploy | `npx hardhat run scripts/deploy.ts` | `forge script script/Deploy.s.sol --broadcast` |
| Clean | `npx hardhat clean` | `forge clean` |
| Format | `npx prettier --write .` | `forge fmt` |
| Gas report | `REPORT_GAS=true npx hardhat test` | `forge test --gas-report` |
| Coverage | `npx hardhat coverage` | `forge coverage` |

---

## File Layout Comparison

| Hardhat | Foundry | Notes |
|---------|---------|-------|
| `contracts/` | `src/` | Source contracts |
| `test/` | `test/` | Same directory name |
| `scripts/` | `script/` | Singular in Foundry |
| `node_modules/` | `lib/` | Dependencies |
| `hardhat.config.ts` | `foundry.toml` | Config |
| `package.json` | N/A | Not needed |
| `tsconfig.json` | N/A | Not needed |

---

## Mock Helpers — Side by Side

The full mapping from Hardhat's `fhevmjs` API to Foundry's `FhevmTest` helpers:

### Encryption

| Hardhat (`fhevmjs`) | Foundry (`FhevmTest`) |
|--------------------|---------------------|
| `fhevm.createEncryptedInput(addr, user).add8(v).encrypt()` | `mockEncrypt8(v)` |
| `fhevm.createEncryptedInput(addr, user).add16(v).encrypt()` | `mockEncrypt16(v)` |
| `fhevm.createEncryptedInput(addr, user).add32(v).encrypt()` | `mockEncrypt32(v)` |
| `fhevm.createEncryptedInput(addr, user).add64(v).encrypt()` | `mockEncrypt64(v)` |
| `fhevm.createEncryptedInput(addr, user).add128(v).encrypt()` | `mockEncrypt128(v)` |
| `fhevm.createEncryptedInput(addr, user).add256(v).encrypt()` | `mockEncrypt256(v)` |
| `fhevm.createEncryptedInput(addr, user).addAddress(v).encrypt()` | `mockEncryptAddress(v)` |

### Decryption

| Hardhat (`fhevmjs`) | Foundry (`FhevmTest`) |
|--------------------|---------------------|
| `fhevm.userDecryptEuint("euint8", ct, addr, signer)` | `mockDecrypt8(ct)` |
| `fhevm.userDecryptEuint("euint16", ct, addr, signer)` | `mockDecrypt16(ct)` |
| `fhevm.userDecryptEuint("euint32", ct, addr, signer)` | `mockDecrypt32(ct)` |
| `fhevm.userDecryptEuint("euint64", ct, addr, signer)` | `mockDecrypt64(ct)` |
| `fhevm.userDecryptEuint("euint128", ct, addr, signer)` | `mockDecrypt128(ct)` |
| `fhevm.userDecryptEuint("euint256", ct, addr, signer)` | `mockDecrypt256(ct)` |
| `fhevm.userDecryptEuint("eaddress", ct, addr, signer)` | `mockDecryptAddress(ct)` |

For full details on mock helpers, see the [FHE Cheat Sheet](/resources/cheatsheet#mock-testing-quick-reference).

---

## Common Gotchas

These are the most frequent issues developers hit when migrating. Save yourself hours of debugging by reading this section.

### 1. Forgotten `super.setUp()`

Every test contract **must** call `super.setUp()` in its `setUp()` function. This deploys the mock FHE infrastructure. Without it, all FHE operations revert with cryptic errors.

```solidity
function setUp() public override {
    super.setUp();    // ← DON'T FORGET THIS
    myContract = new MyContract();
}
```

### 2. `vm.prank` Is Single-Use

In Hardhat, `contract.connect(alice)` persists for all calls on that instance. In Foundry, `vm.prank(alice)` only applies to the **next** call:

```solidity
// ❌ This DOES NOT work as expected
vm.prank(alice);
contract.foo();   // ← as alice
contract.bar();   // ← as test contract (NOT alice!)

// ✅ Use vm.startPrank for multiple calls
vm.startPrank(alice);
contract.foo();   // ← as alice
contract.bar();   // ← as alice
vm.stopPrank();
```

### 3. `vm.expectRevert` Comes BEFORE the Call

In Chai, `expect(fn()).to.be.reverted` wraps the call. In Foundry, `expectRevert` is set up **before** the call:

```solidity
// Foundry pattern
vm.expectRevert(MyContract.OnlyOwner.selector);
myContract.restrictedFunction();   // ← this call is expected to revert
```

### 4. Remapping Paths Must Match Exactly

If your Hardhat contracts import `@fhevm/solidity/lib/FHE.sol`, the remapping must map `@fhevm/solidity/` to `lib/fhevm-solidity/`. Any mismatch causes "file not found" errors during compilation.

```toml
# ✅ Correct — trailing slashes match
remappings = ["@fhevm/solidity/=lib/fhevm-solidity/"]

# ❌ Wrong — missing trailing slash
remappings = ["@fhevm/solidity=lib/fhevm-solidity"]
```

### 5. No `async/await` in Foundry Tests

Foundry tests are synchronous Solidity. There's no `await`. Contract calls are direct:

```solidity
// Just call it — no await needed
uint32 result = mockDecrypt32(counter.getCount());
```

### 6. Test Function Naming

Foundry test functions **must** start with `test` (or `testFuzz` for fuzz tests). Functions without the `test` prefix are silently ignored:

```solidity
function test_increment() public { ... }     // ✅ Runs
function testIncrement() public { ... }      // ✅ Runs
function increment() public { ... }          // ❌ Ignored
function test_fail_overflow() public { ... } // ✅ Expected to revert
```

### 7. Handling `.env` Variables

Hardhat uses `dotenv` + `process.env`. Foundry reads `.env` automatically or via cheatcodes:

```solidity
// Read from .env (in scripts)
uint256 pk = vm.envUint("PRIVATE_KEY");
string memory rpc = vm.envString("RPC_URL");

// With a default fallback
bool isMock = vm.envOr("FHEVM_MOCK", true);
```

---

## Migration Checklist

Use this checklist to track your migration progress:

- [ ] Install Foundry (`foundryup`)
- [ ] Create `foundry.toml` with correct remappings
- [ ] Copy FHE Solidity libraries into `lib/`
- [ ] Move contracts from `contracts/` to `src/`
- [ ] Copy `FhevmTest.sol` and mock contracts into `test/`
- [ ] Rewrite each test file from TypeScript to Solidity
- [ ] Convert `fhevm.createEncryptedInput()` calls to `mockEncrypt*()` helpers
- [ ] Convert `fhevm.userDecryptEuint()` calls to `mockDecrypt*()` helpers
- [ ] Replace `connect(signer)` with `vm.prank(addr)` or `vm.startPrank(addr)`
- [ ] Replace Chai assertions with forge-std assertions
- [ ] Convert deployment scripts from TypeScript to Solidity Forge scripts
- [ ] Run `forge build` — zero errors
- [ ] Run `forge test -vvv` — all tests pass
- [ ] Create `.env.example` with `FHEVM_MOCK`, `RPC_URL`, `PRIVATE_KEY`
- [ ] Update `.gitignore` for Foundry artifacts (`out/`, `cache/`)

---

## Further Reading

- [Getting Started](/getting-started) — Set up the Foundry environment from scratch
- [Week 1, Lesson 2: Environment Setup](/week-1/lesson-2-setup) — Deep dive into the mock framework
- [FHE Cheat Sheet](/resources/cheatsheet) — Quick reference for all FHE operations
- [Glossary](/resources/glossary) — Definitions for every term in the bootcamp
- [Foundry Book](https://book.getfoundry.sh/) — Official Foundry documentation
- [Zama FHEVM Documentation](https://docs.zama.ai/fhevm) — Official FHEVM docs (Hardhat-focused)
