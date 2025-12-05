"use client";

import { useState, useEffect } from "react";
import { useSignMessage } from "wagmi";
import { autopilotApi, prepareSweep, submitSigned, type DustBalance, type DustSummaryResponse } from "@/lib/api/client";

type SweepStatus = "idle" | "preparing" | "signing" | "submitting" | "success" | "error";

interface DustBalancesProps {
  walletAddress: string;
  onSweepComplete?: () => void;
}

export function DustBalances({ walletAddress, onSweepComplete }: DustBalancesProps) {
  const [dustSummary, setDustSummary] = useState<DustSummaryResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [sweepStatus, setSweepStatus] = useState<SweepStatus>("idle");
  const [error, setError] = useState<string | null>(null);

  // Hook for signing messages (user's wallet)
  const { signMessageAsync } = useSignMessage();

  // Fetch dust balances
  useEffect(() => {
    if (!walletAddress) return;

    const fetchDustBalances = async () => {
      setIsLoading(true);
      setError(null);
      try {
        const summary = await autopilotApi.getDustSummary(walletAddress);
        setDustSummary(summary);
      } catch (err) {
        console.error("Failed to fetch dust balances:", err);
        setError("Failed to load dust balances");
      } finally {
        setIsLoading(false);
      }
    };

    fetchDustBalances();
  }, [walletAddress]);

  const handleSweep = async () => {
    if (!dustSummary?.sweepableTokens?.length) return;

    try {
      // 1. Backend prepares UserOp with paymaster data (user-signed flow)
      setSweepStatus("preparing");
      const { userOp, userOpHash } = await prepareSweep({
        walletAddress,
        dustTokens: dustSummary.sweepableTokens,
      });

      // 2. User signs the UserOp hash (wallet popup)
      setSweepStatus("signing");
      console.log("[DustBalances] userOpHash from backend:", userOpHash);
      const signature = await signMessageAsync({
        message: { raw: userOpHash as `0x${string}` },
      });
      console.log("[DustBalances] signature:", signature);

      // 3. Submit signed UserOp to bundler
      setSweepStatus("submitting");
      await submitSigned({ userOp, signature });

      setSweepStatus("success");

      // Refresh balances after sweep
      const updatedSummary = await autopilotApi.getDustSummary(walletAddress);
      setDustSummary(updatedSummary);

      onSweepComplete?.();

      // Reset status after 3 seconds
      setTimeout(() => setSweepStatus("idle"), 3000);
    } catch (err) {
      console.error("Sweep failed:", err);
      setSweepStatus("error");
      setTimeout(() => setSweepStatus("idle"), 3000);
    }
  };

  // Don't render if no dust balances
  if (!isLoading && (!dustSummary?.dustBalances?.length)) {
    return null;
  }

  const sweepableCount = dustSummary?.sweepableTokens?.length || 0;
  const isProcessing = sweepStatus === "preparing" || sweepStatus === "signing" || sweepStatus === "submitting";
  const canSweep = sweepableCount > 0 && sweepStatus === "idle";

  return (
    <div className="bg-white rounded-lg p-6 border border-gray-200 shadow-sm">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <svg className="w-5 h-5 text-amber-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z" />
          </svg>
          <h2 className="text-lg font-semibold text-gray-900">Dust Tokens</h2>
        </div>
        {sweepableCount > 0 && (
          <div className="flex items-center gap-2">
            {dustSummary?.totalDustValueUsd !== undefined && (
              <span className="text-sm font-medium text-green-600">
                ${dustSummary.totalDustValueUsd.toFixed(2)}
              </span>
            )}
            <span className="text-xs bg-amber-100 text-amber-700 px-2 py-1 rounded-full">
              {sweepableCount} sweepable
            </span>
          </div>
        )}
      </div>

      {isLoading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="flex items-center justify-between py-2">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 bg-gray-100 rounded-full animate-pulse" />
                <div className="space-y-1">
                  <div className="h-4 w-16 bg-gray-100 rounded animate-pulse" />
                  <div className="h-3 w-24 bg-gray-100 rounded animate-pulse" />
                </div>
              </div>
              <div className="h-4 w-20 bg-gray-100 rounded animate-pulse" />
            </div>
          ))}
        </div>
      ) : error ? (
        <div className="text-center py-4 text-red-500 text-sm">{error}</div>
      ) : (
        <>
          <div className="space-y-3 max-h-48 overflow-y-auto">
            {dustSummary?.dustBalances.map((dust) => (
              <DustTokenRow key={dust.token.tokenAddress} dust={dust} />
            ))}
          </div>

          {sweepableCount > 0 && (
            <div className="mt-4 pt-4 border-t border-gray-100">
              <button
                onClick={handleSweep}
                disabled={!canSweep}
                className={`w-full py-3 rounded-lg font-medium text-sm transition-all flex items-center justify-center gap-2 ${
                  sweepStatus === "success"
                    ? "bg-green-100 text-green-700"
                    : sweepStatus === "error"
                    ? "bg-red-100 text-red-700"
                    : isProcessing
                    ? "bg-amber-400 text-white cursor-wait"
                    : canSweep
                    ? "bg-amber-500 hover:bg-amber-600 text-white"
                    : "bg-gray-100 text-gray-400 cursor-not-allowed"
                }`}
              >
                {isProcessing ? (
                  <>
                    <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                    </svg>
                    <span>
                      {sweepStatus === "preparing" && "Preparing..."}
                      {sweepStatus === "signing" && "Sign in wallet..."}
                      {sweepStatus === "submitting" && "Submitting..."}
                    </span>
                  </>
                ) : sweepStatus === "success" ? (
                  <>
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                    </svg>
                    <span>Swept to USDC!</span>
                  </>
                ) : sweepStatus === "error" ? (
                  <>
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                    <span>Sweep failed</span>
                  </>
                ) : (
                  <>
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z" />
                    </svg>
                    <span>
                      Sweep {sweepableCount} token{sweepableCount > 1 ? "s" : ""}
                      {dustSummary?.totalDustValueUsd !== undefined && ` (~$${dustSummary.totalDustValueUsd.toFixed(2)})`} to USDC
                    </span>
                  </>
                )}
              </button>
              <p className="text-xs text-gray-500 text-center mt-2">
                Converts dust tokens to USDC and deposits to yield
              </p>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function DustTokenRow({ dust }: { dust: DustBalance }) {
  const { token, balanceFormatted, balanceUsd, isDust } = dust;

  // Format balance for display
  const displayBalance = balanceFormatted
    ? parseFloat(balanceFormatted).toLocaleString(undefined, {
        maximumFractionDigits: 4,
      })
    : "0";

  // Format USD value
  const displayUsd = balanceUsd !== undefined
    ? balanceUsd < 0.01
      ? "<$0.01"
      : `$${balanceUsd.toFixed(2)}`
    : null;

  return (
    <div className="flex items-center justify-between py-2 hover:bg-gray-50 rounded-lg px-2 -mx-2 transition-colors">
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 bg-gradient-to-br from-gray-100 to-gray-200 rounded-full flex items-center justify-center">
          <span className="text-xs font-bold text-gray-600">
            {token.symbol.slice(0, 2)}
          </span>
        </div>
        <div>
          <p className="font-medium text-gray-900 text-sm">{token.symbol}</p>
          <p className="text-xs text-gray-500">{token.name}</p>
        </div>
      </div>
      <div className="text-right">
        <p className="font-mono text-sm text-gray-900">{displayBalance}</p>
        {displayUsd ? (
          <p className="text-xs text-gray-500">{displayUsd}</p>
        ) : isDust && token.suggestedAction === "swap" ? (
          <p className="text-xs text-amber-600">Sweepable</p>
        ) : null}
      </div>
    </div>
  );
}

export default DustBalances;
