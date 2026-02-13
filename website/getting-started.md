# Getting Started

## Prerequisites

This bootcamp is designed for:

- **Web3 developers** with basic Ethereum and Solidity knowledge
- **Smart contract developers** looking to add privacy-preserving capabilities
- **Technical educators** planning to run FHEVM workshops

You should have:

- Basic understanding of Ethereum and smart contracts
- Familiarity with Solidity syntax
- Experience with development tools (Hardhat or Foundry)

**No prior FHE or cryptography knowledge is required.** Week 1 covers all the theory you need.

## Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge --version   # Verify installation
```

## Clone the Repository

```bash
git clone --recurse-submodules https://github.com/0xNana/fhevm-bootcamp.git
cd fhevm-bootcamp
```

## Build and Test

```bash
forge build           # Compile all contracts
forge test -vvv       # Run all 30 tests
```

Expected output: **30 tests passing** across 4 test suites in under 20 milliseconds.

## How to Use This Bootcamp

### Self-Paced Learning

Work through the weeks sequentially. Each week builds on the previous:

1. Read the **Week Overview** for milestones and time estimates
2. Work through each **Lesson** in order
3. Complete the **Homework** assignment
4. Check your work against the grading rubric

Expect **8-10 hours per week** including homework.

### Cohort-Based Workshop

If you are running a workshop or course:

1. Review the **Instructor Notes** for each week
2. Use the suggested **live-coding segments** and **discussion prompts**
3. Distribute **starter templates** from the `starter/` directory
4. Grade homework using the provided **rubrics**

See the [Instructor Notes](/week-1/instructor) for detailed teaching guidance.

### Coming from Hardhat?

If you have experience with the [fhevm-hardhat-template](https://github.com/zama-ai/fhevm-hardhat-template), see our [Hardhat Migration Guide](/resources/migration) for a complete side-by-side comparison.

## Project Structure

```
fhevm-bootcamp/
├── src/                    # Solution contracts (4 contracts)
│   ├── FHECounter.sol          # Week 1: Encrypted counter
│   ├── EncryptedVault.sol      # Week 2: Per-user encrypted vault
│   ├── ConfidentialERC20.sol   # Week 3: Encrypted ERC20 token
│   └── SealedBidAuction.sol    # Week 4: Sealed-bid auction
├── test/                   # Solution tests (30 tests)
│   ├── FhevmTest.sol           # Base test: mock FHE infrastructure
│   └── mocks/                  # Mock coprocessor, ACL, KMS, InputVerifier
├── starter/                # Homework starter templates
│   ├── week-1/                 # EncryptedPoll skeleton
│   ├── week-2/                 # EncryptedTipJar skeleton
│   ├── week-3/                 # ConfidentialERC20Extended skeleton
│   └── week-4/                 # VickreyAuction skeleton
├── script/                 # Deployment scripts
├── website/                # This learning platform (VitePress)
└── lib/                    # Dependencies (forge-std, fhevm-solidity)
```

## Next Step

Begin with [Week 1: Foundations & First Contract](/week-1/).
