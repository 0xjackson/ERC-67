# Smart Sweep Implementation Status

**Last Updated:** December 5, 2024
**Status:** ✅ COMPLETE - v6 Contracts Deployed, User-Signed Flow Implemented

---

## Executive Summary

We have implemented dust sweep functionality that swaps small token balances to USDC via Aerodrome and deposits them into yield. The **full ERC-4337 UserOp flow has been validated** with comprehensive tests against Base mainnet via fork testing. Frontend UI for displaying dust balances with **real-time USD values** (via CoinGecko) and triggering sweeps has been implemented.

**Confidence Level:** 9/10 for production readiness

**v6 contracts deployed and verified on Base mainnet.**

---

## 1. What's Been Implemented

### 1.1 Smart Contract Changes

#### AutoYieldModule.sol
| Change | Status | Description |
|--------|--------|-------------|
| `Route` struct | ✅ Added | Aerodrome-compatible swap route struct |
| `InvalidRouter` error | ✅ Added | Error for zero address router |
| `DustSwept` event | ✅ Added | Emits account, token, count, amount |
| `sweepDustAndCompound()` | ✅ Added | Main sweep function |

**Function Signature:**
```solidity
function sweepDustAndCompound(
    address router,           // Aerodrome router address
    address consolidationToken, // USDC
    address[] calldata dustTokens // Array of tokens to sweep
) external onlyAuthorized(msg.sender)
```

**What it does:**
1. Loops through `dustTokens` array
2. For each token with balance > 0:
   - Approves Aerodrome router
   - Builds Route struct (from, to, stable=false, factory=0x0)
   - Calls `swapExactTokensForTokens` on router
3. After all swaps, deposits surplus USDC to yield vault

#### AutopilotFactory.sol
| Change | Status | Description |
|--------|--------|-------------|
| `SELECTOR_SWEEP` | ✅ Added | `0x8fd059b6` |
| `DEFAULT_THRESHOLD` | ✅ Changed | `0` (was `1e6`) |
| `allowedSelectors` array | ✅ Updated | Now 3 selectors (rebalance, migrate, sweep) |

### 1.2 Backend Changes

#### bundler/constants.ts
| Change | Status |
|--------|--------|
| `AERODROME_ROUTER` address added | ✅ |
| `sweepDustAndCompound` ABI updated | ✅ |

#### bundler/submit.ts
| Change | Status |
|--------|--------|
| `submitSweepDustUserOp()` - automation key signed | ✅ |
| `prepareUserSweepOp()` - **user-signed flow (ECDSA)** | ✅ NEW |

#### server.ts
| Change | Status |
|--------|--------|
| `POST /ops/dust` endpoint added | ✅ |
| `POST /ops/prepare-sweep` - **user-signed sweep prep** | ✅ NEW |
| `GET /dust/summary` - real on-chain balances + USD | ✅ |

#### dustService.ts
| Change | Status |
|--------|--------|
| `fetchTokenBalances()` via multicall | ✅ |
| `fetchTokenPrices()` via CoinGecko API | ✅ NEW |
| `getDustSummary()` returns balances + USD values | ✅ |

#### scheduler.ts
| Change | Status |
|--------|--------|
| `sweepDust` case updated to pass dust tokens | ✅ |

### 1.3 Frontend Changes

| Change | Status |
|--------|--------|
| `DustBalances` component | ✅ Implemented |
| Dust token balance display | ✅ Implemented |
| **USD values per token** (via CoinGecko) | ✅ NEW |
| **Total dust value display** | ✅ NEW |
| "Sweep to USDC" button with USD value | ✅ Implemented |
| **User wallet signing** (not automation key) | ✅ NEW |
| `getDustSummary()` API function | ✅ Implemented |
| `prepareSweep()` API function | ✅ NEW |
| Dashboard integration | ✅ Implemented |

---

## 2. What's Been Validated

### 2.1 Fork Tests (ALL PASSING)

All tests run against real Base mainnet state via `--fork-url https://mainnet.base.org`

#### Original Module Tests
| Test | Result | What It Proves |
|------|--------|----------------|
| `test_fork_sweepDust_singleToken` | ✅ PASS | 1000 DEGEN → USDC → vault shares works |
| `test_fork_sweepDust_multipleTokens` | ✅ PASS | DEGEN + AERO → USDC works |
| `test_fork_sweepDust_depositsToYield` | ✅ PASS | Swept USDC goes to Morpho vault |
| `test_fork_sweepDust_skipsZeroBalance` | ✅ PASS | No revert on 0 balance tokens |

