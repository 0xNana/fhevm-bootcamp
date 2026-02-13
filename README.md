# FHEVM Bootcamp: Zero to Mainnet

A comprehensive, hands-on bootcamp for building **confidential smart contracts** using [Zama's FHEVM](https://docs.zama.ai/fhevm) and [Foundry](https://book.getfoundry.sh/).

Build production-grade encrypted applications — from your first encrypted counter to a sealed-bid auction inspired by [Zama Auction](https://www.zama.ai/post/announcing-zama-auction), the first application on Zama Protocol mainnet.

**[View the Learning Platform](https://0xnana.github.io/fhevm-bootcamp/)**

---

## The Problem: Zama Only Supports Hardhat

Zama's official FHEVM tooling — the [fhevm-hardhat-template](https://github.com/zama-ai/fhevm-hardhat-template), `@fhevm/hardhat-plugin`, and every existing tutorial — is built exclusively for Hardhat. There is **no official Foundry support**.

Yet Foundry has become the standard for serious Solidity development: sub-second compilation, Solidity-native tests, built-in fuzzing, and a developer experience that Hardhat cannot match. Developers who prefer Foundry are currently locked out of the FHEVM ecosystem.

**This bootcamp bridges that gap.** It is the first and only FHEVM curriculum built entirely on Foundry, complete with a custom mock testing infrastructure that replaces the `@fhevm/hardhat-plugin` with pure Solidity — no JavaScript, no npm, no plugin dependencies.

### Hardhat vs Foundry at a Glance

| | Hardhat (Zama's official) | This Bootcamp (Foundry) |
|--|---------------------------|------------------------|
| Test language | TypeScript + Mocha/Chai | Solidity (forge-std) |
| Compile speed | ~5-10 seconds | **<2 seconds** |
| Test speed (30 tests) | ~8-15 seconds | **<20 milliseconds** |
| Dependencies | npm, ethers, hardhat-plugin | **Zero JS dependencies** |
| FHE mock infra | `@fhevm/hardhat-plugin` | `FhevmTest.sol` (open, reusable) |
| Contract code | `FHECounter.sol` | **Identical** `FHECounter.sol` |

The smart contracts are **identical** between Hardhat and Foundry — the same `FHECounter.sol` compiles in both without a single line changed.

---

## Quick Start

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/0xNana/fhevm-bootcamp.git
cd fhevm-bootcamp

# Build
forge build

# Run all tests (mock mode — no real FHE needed)
forge test -vvv
```

Expected output: **30 tests passing** across 4 test suites in under 20 milliseconds.

---

## 4-Week Curriculum

The bootcamp is structured as a progressive 4-week program. Each week includes lessons, a formal homework assignment with grading rubrics, and instructor notes.

| Week | Focus | What You Build | Homework |
|------|-------|---------------|----------|
| **1** | Foundations & First Contract | `FHECounter.sol` | EncryptedPoll |
| **2** | Encrypted State & Access Control | `EncryptedVault.sol` | EncryptedTipJar |
| **3** | Confidential DeFi | `ConfidentialERC20.sol` | Extended ERC20 |
| **4** | Capstone & Production | `SealedBidAuction.sol` | Vickrey Auction |

**Total: 4 weeks** | ~8-10 hours per week | 30 tests across 4 contracts

Browse the full curriculum on the **[learning platform](https://0xnana.github.io/fhevm-bootcamp/)**.

---

## Project Structure

```
fhevm-bootcamp/
├── src/                              # Solution contracts (4 contracts)
│   ├── FHECounter.sol                    # Week 1: Encrypted counter
│   ├── EncryptedVault.sol                # Week 2: Per-user encrypted vault
│   ├── ConfidentialERC20.sol             # Week 3: Encrypted ERC20 token
│   └── SealedBidAuction.sol              # Week 4: Sealed-bid auction
│
├── test/                             # Solution tests (30 tests)
│   ├── FhevmTest.sol                     # Base test: deploys mock FHE infrastructure
│   ├── mocks/                            # Mock coprocessor, ACL, KMS, InputVerifier
│   ├── FHECounter.t.sol                  # 5 tests
│   ├── EncryptedVault.t.sol              # 7 tests
│   ├── ConfidentialERC20.t.sol           # 8 tests
│   └── SealedBidAuction.t.sol            # 10 tests
│
├── starter/                          # Homework starter templates
│   ├── week-1/                           # EncryptedPoll (skeleton + tests)
│   ├── week-2/                           # EncryptedTipJar (skeleton + tests)
│   ├── week-3/                           # ConfidentialERC20Extended (skeleton + tests)
│   └── week-4/                           # VickreyAuction (skeleton + tests)
│
├── website/                          # VitePress learning platform
│   ├── .vitepress/config.ts              # Site config, sidebar, navigation
│   ├── week-1/ through week-4/           # Lessons, homework specs, instructor notes
│   └── resources/                        # Cheat sheet, glossary, migration guide
│
├── script/
│   └── Deploy.s.sol                  # Deployment script
│
├── lib/                              # Dependencies (git submodules)
│   ├── forge-std/                        # Forge standard library
│   ├── fhevm-solidity/                   # @fhevm/solidity (FHE.sol, ZamaConfig)
│   └── encrypted-types/                  # Encrypted type definitions
│
├── .github/workflows/
│   ├── test.yml                      # CI: format, build, test
│   └── deploy.yml                    # CD: VitePress → GitHub Pages
│
├── VIDEO_SCRIPT.md                   # 5-minute demo video script
└── foundry.toml                      # Foundry configuration
```

---

## How Mock Mode Works

All tests run locally without any real FHE infrastructure. The test base contract (`FhevmTest.sol`) deploys mock contracts at the addresses `ZamaConfig` expects:

```
                    ┌─────────────────────────┐
Your Contract       │  FHE.add(a, b)          │
(e.g. FHECounter)   │      │                  │
                    │      ▼                  │
                    │  Impl.add()             │
                    │      │                  │
                    │      ▼                  │
                    │  IFHEVMExecutor          │
                    │  @ 0xe3a910...          │
                    └──────┬──────────────────┘
                           │
                           ▼
                    ┌─────────────────────────┐
                    │  MockFHEVMExecutor       │
                    │  fheAdd(a, b, _)        │
                    │  → bytes32(a + b)       │
                    │  (plaintext arithmetic) │
                    └─────────────────────────┘
```

In mock mode, encrypted handles are `bytes32`-encoded plaintext values. `fheAdd(3, 5)` returns `8`. This is fast, deterministic, and requires no real FHE.

## FHE Concepts Covered

| Concept | Week | Description |
|---------|------|-------------|
| Encrypted types | 1 | `euint32`, `euint64`, `eaddress`, `ebool` |
| External inputs | 1 | `externalEuint32`, `FHE.fromExternal()` |
| Arithmetic | 1 | `FHE.add()`, `FHE.sub()`, `FHE.mul()` |
| Access control | 2 | `FHE.allowThis()`, `FHE.allow()`, `FHE.allowTransient()` |
| Comparisons | 2 | `FHE.le()`, `FHE.gt()`, `FHE.eq()` |
| Conditionals | 2 | `FHE.select()` — encrypted if/then/else |
| Trivial encryption | 3 | `FHE.asEuint64()` — plaintext to encrypted |
| Silent-zero pattern | 3 | Privacy-preserving error handling |
| Encrypted addresses | 4 | `eaddress`, `FHE.asEaddress()` |
| State machines | 4 | Phase-based FHE contract design |

## Running Tests

```bash
# All tests (30 total)
forge test -vvv

# By week
forge test --match-contract FHECounterTest -vvv          # Week 1
forge test --match-contract EncryptedVaultTest -vvv       # Week 2
forge test --match-contract ConfidentialERC20Test -vvv    # Week 3
forge test --match-contract SealedBidAuctionTest -vvv     # Week 4
```

## Coming from Hardhat?

See the full **[Hardhat to Foundry Migration Guide](https://0xnana.github.io/fhevm-bootcamp/resources/migration)** on the learning platform for a step-by-step walkthrough with side-by-side code comparisons, a complete cheat sheet, and a migration checklist.

Quick mapping:

| Hardhat | Foundry |
|---------|---------|
| `npx hardhat test` | `forge test` |
| `@fhevm/hardhat-plugin` | `FhevmTest.sol` + mocks |
| `fhevm.createEncryptedInput().add32(v).encrypt()` | `mockEncrypt32(v)` |
| `fhevm.userDecryptEuint(...)` | `mockDecrypt32(ct)` |
| `hardhat.config.ts` | `foundry.toml` |

The smart contract code is **identical** — `FHECounter.sol` works in both templates unchanged.

## License

MIT

## Acknowledgments

- [Zama](https://www.zama.org/) — for building FHEVM and the fhEVM Solidity library
- [Foundry](https://book.getfoundry.sh/) — for the best Ethereum development toolkit
- Inspired by [Zama Auction](https://www.zama.ai/post/announcing-zama-auction) — the first application on Zama Protocol mainnet
