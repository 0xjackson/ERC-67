/**
 * B4: Dust Token Metadata Service
 *
 * Service layer for managing dust token metadata and configuration.
 * Provides functions to query dust tokens, get consolidation config,
 * and read wallet balances via multicall.
 */

import {
  DustTokenMeta,
  DustConfig,
  DustBalance,
  DustSummaryResponse,
} from "./types";
import {
  dustTokens,
  DEFAULT_CONSOLIDATION_TOKEN,
  DEFAULT_CONSOLIDATION_ADDRESS,
} from "./dustConfig";
import { CHAIN_IDS } from "./strategies";
import { createPublicClient, http, erc20Abi, formatUnits, type Address } from "viem";
import { base } from "viem/chains";

// ============================================================================
// Constants
// ============================================================================

/** Default chain ID for dust operations */
export const DEFAULT_DUST_CHAIN_ID = CHAIN_IDS.BASE_MAINNET;

/** CoinGecko API base URL (free tier, no API key required) */
const COINGECKO_API_URL = "https://api.coingecko.com/api/v3";

/** Map token addresses to CoinGecko IDs (Base mainnet) */
const TOKEN_TO_COINGECKO_ID: Record<string, string> = {
  "0x4ed4e862860bed51a9570b96d89af5e1b0efefed": "degen-base", // DEGEN
  "0x940181a94a35a4569e4529a3cdfb74e38fd98631": "aerodrome-finance", // AERO
  "0x0578d8a44db98b23bf096a382e016e29a5ce0ffe": "higher", // HIGHER
  "0xac1bd2486aaf3b5c0fc3fd868558b082a531b2b4": "toshi", // TOSHI
  "0x532f27101965dd16442e59d40670faf5ebb142e4": "brett", // BRETT
  "0xd9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca": "bridged-usd-coin-base", // USDbC
};

/** Price cache to avoid hitting rate limits */
interface PriceCache {
  prices: Record<string, number>;
  timestamp: number;
}

let priceCache: PriceCache | null = null;
const CACHE_TTL_MS = 60_000; // 1 minute cache

// ============================================================================
// Query Functions
// ============================================================================

/**
 * Get all dust tokens for a specific chain
 *
 * @param chainId - Chain ID to filter by
 * @returns Array of dust token metadata
 */
export function getDustTokens(chainId: number): DustTokenMeta[] {
  return dustTokens.filter((t) => t.chainId === chainId);
}

/**
 * Get only tokens marked as dust sources for a chain
 *
 * @param chainId - Chain ID to filter by
 * @returns Array of dust source tokens
 */
export function getDustSources(chainId: number): DustTokenMeta[] {
  return dustTokens.filter((t) => t.chainId === chainId && t.isDustSource);
}

/**
 * Get tokens that can be used as consolidation targets
 *
 * @param chainId - Chain ID to filter by
 * @returns Array of consolidation target tokens
 */
export function getConsolidationTargets(chainId: number): DustTokenMeta[] {
  return dustTokens.filter((t) => t.chainId === chainId && t.isConsolidationTarget);
}

/**
 * Get a specific token by address
 *
 * @param chainId - Chain ID
 * @param tokenAddress - Token contract address
 * @returns Token metadata or undefined
 */
export function getTokenByAddress(
  chainId: number,
  tokenAddress: string
): DustTokenMeta | undefined {
  const normalizedAddress = tokenAddress.toLowerCase();
  return dustTokens.find(
    (t) =>
      t.chainId === chainId &&
      t.tokenAddress.toLowerCase() === normalizedAddress
  );
}

/**
 * Get a specific token by symbol
 *
 * @param chainId - Chain ID
 * @param symbol - Token symbol (case-insensitive)
 * @returns Token metadata or undefined
 */
export function getTokenBySymbol(
  chainId: number,
  symbol: string
): DustTokenMeta | undefined {
  const normalizedSymbol = symbol.toUpperCase();
  return dustTokens.find(
    (t) =>
      t.chainId === chainId &&
      t.symbol.toUpperCase() === normalizedSymbol
  );
}

/**
 * Get the default consolidation token for a chain
 *
 * @param chainId - Chain ID
 * @returns Token metadata for default consolidation target, or undefined
 */
export function getDefaultConsolidationToken(
  chainId: number
): DustTokenMeta | undefined {
  const symbol = DEFAULT_CONSOLIDATION_TOKEN[chainId];
  if (!symbol) return undefined;
  return getTokenBySymbol(chainId, symbol);
}

