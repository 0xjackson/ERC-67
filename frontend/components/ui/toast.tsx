"use client";

import { useState, useEffect, createContext, useContext, ReactNode } from "react";

type ToastType = "success" | "error" | "info" | "loading";

interface Toast {
  id: string;
  type: ToastType;
  message: string;
  txHash?: string;
}

interface ToastContextValue {
  toasts: Toast[];
  showToast: (type: ToastType, message: string, txHash?: string) => string;
  hideToast: (id: string) => void;
  updateToast: (id: string, type: ToastType, message: string, txHash?: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const showToast = (type: ToastType, message: string, txHash?: string): string => {
    const id = Math.random().toString(36).slice(2);
    setToasts(prev => [...prev, { id, type, message, txHash }]);

    // Auto-hide after 5 seconds (except loading)
    if (type !== "loading") {
      setTimeout(() => hideToast(id), 5000);
    }

    return id;
  };

  const hideToast = (id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  };

  const updateToast = (id: string, type: ToastType, message: string, txHash?: string) => {
    setToasts(prev => prev.map(t =>
      t.id === id ? { ...t, type, message, txHash } : t
    ));

    // Auto-hide after update (except loading)
    if (type !== "loading") {
      setTimeout(() => hideToast(id), 5000);
    }
  };

  return (
    <ToastContext.Provider value={{ toasts, showToast, hideToast, updateToast }}>
      {children}
      <ToastContainer toasts={toasts} onClose={hideToast} />
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast must be used within ToastProvider");
  return context;
}

// Toast container component
function ToastContainer({
  toasts,
  onClose
}: {
  toasts: Toast[];
  onClose: (id: string) => void;
}) {
  return (
    <div className="fixed bottom-4 right-4 z-50 flex flex-col gap-2">
      {toasts.map(toast => (
        <div
          key={toast.id}
          className={`
            px-4 py-3 rounded-lg shadow-lg flex items-center gap-3 min-w-[300px]
            ${toast.type === "success" ? "bg-green-900 border border-green-700" : ""}
            ${toast.type === "error" ? "bg-red-900 border border-red-700" : ""}
            ${toast.type === "info" ? "bg-blue-900 border border-blue-700" : ""}
            ${toast.type === "loading" ? "bg-gray-800 border border-gray-700" : ""}
          `}
        >
          {/* Icon */}
          {toast.type === "loading" && (
            <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
          )}
          {toast.type === "success" && <span>✓</span>}
          {toast.type === "error" && <span>✕</span>}
          {toast.type === "info" && <span>ℹ</span>}

          {/* Message */}
          <div className="flex-1">
            <p className="text-sm text-white">{toast.message}</p>
            {toast.txHash && (
              <a
                href={`https://basescan.org/tx/${toast.txHash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-blue-400 hover:underline"
              >
                View on BaseScan →
              </a>
            )}
          </div>

          {/* Close button */}
          <button
            onClick={() => onClose(toast.id)}
            className="text-gray-400 hover:text-white"
          >
            ×
          </button>
        </div>
      ))}
    </div>
  );
}
