# Tokenized ETF Project Documentation

This document provides a technical overview and functional analysis of the smart contracts in the Tokenized ETF project.

## Architecture Overview

The system is designed to facilitate the trading of tokenized ETFs using a digital version of the Hong Kong Dollar (eHKD). Key components include:

- **KYC Registry**: An external contract (defined by `IKYC`) that manages whitelisted addresses.
- **eHKD**: A compliant ERC20 token representing digital HKD, restricted to KYC-verified users.
- **ETFVault**: An ERC4626-compliant vault representing the tokenized ETF (e.g., Tracker Fund 2800.HK).
- **ETFClearing**: A trade settlement engine that handles authorized trades between buyers and sellers.

---

## 1. IKYC.sol (Interface)

A simple interface for interacting with a KYC/Whitelisting service. This interface is implemented by `KYCRegistry.sol`.

### Functions:
- `isWhitelisted(address user)`: Returns `true` if the given address is authorized to interact with the system's tokens.

---

## 2. KYCRegistry.sol

The `KYCRegistry` is the implementation of the `IKYC` interface. it serves as the central authority for user verification in the ecosystem.

### Key Features:
- **Centralized Whitelist**: Maintains a mapping of addresses that have passed KYC requirements.
- **Access Control**: Only the contract owner (e.g., a regulatory body or a bank) can add or remove addresses.
- **Batch Processing**: Supports adding multiple addresses at once for efficiency.

### Function Analysis:
- `addAddress(address account)`: Adds a single address to the whitelist.
- `removeAddress(address account)`: Revokes an address's whitelisted status.
- `isWhitelisted(address account)`: Public view function providing the verification status to other contracts.
- `batchAddAddresses(address[] accounts)`: Efficiently whitelists multiple users in one transaction.

---

## 3. eHKD.sol

The `eHKD` contract is an ERC20 token representing the Digital Hong Kong Dollar. It extends `ERC20` and `Ownable`.

### Key Features:
- **KYC Restricted**: All transfers (including minting) are gated by the `kycRegistry`. Both the sender and receiver must be whitelisted.
- **Owner Controlled**: Only the owner can mint new tokens.

### Function Analysis:
- `constructor(address _kycRegistry)`: Initializes the token name ("Digital Hong Kong Dollar"), symbol ("eHKD"), and sets the KYC registry address.
- `mint(address to, uint256 amount)`: Allows the owner to issue new eHKD to a whitelisted address.
- `_update(address from, address to, uint256 value)`: Internal override of the ERC20 transfer logic. It ensures that both `from` and `to` addresses are whitelisted before any transfer, mint, or burn occurs (except for address zero checks).

---

## 3. ETFVault.sol

The `ETFVault` contract is an ERC4626 Yield-Bearing Vault representing the tokenized ETF shares.

### Key Features:
- **ERC4626 Standard**: Inherits standard vault functionality, allowing users to deposit assets and receive vault shares.
- **KYC Restricted**: Similar to eHKD, all share transfers are gated by the `kycRegistry`.

### Function Analysis:
- `constructor(IERC20 _asset, address _kycRegistry)`: Sets the underlying asset, the vault name ("Tokenized 2800.HK"), and the symbol ("t2800.HK").
- `_update(address from, address to, uint256 value)`: Internal override that enforces KYC checks on both participants of a share transfer.

---

## 4. ETFClearing.sol

The `ETFClearing` contract acts as the settlement layer for trading `ETFVault` shares for `eHKD`. It uses a 2-step trade authorization process.

### Key Features:
- **Price Management**: The owner can update the `priceRatio` between eHKD and the ETF.
- **Authorized Trades**: Sellers must authorize a specific trade (buyer, amount, price, deadline) before it can be executed.
- **Atomic Settlement**: Uses `safeTransferFrom` to move tokens between buyer and seller in a single transaction.
- **Reentrancy Protection**: Uses `ReentrancyGuard` on execution.

### Function Analysis:
- `setPriceRatioScaled(uint256 _newPrice)` / `setPriceUnscaled(uint256 _newNominalPrice)`: Administrative functions to set the current market price of the ETF in eHKD (scaled by 1e18).
- `authorizeTrade(address buyer, uint256 etfAmount, uint256 expectedPriceRatio, uint256 deadline)`: Called by the **seller** to create a unique `tradeId` and authorize a specific trade. Validates that both parties are whitelisted and the deadline is valid.
- `executeTrade(address buyer, address seller, uint256 etfAmount, uint256 expectedPriceRatio, uint256 deadline)`: Called by the **buyer** to finalize the trade. 
    - Verifies the `tradeId` exists and is authorized.
    - Verifies the current `priceRatio` matches the `expectedPriceRatio`.
    - Transfers `eHKD` from buyer to seller and `ETFVault` shares from seller to buyer.
    - Deletes the `tradeId` to prevent replay attacks.
- `quoteEHKD(uint256 etfAmount)`: A view function to calculate the eHKD cost for a given amount of ETF shares based on the current price.
- `_tradeId(...)`: Internal pure function that generates a unique hash of the trade parameters to track authorizations.

---

## Logical Workflow (How the ETF Works)

This project simulates the complete lifecycle of a Tokenized ETF:

### Phase 1: Compliance & Setup
1.  **KYC Onboarding**: A regulator adds "Authorized Participants" (Banks) and "Retail Investors" to the `KYCRegistry`.
2.  **Deployment**: All contracts are deployed, pointing to the same `KYCRegistry`.
3.  **Liquidity**: The Bank (Owner) mints `eHKD` to whitelisted investors so they have money to buy shares.

### Phase 2: Creation (Primary Market)
1.  **Custody**: A bank or custodian holds physical shares (represented by `MockUnderlying`).
2.  **Tokenization**: The custodian deposits `MockUnderlying` into the `ETFVault`.
3.  **Issuance**: The `ETFVault` mints `t2800.HK` shares back to the custodian. Now, real shares have been "turned into" tokens.

### Phase 3: Trading (Secondary Market)
1.  **Pricing**: The administrator updates the `priceRatio` in `ETFClearing` (e.g., 1 ETF share = 1000 eHKD).
2.  **Order Matching**: A seller (e.g., the custodian or a market maker) calls `authorizeTrade` to list shares for a buyer.
3.  **Settlement**: The buyer calls `executeTrade`. `ETFClearing` automatically swaps the buyer's `eHKD` for the seller's `t2800.HK` shares.

### Phase 4: Redemption (Primary Market)
1.  **Exit**: An investor who wants the physical asset back goes to the `ETFVault`.
2.  **Burn**: They call `withdraw` or `redeem`. The vault burns the `t2800.HK` tokens and returns the `MockUnderlying` (physical shares) to the investor.
