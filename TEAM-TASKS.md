# Team Task Breakdown

This document explains what each team member needs to build, how the pieces connect, and current status.

---

## Current Status Summary

### Contracts: DEPLOYED ON BASE MAINNET

| Contract | Address | Status |
|----------|---------|--------|
| **AutoYieldModule** | `0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce` | Deployed |
| **MorphoAdapter** | `0x8438E34f258044cf656EBA796B8559bA1ee3020a` | Deployed |
| **AutopilotFactory** | `0xc627874FE7444f8e9750e5043c19bA01E990D581` | Deployed |
| **Automation Key** | `0xD78F5099987389e33bD6Ec15FF3Ca4dBedD507f3` | Configured |

All 33 tests pass. Factory `getAddress()` works correctly.

### What's Ready

- Factory can predict and create smart wallet addresses
- AutoYieldModule has full functionality: `rebalance`, `migrateStrategy`, `executeWithAutoYield`, `flushToChecking`
- MorphoAdapter integrates with real Morpho vault (Moonwell Flagship USDC - 6%+ APY)
- Backend has live yield data from Morpho/Aave/Moonwell APIs

---

## How Everything Connects

```
USER CLICKS "CREATE WALLET"
         |
         v
[Frontend: Connect EOA wallet]
         |
         |-- 1. User connects Coinbase Wallet / MetaMask
         |-- 2. Frontend calls factory.createAccount(salt)
         |-- 3. Gets new smart wallet address back
         |
         v
[User deposits USDC to smart wallet address]
         |
         v
[Smart Wallet auto-rebalances]
         |
         |-- Module detects balance > threshold
         |-- Deposits excess to Morpho vault via MorphoAdapter
         |
         v
[User spends from wallet]
         |
         |-- executeWithAutoYield() auto-withdraws from yield if needed
         |-- Executes transfer
         |-- Re-deposits any excess
```

---

## Jackson (Contracts) - COMPLETE

All core contracts are deployed and working on Base mainnet.

### Deployed Contracts

| Contract | File | Description | Status |
|----------|------|-------------|--------|
| IYieldAdapter | `src/interfaces/IYieldAdapter.sol` | Adapter interface | Done |
| MorphoAdapter | `src/adapters/MorphoAdapter.sol` | Wraps Morpho ERC-4626 vaults | Done |
| AutoYieldModule | `src/AutoYieldModule.sol` | ERC-7579 executor module | Done |
| AutopilotFactory | `src/AutopilotFactory.sol` | Deploys Kernel wallets | Done |

### Test Commands

```bash
cd contracts

# Unit tests (17 pass)
forge test --match-contract AutoYieldModuleTest

# Fork tests against real Morpho (16 pass)
BASESCAN_API_KEY=dummy forge test --match-contract MorphoAdapterForkTest \
  --fork-url https://mainnet.base.org --fork-block-number 23000000

# Verify deployed contracts work
forge script script/TestDeployment.s.sol:TestDeployment \
  --rpc-url https://mainnet.base.org -vvv
```

---

## Bryce (Backend) - IN PROGRESS

Backend has yield indexing working. Next: wire up UserOp submission.

### Completed

- B1: Strategy indexer with live data from Morpho/Aave/Moonwell APIs
- B2: Recommendation engine with risk preferences
- B3: Scheduler framework (simulated execution)
- B4: Dust token metadata service

### Next Steps

1. **Add `/automation-key` endpoint** - Frontend needs this for wallet creation
2. **Implement real UserOp submission** in `bundler.ts` - Replace `[SIMULATED]` logs with actual bundler calls
3. **Update adapter addresses** in `src/config/adapterAddresses.ts`:

```typescript
// Real deployed adapter
export const ADAPTER_ADDRESSES = {
  morpho: {
    USDC: "0x33fD350a1ecE1239B880B3b3f91eb39407A7eDf9", // MorphoAdapter on Base
  }
};
```

### Environment Variables Needed

```env
# backend/.env
CDP_BUNDLER_URL=https://api.developer.coinbase.com/rpc/v1/base/YOUR_KEY
AUTOMATION_PRIVATE_KEY=0x...  # Generate with: npx ts-node scripts/generateSessionKey.ts
AUTOMATION_PUBLIC_ADDRESS=0x...

# Contract addresses
AUTO_YIELD_MODULE_ADDRESS=0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce
FACTORY_ADDRESS=0xc627874FE7444f8e9750e5043c19bA01E990D581
MORPHO_ADAPTER_ADDRESS=0x8438E34f258044cf656EBA796B8559bA1ee3020a
```

---

## Logan (Frontend) - Wallet Creation Flow

Build the connect wallet + create smart wallet flow.

### Key Files to Create/Update

1. **`lib/constants.ts`** - Contract addresses:
```typescript
export const CONTRACTS = {
  FACTORY: "0xc627874FE7444f8e9750e5043c19bA01E990D581",
  MODULE: "0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce",
  ADAPTER: "0x8438E34f258044cf656EBA796B8559bA1ee3020a",
  USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
} as const;
```

2. **Wallet creation component** - Call factory:
```typescript
// User connects EOA, then:
const salt = keccak256(toBytes(ownerAddress));
const tx = await writeContract({
  address: CONTRACTS.FACTORY,
  abi: FACTORY_ABI,
  functionName: "createAccount",
  args: [salt],  // Factory uses msg.sender as owner
});
```

3. **Factory ABI** (minimal):
```typescript
export const FACTORY_ABI = [
  {
    name: "createAccount",
    type: "function",
    inputs: [{ name: "salt", type: "bytes32" }],
    outputs: [{ name: "account", type: "address" }],
    stateMutability: "nonpayable",
  },
  {
    name: "getAddress",
    type: "function",
    inputs: [
      { name: "owner", type: "address" },
      { name: "salt", type: "bytes32" },
    ],
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
  },
] as const;
```

### User Flow

1. User lands on `/` - sees "Create Autopilot Wallet"
2. Clicks connect - Coinbase Wallet / MetaMask modal
3. After connecting, sees "Create Wallet" button
4. Clicks create - signs transaction
5. Wallet deployed - redirect to dashboard
6. User deposits USDC to their new smart wallet address

---

## Robby (Frontend) - State & UX

Build the React context and dashboard components.

### Key Files

1. **`contexts/AutopilotContext.tsx`** - Global wallet state
2. **`components/ui/toast.tsx`** - Transaction notifications
3. **Dashboard updates** - Display checking/yield balances

### Balance Reading

Once wallet exists, read balances:

```typescript
// Checking balance (USDC in wallet)
const checking = await publicClient.readContract({
  address: USDC_ADDRESS,
  abi: erc20Abi,
  functionName: "balanceOf",
  args: [walletAddress],
});

// Yield balance (USDC in Morpho via adapter)
const yieldBal = await publicClient.readContract({
  address: MODULE_ADDRESS,
  abi: MODULE_ABI,
  functionName: "getYieldBalance",
  args: [walletAddress, USDC_ADDRESS],
});
```

---

## External Addresses (Base Mainnet)

| Contract | Address |
|----------|---------|
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Morpho Vault (Moonwell USDC) | `0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca` |
| Kernel Factory v3.3 | `0x2577507b78c2008Ff367261CB6285d44ba5eF2E9` |
| ECDSA Validator | `0x845ADb2C711129d4f3966735eD98a9F09fC4cE57` |
| EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |

---

## Quick Start Commands

```bash
# Backend
cd backend
npm install
npm run dev  # Runs on :3001

# Frontend
cd frontend
npm install
npm run dev  # Runs on :3000

# Contracts (testing)
cd contracts
forge test
```
