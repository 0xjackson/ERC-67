# Autopilot Contract Deployments

## Base Mainnet (Chain ID: 8453)

Last Updated: December 3, 2024

### Core Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **AutoYieldModule** | [`0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce`](https://basescan.org/address/0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce) | ERC-7579 executor module - the brain of auto-yield logic |
| **MorphoAdapter** | [`0x8438E34f258044cf656EBA796B8559bA1ee3020a`](https://basescan.org/address/0x8438E34f258044cf656EBA796B8559bA1ee3020a) | Adapter for Moonwell Flagship USDC vault |
| **AutopilotFactory** | [`0xc627874FE7444f8e9750e5043c19bA01E990D581`](https://basescan.org/address/0xc627874FE7444f8e9750e5043c19bA01E990D581) | Factory for deploying Autopilot smart wallets |

### Configuration

- **Default Checking Threshold:** 100 USDC (keeps $100 liquid, rest goes to yield)
- **Automation Key:** `0xD78F5099987389e33bD6Ec15FF3Ca4dBedD507f3` (backend session signer)

### External Dependencies

| Contract | Address | Description |
|----------|---------|-------------|
| USDC | [`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`](https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) | Native USDC on Base |
| Morpho Vault | [`0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca`](https://basescan.org/address/0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca) | Moonwell Flagship USDC MetaMorpho vault |
| Kernel Factory | [`0x2577507b78c2008Ff367261CB6285d44ba5eF2E9`](https://basescan.org/address/0x2577507b78c2008Ff367261CB6285d44ba5eF2E9) | ZeroDev Kernel v3.3 Factory |
| ECDSA Validator | [`0x845ADb2C711129d4f3966735eD98a9F09fC4cE57`](https://basescan.org/address/0x845ADb2C711129d4f3966735eD98a9F09fC4cE57) | ZeroDev ECDSA Validator |

---

## Quick Copy-Paste

```typescript
// Frontend/Backend constants
export const CONTRACTS = {
  FACTORY: "0xc627874FE7444f8e9750e5043c19bA01E990D581",
  MODULE: "0xC35Eeb30a36d1ac157B41719BEAf513a0C557Bce",
  ADAPTER: "0x8438E34f258044cf656EBA796B8559bA1ee3020a",
  USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
} as const;

// Automation key (for backend .env)
AUTOMATION_PUBLIC_ADDRESS=0xD78F5099987389e33bD6Ec15FF3Ca4dBedD507f3
```

---

## Testing

```bash
cd contracts

# Verify deployed contracts work
forge script script/TestDeployment.s.sol:TestDeployment \
  --rpc-url https://mainnet.base.org -vvv

# Unit tests
forge test --match-contract AutoYieldModuleTest

# Fork tests against real Morpho
BASESCAN_API_KEY=dummy forge test --match-contract MorphoAdapterForkTest \
  --fork-url https://mainnet.base.org --fork-block-number 23000000
```
