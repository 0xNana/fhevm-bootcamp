# Lesson 1: FHE Theory & FHEVM Architecture

**Duration:** ~45 minutes (reading) | **Prerequisites:** Basic Solidity knowledge | **Code:** None (theory lesson)

---

## Learning Objectives

By the end of this lesson, you will understand:

- What Fully Homomorphic Encryption (FHE) is and why it matters for blockchain
- How the FHEVM coprocessor architecture works
- The encrypted data lifecycle: encrypt, compute, decrypt
- Key concepts: encrypted types, access control (ACL), and the KMS
- What you **cannot** do with FHE (and the workarounds)

---

## 1. The Privacy Problem in Blockchain

Every transaction on Ethereum is public. Balances, transfers, votes, bids — all visible to anyone. This is great for transparency but terrible for privacy.

Consider these scenarios that are **impossible** on a transparent blockchain:

- **Sealed-bid auctions** — bidders would see each other's bids
- **Private voting** — everyone could see who voted for what
- **Confidential transfers** — anyone can track your balance
- **Dark pool trading** — positions are visible to front-runners

The blockchain industry has tried workarounds (zero-knowledge proofs, TEEs, MPC), but they all involve tradeoffs between composability, generality, and developer experience.

## 2. What is Fully Homomorphic Encryption?

FHE allows **computation on encrypted data without decrypting it**.

```
Encrypted(3) + Encrypted(5) = Encrypted(8)
```

The computation happens entirely on ciphertext. Nobody — not the node, not the validator, not any observer — ever sees the plaintext values during computation. Only the holder of the decryption key can reveal the result.

This is not a new idea (Craig Gentry proposed it in 2009), but it was impractically slow for years. Recent breakthroughs by Zama and others have made it fast enough for real applications.

### FHE vs Other Privacy Solutions

| Approach | Composable | General-Purpose | Developer Experience |
|----------|-----------|-----------------|---------------------|
| ZK Proofs | Limited | Circuit-specific | Complex |
| TEEs (SGX) | Yes | Yes | Good, but trust assumptions |
| MPC | Limited | Expensive for >2 parties | Complex |
| **FHE (FHEVM)** | **Yes** | **Yes** | **Solidity-native** |

## 3. The HTTPS Analogy

Remember the internet in the 1990s? Data was shared publicly. There were no real use cases beyond email and static websites. Then **HTTPS changed everything**.

With encryption as infrastructure, entire industries became possible. E-commerce emerged. Banking went digital. SaaS platforms scaled globally.

**FHE is the HTTPS moment for blockchain.** It makes the base layer private by default, enabling entirely new categories of applications.

## 4. FHEVM Architecture

The FHEVM (Fully Homomorphic Encryption Virtual Machine) adds a **confidential computing layer** to the EVM. Here's how it works:

### The Coprocessor Model

```
                                    ┌──────────────────┐
                                    │   KMS Network    │
                                    │  (Key Management)│
                                    └────────┬─────────┘
                                             │
┌────────────┐    tx    ┌───────────────┐    │    ┌──────────────────┐
│   User     │ ──────── │   EVM Chain   │ ───┼──► │   Coprocessor    │
│ (Wallet +  │          │  (Contracts)  │    │    │  (FHE Executor)  │
│  fhevmjs)  │ ◄─────── │              │ ◄──┘    │                  │
└────────────┘  result  └───────────────┘         └──────────────────┘
```

**The key insight**: Smart contracts look like normal Solidity. The encrypted operations (`FHE.add`, `FHE.sub`, etc.) are delegated to a **coprocessor** that performs the actual FHE computation off-chain, then returns the encrypted result.

### Components

1. **FHE Library (`FHE.sol`)** — Solidity library providing encrypted type operations. You call `FHE.add(a, b)` just like you'd write `a + b`.

2. **Coprocessor (FHEVMExecutor)** — Performs FHE computations. Lives at a known address on-chain, receives encrypted operands, returns encrypted results.

3. **ACL (Access Control List)** — Controls who can read encrypted values. A ciphertext handle is useless unless you have permission.

4. **KMS (Key Management Service)** — Threshold network that manages the global FHE key. No single party can decrypt — it requires threshold cooperation.

5. **fhevmjs** — Client-side JavaScript/TypeScript SDK for encrypting inputs and decrypting outputs.

## 5. Encrypted Types

FHEVM introduces encrypted equivalents of Solidity integer types:

