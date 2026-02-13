---
layout: home

hero:
  name: "FHEVM Bootcamp"
  text: "Zero to Mainnet"
  tagline: "The first Foundry-based FHEVM curriculum. 4 weeks from FHE theory to confidential smart contracts on mainnet."
  actions:
    - theme: brand
      text: Start Learning
      link: /getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/0xNana/fhevm-bootcamp

features:
  - title: "Foundry-First"
    details: "Zama only supports Hardhat. This bootcamp brings FHEVM to Foundry — faster tests, Solidity-native, zero JavaScript dependencies."
    icon: "&#9889;"
  - title: "4-Week Curriculum"
    details: "Progressive structure from FHE theory to mainnet deployment. Works for cohort-based workshops and self-paced learning."
    icon: "&#128218;"
  - title: "30 Passing Tests"
    details: "4 production-grade contracts with comprehensive test suites. All running in mock mode — no real FHE infrastructure needed."
    icon: "&#9989;"
  - title: "Homework & Grading"
    details: "Weekly assignments with starter templates, pre-written test suites, and detailed grading rubrics."
    icon: "&#128221;"
  - title: "Reusable Mock Framework"
    details: "FhevmTest.sol + 4 mock contracts that any Foundry project can drop in to test FHE contracts locally."
    icon: "&#128295;"
  - title: "Real-World Capstone"
    details: "Culminates in a sealed-bid auction mirroring Zama Auction — the first application on Zama Protocol mainnet."
    icon: "&#127942;"
---

## Curriculum at a Glance

| Week | Focus | What You Build | Homework |
|------|-------|---------------|----------|
| [**1**](/week-1/) | Foundations & First Contract | `FHECounter.sol` | EncryptedPoll |
| [**2**](/week-2/) | Encrypted State & Access Control | `EncryptedVault.sol` | EncryptedTipJar |
| [**3**](/week-3/) | Confidential DeFi | `ConfidentialERC20.sol` | Extended ERC20 |
| [**4**](/week-4/) | Capstone & Production | `SealedBidAuction.sol` | Vickrey Auction |

**Total: 4 weeks** | ~8-10 hours per week | 30 tests across 4 contracts

## The Problem This Bootcamp Solves

Zama's official FHEVM tooling is built exclusively for Hardhat. There is **no official Foundry support** — no plugin, no templates, no testing infrastructure.

This bootcamp bridges that gap with:

- A complete **Foundry mock framework** (`FhevmTest.sol`) that replaces the `@fhevm/hardhat-plugin`
- **4 progressive contracts** covering every core FHE pattern
- **Side-by-side Hardhat migration guide** for developers transitioning toolchains

The smart contracts are **identical** between Hardhat and Foundry — the same `FHECounter.sol` compiles in both without a single line changed.

## Quick Start

```bash
git clone --recurse-submodules https://github.com/0xNana/fhevm-bootcamp.git
cd fhevm-bootcamp
forge build
forge test -vvv   # 30 tests passing
```
