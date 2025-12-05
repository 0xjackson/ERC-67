# Feature PRD: Smart Dust Sweeps

**Feature Name:** Smart Dust Sweeps
**Status:** Proposed
**Author:** Autopilot Team
**Created:** December 5, 2024
**Target:** Hackathon MVP

---

## 1. Executive Summary

### 1.1 What Is This Feature?

Smart Dust Sweeps automatically consolidates small "dust" token balances (airdrops, leftover swaps, meme tokens) into USDC and deposits the consolidated amount into yield. This happens via a single gasless UserOperation signed by the automation key.

### 1.2 Why Does It Matter?

- Users accumulate dust tokens worth $0.50-$10 that are individually too small to manage
- Manual swapping costs more in gas than the tokens are worth
- Dust sits idle instead of earning yield
- Autopilot should handle ALL idle capital, not just USDC deposits

### 1.3 User Experience

**Before:** User has 0.3 DEGEN, 2.1 AERO, 0.05 BRETT scattered in wallet. Worth ~$8 total. Does nothing.

**After:** Backend detects dust → builds sweep UserOp → swaps all dust to USDC → deposits to yield. User sees: "Swept 3 tokens → $8.23 USDC → now earning 8.2% APY"

---

## 2. Current System State

### 2.1 What's Already Built

| Component | Location | Status |
|-----------|----------|--------|
| Dust token registry | `backend/src/dustConfig.ts` | Complete |
| Dust service API | `backend/src/dustService.ts` | Complete (mock balances) |
| Scheduler sweep support | `backend/src/scheduler.ts` | Complete |
| UserOp submission | `backend/src/bundler/submit.ts` | Complete |
| Settings UI | `frontend/components/SettingsForm.tsx` | Complete |
| API client | `frontend/lib/api/client.ts` | Complete |

### 2.2 What's Missing

| Component | Location | Gap |
|-----------|----------|-----|
| **Contract function** | `contracts/src/AutoYieldModule.sol` | `sweepDustAndCompound()` does not exist |
| **Selector whitelist** | `contracts/src/AutopilotFactory.sol` | Sweep selector not in `allowedSelectors` |
| Backend endpoint | `backend/src/server.ts` | `POST /ops/dust` not implemented |
| Real balance reading | `backend/src/dustService.ts` | Uses mock data, needs multicall |
| Frontend trigger | `frontend/app/dashboard/page.tsx` | No "Clean Up Wallet" button |

### 2.3 Deployed Contracts (Base Mainnet)

| Contract | Address | Relevance |
|----------|---------|-----------|
| AutoYieldModule | `0x71b5A4663A49FF02BE672Ea9560256D2268727B7` | Needs new function |
| AutomationValidator | `0x47A6b2f3bD564F9DeA17AcF8AbE73890c546900b` | Validates sweep selector |
| AutopilotFactory | `0xFBb91eb4234558b191c393985eF34282B551e81B` | Needs selector update |
| MorphoAdapter | `0x42EFecD83447e5b90c5F706309FaC8f9615bd68F` | Receives consolidated USDC |

---

## 3. Technical Architecture

