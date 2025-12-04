# Autopilot Wallet - Outstanding Tasks

Last Updated: December 4, 2024

---

## Status Overview

| Area | Status |
|------|--------|
| **Contracts** | v2 Deployed on Base Mainnet |
| **Backend** | B1-B6 Complete, Railway env vars configured |
| **Frontend** | UI Built, Needs Contract Wiring |

---

## Deployed Contracts (v2)

| Contract | Address |
|----------|---------|
| AutopilotFactory | `0xcf10279BAA0d5407Dbb637517d23055A55E72923` |
| AutoYieldModule | `0x71b5A4663A49FF02BE672Ea9560256D2268727B7` |
| AutomationValidator | `0xe29ed376a2780f653C14EEC203eD25094c0E772A` |
| MorphoAdapter | `0x42EFecD83447e5b90c5F706309FaC8f9615bd68F` |
| Automation Key | `0xD78F5099987389e33bD6Ec15FF3Ca4dBedD507f3` |

---

## Outstanding Tasks

### 1. Frontend: Wire Dashboard to Real Balances
**Priority:** High
**Status:** TODO
**Files:** `frontend/app/dashboard/page.tsx`, `frontend/lib/services/`

**Current State:**
- Shows hardcoded mock data from `lib/mock-data.ts`

**Implementation:**
```typescript
// Read checking balance (USDC in wallet)
const checking = await publicClient.readContract({
  address: CONTRACTS.USDC,
  abi: erc20Abi,
  functionName: "balanceOf",
  args: [walletAddress],
});

// Read yield balance via adapter
const adapter = await publicClient.readContract({
  address: CONTRACTS.MODULE,
  abi: MODULE_ABI,
  functionName: "currentAdapter",
  args: [walletAddress, CONTRACTS.USDC],
});

const yieldBalance = await publicClient.readContract({
  address: adapter,
  abi: ADAPTER_ABI,
  functionName: "totalValue",
  args: [],
});
```

---

### 2. Frontend: Wire Send Page to Contract
**Priority:** High
**Status:** TODO
**File:** `frontend/app/send/page.tsx`

**Current State:**
- 100% simulated with 90% success rate mock

**Implementation:**
- Build userOp calling `executeWithAutoYield(token, to, amount, data)`
- Submit via bundler (can use same pattern as backend B5)
- Show real transaction hash and link to BaseScan

---

### 3. Frontend: Wire Settings Page to Contract
**Priority:** Medium
**Status:** TODO
**File:** `frontend/app/settings/page.tsx`

**Current State:**
- UI exists but no contract writes

**Implementation:**
- `setCheckingThreshold(token, threshold)` - Update checking buffer
- `setAdapterAllowed(adapter, bool)` - Allowlist adapters
- `setAutomationKey(address)` - Change/revoke automation key

---

### 4. Backend: Real Dust Balance Reading
**Priority:** Low
**Status:** TODO
**File:** `backend/src/dustService.ts`

**Current State:**
- `getDustSummary()` returns hardcoded mock balances

**Implementation:**
- Use viem to read ERC20 balances for tracked dust tokens
- Return real on-chain balances

---

### 5. E2E Flow Test
**Priority:** Medium (After wiring complete)
**Status:** TODO

**Test Flow:**
1. Create wallet via factory
2. Deposit USDC to smart wallet address
3. Verify auto-rebalance moves excess to yield
4. Send USDC (triggers auto-withdraw from yield)
5. Verify final balances correct

---

## Completed Tasks

- [x] Contract deployment (v2 with AutomationValidator)
- [x] Factory initialization fix (Kernel v3 module install format)
- [x] Backend strategy indexer (B1)
- [x] Backend recommendation engine (B2)
- [x] Backend scheduler framework (B3)
- [x] Backend dust token service (B4)
- [x] Backend real UserOp submission via CDP bundler (B5)
- [x] Backend connect cron to wallet registry with on-chain balance checks (B6)
- [x] Railway backend deployment
- [x] Railway env vars configured (CDP_BUNDLER_URL, AUTOMATION_PRIVATE_KEY, AUTO_YIELD_MODULE_ADDRESS, BASE_RPC_URL)
- [x] Wallet registry setup
- [x] Frontend UI (landing, dashboard, send, settings pages)
- [x] Frontend: Update contract addresses to v2

---

## Critical Path

```
[1] Dashboard balances ──→ [2] Send wiring ──→ [5] E2E test
```

Backend is complete. Frontend wiring is the remaining blocker.
