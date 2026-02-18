"use client";

import { useEffect, useState } from "react";
import StatusBar from "./StatusBar";
import { formatEther } from "viem";

// 🛡️ THE FIX: This block was likely missing or misspelled
interface PotCardProps {
  potBalance?: bigint;
  currentTime: Date;
  isOpen: boolean;
  isClosingSoon: boolean;
  timeRemaining: string;
}

export default function PotCard({ potBalance, currentTime, isOpen, isClosingSoon, timeRemaining }: PotCardProps) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <div className="relative overflow-hidden rounded-xl border border-slate-800 bg-slate-900 shadow-2xl p-8 min-h-[160px]">
      <div className="flex justify-between items-start mb-6">
        <div>
          <h2 className="text-slate-400 text-xs font-bold uppercase tracking-widest mb-1">Current Pot</h2>
          <div className="flex items-baseline gap-2">
            <span className="text-6xl font-black text-yellow-500 drop-shadow-[0_0_15px_rgba(234,179,8,0.3)]">
              {potBalance ? Number(formatEther(potBalance)).toFixed(4) : "0.0000"}
            </span>
            <span className="text-xl font-bold text-yellow-500/50">ETH</span>
          </div>
        </div>

        <div className="text-right">
          <p className="text-slate-500 text-[10px] font-bold uppercase tracking-tighter">Your Local Time</p>
          <p className="text-2xl font-mono text-white min-w-[120px]">
            {mounted ? (
              currentTime.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
            ) : (
              <span className="opacity-20">--:--:--</span>
            )}
          </p>
        </div>
      </div>

      <div
        className={`transition-all duration-700 ${mounted ? "opacity-100 translate-y-0" : "opacity-0 translate-y-2"}`}
      >
        {mounted ? (
          <StatusBar isOpen={isOpen} isClosingSoon={isClosingSoon} timeRemaining={timeRemaining} />
        ) : (
          <div className="h-10 w-full bg-slate-800/50 animate-pulse rounded-lg" />
        )}
      </div>
    </div>
  );
}