### 3.1 End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SMART SWEEP FLOW                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. TRIGGER                                                                  │
│     ─────────                                                                │
│     • Manual: User clicks "Clean Up Wallet" on dashboard                    │
│     • Auto: Scheduler detects dust above threshold                          │
│                                                                              │
│  2. BACKEND BUILDS USEROP                                                   │
│     ────────────────────────                                                │
│     POST /ops/dust { wallet: "0x...", consolidationToken: "USDC" }          │
│           │                                                                  │
│           ▼                                                                  │
│     submitSweepDustUserOp(walletAddress)                                    │
│           │                                                                  │
│           ▼                                                                  │
│     encodeFunctionData({ functionName: "sweepDustAndCompound" })            │
│           │                                                                  │
│           ▼                                                                  │
│     Sign with AUTOMATION_PRIVATE_KEY                                        │
│           │                                                                  │
│           ▼                                                                  │
│     Request gas sponsorship from Paymaster                                  │
│           │                                                                  │
│           ▼                                                                  │
│     Submit to CDP Bundler                                                   │
│                                                                              │
│  3. ON-CHAIN EXECUTION (inside AutoYieldModule)                             │
│     ────────────────────────────────────────────                            │
│     sweepDustAndCompound() {                                                │
│       for each dustToken in config:                                         │
│         balance = IERC20(dustToken).balanceOf(account)                      │
│         if (balance > 0 && valueUsd >= minSweepValue):                      │
│           │                                                                  │
│           │  ┌─────────────────────────────────────┐                        │
│           └─▶│ IKernel(account).execute(           │                        │
│              │   dustToken,                         │                        │
│              │   0,                                 │                        │
│              │   approve(dexRouter, balance)       │                        │
│              │ )                                    │                        │
│              └─────────────────────────────────────┘                        │
│           │                                                                  │
│           │  ┌─────────────────────────────────────┐                        │
│           └─▶│ IKernel(account).execute(           │                        │
│              │   dexRouter,                         │                        │
│              │   0,                                 │                        │
│              │   swap(dustToken → USDC)            │                        │
│              └─────────────────────────────────────┘                        │
│                                                                              │
│       // After all swaps complete:                                          │
│       usdcBalance = IERC20(usdc).balanceOf(account)                        │
│       surplus = usdcBalance - checkingThreshold                            │
│       if (surplus > 0):                                                     │
│         _depositToYield(account, adapter, usdc, surplus)                   │
│     }                                                                        │
│                                                                              │
│  4. RESULT                                                                   │
│     ────────                                                                │
│     • Dust tokens → 0 balance                                               │
│     • USDC checking balance maintained                                      │
│     • Surplus USDC now in yield vault                                       │
│     • User notified: "Swept $X.XX into yield"                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Contract Changes

#### 3.2.1 New Storage in AutoYieldModule

```solidity
// Dust sweep configuration per account
struct DustConfig {
    address dexRouter;           // Aerodrome/Uniswap router
    address consolidationToken;  // USDC address
    address[] trackedTokens;     // Dust tokens to sweep
    uint256 minSweepValueUsd;    // Min value to trigger sweep (6 decimals, e.g., 1000000 = $1)
}

mapping(address account => DustConfig) public dustConfig;
```

#### 3.2.2 New Function: `sweepDustAndCompound()`

```solidity
/**
 * @notice Sweep dust tokens to consolidation token and deposit to yield
 * @dev Can only be called by account or automation key
 */
function sweepDustAndCompound() external onlyAuthorized(msg.sender) {
    address account = msg.sender;
    if (!isInitialized[account]) revert NotInitialized();

    DustConfig storage config = dustConfig[account];
    if (config.dexRouter == address(0)) revert DustConfigNotSet();

    address consolidationToken = config.consolidationToken;
    address adapter = currentAdapter[account][consolidationToken];

    // Swap each dust token to consolidation token
    for (uint256 i = 0; i < config.trackedTokens.length; i++) {
        address dustToken = config.trackedTokens[i];
        uint256 balance = IERC20(dustToken).balanceOf(account);

        if (balance > 0) {
            _swapToConsolidation(account, dustToken, balance, config);
        }
    }

    // Deposit surplus to yield
    uint256 threshold = checkingThreshold[account][consolidationToken];
    uint256 checking = IERC20(consolidationToken).balanceOf(account);

    if (checking > threshold && adapter != address(0)) {
        uint256 surplus = checking - threshold;
        _depositToYield(account, adapter, consolidationToken, surplus);
        emit Deposited(account, consolidationToken, surplus);
    }

    emit DustSwept(account, config.trackedTokens.length);
}

/**
 * @notice Configure dust sweep settings
 * @param config The dust configuration
 */
function setDustConfig(DustConfig calldata config) external onlyAccount(msg.sender) {
    dustConfig[msg.sender] = config;
    emit DustConfigUpdated(msg.sender, config.consolidationToken, config.trackedTokens.length);
}
```

#### 3.2.3 Internal Swap Helper

```solidity
function _swapToConsolidation(
    address account,
    address tokenIn,
    uint256 amountIn,
    DustConfig storage config
) internal {
    // Approve router
    bytes memory approveData = abi.encodeCall(IERC20.approve, (config.dexRouter, amountIn));
    IKernel(account).execute(tokenIn, 0, approveData);

    // Build swap calldata (Aerodrome/Uniswap V2 style)
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = config.consolidationToken;

    bytes memory swapData = abi.encodeWithSignature(
        "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
        amountIn,
        0, // Accept any amount (slippage handled by min sweep value)
        path,
        account,
        block.timestamp + 300
    );

    IKernel(account).execute(config.dexRouter, 0, swapData);
}
```

#### 3.2.4 Factory Update for New Selector

```solidity
// In AutopilotFactory.sol - _buildInitData()
bytes4 private constant SELECTOR_SWEEP = 0x...; // sweepDustAndCompound()

bytes4[] memory allowedSelectors = new bytes4[](3);  // Was 2
allowedSelectors[0] = SELECTOR_REBALANCE;
allowedSelectors[1] = SELECTOR_MIGRATE;
allowedSelectors[2] = SELECTOR_SWEEP;  // NEW
```

### 3.3 Backend Changes

#### 3.3.1 New Endpoint: `POST /ops/dust`

```typescript
// In server.ts
app.post("/ops/dust", async (req: Request, res: Response) => {
  const { wallet, chainId, consolidationToken } = req.body;

  // Validate wallet
  if (!isValidWalletAddress(wallet)) {
    return res.status(400).json({ error: "Invalid wallet address" });
  }

  // Check wallet is registered
  if (!walletRegistry.has(wallet.toLowerCase())) {
    return res.status(404).json({ error: "Wallet not registered" });
  }

  try {
    const userOpHash = await submitSweepDustUserOp(wallet as Address);

    return res.json({
      success: true,
      userOpHash,
      message: "Dust sweep submitted",
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: error instanceof Error ? error.message : "Sweep failed",
    });
  }
});
```

#### 3.3.2 Real Balance Reading (Replace Mock)

```typescript
// In dustService.ts - replace getDustSummary()
import { createPublicClient, http, erc20Abi } from "viem";
import { base } from "viem/chains";

const client = createPublicClient({
  chain: base,
  transport: http(process.env.BASE_RPC_URL),
});

export async function getDustSummary(
  wallet: string,
  chainId: number,
  consolidationSymbol?: string
): Promise<DustSummaryResponse> {
  const dustSources = getDustSources(chainId);

  // Multicall to get all balances at once
  const balanceCalls = dustSources.map((token) => ({
    address: token.tokenAddress as Address,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [wallet as Address],
  }));

  const results = await client.multicall({ contracts: balanceCalls });

  const dustBalances: DustBalance[] = dustSources
    .map((token, i) => ({
      token,
      balance: (results[i].result as bigint)?.toString() || "0",
      balanceUsd: 0, // TODO: Price oracle integration
      isDust: true,
    }))
    .filter((b) => b.balance !== "0");

  return {
    wallet,
    chainId,
    consolidationToken: consolidationSymbol || "USDC",
    dustBalances,
    totalDustValueUsd: dustBalances.reduce((sum, b) => sum + (b.balanceUsd || 0), 0),
  };
}
```

### 3.4 Frontend Changes

#### 3.4.1 Dashboard "Clean Up Wallet" Button

```tsx
// In dashboard/page.tsx
const [dustSummary, setDustSummary] = useState<DustSummaryResponse | null>(null);
const [isSweeping, setIsSweeping] = useState(false);

// Fetch dust summary on load
useEffect(() => {
  if (walletAddress) {
    api.getDustSummary(walletAddress).then(setDustSummary);
  }
}, [walletAddress]);

const handleSweep = async () => {
  setIsSweeping(true);
  try {
    const result = await api.sweepDust({ wallet: walletAddress });
    toast.success(`Swept dust tokens! TX: ${result.txHash}`);
    // Refresh balances
  } catch (error) {
    toast.error("Sweep failed");
  } finally {
    setIsSweeping(false);
  }
};

// In JSX
{dustSummary && dustSummary.dustBalances.length > 0 && (
  <Card>
    <CardHeader>
      <CardTitle>Dust Tokens</CardTitle>
      <CardDescription>
        {dustSummary.dustBalances.length} tokens worth ~${dustSummary.totalDustValueUsd.toFixed(2)}
      </CardDescription>
    </CardHeader>
    <CardContent>
      <Button onClick={handleSweep} disabled={isSweeping}>
        {isSweeping ? "Sweeping..." : "Clean Up Wallet"}
      </Button>
    </CardContent>
  </Card>
)}
```

---

## 4. Dust Classification & Sweep Thresholds

### 4.1 What Is Dust?

**Dust** = a token balance worth **less than the dust threshold** (default: $1.10)

This prevents sweeping tokens the user intentionally holds (e.g., $150 of AERO).

### 4.2 Threshold Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `dustThresholdUsd` | **$1.10** | Token is dust if value < this |
| `minTotalSweepUsd` | **$3.00** | Only sweep if total dust value >= this |

### 4.3 Example Scenario (Demo-Friendly)

User has these token balances:

| Token | Balance | USD Value | Is Dust? (< $1.10) |
|-------|---------|-----------|-------------------|
| DEGEN | 50 | $0.80 | Yes |
| AERO | 2 | $0.90 | Yes |
| HIGHER | 100 | $1.00 | Yes |
| BRETT | 500 | $150.00 | **No** (intentional holding) |

**Dust tokens:** DEGEN, AERO, HIGHER
**Total dust value:** $2.70
**Sweep triggers?** No - under $3.00 minimum

*User receives another airdrop:*

| Token | Balance | USD Value | Is Dust? |
|-------|---------|-----------|----------|
| TOSHI | 200 | $0.50 | Yes |

**New total dust value:** $3.20
**Sweep triggers?** **Yes** - exceeds $3.00 minimum

**Result:** DEGEN, AERO, HIGHER, TOSHI all swept to USDC → deposited to yield. BRETT untouched.

### 4.4 Where Price Data Comes From

| Layer | Responsibility |
|-------|----------------|
| **Backend** | Fetches token prices (CoinGecko/DeFiLlama), caches them |
| **Backend** | Classifies each token as dust or not |
| **Backend** | Calculates total dust value |
| **Backend** | Decides whether to trigger sweep |
| **Contract** | Trusts backend decision, executes swap for provided tokens |

No on-chain price oracle needed - keeps contract simple for hackathon.

### 4.5 Backend Gating Logic

```typescript
interface DustSettings {
  dustThresholdUsd: number;    // Default: 1.10
  minTotalSweepUsd: number;    // Default: 3.00
}

function getDustTokensToSweep(
  balances: TokenBalance[],
  settings: DustSettings
): TokenBalance[] {
  // 1. Filter to only dust (value < threshold)
  const dustTokens = balances.filter(t => t.valueUsd < settings.dustThresholdUsd);

  // 2. Calculate total dust value
  const totalDustValue = dustTokens.reduce((sum, t) => sum + t.valueUsd, 0);

  // 3. Only return tokens if total >= minimum
  if (totalDustValue < settings.minTotalSweepUsd) {
    return []; // Don't sweep - not worth it
  }

  return dustTokens;
}
```

---

## 5. Risk Analysis & Concerns

### 5.1 Critical Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **DEX swap fails mid-execution** | High | Wrap each swap in try/catch, continue with remaining tokens. Failed swaps stay as dust. |
| **Slippage on low-liquidity tokens** | Medium | Accept 0 minOut (any amount). Only sweep tokens with known DEX pairs. |
| **Gas cost exceeds dust value** | Medium | Backend estimates gas before submitting. Skip if `gasCost > dustValue * 0.5`. |
| **New function not whitelisted** | High | **Existing wallets cannot use sweep until owner whitelists selector.** |

### 5.2 Existing Wallet Upgrade Path

**Problem:** The `AutomationValidator` only allows selectors that were whitelisted at wallet creation. Existing wallets have:
- `rebalance(address)` - whitelisted
- `migrateStrategy(address,address)` - whitelisted
- `sweepDustAndCompound()` - **NOT whitelisted**

**Solutions:**

| Option | Effort | UX Impact |
|--------|--------|-----------|
| **A. Owner whitelist tx** | Low | User signs one tx to enable sweep |
| **B. New factory only** | None | Only new wallets get sweep |
| **C. Proxy upgrade** | High | Out of scope for hackathon |

**Recommendation for hackathon:** Option B (new wallets only) with Option A available for demos.

### 5.3 What Could Break?

| Scenario | Impact | Likelihood |
|----------|--------|------------|
| Sweep runs during pending tx | UserOp fails (nonce collision) | Low - bundler handles |
| DEX router gets exploited | User funds at risk during swap | Very Low - use audited routers |
| Gas price spikes mid-sweep | UserOp fails, dust remains | Low - paymaster handles |
| Consolidation token depegs | Swapped to depegged token | Very Low - only use USDC |

### 5.4 Security Considerations

1. **Automation key cannot steal funds** - It can only call `sweepDustAndCompound()`, which swaps TO the wallet's USDC and deposits to yield. No external transfers.

2. **DEX router is hardcoded per-account** - User sets it once via `setDustConfig()`. Backend cannot change it.

3. **Tracked tokens are user-controlled** - Only tokens in `dustConfig.trackedTokens` are swept. Backend cannot add arbitrary tokens.

---

## 6. Hackathon Scope

### 6.1 MVP (Must Have)

| Item | Component | Lines of Code |
|------|-----------|---------------|
| `sweepDustAndCompound()` | Contract | ~60 |
| `setDustConfig()` | Contract | ~10 |
| `_swapToConsolidation()` | Contract | ~30 |
| Update factory selectors | Contract | ~5 |
| `POST /ops/dust` endpoint | Backend | ~30 |
| "Clean Up Wallet" button | Frontend | ~40 |

**Total:** ~175 lines of code

### 6.2 Nice to Have (If Time Permits)

| Item | Component | Effort |
|------|-----------|--------|
| Real balance reading (multicall) | Backend | ~50 LOC |
| Price oracle for USD values | Backend | ~100 LOC |
| Auto-sweep scheduler task | Backend | ~30 LOC |
| Sweep confirmation modal | Frontend | ~60 LOC |
| Sweep history display | Frontend | ~80 LOC |

### 6.3 Out of Scope

- Multi-hop swaps (token → ETH → USDC)
- Cross-DEX routing for best price
- Automatic dust token discovery
- Existing wallet upgrade mechanism

---

## 7. Implementation Plan

### Phase 1: Contract (Highest Priority)

1. Add `DustConfig` struct and storage to `AutoYieldModule.sol`
2. Implement `setDustConfig()`
3. Implement `_swapToConsolidation()` helper
4. Implement `sweepDustAndCompound()`
5. Add `SELECTOR_SWEEP` to `AutopilotFactory.sol`
6. Write tests
7. Deploy new contracts to Base

### Phase 2: Backend

1. Add `POST /ops/dust` endpoint to `server.ts`
2. (Optional) Replace mock balances with multicall

### Phase 3: Frontend

1. Add dust summary fetch to dashboard
2. Add "Clean Up Wallet" card/button
3. Wire up API call

### Phase 4: Testing

1. Create test wallet with dust tokens
2. Configure dust settings via contract call
3. Trigger sweep from dashboard
4. Verify USDC lands in yield

---

## 8. Contract Interface Summary

### New Functions

```solidity
// Configuration (owner only)
function setDustConfig(DustConfig calldata config) external;

// Execution (owner or automation key)
function sweepDustAndCompound() external;

// View
function getDustConfig(address account) external view returns (DustConfig memory);
```

### New Events

```solidity
event DustConfigUpdated(address indexed account, address consolidationToken, uint256 tokenCount);
event DustSwept(address indexed account, uint256 tokenCount);
```

### New Errors

```solidity
error DustConfigNotSet();
error SwapFailed(address token);
```

---

## 9. Testing Checklist

### Unit Tests (Foundry)

- [ ] `setDustConfig` stores config correctly
- [ ] `setDustConfig` reverts for non-owner
- [ ] `sweepDustAndCompound` reverts if not initialized
- [ ] `sweepDustAndCompound` reverts if config not set
- [ ] `sweepDustAndCompound` swaps single token correctly
- [ ] `sweepDustAndCompound` handles multiple tokens
- [ ] `sweepDustAndCompound` deposits surplus to yield
- [ ] `sweepDustAndCompound` works with automation key

### Integration Tests (Fork)

- [ ] Full sweep flow with real Aerodrome router
- [ ] Sweep with Morpho adapter deposit
- [ ] Gas estimation accuracy

### E2E Tests (Manual)

- [ ] Frontend button triggers sweep
- [ ] UserOp confirmed on Base
- [ ] Balances update correctly

---

## 10. Open Questions / Decisions Needed

### 10.1 Who Can Trigger Sweeps?

| Option | Access | Use Case |
|--------|--------|----------|
| **A) Owner only** | `onlyAccount(msg.sender)` | Manual "Clean Up Wallet" button only |
| **B) Owner + Automation** | `onlyAuthorized(msg.sender)` | Manual button + backend auto-sweep |

