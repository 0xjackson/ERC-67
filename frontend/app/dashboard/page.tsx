"use client";

import { useAutopilot } from "@/contexts/AutopilotContext";

export default function DashboardPage() {
  const {
    walletAddress,
    checkingBalance,
    yieldBalance,
    totalBalance,
    currentStrategy,
    isLoading,
    isPolling,
    refreshBalances,
  } = useAutopilot();

  if (isLoading) {
    return <div className="p-8">Loading...</div>;
  }

  if (!walletAddress) {
    return (
      <div className="p-8">
        <p>No wallet found. Please create one first.</p>
        <a href="/create" className="text-blue-400 hover:underline">
          Create Wallet →
        </a>
      </div>
    );
  }

  const formatApy = (apy: number) => `${(apy * 100).toFixed(2)}%`;

  return (
    <div className="space-y-8 p-8">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <button
          onClick={refreshBalances}
          disabled={isPolling}
          className="text-sm text-gray-400 hover:text-white"
        >
          {isPolling ? "Refreshing..." : "Refresh"}
        </button>
      </div>

      {/* Balance Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-gray-900 rounded-lg p-6 border border-gray-800">
          <p className="text-gray-400 text-sm">Checking Balance</p>
          <p className="text-2xl font-bold mt-1">
            ${checkingBalance || "0.00"}
          </p>
          <p className="text-gray-500 text-xs mt-1">Available for spending</p>
        </div>

        <div className="bg-gray-900 rounded-lg p-6 border border-gray-800">
          <p className="text-gray-400 text-sm">Yield Balance</p>
          <p className="text-2xl font-bold mt-1 text-green-400">
            ${yieldBalance || "0.00"}
          </p>
          <p className="text-gray-500 text-xs mt-1">
            {currentStrategy
              ? `${currentStrategy.name} • ${formatApy(currentStrategy.apy)} APY`
              : "Not earning yield"
            }
          </p>
        </div>

        <div className="bg-gray-900 rounded-lg p-6 border border-gray-800">
          <p className="text-gray-400 text-sm">Total Balance</p>
          <p className="text-2xl font-bold mt-1">
            ${totalBalance || "0.00"}
          </p>
          <p className="text-gray-500 text-xs mt-1">USDC</p>
        </div>
      </div>

      {/* Wallet Address */}
      <div className="bg-gray-900 rounded-lg p-6 border border-gray-800">
        <p className="text-gray-400 text-sm">Wallet Address</p>
        <p className="text-sm font-mono mt-1">{walletAddress}</p>
      </div>
    </div>
  );
}
