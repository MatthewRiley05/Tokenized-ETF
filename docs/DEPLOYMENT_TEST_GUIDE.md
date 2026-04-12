# Deployment & Testing Guide

This guide explains how to deploy and test the Tokenized ETF system. 

## 1. Deployment Order (Critical)

The contracts have specific dependencies. They **must** be deployed in this exact order:

1.  **KYCRegistry**: The "Source of Truth" for all other contracts.
    *   *No parameters.*
2.  **MockUnderlying**: Represents the physical shares (e.g., 2800.HK).
    *   *No parameters.*
3.  **eHKD**: The digital currency.
    *   *Parameter*: `_kycRegistry` (Address of Step 1).
4.  **ETFVault**: The creation/redemption engine.
    *   *Parameters*: `_asset` (Address of Step 2), `_kycRegistry` (Address of Step 1).
5.  **ETFClearing**: The secondary market trading engine.
    *   *Parameters*: `_eHKD` (Step 3), `_etfVault` (Step 4), `_kyc` (Step 1).

---

## 2. Recommended Test Story (The "Golden Path")

To prove the logic works, follow these steps in your testing environment (e.g., Remix, Foundry, or Hardhat):

### Step 1: Compliance Setup
1.  **Deploy** all contracts in the order above.
2.  In **KYCRegistry**, call `batchAddAddresses` with the addresses of:
    *   The **Bank** (The account that will issue tokens).
    *   The **Buyer** (The account that will buy the ETF).
    *   *Result: Only these two can now hold or move tokens.*

### Step 2: Liquidity & Creation
1.  In **eHKD**, call `mint` to give the **Buyer** 10,000 eHKD.
2.  In **MockUnderlying**, call `mint` to give the **Bank** 100 "Physical Shares".
3.  In **MockUnderlying**, the Bank calls `approve` for the **ETFVault** address (for 100 shares).
4.  In **ETFVault**, the Bank calls `deposit(100, BankAddress)`.
    *   *Result: The Bank now holds 100 `t2800.HK` (Tokenized ETF shares).*

### Step 3: Trade Preparation
1.  In **ETFClearing**, the owner calls `setPriceUnscaled(100)`.
    *   *Logic: 1 ETF share now costs 100 eHKD.*
2.  In **ETFVault**, the Bank calls `approve` for the **ETFClearing** address (for 10 shares).
3.  In **eHKD**, the Buyer calls `approve` for the **ETFClearing** address (for 1,000 eHKD).

### Step 4: The Trade (2-Step Settlement)
1.  **Authorize**: The **Bank** (Seller) calls `authorizeTrade`:
    *   `buyer`: BuyerAddress
    *   `etfAmount`: 10
    *   `expectedPriceRatio`: 100 * 1e18 (The scaled price)
    *   `deadline`: A future timestamp (e.g., current time + 3600).
2.  **Execute**: The **Buyer** calls `executeTrade` using the exact same parameters.
    *   *Result: Atomic Swap! The Buyer gets 10 ETF shares, and the Bank gets 1,000 eHKD.*

---

## 3. Negative Tests (Edge Cases)

To "satisfy the logic," you should also show what **fails**:

*   **KYC Failure**: Try to transfer `eHKD` or `t2800.HK` to a random address that hasn't been added to the `KYCRegistry`. It should revert with `KYC_NotWhitelisted`.
*   **Price Slip**: If the Bank authorizes a trade at price 100, but the Owner updates the price to 101 before the buyer executes, the trade will fail. This protects the buyer.
*   **Unauthorized**: If the Buyer tries to `executeTrade` without the Bank first calling `authorizeTrade`, it will fail.