// ============================================================================
// Configuration Functions
// ============================================================================

/**
 * Get full dust configuration for a chain with a specific consolidation token
 *
 * @param chainId - Chain ID
 * @param consolidationSymbol - Token symbol to consolidate into (default: USDC)
 * @returns Dust configuration object
 */
export function getDustConfig(
  chainId: number,
  consolidationSymbol?: string
): DustConfig | null {
  // Get consolidation token (use default if not specified)
  const targetSymbol = consolidationSymbol || DEFAULT_CONSOLIDATION_TOKEN[chainId];
  if (!targetSymbol) return null;

  const consolidationToken = getTokenBySymbol(chainId, targetSymbol);
  if (!consolidationToken) return null;

  // Get all dust sources that should consolidate to this token
  const dustSources = getDustSources(chainId).filter(
    (t) =>
      !t.consolidationTarget ||
      t.consolidationTarget.toLowerCase() === consolidationToken.tokenAddress.toLowerCase()
  );

  // Get all available consolidation targets
  const consolidationTargets = getConsolidationTargets(chainId);

  return {
    chainId,
    defaultConsolidationToken: consolidationToken.symbol,
    defaultConsolidationAddress: consolidationToken.tokenAddress,
    trackedDustTokens: dustSources,
    consolidationTargets,
  };
}

/**
 * Get dust configuration by consolidation token address
 *
 * @param chainId - Chain ID
 * @param consolidationAddress - Token address to consolidate into
 * @returns Dust configuration object or null
 */
export function getDustConfigByAddress(
  chainId: number,
  consolidationAddress: string
): DustConfig | null {
  const token = getTokenByAddress(chainId, consolidationAddress);
  if (!token || !token.isConsolidationTarget) return null;
  return getDustConfig(chainId, token.symbol);
}

// ============================================================================
// Viem Client
// ============================================================================

const publicClient = createPublicClient({
  chain: base,
  transport: http(process.env.BASE_RPC_URL || "https://mainnet.base.org"),
});

// ============================================================================
// Price Fetching (CoinGecko)
// ============================================================================

/**
 * Fetch USD prices for dust tokens from CoinGecko
 * Uses caching to avoid rate limits (free tier: 10-30 calls/min)
 *
 * @returns Map of token address (lowercase) to USD price
 */
async function fetchTokenPrices(): Promise<Record<string, number>> {
  // Check cache
  if (priceCache && Date.now() - priceCache.timestamp < CACHE_TTL_MS) {
    console.log("[dustService] Using cached prices");
    return priceCache.prices;
  }

  const coinGeckoIds = Object.values(TOKEN_TO_COINGECKO_ID);
  if (coinGeckoIds.length === 0) return {};

  try {
    const idsParam = coinGeckoIds.join(",");
    const url = `${COINGECKO_API_URL}/simple/price?ids=${idsParam}&vs_currencies=usd`;

    console.log("[dustService] Fetching prices from CoinGecko...");
    const response = await fetch(url, {
      headers: {
        "Accept": "application/json",
      },
    });

    if (!response.ok) {
      console.error(`[dustService] CoinGecko API error: ${response.status}`);
      return priceCache?.prices || {};
    }

    const data = await response.json() as Record<string, { usd?: number }>;

    // Map CoinGecko IDs back to token addresses
    const prices: Record<string, number> = {};
    for (const [address, geckoId] of Object.entries(TOKEN_TO_COINGECKO_ID)) {
      const priceData = data[geckoId];
      if (priceData?.usd !== undefined) {
        prices[address.toLowerCase()] = priceData.usd;
      }
    }

    // Update cache
    priceCache = {
      prices,
      timestamp: Date.now(),
    };

    console.log("[dustService] Fetched prices:", prices);
    return prices;
  } catch (error) {
    console.error("[dustService] Failed to fetch prices:", error);
    // Return cached prices if available, otherwise empty
    return priceCache?.prices || {};
  }
}

/**
 * Get USD price for a specific token
 *
 * @param tokenAddress - Token contract address
 * @param prices - Price map from fetchTokenPrices
 * @returns USD price or undefined if not available
 */
function getTokenPrice(
  tokenAddress: string,
  prices: Record<string, number>
): number | undefined {
  return prices[tokenAddress.toLowerCase()];
}

// ============================================================================
// Wallet Balance Fetching
// ============================================================================