#### NEW: Full UserOp Simulation Tests (21 tests)
| Test | Result | What It Proves |
|------|--------|----------------|
| `test_userOp_01_validatorInstalled` | ✅ PASS | AutomationValidator properly installed |
| `test_userOp_02_sweepSelectorWhitelisted` | ✅ PASS | `0x8fd059b6` is whitelisted |
| `test_userOp_03_rebalanceSelectorWhitelisted` | ✅ PASS | `0x21c28191` is whitelisted |
| `test_userOp_04_migrateSelectorWhitelisted` | ✅ PASS | `0x6cb56d19` is whitelisted |
| `test_userOp_05_unknownSelectorNotWhitelisted` | ✅ PASS | Random selectors rejected |
| `test_userOp_06_callDataParsing_sweep` | ✅ PASS | Byte offsets 100:120 and 152:156 correct |
| `test_userOp_07_callDataParsing_rebalance` | ✅ PASS | CallData encoding verified |
| `test_userOp_08_validateUserOp_rebalance_succeeds` | ✅ PASS | Validator accepts valid rebalance |
| `test_userOp_09_validateUserOp_sweep_succeeds` | ✅ PASS | Validator accepts valid sweep |
| `test_userOp_10_validateUserOp_wrongSigner_fails` | ✅ PASS | Wrong key rejected |
| `test_userOp_11_validateUserOp_wrongTarget_fails` | ✅ PASS | Wrong target rejected |
| `test_userOp_12_validateUserOp_wrongSelector_fails` | ✅ PASS | Non-whitelisted selector rejected |
| `test_userOp_13_entryPoint_rebalance` | ✅ PASS | Full EntryPoint→Kernel→Module flow |
| `test_userOp_14_entryPoint_sweep_singleToken` | ✅ PASS | **Full sweep via EntryPoint works!** |
| `test_userOp_15_entryPoint_sweep_multipleTokens` | ✅ PASS | Multi-token sweep via EntryPoint |
| `test_userOp_16_entryPoint_migrate` | ✅ PASS | Migration via EntryPoint |
| `test_userOp_17_gasEstimate_rebalance` | ✅ PASS | ~634k gas |
| `test_userOp_18_gasEstimate_sweep_1token` | ✅ PASS | ~831k gas |
| `test_userOp_19_gasEstimate_sweep_3tokens` | ✅ PASS | ~1.17M gas |
| `test_userOp_20_sweep_emptyArray` | ✅ PASS | Empty array doesn't revert |
| `test_userOp_21_sweep_zeroBalanceTokens` | ✅ PASS | Zero balance tokens skipped |

### 2.2 What These Tests Prove

✅ **Selector calculation is correct** - `0x8fd059b6` verified via `cast sig`

✅ **CallData byte offsets are correct**
- Bytes 100-120: target address (module)
- Bytes 152-156: inner selector

✅ **Nonce key format for Kernel v3 secondary validators**
```solidity
uint192 nonceKey = uint192(
    (uint256(0x00) << 184) |     // mode
    (uint256(0x01) << 176) |     // type = VALIDATOR
    (uint256(uint160(validatorAddr)) << 16) |  // validator address
    uint256(0)                    // key
);
```

✅ **Full ERC-4337 flow works**
- EntryPoint.handleOps() → Kernel.validateUserOp() → AutomationValidator → Kernel.execute() → AutoYieldModule.sweepDustAndCompound()

✅ **Gas limits are sufficient**
| Operation | Gas Used | Configured Limit |
|-----------|----------|------------------|
| Rebalance | ~634k | 1.5M ✅ |
| 1-token sweep | ~831k | 1.5M ✅ |
| 3-token sweep | ~1.17M | 1.5M ✅ |

### 2.3 How to Run Tests

```bash
# Run all UserOp simulation tests
BASESCAN_API_KEY=dummy forge test --match-contract UserOpSimulationTest --fork-url https://mainnet.base.org -vv

# Run original fork tests
BASESCAN_API_KEY=dummy forge test --match-test "test_fork_sweepDust" --fork-url https://mainnet.base.org -vv
```

---

## 3. Architecture Clarification

### 3.1 Two Validators, Two Signing Paths

The Kernel wallet has **two validators installed**:

| Validator | Type | Signs With | Use Case |
|-----------|------|------------|----------|
| ECDSA Validator | Root (0x00) | User's EOA | User-initiated actions (sends, manual sweeps) |
| AutomationValidator | Secondary (0x01) | Automation key | Background automation (scheduled sweeps) |

### 3.2 Nonce Key Determines Validator

The nonce's upper bits encode which validator handles the UserOp:

```
Nonce Key Format (192 bits):
[mode: 8 bits][type: 8 bits][validator address: 160 bits][key: 16 bits]

Root validator:     0x00 + 0x00 + 0x00...00 + key
Secondary validator: 0x00 + 0x01 + validatorAddr + key
```

### 3.3 Sweep Can Use Either Validator

The sweep selector is whitelisted in AutomationValidator, but the user can also sign via ECDSA:

| Flow | Nonce Key | Signer | When to Use |
|------|-----------|--------|-------------|
| Automation | `0x0001{validatorAddr}0000` | Backend automation key | Scheduled background sweeps |
| User-signed | `0x0000{zeros}0000` | User's EOA wallet | Manual "Sweep" button in UI |

**✅ IMPLEMENTED:** Both flows are now available:
- `POST /ops/dust` - Automation key signed (for scheduled sweeps)
- `POST /ops/prepare-sweep` + `POST /ops/submit-signed` - User wallet signed (for UI button)

---

## 4. Frontend Implementation Details

### 4.1 New Files

#### `frontend/components/DustBalances.tsx`
- Displays list of dust token balances
- Shows token symbol, name, and formatted balance
- **Shows USD value per token** (e.g., "1,234 DEGEN" / "$0.15")
- **Shows total dust value** (e.g., "$2.47" in header)
- Indicates which tokens are "sweepable"
- "Sweep X tokens (~$Y.YY) to USDC" button with USD value
- **User signs with wallet** (uses `useSignMessage` hook)
- Multi-step status: Preparing → Sign in wallet → Submitting
- Auto-hides when no dust balances exist

#### `frontend/lib/api/client.ts` (updated)
- Added `DustSummaryResponse` type with `balanceUsd` and `totalDustValueUsd`
- Added `getDustSummary()` function
- Added `PrepareSweepParams` and `PrepareSweepResponse` types
- Added `prepareSweep()` function for user-signed flow
- Updated `SweepDustRequest` to include `dustTokens` array

### 4.2 Dashboard Integration

The `DustBalances` component is rendered between Strategy Info and Send sections:

```tsx
{/* Dust Balances Section */}
{smartWalletAddress && (
  <DustBalances
    key={dustRefreshKey}
    walletAddress={smartWalletAddress}
    onSweepComplete={() => {
      setDustRefreshKey((k) => k + 1);
      setToast({
        message: "Dust tokens swept to USDC and deposited to yield!",
        type: "success",
      });
    }}
  />
)}
```

### 4.3 Backend Balance Fetching

`GET /dust/summary?wallet=0x...` now returns **real on-chain balances** via multicall:

```typescript
// dustService.ts
async function fetchTokenBalances(wallet: string, tokens: DustTokenMeta[]): Promise<bigint[]> {
  const results = await publicClient.multicall({
    contracts: tokens.map((token) => ({
      address: token.tokenAddress as Address,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [wallet as Address],
    })),
    allowFailure: true,
  });
  // ...
}
```

---

## 5. Technical Details

### 5.1 Contract Addresses (v6 - CURRENT)

✅ **v6 contracts deployed and verified on Base mainnet:**

