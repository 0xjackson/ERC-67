# Autopilot Wallet - Engineering Tickets

---

## STATUS OVERVIEW

### Contracts - COMPLETE

All contract tickets are done. Deployed to Base mainnet.

| Ticket | Description | Status |
|--------|-------------|--------|
| C1 | Automation key + adapter whitelist | DONE |
| C2 | Core logic (executeWithAutoYield, rebalance) | DONE |
| C3 | migrateStrategy function | DONE |
| C4 | flushToChecking function | DONE |
| C5 | sweepDustAndCompound (stub) | DONE |
| C6 | onInstall enhancement | DONE |
| C7 | MorphoAdapter (real adapter) | DONE |

### Backend - IN PROGRESS

| Ticket | Description | Status |
|--------|-------------|--------|
| B1 | Strategy indexer | DONE |
| B2 | Recommendation engine | DONE |
| B3 | Scheduler framework | DONE (simulated) |
| B4 | Dust token service | DONE |
| B5 | Real UserOp submission | TODO |
| B6 | Wallet registry | TODO |

### Frontend - TODO

| Ticket | Description | Status |
|--------|-------------|--------|
| F1 | Landing + onboarding | TODO |
| F2 | Wire real contracts | TODO |
| F3 | Delete merchant page | TODO |
| F4 | Send page | TODO |
| F5 | Settings page | TODO |
| F6 | Transaction history | TODO |
| F7 | Dashboard yield display | TODO |

---

## NEXT PRIORITY: Frontend Wallet Creation

The contracts are deployed. The critical path is now:

1. **Frontend: Connect wallet flow** - Let users connect Coinbase Wallet / MetaMask
2. **Frontend: Create wallet flow** - Call `factory.createAccount(salt)`
3. **Frontend: Dashboard** - Show wallet address, balances
4. **Backend: UserOp submission** - Replace `[SIMULATED]` with real bundler calls

---

## Deployed Contract Addresses

| Contract | Address |
|----------|---------|
| AutoYieldModule | `0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce` |
| MorphoAdapter | `0x8438E34f258044cf656EBA796B8559bA1ee3020a` |
| AutopilotFactory | `0xc627874FE7444f8e9750e5043c19bA01E990D581` |
| Automation Key | `0xD78F5099987389e33bD6Ec15FF3Ca4dBedD507f3` |

---

## BACKEND TICKETS (Remaining)

### B5: Implement Real UserOp Submission

**Problem**
Scheduler logs `[SIMULATED]` instead of submitting real userOps.

**Blocked By:** Nothing - contracts are deployed

**Deliverables**
- `bundler.ts` with real userOp building and submission
- Integration with CDP Bundler/Paymaster
- Replace simulation in scheduler with real calls

**Steps**
1. Set up CDP Bundler endpoint
2. Implement `submitRebalanceUserOp()` using ZeroDev SDK
3. Update scheduler to call real bundler

---

### B6: Add Wallet Registry

**Problem**
No persistent storage for registered wallets.

**Deliverables**
- Database schema for wallets
- `POST /register` endpoint
- `GET /wallet/:address` endpoint

---

## FRONTEND TICKETS

### F1: Landing Page + Connect Wallet

**Problem**
No way for users to connect their EOA wallet.

**Deliverables**
- Landing page at `/` with "Get Started" button
- Connect wallet modal (Coinbase Wallet, MetaMask)
- Store connected address

**Implementation**
Use wagmi + OnchainKit:
```typescript
import { ConnectButton } from "@rainbow-me/rainbowkit";
// or
import { ConnectWallet } from "@coinbase/onchainkit/wallet";
```

---

### F2: Create Wallet Flow

**Problem**
Users can't create their Autopilot smart wallet.

**Deliverables**
- "Create Wallet" button after connecting
- Call `factory.createAccount(salt)`
- Show new wallet address
- Redirect to dashboard

**Implementation**
```typescript
const salt = keccak256(toBytes(ownerAddress));
const { writeContract } = useWriteContract();

// Create wallet
writeContract({
  address: "0xc627874FE7444f8e9750e5043c19bA01E990D581",
  abi: FACTORY_ABI,
  functionName: "createAccount",
  args: [salt],
});
```

---

### F3: Delete Merchant Page

**Problem**
Merchant page doesn't fit the product.

**Deliverables**
- Delete `app/merchant/` directory
- Remove nav links to it

---

### F4: Build Send Page

**Problem**
No way to send USDC from the wallet.

**Deliverables**
- `/send` page with recipient + amount inputs
- Preview showing if withdrawal from yield is needed
- Execute via `executeWithAutoYield()`

---

### F5: Build Settings Page

**Problem**
No way to configure thresholds.

**Deliverables**
- Checking threshold slider
- Auto-yield toggle
- Current vault display

---

### F6: Transaction History

**Problem**
No transaction history page.

**Deliverables**
- `/history` page
- List of past transactions
- Links to BaseScan

---

### F7: Dashboard Yield Display

**Problem**
Dashboard doesn't show yield information.

**Deliverables**
- Current vault name + APY
- Yield earned estimate
- Checking vs yield balance split

---

## Factory ABI Reference

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

---

## Module ABI Reference (Key Functions)

```typescript
export const MODULE_ABI = [
  {
    name: "rebalance",
    type: "function",
    inputs: [{ name: "token", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    name: "executeWithAutoYield",
    type: "function",
    inputs: [
      { name: "token", type: "address" },
      { name: "to", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
    outputs: [{ name: "", type: "bytes" }],
    stateMutability: "nonpayable",
  },
  {
    name: "getCheckingBalance",
    type: "function",
    inputs: [
      { name: "account", type: "address" },
      { name: "token", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    name: "getYieldBalance",
    type: "function",
    inputs: [
      { name: "account", type: "address" },
      { name: "token", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
] as const;
```
