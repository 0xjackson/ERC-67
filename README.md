# Autopilot Wallet

**An ERC-4337 Smart Wallet with Autonomous Yield Optimization**

Autopilot Wallet is a self-custodial smart wallet deployed live on Base mainnet that automatically manages idle capital. Users interact with it like a normal wallet—send, receive, pay—but behind the scenes, idle USDC seamlessly earns the best available APY from Morpho Blue vaults, withdraws automatically when spending, and compounds dust tokens—all without user intervention.

> "Your money works while you sleep. One click to spend. Zero gas. True autopilot."

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Smart Contracts](#smart-contracts)
- [Backend Scheduler](#backend-scheduler)
- [Frontend Application](#frontend-application)
- [Technical Deep Dive](#technical-deep-dive)
- [Security Model](#security-model)
- [Deployment](#deployment)
- [Getting Started](#getting-started)
- [Demo Flow](#demo-flow)

---

## Overview

### The Problem

Traditional DeFi UX is broken:

1. **Manual yield management** — Users must constantly monitor APYs, manually deposit into vaults, and withdraw when spending
2. **Yield vs. liquidity tradeoff** — Funds in yield can't be spent instantly; users choose between earning or having liquid funds
3. **Dust accumulation** — Random airdrops and swap leftovers sit idle, too small to manage
4. **Gas friction** — Every interaction requires ETH and signatures

### Our Solution

Autopilot Wallet eliminates all of this:

- **Automatic yield** — Idle USDC earns the best available APY from Morpho Blue vaults on Base
- **Optional liquidity** — Users can configure a liquid balance if needed, but by default everything earns yield
- **Invisible withdrawals** — When you spend, the wallet auto-unstakes to cover the transaction
- **Background optimization** — A scheduler continuously migrates funds to better-yielding vaults
- **Dust consolidation** — Sweep random tokens into USDC and compound into yield
- **Gasless UX** — All transactions sponsored via paymaster; users never need ETH

**User's mental model:** "I deposited money. It earns yield. I can spend anytime. I never think about it again."

---

## Key Features

| Feature | Description |
|---------|-------------|
| **Auto-Yield Deposits** | USDC automatically deposited to highest-APY Morpho Blue vault on Base |
| **Seamless Spending** | `executeWithAutoYield()` auto-withdraws from yield when spending |
| **Dynamic Vault Selection** | Backend queries Morpho GraphQL API to find the best vault |
| **Automated Rebalancing** | Scheduler migrates funds to better vaults when APY improves |
| **Dust Sweep & Compound** | Swap DEGEN, AERO, BRETT, etc. to USDC via Aerodrome, deposit to yield |
| **Gasless Transactions** | All UserOps sponsored via Pimlico paymaster |
| **Session Key Automation** | Backend signs rebalance operations without user interaction |
| **ERC-4337 + ERC-7579** | Modern account abstraction with modular plugin architecture |
| **Live on Base Mainnet** | All contracts deployed and verified on Base mainnet |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           AUTOPILOT WALLET SYSTEM                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────┐                    ┌────────────────────────────────┐ │
│   │   Frontend (Next.js) │                   │   Backend Scheduler (Node.js)  │ │
│   │                      │                   │                                │ │
│   │  • Wallet Creation   │                   │  ┌─────────────────────────┐   │ │
│   │  • Dashboard/Balance │                   │  │   Yield Aggregator      │   │ │
│   │  • Send/Pay Flow     │                   │  │   • Morpho GraphQL      │   │ │
│   │  • Dust Sweep UI     │                   │  │   • Aave GraphQL        │   │ │
│   │  • Settings Config   │                   │  │   • Moonwell SDK        │   │ │
│   └──────────┬───────────┘                   │  └───────────┬─────────────┘   │ │
│              │                               │              │                  │ │
│              │ User signs                    │  ┌───────────▼─────────────┐   │ │
│              │ with EOA                      │  │   Smart Scheduler       │   │ │
│              │                               │  │   • Wallet monitoring   │   │ │
│              │                               │  │   • Rebalance triggers  │   │ │
│              │                               │  │   • Migration decisions │   │ │
│              │                               │  └───────────┬─────────────┘   │ │
│              │                               │              │                  │ │
│              │                               │  ┌───────────▼─────────────┐   │ │
│              │                               │  │   UserOp Submitter      │   │ │
│              │                               │  │   • Signs w/ session key│   │ │
│              │                               │  │   • Submits to bundler  │   │ │
│              │                               │  └───────────┬─────────────┘   │ │
│              │                               └──────────────┼────────────────┘ │
│              │                                              │                   │
│              │ (ECDSA Validator)                            │ (Automation      │
│              │                                              │  Validator)      │
│              ▼                                              ▼                   │
│   ┌─────────────────────────────────────────────────────────────────────────┐  │
│   │                              Base Network                                │  │
│   │                                                                          │  │
│   │   ┌─────────────┐    ┌─────────────┐    ┌────────────────────────────┐  │  │
│   │   │   Pimlico   │───▶│  EntryPoint │───▶│      Kernel Account        │  │  │
│   │   │   Bundler   │    │   (4337)    │    │    (User's Smart Wallet)   │  │  │
│   │   └─────────────┘    └─────────────┘    │                            │  │  │
│   │                                         │  ┌────────────────────────┐│  │  │
│   │   ┌─────────────┐                       │  │   ECDSA Validator      ││  │  │
│   │   │  Paymaster  │── sponsors gas ──────▶│  │   (Owner signatures)   ││  │  │
│   │   │  (Pimlico)  │                       │  ├────────────────────────┤│  │  │
│   │   └─────────────┘                       │  │  Automation Validator  ││  │  │
│   │                                         │  │   (Session key sigs)   ││  │  │
│   │                                         │  ├────────────────────────┤│  │  │
│   │                                         │  │   AutoYieldModule      ││  │  │
│   │                                         │  │   (Yield automation)   ││  │  │
│   │                                         │  └────────────────────────┘│  │  │
│   │                                         └─────────────┬──────────────┘  │  │
│   │                                                       │                  │  │
│   │                                         ┌─────────────▼──────────────┐  │  │
│   │                                         │   Morpho Blue Vaults       │  │  │
│   │                                         │      (ERC-4626)            │  │  │
│   │                                         │  ┌─────────────────────┐   │  │  │
│   │                                         │  │  Morpho USDC Vaults │   │  │  │
│   │                                         │  │  (Best APY on Base) │   │  │  │
│   │                                         │  └─────────────────────┘   │  │  │
│   │                                         └────────────────────────────┘  │  │
│   └─────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Smart Contracts

### Contract Overview

| Contract | Address | Purpose |
|----------|---------|---------|
| **AutopilotFactory** | `0x6fa5d...F3` | Deploys Kernel smart wallets with modules pre-installed |
| **AutoYieldModule** | `0x2B1E6...6C` | ERC-7579 executor handling all yield automation logic |
| **AutomationValidator** | `0x47A6b...0b` | ERC-7579 validator for session key authentication |

### AutoYieldModule (ERC-7579 Executor)

The core brain of the system. Handles automatic yield deposits, withdrawals, and rebalancing.

```solidity
// Key Functions

// User-facing: Execute a transfer with automatic yield management
function executeWithAutoYield(
    address token,     // Token being spent (e.g., USDC)
    address to,        // Target contract to call
    uint256 value,     // ETH value (0 for ERC20)
    bytes calldata data // Calldata (e.g., ERC20.transfer)
) external;

// Automation: Move surplus checking balance to yield
function rebalance(address token) external;

// Automation: Migrate funds to a new, better-yielding vault
function migrateStrategy(address token, address newVault) external;

// Automation/User: Swap dust tokens to USDC and compound
function sweepDustAndCompound(
    address router,           // Aerodrome router
    address consolidationToken, // USDC
    address[] calldata dustTokens // [DEGEN, AERO, BRETT, ...]
) external;

// Config: Optionally set a liquid balance to keep (default: 0, all goes to yield)
function setCheckingThreshold(address token, uint256 threshold) external;
```

**executeWithAutoYield Flow:**

```
1. User wants to send 150 USDC (all 500 USDC currently in yield vault)
2. Module calculates: need 150 USDC for transfer
3. Withdraws 150 from Morpho vault
4. Executes USDC.transfer(recipient, 150)
5. Remaining 350 USDC stays in vault earning yield

All steps happen atomically in ONE transaction!
```

### AutomationValidator (ERC-7579 Validator)

Validates UserOperations signed by the automation session key. Only permits specific function calls:

```solidity
// Whitelisted selectors:
bytes4 SELECTOR_REBALANCE = 0x21c28191;   // rebalance(address)
bytes4 SELECTOR_MIGRATE   = 0x6cb56d19;   // migrateStrategy(address,address)
bytes4 SELECTOR_SWEEP     = 0x8fd059b6;   // sweepDustAndCompound(...)

// Cannot call:
// - transfer() / transferFrom()
// - executeWithAutoYield() (owner only)
// - setCheckingThreshold() (owner only)
// - Any external addresses
```

### AutopilotFactory

Deploys new Kernel accounts with both modules pre-installed in a single transaction:

```solidity
function createAccount(bytes32 salt) external returns (address account) {
    // 1. Build init data with:
    //    - ECDSA Validator (root) for owner signatures
    //    - AutoYieldModule (executor) for yield logic
    //    - AutomationValidator for backend session key
    // 2. Deploy via KernelFactory.createAccount()
    // 3. Register in accountOf mapping
}
```

---

## Backend Scheduler

### Overview

A Node.js service that continuously monitors registered wallets and triggers yield optimization operations automatically.

**Location:** `backend/src/scheduler.ts`

### Core Components

#### Yield Aggregator (`yieldAggregator.ts`)

Fetches real-time APY data from Morpho Blue's GraphQL API:

```typescript
// Data Source: Morpho Blue API
// https://blue-api.morpho.org/graphql

interface Vault {
  name: string;        // "Moonwell Flagship USDC"
  address: string;     // Vault contract address
  apy: number;         // 0.0583 = 5.83%
  tvlUsd: number;      // Total value locked
}

// Returns Morpho vaults sorted by APY, filtered by TVL
async function getBestVaults(options): Promise<VaultFetchResult>
```

#### Smart Scheduler (`scheduler.ts`)

Monitors wallets and triggers operations:

```typescript
// Intervals:
const TICK_INTERVAL_MS = 30_000;        // Check task queue
const REGISTRY_CHECK_MS = 10_000;       // Check wallet balances

// Scheduler Loop:
1. Read all registered wallets from registry
2. Batch-read on-chain state via multicall:
   - checkingBalance = USDC.balanceOf(wallet)
   - threshold = module.checkingThreshold(wallet, USDC)
   - yieldBalance = vault.convertToAssets(vault.balanceOf(wallet))
   - currentVault = module.currentVault(wallet, USDC)

3. For each wallet:
   - If surplus > 0 && no vault → migrateStrategy (first deposit)
   - If surplus > 0 && has vault → rebalance
   - If currentVault != bestVault → migrateStrategy (migration)

4. Build and submit UserOperations signed by session key
```

#### UserOp Submission (`bundler/submit.ts`)

Builds ERC-4337 UserOperations and submits to Pimlico bundler:

```typescript
async function submitAutomationUserOp(wallet, moduleCallData) {
  // 1. Get nonce from EntryPoint (using AutomationValidator)
  // 2. Build UserOperation
  // 3. Request sponsorship from paymaster
  // 4. Sign with AUTOMATION_PRIVATE_KEY
  // 5. Submit to Pimlico bundler
  // 6. Wait for confirmation
}
```

### API Endpoints

```
GET  /strategies/:token     → List available yield strategies
GET  /recommend            → Get best strategy based on preferences
GET  /wallet/:address/summary → Dashboard data (balances, APY, vault)
POST /register             → Register wallet for automation
POST /ops/prepare-send     → Build send UserOp for user signing
POST /ops/prepare-sweep    → Build sweep UserOp for user signing
POST /ops/submit-signed    → Submit user-signed UserOp
GET  /scheduler/status     → Current scheduler state
GET  /dust/summary/:wallet → Dust token balances
```

---

## Frontend Application

### Stack

- **Framework:** Next.js 14 (App Router)
- **Web3:** Wagmi + viem + Coinbase OnchainKit
- **Wallet Flows:** OnchainKit components for seamless wallet connection and transactions
- **Styling:** Tailwind CSS

### Key Pages

| Page | Path | Function |
|------|------|----------|
| Landing | `/` | Hero, features, "Get Started" CTA |
| Create Wallet | `/create` | Deploy smart wallet via factory |
| Dashboard | `/dashboard` | View balances, send, sweep dust |
| Settings | `/settings` | Configure preferences |

### User Flows

**Wallet Creation:**
```
1. Connect EOA (Coinbase Wallet)
2. Click "Create Autopilot Wallet"
3. Frontend calls factory.createAccount(salt)
4. User signs one transaction
5. Smart wallet deployed with modules
6. Wallet registered with backend scheduler
```

**Send/Pay Flow:**
```
1. Enter recipient + amount on dashboard
2. Frontend calls POST /ops/prepare-send
3. Backend builds UserOp with:
   - executeWithAutoYield(USDC, USDC, 0, transfer(recipient, amount))
   - Paymaster sponsorship
4. Frontend prompts wallet signature
5. User signs message (UserOp hash)
6. Frontend calls POST /ops/submit-signed
7. Transaction confirmed - funds sent!
```

**Dust Sweep:**
```
1. Dashboard shows dust balances (DEGEN: $0.50, AERO: $0.30, ...)
2. Click "Clean Up Wallet"
3. Frontend builds sweepDustAndCompound UserOp
4. User signs once
5. All dust → USDC → Yield vault
```

---

## Technical Deep Dive

### Dual-Validator Architecture

The wallet uses two validators for different authentication modes:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DUAL-KEY VALIDATION                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                ECDSA VALIDATOR (Root)                        │    │
│  │                                                              │    │
│  │  Signer: User's EOA (MetaMask/Coinbase Wallet)              │    │
│  │  Permissions: FULL ACCESS                                    │    │
│  │  • executeWithAutoYield() - spend with auto-unstake          │    │
│  │  • setCheckingThreshold() - configure settings               │    │
│  │  • flushToChecking() - emergency withdraw                    │    │
│  │  • Any other operation                                       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              AUTOMATION VALIDATOR (Session Key)              │    │
│  │                                                              │    │
│  │  Signer: Backend service key                                 │    │
│  │  Permissions: RESTRICTED (3 functions only)                  │    │
│  │  ✓ rebalance(token) - deposit surplus to yield               │    │
│  │  ✓ migrateStrategy(token, vault) - move to better vault      │    │
│  │  ✓ sweepDustAndCompound(...) - consolidate dust              │    │
│  │                                                              │    │
│  │  CANNOT:                                                     │    │
│  │  ✗ transfer() - cannot send funds out                        │    │
│  │  ✗ executeWithAutoYield() - cannot initiate spends           │    │
│  │  ✗ setCheckingThreshold() - cannot change config             │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### ERC-4337 UserOperation Flow

```
User Action: "Send 150 USDC to 0x1234..."
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. BUILD USEROPERATION                                          │
│                                                                  │
│  sender: 0xSmartWallet...                                       │
│  nonce: (from EntryPoint, keyed by validator)                   │
│  callData: Kernel.execute(mode, [                               │
│      target: AutoYieldModule,                                   │
│      value: 0,                                                  │
│      data: executeWithAutoYield(USDC, USDC, 0, transfer(...))   │
│  ])                                                             │
│  signature: (user will sign)                                    │
│  paymaster: 0xPimlicoPaymaster...                               │
│  paymasterData: (Pimlico sponsorship signature)                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. GET PAYMASTER SPONSORSHIP                                    │
│                                                                  │
│  pm_getPaymasterStubData → gas limits                           │
│  pm_getPaymasterData → Pimlico signature                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. USER SIGNS USEROP HASH                                       │
│                                                                  │
│  hash = keccak256(packUserOp || entryPoint || chainId)          │
│  signature = wallet.signMessage(hash)                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. SUBMIT TO BUNDLER                                            │
│                                                                  │
│  eth_sendUserOperation(userOp, entryPoint)                      │
│  → Bundler validates, bundles with other ops                    │
│  → Submits to Base network                                      │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. ON-CHAIN EXECUTION                                           │
│                                                                  │
│  EntryPoint.handleOps([userOp])                                 │
│    → Kernel.validateUserOp() via ECDSA Validator                │
│    → Kernel.execute() → AutoYieldModule.executeWithAutoYield()  │
│        → Check balance, withdraw from vault if needed           │
│        → Execute USDC.transfer(recipient, amount)               │
│        → Deposit surplus back to vault                          │
│    → Paymaster pays gas                                         │
└─────────────────────────────────────────────────────────────────┘
```

### Module-to-Kernel Communication

The AutoYieldModule uses Kernel's `executeFromExecutor()` to callback:

```solidity
function _executeOnKernel(
    address account,
    address target,
    uint256 value,
    bytes memory data
) internal {
    // Pack execution data: target (20 bytes) + value (32 bytes) + data
    bytes memory executionCalldata = abi.encodePacked(target, value, data);

    // Use executeFromExecutor, NOT execute()
    // This bypasses root validator re-validation
    IKernel(account).executeFromExecutor(EXEC_MODE_DEFAULT, executionCalldata);
}
```

---

## Security Model

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 1: Key Separation                                         │
│  └─ Automation key CANNOT transfer funds to external addresses   │
│     Only owner key can initiate actual transfers                 │
│                                                                  │
│  Layer 2: Function Whitelisting                                  │
│  └─ AutomationValidator only allows 3 function selectors:        │
│     rebalance, migrateStrategy, sweepDustAndCompound             │
│                                                                  │
│  Layer 3: Vault Allowlist                                        │
│  └─ migrateStrategy can only move funds to allowedVaults         │
│     New vaults auto-added, but cannot withdraw to EOAs           │
│                                                                  │
│  Layer 4: Configurable Liquidity                                 │
│  └─ Users can optionally keep a liquid balance                   │
│     By default, all idle funds go to yield                       │
│                                                                  │
│  Layer 5: User Override                                          │
│  └─ Owner can revoke automation key anytime                      │
│     Owner can flushToChecking() to exit all yield                │
│                                                                  │
│  Layer 6: Non-Upgradeable                                        │
│  └─ Module code cannot be changed after deployment               │
│     No admin keys, no proxy upgrades                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### What If Session Key Is Compromised?

```
Scenario: Hacker steals backend's session key

Hacker tries: Call USDC.transfer(hackerAddress, balance)
  → AutomationValidator: "transfer() selector not allowed"
  → Transaction REVERTS — hacker gets nothing

Hacker tries: Call executeWithAutoYield(..., transfer(hacker, ...))
  → AutomationValidator: "executeWithAutoYield selector not allowed"
  → Transaction REVERTS — hacker gets nothing

What hacker CAN do: Call rebalance(USDC)
  → Funds move from checking to allowed vault
  → User's funds are SAFE — just earning yield

What hacker CAN do: Call migrateStrategy(USDC, differentVault)
  → Funds move from one Morpho vault to another
  → User's funds are SAFE — still in legitimate protocol
```

---

## Deployment

All contracts are deployed and verified on **Base Mainnet**.

### Current Contracts (Base Mainnet)

| Contract | Address | Basescan |
|----------|---------|----------|
| AutopilotFactory | `0x6fa5d5CA703e98213Fdd641061a0D739a79341F3` | [View](https://basescan.org/address/0x6fa5d5CA703e98213Fdd641061a0D739a79341F3) |
| AutoYieldModule | `0x2B1E677C05e2C525605264C81dC401AB9E069F6C` | [View](https://basescan.org/address/0x2B1E677C05e2C525605264C81dC401AB9E069F6C) |
| AutomationValidator | `0x47A6b2f3bD564F9DeA17AcF8AbE73890c546900b` | [View](https://basescan.org/address/0x47A6b2f3bD564F9DeA17AcF8AbE73890c546900b) |

### External Dependencies

| Contract | Address | Description |
|----------|---------|-------------|
| Kernel Factory | `0x2577507b78c2008Ff367261CB6285d44ba5eF2E9` | ZeroDev Kernel v3.3 |
| ECDSA Validator | `0x845ADb2C711129d4f3966735eD98a9F09fC4cE57` | ZeroDev root validator |
| EntryPoint | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | ERC-4337 v0.7 |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | Native USDC on Base |
| Aerodrome Router | `0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43` | For dust swaps |

---

## Getting Started

### Prerequisites

- Node.js 18+
- Foundry (for contracts)
- Pimlico API key
- Base RPC URL

### Backend

```bash
cd backend
cp .env.example .env
# Configure:
#   PIMLICO_API_KEY=...
#   AUTOMATION_PRIVATE_KEY=0x...
#   BASE_RPC_URL=https://mainnet.base.org

npm install
npm run dev  # Starts on port 3001
```

### Frontend

```bash
cd frontend
cp .env.example .env.local
# Configure:
#   NEXT_PUBLIC_API_URL=http://localhost:3001
#   NEXT_PUBLIC_ONCHAINKIT_API_KEY=...

npm install
npm run dev  # Starts on port 3000
```

### Contracts

```bash
cd contracts
forge build
forge test

# Deploy (requires PRIVATE_KEY in env)
forge script script/DeployV6.s.sol --rpc-url $BASE_RPC_URL --broadcast
```

---

## Demo Flow

### Scene 1: Create Wallet (30s)
1. Landing page → "Get Started"
2. Connect Coinbase Wallet
3. Click "Create Autopilot Wallet"
4. Sign one transaction
5. New smart wallet deployed!

### Scene 2: Fund & Auto-Yield (30s)
1. Send 500 USDC to smart wallet
2. Dashboard shows: 500 USDC
3. Backend scheduler detects idle balance
4. Auto-deposits 500 USDC to best Morpho vault
5. Dashboard now shows: 500 USDC earning ~5-6% APY
6. **"Zero clicks. Zero signatures. It just happened."**

### Scene 3: Spend with Auto-Unstake (45s)
1. Enter: "Send 150 USDC to 0x..."
2. Click "Send"
3. Sign one message
4. Behind the scenes:
   - Module withdraws 150 from Morpho vault
   - Sends 150 to recipient
   - Remaining balance continues earning yield
5. Dashboard: 350 USDC still earning yield
6. **"One signature. Auto-unstake + send. Invisible."**

### Scene 4: Background Optimization (30s)
1. (Simulate: Different Morpho vault now offers better APY)
2. Scheduler detects the improvement
3. Auto-migrates to better vault
4. Dashboard updates with new APY
5. **"User did nothing. Money moved to better yield."**

### Scene 5: Dust Sweep (30s)
1. Receive random airdrops: DEGEN, AERO, BRETT
2. Dashboard shows dust balances
3. Click "Clean Up Wallet"
4. Sign once
5. All dust → USDC → Yield vault
6. **"Trash tokens earning yield. One click."**

---

## Tech Stack Summary

| Layer | Technology |
|-------|------------|
| Smart Account | ZeroDev Kernel v3 (ERC-4337) |
| Module Standard | ERC-7579 (Rhinestone) |
| Network | Base Mainnet (Chain ID: 8453) |
| Bundler | Pimlico* |
| Paymaster | Pimlico* |
| Yield Source | Morpho Blue MetaMorpho Vaults (ERC-4626) |
| Dust Swaps | Aerodrome Router (Base native DEX) |
| Backend | Node.js + Express + viem |
| Frontend | Next.js 14 + Wagmi + Coinbase OnchainKit |
| Yield Data | Morpho Blue GraphQL API |

*\*Note: We use Pimlico for bundler and paymaster because Coinbase's paymaster and bundler do not yet support EntryPoint v0.7, which is required by Kernel v3.*

---

## Repository Structure

```
├── contracts/                 # Foundry smart contracts
│   ├── src/
│   │   ├── AutoYieldModule.sol      # ERC-7579 executor (yield logic)
│   │   ├── AutomationValidator.sol  # ERC-7579 validator (session keys)
│   │   ├── AutopilotFactory.sol     # Account deployment factory
│   │   └── interfaces/              # IKernel, IERC7579Module
│   ├── test/                        # Foundry tests
│   └── script/                      # Deployment scripts
│
├── backend/                   # Node.js scheduler service
│   ├── src/
│   │   ├── scheduler.ts            # Auto-rebalance cron
│   │   ├── server.ts               # Express API
│   │   ├── yieldAggregator.ts      # Morpho/Aave/Moonwell fetcher
│   │   ├── chainReader.ts          # On-chain state via multicall
│   │   └── bundler/                # UserOp building & submission
│
├── frontend/                  # Next.js application
│   ├── app/                        # App Router pages
│   ├── components/                 # React components
│   └── lib/                        # API client, constants
│
├── hackathon-prd.md          # Full product requirements
├── CLAUDE.md                 # Development guidelines
└── README.md                 # This file
```

---

## License

MIT

---

**Built for the Based India Hackathon 2024**

Deployed live on Base Mainnet. Enabling users to interact with the best APY from Morpho Blue vaults completely seamlessly.
