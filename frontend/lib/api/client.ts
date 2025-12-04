import axios, { AxiosInstance, AxiosError, AxiosResponse } from "axios";

// ============================================================================
// Types
// ============================================================================

export type RiskTier = "low" | "med" | "high";

export type Strategy = {
  id: string;
  chainId: number;
  token: string;
  tokenAddress: string;
  vaultAddress: string;
  protocolName: string;
  apy: number;
  riskTier?: RiskTier;
  isActive: boolean;
};

export type ScoredStrategy = Strategy & {
  score: number;
};

export type StrategyPreferences = {
  riskTolerance: RiskTier;
  minApy: number;
};

export type DustAction = "swap" | "hold" | "ignore";

export type DustTokenMeta = {
  chainId: number;
  tokenAddress: string;
  symbol: string;
  name: string;
  decimals: number;
  isDustSource: boolean;
  suggestedAction: DustAction;
  consolidationTarget?: string;
  notes?: string;
  isConsolidationTarget?: boolean;
  dustThreshold?: number;
};

export type DustBalance = {
  token: DustTokenMeta;
  balance: string;
  balanceUsd?: number;
  isDust: boolean;
};

// ============================================================================
// Request Types
// ============================================================================

export type PayRequest = {
  wallet: string;
  to: string;
  token: string;
  amount: string;
  chainId?: number;
};

export type RebalanceRequest = {
  wallet: string;
  token?: string;
  chainId?: number;
  riskTolerance?: RiskTier;
  preferredStrategyId?: string;
};

export type SweepDustRequest = {
  wallet: string;
  chainId?: number;
  consolidationToken?: string;
};

export type GetStrategiesParams = {
  token?: string;
  chainId?: number;
};

export type GetRecommendationParams = {
  chainId?: number;
};

export type GetDustTokensParams = {
  chainId?: number;
};

export type GetDustSummaryParams = {
  chainId?: number;
  consolidation?: string;
};

// ============================================================================
// Response Types
// ============================================================================

export type PayResponse = {
  success: boolean;
  txHash?: string;
  message: string;
};

export type RebalanceResponse = {
  success: boolean;
  strategyUsed?: string;
  strategyScore?: number;
  txHash?: string;
  message: string;
};

export type SweepDustResponse = {
  success: boolean;
  swappedTokens?: string[];
  consolidatedTo?: string;
  txHash?: string;
  message: string;
};

export type StrategiesResponse = {
  token: string;
  chainId: number;
  strategies: Strategy[];
};

export type RecommendResponse = {
  token: string;
  chainId: number;
  strategy: Strategy;
};

export type DustTokensResponse = {
  chainId: number;
  tokens: DustTokenMeta[];
  totalCount: number;
  dustSourceCount: number;
};

export type DustSummaryResponse = {
  wallet: string;
  chainId: number;
  consolidationToken: string;
  dustBalances: DustBalance[];
  totalDustValueUsd?: number;
  note: string;
};

export type ErrorResponse = {
  error: string;
};

// ============================================================================
// API Error Handling
// ============================================================================

export class ApiError extends Error {
  public readonly status: number;
  public readonly code: string;
  public readonly originalError?: AxiosError;

  constructor(
    message: string,
    status: number,
    code: string = "API_ERROR",
    originalError?: AxiosError
  ) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.originalError = originalError;
  }
}

function unwrapServerError(error: unknown): never {
  if (axios.isAxiosError(error)) {
    const axiosError = error as AxiosError<ErrorResponse>;
    const status = axiosError.response?.status ?? 500;
    const serverMessage = axiosError.response?.data?.error;
    const message = serverMessage ?? axiosError.message ?? "Unknown API error";

    let code = "API_ERROR";
    if (axiosError.code === "ECONNABORTED") code = "TIMEOUT";
    else if (axiosError.code === "ERR_NETWORK") code = "NETWORK_ERROR";
    else if (status === 400) code = "BAD_REQUEST";
    else if (status === 401) code = "UNAUTHORIZED";
    else if (status === 403) code = "FORBIDDEN";
    else if (status === 404) code = "NOT_FOUND";
    else if (status === 422) code = "VALIDATION_ERROR";
    else if (status >= 500) code = "SERVER_ERROR";

    throw new ApiError(message, status, code, axiosError);
  }

  if (error instanceof Error) {
    throw new ApiError(error.message, 500, "UNKNOWN_ERROR");
  }

  throw new ApiError("An unknown error occurred", 500, "UNKNOWN_ERROR");
}