**Trade-offs:**
- Option A is simpler, user always in control
- Option B enables "set and forget" automation

**Decision needed:** Which approach for hackathon?

### 10.2 DEX Router

| Option | Pros | Cons |
|--------|------|------|
| **Aerodrome** | Native Base DEX, best liquidity for Base meme tokens | Less universal |
| **Uniswap V3** | Universal, well-audited | May lack pairs for Base-native tokens |

**Recommendation:** Aerodrome for MVP (better DEGEN/AERO/BRETT liquidity)

### 10.3 Resolved Decisions

| Question | Decision |
|----------|----------|
| Dust threshold | < $1.10 per token |
| Min total sweep | >= $3.00 combined |
| Price data source | Backend (CoinGecko/DeFiLlama cache) |
| On-chain oracle | Not needed for hackathon |

---

## 11. Appendix

### A. Dust Token Registry (Base Mainnet)

| Token | Address | Notes |
|-------|---------|-------|
| DEGEN | `0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed` | Airdrop token |
| AERO | `0x940181a94A35A4569E4529A3CDfB74e38FD98631` | Aerodrome governance |
| HIGHER | `0x0578d8A44db98B23BF096A382e016e29a5Ce0ffe` | Meme token |
| TOSHI | `0xAC1Bd2486aAf3B5C0fc3Fd868558b082a531B2B4` | Base meme coin |
| BRETT | `0x532f27101965dd16442E59d40670FaF5eBB142E4` | Meme coin |
| USDbC | `0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA` | Old bridged USDC |

### B. Selector Calculation

```solidity
bytes4 SELECTOR_SWEEP = bytes4(keccak256("sweepDustAndCompound()"));
// = 0x...
```

### C. Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| Single token swap | ~150,000 |
| Yield deposit | ~100,000 |
| Full sweep (3 tokens) | ~600,000 |

With Base gas at ~0.001 gwei, cost is negligible (<$0.01).
