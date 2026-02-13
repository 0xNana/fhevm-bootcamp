# Lesson 3: Hello FHE — Your First Encrypted Contract

**Duration:** ~60 minutes | **Prerequisites:** [Lesson 2: Environment Setup](/week-1/lesson-2-setup) | **Contract:** `src/FHECounter.sol`

---

## Learning Objectives

By the end of this lesson, you will:

- Understand the `FHECounter` contract line by line
- Know how encrypted types (`euint32`, `externalEuint32`) work in practice
- Master the encrypt → compute → authorize → decrypt flow
- Write Forge tests for FHE contracts using mock helpers
- Be able to add new FHE operations to an existing contract

---

## 1. The Contract

Open `src/FHECounter.sol`. This is **identical** to the Hardhat template's `FHECounter.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract FHECounter is ZamaEthereumConfig {
    euint32 private _count;

    function getCount() external view returns (euint32) {
        return _count;
    }

    function increment(externalEuint32 inputEuint32, bytes calldata inputProof) external {
        euint32 encryptedEuint32 = FHE.fromExternal(inputEuint32, inputProof);
        _count = FHE.add(_count, encryptedEuint32);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }

    function decrement(externalEuint32 inputEuint32, bytes calldata inputProof) external {
        euint32 encryptedEuint32 = FHE.fromExternal(inputEuint32, inputProof);
        _count = FHE.sub(_count, encryptedEuint32);
        FHE.allowThis(_count);
        FHE.allow(_count, msg.sender);
    }
}
```

Let's break it down.

## 2. Line-by-Line Walkthrough

### Imports

```solidity
import {FHE, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
```

- **`FHE`** — The main library. All encrypted operations go through `FHE.add()`, `FHE.sub()`, `FHE.allow()`, etc.
- **`euint32`** — An encrypted unsigned 32-bit integer. Stored as `bytes32` on-chain (a handle pointing to the ciphertext in the coprocessor).
- **`externalEuint32`** — An "unverified" encrypted input from a user. Must be validated with `FHE.fromExternal()`.

```solidity
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
```

- **`ZamaEthereumConfig`** — Abstract contract whose constructor calls `FHE.setCoprocessor()` with the correct addresses for the current chain (mainnet, Sepolia, or local).

### State Variable

```solidity
euint32 private _count;
```

This is the encrypted counter. It's stored as `bytes32(0)` initially (uninitialized). The FHE library handles uninitialized values gracefully — `FHE.add(uninitialized, x)` treats uninitialized as zero.

### Reading the Count

```solidity
function getCount() external view returns (euint32) {
    return _count;
}
```

This returns the **encrypted** count. The caller gets a `bytes32` handle, not a plaintext number. To see the actual value, the caller must decrypt it off-chain (and must have been granted permission via `FHE.allow`).

### Increment

```solidity
function increment(externalEuint32 inputEuint32, bytes calldata inputProof) external {
    // Step 1: Verify the encrypted input
    euint32 encryptedEuint32 = FHE.fromExternal(inputEuint32, inputProof);

    // Step 2: Add the encrypted value to the counter
    _count = FHE.add(_count, encryptedEuint32);

    // Step 3: Grant permissions on the new encrypted result
    FHE.allowThis(_count);        // Contract can use _count in future operations
    FHE.allow(_count, msg.sender); // Caller can decrypt _count
}
```

**Why three steps?** Every FHE operation produces a **new** encrypted handle. The old `_count` handle and the new one are different values. Permissions don't carry over — you must re-authorize after each operation.

### Decrement

```solidity
function decrement(externalEuint32 inputEuint32, bytes calldata inputProof) external {
    euint32 encryptedEuint32 = FHE.fromExternal(inputEuint32, inputProof);
    _count = FHE.sub(_count, encryptedEuint32);
    FHE.allowThis(_count);
    FHE.allow(_count, msg.sender);
}
```

Same pattern as increment, but uses `FHE.sub`.

## 3. The Test

Open `test/FHECounter.t.sol`:

```solidity
contract FHECounterTest is FhevmTest {
    FHECounter public counter;
    address public alice;

    function setUp() public override {
        super.setUp();              // Deploy mock FHE infrastructure
        alice = makeAddr("alice");
        counter = new FHECounter(); // Deploy the contract
    }

    function test_incrementByOne() public {
        // 1. Encrypt the value 1
        (externalEuint32 handle, bytes memory inputProof) = mockEncrypt32(1);

        // 2. Call increment as alice
        vm.prank(alice);
        counter.increment(handle, inputProof);

        // 3. Decrypt and verify
        uint32 clearCount = mockDecrypt32(counter.getCount());
        assertEq(clearCount, 1);
    }
}
```

### The Test Pattern

This three-step pattern is the Foundry equivalent of the Hardhat test flow:

| Step | Hardhat | Foundry |
|------|---------|---------|
| Encrypt | `fhevm.createEncryptedInput(addr, user).add32(1).encrypt()` | `mockEncrypt32(1)` |
| Call | `contract.connect(alice).increment(handles[0], inputProof)` | `vm.prank(alice); contract.increment(handle, proof)` |
| Decrypt | `fhevm.userDecryptEuint(euint32, ct, addr, signer)` | `mockDecrypt32(ct)` |

### What happens under the hood in mock mode

When you call `mockEncrypt32(1)`:
- Returns `handle = externalEuint32.wrap(bytes32(uint256(1)))` — the plaintext value 1 encoded as bytes32
- Returns `inputProof = bytes(0x00)` — a dummy non-empty proof

When the contract calls `FHE.fromExternal(handle, proof)`:
- The proof is non-empty, so it calls `Impl.verify()` → `MockFHEVMExecutor.verifyInput()` → returns the handle as-is
- Result: `euint32.wrap(bytes32(1))`

When the contract calls `FHE.add(_count, encryptedValue)`:
- `_count` is `bytes32(0)` (uninitialized), so FHE auto-initializes it to `trivialEncrypt(0)` → `bytes32(0)`
- Calls `MockFHEVMExecutor.fheAdd(bytes32(0), bytes32(1), 0x00)` → returns `bytes32(0 + 1)` = `bytes32(1)`

When you call `mockDecrypt32(counter.getCount())`:
- Unwraps the `euint32` to `bytes32`, casts to `uint32` → returns `1`

## 4. Run the Tests

```bash
forge test -vvv
```

All 5 tests should pass:
- `test_initialCountIsZero` — Counter starts at bytes32(0)
- `test_incrementByOne` — Increment by 1, decrypt to verify
- `test_decrementByOne` — Increment then decrement, verify returns to 0
- `test_multipleIncrements` — 5 + 3 = 8
- `test_differentUsersCanIncrement` — Alice adds 10, Bob adds 20, total is 30

## 5. Exercise: Add a Multiply Function

Now it's your turn. Try adding a `multiply` function to `FHECounter.sol`:

```solidity
function multiply(externalEuint32 inputEuint32, bytes calldata inputProof) external {
    euint32 encryptedEuint32 = FHE.fromExternal(inputEuint32, inputProof);
    _count = FHE.mul(_count, encryptedEuint32);
    FHE.allowThis(_count);
    FHE.allow(_count, msg.sender);
}
```

Then write a test:

```solidity
function test_multiply() public {
    // Set count to 5
    (externalEuint32 h1, bytes memory p1) = mockEncrypt32(5);
    vm.prank(alice);
    counter.increment(h1, p1);

    // Multiply by 3
    (externalEuint32 h2, bytes memory p2) = mockEncrypt32(3);
    vm.prank(alice);
    counter.multiply(h2, p2);

    // Should be 15
    assertEq(mockDecrypt32(counter.getCount()), 15);
}
```

Notice how the pattern is always the same: **encrypt → call → decrypt → assert**. This is the rhythm of FHE testing.

## 6. Common Mistakes

1. **Forgetting `FHE.allowThis()`** — If you don't call `allowThis` after an operation, the contract cannot use the result in future operations. The next call that reads `_count` will revert.

2. **Forgetting `FHE.allow()`** — If you don't allow the caller, they cannot decrypt the result off-chain.

3. **Using `externalEuint32` without `fromExternal`** — External types are unverified. Always validate with `FHE.fromExternal(handle, proof)`.

4. **Expecting plaintext returns** — `getCount()` returns an encrypted handle, not a number. You must decrypt off-chain.

---

## Key Concepts Introduced

| Concept | What It Does |
|---------|-------------|
| `euint32` | Encrypted unsigned 32-bit integer (stored as bytes32 handle) |
| `externalEuint32` | Unverified encrypted input from user |
| `FHE.fromExternal()` | Verify and convert external input to internal type |
| `FHE.add()` / `FHE.sub()` | Encrypted arithmetic |
| `FHE.allowThis()` | Grant contract permission to use a value |
| `FHE.allow()` | Grant a user permission to decrypt a value |
| `ZamaEthereumConfig` | Auto-configures coprocessor addresses for current chain |

---

## Key Takeaways

1. The **FHE pattern** is always: verify input → compute on ciphertext → authorize → decrypt off-chain
2. Every FHE operation produces a **new handle** — you must re-authorize after each operation
3. The **test pattern** mirrors the contract pattern: encrypt → call → decrypt → assert
4. Mock mode makes all of this **fast and deterministic** — no real cryptography during testing

---

**Next:** [Homework: EncryptedPoll](/week-1/homework) — Build an encrypted voting contract from scratch.