// ============================================================================
// Axios Instance
// ============================================================================

function createAxiosInstance(): AxiosInstance {
  const baseURL =
    process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";
  console.log("[API Client] Base URL:", baseURL);
  const timeout = parseInt(process.env.NEXT_PUBLIC_API_TIMEOUT_MS ?? "30000", 10);

  const instance = axios.create({
    baseURL,
    timeout,
    headers: {
      "Content-Type": "application/json",
    },
  });

  // Response interceptor for consistent error handling
  instance.interceptors.response.use(
    (response: AxiosResponse) => response,
    (error: AxiosError) => Promise.reject(error)
  );

  return instance;
}

const axiosInstance = createAxiosInstance();

// ============================================================================
// API Interface & Implementation
// ============================================================================

export interface AutopilotAPI {
  pay(request: PayRequest): Promise<PayResponse>;
  rebalance(request: RebalanceRequest): Promise<RebalanceResponse>;
  sweepDust(request: SweepDustRequest): Promise<SweepDustResponse>;
  getStrategies(params?: GetStrategiesParams): Promise<StrategiesResponse>;
  getRecommendation(
    token: string,
    params?: GetRecommendationParams
  ): Promise<RecommendResponse>;
  getDustTokens(params?: GetDustTokensParams): Promise<DustTokensResponse>;
  getDustSummary(
    walletAddress: string,
    params?: GetDustSummaryParams
  ): Promise<DustSummaryResponse>;
}

async function pay(request: PayRequest): Promise<PayResponse> {
  try {
    const response = await axiosInstance.post<PayResponse>("/ops/pay", request);
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

async function rebalance(request: RebalanceRequest): Promise<RebalanceResponse> {
  try {
    const response = await axiosInstance.post<RebalanceResponse>(
      "/ops/rebalance",
      request
    );
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

async function sweepDust(request: SweepDustRequest): Promise<SweepDustResponse> {
  try {
    const response = await axiosInstance.post<SweepDustResponse>(
      "/ops/dust",
      request
    );
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

/**
 * GET /strategies
 * Returns all active strategies for a given token and chain, sorted by APY descending.
 *
 * @param params.token - Token symbol (default: "USDC")
 * @param params.chainId - Chain ID (default: 8453 for Base)
 */
async function getStrategies(
  params?: GetStrategiesParams
): Promise<StrategiesResponse> {
  try {
    const response = await axiosInstance.get<StrategiesResponse>("/strategies", {
      params,
    });
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

/**
 * GET /recommend
 * Returns the single highest-APY strategy for a given token and chain.
 *
 * @param token - Token symbol (e.g., "USDC", "WETH")
 * @param params.chainId - Chain ID (default: 8453 for Base)
 */
async function getRecommendation(
  token: string,
  params?: GetRecommendationParams
): Promise<RecommendResponse> {
  try {
    const response = await axiosInstance.get<RecommendResponse>("/recommend", {
      params: { token, ...params },
    });
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

/**
 * GET /dust/tokens
 * Returns all dust token metadata for a chain.
 *
 * @param params.chainId - Chain ID (default: 8453 for Base)
 */
async function getDustTokens(
  params?: GetDustTokensParams
): Promise<DustTokensResponse> {
  try {
    const response = await axiosInstance.get<DustTokensResponse>("/dust/tokens", {
      params,
    });
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

/**
 * GET /dust/summary
 * Returns dust summary for a wallet (currently returns mock data).
 *
 * @param walletAddress - Wallet address (0x...)
 * @param params.chainId - Chain ID (default: 8453 for Base)
 * @param params.consolidation - Consolidation token symbol (default: "USDC")
 */
async function getDustSummary(
  walletAddress: string,
  params?: GetDustSummaryParams
): Promise<DustSummaryResponse> {
  try {
    const response = await axiosInstance.get<DustSummaryResponse>(
      "/dust/summary",
      {
        params: { wallet: walletAddress, ...params },
      }
    );
    return response.data;
  } catch (error) {
    unwrapServerError(error);
  }
}

// ============================================================================
// Exported API Object
// ============================================================================

export const autopilotApi: AutopilotAPI = {
  pay,
  rebalance,
  sweepDust,
  getStrategies,
  getRecommendation,
  getDustTokens,
  getDustSummary,
};

// Also export individual functions for direct imports
export {
  getStrategies,
  getRecommendation,
  getDustTokens,
  getDustSummary,
};

export default autopilotApi;