| Contract | Address | Notes |
|----------|---------|-------|
| AutopilotFactory | [`0x6fa5d5CA703e98213Fdd641061a0D739a79341F3`](https://basescan.org/address/0x6fa5d5CA703e98213Fdd641061a0D739a79341F3) | v6, sweep enabled |
| AutoYieldModule | [`0x2B1E677C05e2C525605264C81dC401AB9E069F6C`](https://basescan.org/address/0x2B1E677C05e2C525605264C81dC401AB9E069F6C) | v6, sweepDustAndCompound() |
| AutomationValidator | [`0x47A6b2f3bD564F9DeA17AcF8AbE73890c546900b`](https://basescan.org/address/0x47A6b2f3bD564F9DeA17AcF8AbE73890c546900b) | Reused from v3 |

**v5 Addresses (for rollback):**
| Contract | Address |
|----------|---------|
| AutopilotFactory | `0x7673F1EBF4eA4e4F2CCb9bf44dCdeF5a5Ba76B94` |
| AutoYieldModule | `0x598d23dC23095b128aBD4Dbab096d48f9e4b919B` |

### 5.2 Aerodrome Router

| Item | Value |
|------|-------|
| Router Address | `0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43` |
| Function | `swapExactTokensForTokens(uint256,uint256,Route[],address,uint256)` |
| Route Struct | `{address from, address to, bool stable, address factory}` |

### 5.3 Selector Values (VERIFIED)

| Function | Selector | Verified |
|----------|----------|----------|
| `rebalance(address)` | `0x21c28191` | ✅ |
| `migrateStrategy(address,address)` | `0x6cb56d19` | ✅ |
| `sweepDustAndCompound(address,address,address[])` | `0x8fd059b6` | ✅ |
| `execute(bytes32,bytes)` (Kernel) | `0xe9ae5c53` | ✅ |

### 5.4 Dust Token Addresses (Base Mainnet)

| Token | Address | Has USDC Pair? |
|-------|---------|----------------|
| DEGEN | `0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed` | ✅ Verified |
| AERO | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` | ✅ Verified |
| HIGHER | `0x0578d8A44db98B23BF096A382e016e29a5Ce0ffe` | ⚠️ Unverified |
| TOSHI | `0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4` | ⚠️ Unverified |
| BRETT | `0x532f27101965dd16442E59d40670FaF5eBB142E4` | ⚠️ Unverified |
| USDbC | `0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA` | ✅ Verified |

---

## 6. Deployment Checklist

### 6.1 Before Deployment

- [x] Write and pass validator selector test
- [x] Write and pass full UserOp simulation test
- [x] Verify gas limits are sufficient for multi-token sweeps
- [x] Verify DEGEN and AERO have Aerodrome liquidity

### 6.2 Deployment Steps

1. [x] Deploy new AutoYieldModule (v6 with sweep) ✅
2. [x] Deploy new AutopilotFactory (v6 with sweep selector) ✅
3. [x] Update `DEPLOYMENTS.md` with v6 addresses ✅
4. [x] Update backend `constants.ts` with new addresses ✅
5. [ ] Test with new wallet + small real funds

### 6.3 After Deployment

- [ ] Create test wallet via new factory
- [ ] Send small amounts of DEGEN/AERO to wallet
- [ ] Trigger sweep via dashboard UI
- [ ] Verify tokens swept and deposited to yield

---

## 7. Risk Assessment

### 7.1 What Could Go Wrong

| Scenario | Impact | Likelihood | Mitigation |
|----------|--------|------------|------------|
| Selector mismatch | Sweep calls rejected | ~~Medium~~ **Mitigated** | ✅ Validated in tests |
| Gas too low | UserOp fails | ~~Medium~~ **Mitigated** | ✅ Measured actual gas |
| No liquidity for token | Swap reverts, sweep fails | Low | Backend filters by known pairs |
| Aerodrome router upgrade | All swaps fail | Very Low | Monitor Aerodrome announcements |
| Slippage on large amounts | Less USDC received | Low | Backend only sweeps dust (<$1.10) |

### 7.2 Failure Modes

**If sweep fails:**
- Dust tokens remain in wallet (not lost)
- USDC balance unchanged
- User can retry later

**If partial sweep fails:**
- Some tokens swept, some remain
- No funds lost
- Emits DustSwept event with actual count

---

## 8. Open Questions (RESOLVED)

### 8.1 Should sweep be owner-only or automation-key accessible?

**RESOLVED:** Both are supported:
- **Automation key** via AutomationValidator (for scheduled background sweeps)
- **User's EOA** via ECDSA root validator (for manual UI sweeps)

### 8.2 What's the minimum sweep threshold?

- Proposed: Total dust value >= $3.00
- Per-token: < $1.10 to be considered dust
- Implementation: Backend gating via `dustThreshold` in token config

### 8.3 Which DEX router to hardcode?

**RESOLVED:** Passed as parameter for flexibility. Backend defaults to Aerodrome.

---

## 9. Files Modified

### Contracts
- `contracts/src/AutoYieldModule.sol` - Added sweep function
- `contracts/src/AutopilotFactory.sol` - Added selector, changed threshold
- `contracts/test/AutoYieldModule.fork.t.sol` - Added sweep tests
- `contracts/test/UserOpSimulation.t.sol` - **NEW: Full UserOp flow tests**
- `contracts/script/DeployV6.s.sol` - **NEW: v6 deployment script**

### Backend
- `backend/src/bundler/constants.ts` - Updated to v6 addresses, added router
- `backend/src/bundler/submit.ts` - Added `prepareUserSweepOp()` for user-signed flow
- `backend/src/server.ts` - Added POST /ops/dust, POST /ops/prepare-sweep, GET /dust/summary
- `backend/src/dustService.ts` - Added CoinGecko price fetching, USD values
- `backend/src/types.ts` - Updated DustBalance with balanceUsd field
- `backend/src/scheduler.ts` - Fixed sweepDust case

### Frontend
- `frontend/components/DustBalances.tsx` - **NEW: Dust balance display with USD values**
- `frontend/app/dashboard/page.tsx` - Added DustBalances integration
- `frontend/lib/api/client.ts` - Added getDustSummary, prepareSweep, USD types

### Documentation
- `docs/FEATURE-SMART-SWEEPS.md` - Feature PRD
- `docs/SWEEP-IMPLEMENTATION-STATUS.md` - This file
- `contracts/DEPLOYMENTS.md` - Updated with v6 addresses

---

## 10. Next Steps (Priority Order)

1. **~~Write validator selector test~~** ✅ DONE
2. **~~Write full UserOp simulation test~~** ✅ DONE
3. **~~Add user-signed sweep flow~~** ✅ DONE - Uses ECDSA validator like sends
4. **~~Deploy v6 contracts~~** ✅ DONE - Deployed and verified on Base mainnet
5. **~~Add USD values to UI~~** ✅ DONE - CoinGecko integration
6. **Test with real wallet** - Create wallet via v6 factory, send dust tokens, test sweep

---

## 11. Test Output

### UserOp Simulation Tests (21/21 passing)

```
Ran 21 tests for test/UserOpSimulation.t.sol:UserOpSimulationTest
[PASS] test_userOp_01_validatorInstalled() (gas: 19129)
[PASS] test_userOp_02_sweepSelectorWhitelisted() (gas: 15696)
[PASS] test_userOp_03_rebalanceSelectorWhitelisted() (gas: 15740)
[PASS] test_userOp_04_migrateSelectorWhitelisted() (gas: 15738)
[PASS] test_userOp_05_unknownSelectorNotWhitelisted() (gas: 15760)
[PASS] test_userOp_06_callDataParsing_sweep() (gas: 9035)
[PASS] test_userOp_07_callDataParsing_rebalance() (gas: 8432)
[PASS] test_userOp_08_validateUserOp_rebalance_succeeds() (gas: 45928)
[PASS] test_userOp_09_validateUserOp_sweep_succeeds() (gas: 46536)
[PASS] test_userOp_10_validateUserOp_wrongSigner_fails() (gas: 45815)
[PASS] test_userOp_11_validateUserOp_wrongTarget_fails() (gas: 33111)
[PASS] test_userOp_12_validateUserOp_wrongSelector_fails() (gas: 35307)
[PASS] test_userOp_13_entryPoint_rebalance() (gas: 614283)
[PASS] test_userOp_14_entryPoint_sweep_singleToken() (gas: 1148775)
[PASS] test_userOp_15_entryPoint_sweep_multipleTokens() (gas: 1398538)
[PASS] test_userOp_16_entryPoint_migrate() (gas: 1380510)
[PASS] test_userOp_17_gasEstimate_rebalance() (gas: 605481)
[PASS] test_userOp_18_gasEstimate_sweep_1token() (gas: 900522)
[PASS] test_userOp_19_gasEstimate_sweep_3tokens() (gas: 1434377)
[PASS] test_userOp_20_sweep_emptyArray() (gas: 606331)
[PASS] test_userOp_21_sweep_zeroBalanceTokens() (gas: 612510)
Suite result: ok. 21 passed; 0 failed; 0 skipped
```

### Gas Measurements

```
Gas used for rebalance: 633,674
Gas used for 1-token sweep: 831,430
Gas used for 3-token sweep: 1,167,288
```

### Original Fork Tests (4/4 passing)

```
Ran 4 tests for test/AutoYieldModule.fork.t.sol:AutoYieldModuleForkTest
[PASS] test_fork_sweepDust_depositsToYield() (gas: 940193)
[PASS] test_fork_sweepDust_multipleTokens() (gas: 1039036)
[PASS] test_fork_sweepDust_singleToken() (gas: 781213)
[PASS] test_fork_sweepDust_skipsZeroBalance() (gas: 489676)
Suite result: ok. 4 passed; 0 failed; 0 skipped
```
