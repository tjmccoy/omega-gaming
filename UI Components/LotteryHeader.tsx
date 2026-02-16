"use client";

import { Wallet } from "lucide-react";

interface LotteryHeaderProps {
  address?: string | null;
}

export default function LotteryHeader({ address }: LotteryHeaderProps) {
  return (
    <header className="border-b border-slate-800 bg-slate-900/50 backdrop-blur-sm sticky top-0 z-10">
      <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-yellow-500/10 flex items-center justify-center border border-yellow-500/20">
            {/* logo could be passed as prop if needed */}
            <span className="font-bold text-yellow-500">🎲</span>
          </div>
          <h1 className="text-2xl font-bold tracking-tight text-white">Omega Gaming</h1>
        </div>
        {/* Wallet Display */}
        <div className="px-4 py-2 bg-slate-800 rounded-full border border-slate-700 text-sm font-medium flex items-center gap-2">
          <Wallet className="w-4 h-4 text-slate-400" />
          {address ? `${address.slice(0, 6)}...${address.slice(-4)}` : "Not Connected"}
        </div>
      </div>
    </header>
  );
}