| Encrypted Type | Plaintext Equivalent | Use Case |
|---------------|---------------------|----------|
| `ebool` | `bool` | Encrypted flags, conditions |
| `euint8` | `uint8` | Small counters, enums |
| `euint16` | `uint16` | Medium values |
| `euint32` | `uint32` | Counters, IDs |
| `euint64` | `uint64` | Token amounts, balances |
| `euint128` | `uint128` | Large values |
| `euint256` | `uint256` | Very large values |
| `eaddress` | `address` | Encrypted addresses |

All encrypted types are stored as `bytes32` handles on-chain. The actual ciphertext lives in the coprocessor.

### External Types

When a user sends an encrypted value to a contract, they use **external types** (e.g., `externalEuint32`). These are "unverified" encrypted inputs that must be validated:

```solidity
function deposit(externalEuint64 encAmount, bytes calldata inputProof) external {
    // Verify and convert to internal encrypted type
    euint64 amount = FHE.fromExternal(encAmount, inputProof);
    // Now 'amount' is a verified encrypted value you can operate on
}
```

## 6. The Encrypted Data Lifecycle

```
     User                    Contract                 Coprocessor
      │                         │                         │
      │  1. Encrypt (fhevmjs)   │                         │
      │  ─────────────────────► │                         │
      │  handle + inputProof    │                         │
      │                         │                         │
      │                         │  2. FHE.fromExternal()  │
      │                         │  ─────────────────────► │
      │                         │  verifyInput()          │
      │                         │  ◄───────────────────── │
      │                         │                         │
      │                         │  3. FHE.add(a, b)       │
      │                         │  ─────────────────────► │
      │                         │  fheAdd()               │
      │                         │  ◄───────────────────── │
      │                         │  (encrypted result)     │
      │                         │                         │
      │                         │  4. FHE.allow(result,   │
      │                         │     msg.sender)         │
      │                         │  ─────────────────────► │
      │                         │  ACL.allow()            │
      │                         │                         │
      │  5. userDecrypt()       │                         │
      │  (off-chain via KMS)    │                         │
      │  ◄──────────────────────┼─────────────────────────│
      │  plaintext result       │                         │
```

### Step by Step

1. **Encrypt** — The user encrypts a plaintext value client-side using `fhevmjs`. This produces a `handle` (bytes32 identifier) and an `inputProof` (cryptographic proof that the ciphertext is well-formed).

2. **Verify** — The contract calls `FHE.fromExternal(handle, proof)` which asks the coprocessor to verify the input. This prevents malicious ciphertext injection.

3. **Compute** — The contract performs operations on encrypted values (`FHE.add`, `FHE.sub`, `FHE.gt`, etc.). Each operation is delegated to the coprocessor.

4. **Authorize** — The contract grants read access via `FHE.allow(result, user)` or `FHE.allowThis(result)`. Without this, nobody can decrypt the result.

5. **Decrypt** — The user decrypts off-chain using `fhevmjs` and the KMS. The plaintext never touches the blockchain.

## 7. Access Control: Who Can Read What?

The ACL is critical. An encrypted value is useless unless someone has permission to decrypt it.

- **`FHE.allowThis(value)`** — The contract itself can use this value in future computations
- **`FHE.allow(value, account)`** — Grant a specific address permission to decrypt
- **`FHE.allowTransient(value, account)`** — Temporary permission (within one transaction)

**Rule of thumb**: After any FHE operation that produces a new encrypted value, you MUST call `allowThis` (so the contract can use it later) and optionally `allow` (so a user can decrypt it).

## 8. What You Cannot Do with FHE

Understanding the limitations is as important as understanding the capabilities:

- **No encrypted control flow** — You cannot write `if (encryptedValue > 5)` because the EVM cannot branch on encrypted data. Use `FHE.select(condition, ifTrue, ifFalse)` instead.
- **No encrypted loops** — Loop bounds cannot depend on encrypted values.
- **Higher gas costs** — FHE operations are more expensive than plaintext operations (the coprocessor does real work).
- **No cross-contract encrypted reads** — A contract cannot read another contract's encrypted state unless explicitly allowed.

---

## Key Takeaways

1. FHE enables **computation on encrypted data** — the blockchain never sees plaintext
2. FHEVM uses a **coprocessor model** — contracts look like normal Solidity, FHE ops are delegated
3. **Encrypted types** (`euint32`, `euint64`, etc.) replace plaintext types for private data
4. **Access control** (ACL) determines who can decrypt — always `allowThis` + `allow` after computation
5. **Decryption is off-chain** — via fhevmjs and the KMS threshold network

---

**Next:** [Lesson 2: Environment Setup](/week-1/lesson-2-setup) — Install Foundry and run your first FHE test.