/**
 * Fetch real token balances for a wallet using multicall
 *
 * @param wallet - Wallet address
 * @param tokens - Array of token metadata to check
 * @returns Array of balances (in wei as string)
 */
async function fetchTokenBalances(
  wallet: string,
  tokens: DustTokenMeta[]
): Promise<bigint[]> {
  if (tokens.length === 0) return [];

  const results = await publicClient.multicall({
    contracts: tokens.map((token) => ({
      address: token.tokenAddress as Address,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [wallet as Address],
    })),
    allowFailure: true,
  });

  return results.map((result) => {
    if (result.status === "success") {
      return result.result as bigint;
    }
    return 0n;
  });
}

/**
 * Get dust summary for a wallet with real on-chain balances and USD values
 *
 * @param wallet - Wallet address
 * @param chainId - Chain ID
 * @param consolidationSymbol - Consolidation token symbol
 * @returns Dust summary with real balances and USD values
 */
export async function getDustSummary(
  wallet: string,
  chainId: number,
  consolidationSymbol?: string
): Promise<DustSummaryResponse> {
  const consolidationToken = consolidationSymbol || DEFAULT_CONSOLIDATION_TOKEN[chainId] || "USDC";
  const dustSources = getDustSources(chainId);

  // Fetch real balances and prices in parallel
  let dustBalances: DustBalance[] = [];
  let totalDustValueUsd = 0;

  try {
    const [balances, prices] = await Promise.all([
      fetchTokenBalances(wallet, dustSources),
      fetchTokenPrices(),
    ]);

    dustBalances = dustSources.map((token, index) => {
      const rawBalance = balances[index];
      const formattedBalance = formatUnits(rawBalance, token.decimals);
      const numericBalance = parseFloat(formattedBalance);

      // Get USD price for this token
      const price = getTokenPrice(token.tokenAddress, prices);
      const balanceUsd = price !== undefined ? numericBalance * price : undefined;

      // Determine if this is "dust" based on USD value or token threshold
      // Consider dust if value < $5 or below token-specific threshold
      const isDust = numericBalance > 0 && (
        (balanceUsd !== undefined && balanceUsd < 5) ||
        (balanceUsd === undefined && numericBalance < (token.dustThreshold || 1000))
      );

      return {
        token,
        balance: rawBalance.toString(),
        balanceFormatted: formattedBalance,
        balanceUsd,
        isDust,
      };
    }).filter((b) => BigInt(b.balance) > 0n); // Only include non-zero balances

    // Calculate total USD value of dust tokens
    totalDustValueUsd = dustBalances
      .filter((b) => b.isDust && b.token.suggestedAction === "swap")
      .reduce((sum, b) => sum + (b.balanceUsd || 0), 0);

  } catch (error) {
    console.error("[dustService] Failed to fetch balances:", error);
    // Return empty balances on error
    dustBalances = [];
  }

  return {
    wallet,
    chainId,
    consolidationToken,
    dustBalances,
    totalDustValueUsd: totalDustValueUsd > 0 ? totalDustValueUsd : undefined,
    sweepableTokens: dustBalances
      .filter((b) => b.isDust && b.token.suggestedAction === "swap")
      .map((b) => b.token.tokenAddress),
  };
}

// ============================================================================
// Validation Functions
// ============================================================================

/**
 * Check if a token address is a known consolidation target
 *
 * @param chainId - Chain ID
 * @param tokenAddress - Token address to check
 * @returns true if valid consolidation target
 */
export function isValidConsolidationTarget(
  chainId: number,
  tokenAddress: string
): boolean {
  const token = getTokenByAddress(chainId, tokenAddress);
  return token?.isConsolidationTarget === true;
}

/**
 * Check if a token symbol is a known consolidation target
 *
 * @param chainId - Chain ID
 * @param symbol - Token symbol to check
 * @returns true if valid consolidation target
 */
export function isValidConsolidationSymbol(
  chainId: number,
  symbol: string
): boolean {
  const token = getTokenBySymbol(chainId, symbol);
  return token?.isConsolidationTarget === true;
}

/**
 * Get supported chain IDs for dust operations
 */
export function getSupportedDustChainIds(): number[] {
  const chainIds = new Set<number>();
  dustTokens.forEach((t) => chainIds.add(t.chainId));
  return Array.from(chainIds);
}

// ============================================================================
// Future Enhancements
// ============================================================================

// Future: Estimate swap value for dust tokens using DEX quotes
// Future: Auto-discover new dust tokens via transfer events or indexers
// Future: Integrate price oracles for USD valuations
