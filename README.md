# Meridian Research Capital: tokenised research funding prototype

BF3124 Digital Assets in Finance · Group 6

Universities raise research funding by selling **revenue rights tokens**: a share of future commercialisation revenue, not ownership of the IP. This prototype runs the full lifecycle on the Ethereum **Sepolia** test network:

1. Meridian approves investor wallets (KYC).
2. Investors buy tokens at S$10 each (minimum S$500), paying in test tokenised SGD deposits. Their money is held in escrow by the contract.
3. The offering closes. If the S$500,000 minimum is met, the money goes to the university; otherwise every investor can claim a full refund.
4. The university records licensing revenue. 30% goes to token holders, split across a fixed 100,000 tokens.
5. Investors claim their payouts, and can transfer tokens to other approved wallets.

**Live demo:** open the GitHub Pages link for this repository with MetaMask on Sepolia.

## Deployed contracts (Sepolia)

| Contract | Role | Address |
|---|---|---|
| MockSGD | Test SGD money standing in for a bank's tokenised deposits | [0x8faA534DdaCf82c92092B7b93e378c440C0dF6bD](https://sepolia.etherscan.io/address/0x8faA534DdaCf82c92092B7b93e378c440C0dF6bD) |
| KYCRegistry | Meridian's list of approved wallets | [0xD4Ff4E3D84aBc8E8159c1d5AfFC3e2c8f3c2Ebfb](https://sepolia.etherscan.io/address/0xD4Ff4E3D84aBc8E8159c1d5AfFC3e2c8f3c2Ebfb) |
| RevenueRightsToken | The "Next-gen Solar Cells" project (token SOLAR) | [0x2a87a9db9061cff911365996b7c0a2a2e234c93e](https://sepolia.etherscan.io/address/0x2a87a9db9061cff911365996b7c0a2a2e234c93e) |

## Files

| File | What it is |
|---|---|
| `index.html` | The website (one file, uses ethers.js and MetaMask) |
| `MockSGD.sol`, `KYCRegistry.sol`, `RevenueRightsToken.sol` | Smart contract source code (Solidity 0.8.24, OpenZeppelin 5.0.2) |

## Design choices

- **Escrow with a minimum raise.** Like equity crowdfunding, investors are refunded automatically if the minimum isn't reached. The refund is enforced by code, not promised by the issuer.
- **Fixed 100,000-token split.** A token's share of each payment never shrinks as more tokens are sold. The share belonging to unsold tokens stays with the university.
- **Claim-based payouts.** A running "earned per token" total means payouts cost the same whether there are 10 holders or 10,000.
- **KYC on every transfer.** Tokens can only move between approved wallets, which gives permissioning at the contract level.
- **Pluggable settlement asset.** The project accepts any 2-decimal ERC-20 token. In production it would point at a partner bank's tokenised deposits instead of MockSGD.

## What's simulated

MockSGD is free test money; KYC approval is manual; revenue is reported by the university wallet (production would need an auditor or bank data feed as an oracle); and Sepolia is a public test network rather than a permissioned one.
