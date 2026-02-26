"use client";

import { CalendarDays, Trophy } from "lucide-react";
import { formatEther } from "viem";

interface PotCardProps {
  potBalance: bigint;
  status: number;
  startTime: bigint;
  endTime: bigint;
  winner?: string;
}

/**
 * Formats a Unix timestamp into a readable date string
 */
function formatDate(timestamp: bigint): string {
  if (timestamp === 0n) return "TBD";
  return new Date(Number(timestamp) * 1000).toLocaleDateString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default function PotCard({ potBalance, status, startTime, endTime, winner }: PotCardProps) {
  const isResolved = status === 4;
  const isDrawing = status === 3;
  const isNotStarted = status === 0;

  return (
    <div className="bg-slate-900/50 border border-slate-800 rounded-2xl p-6 shadow-xl relative overflow-hidden group">
      {/* Decorative background glow for winners */}
      {isResolved && <div className="absolute -right-10 -top-10 w-32 h-32 bg-green-500/10 blur-3xl rounded-full" />}

      <div className="flex flex-col md:flex-row justify-between items-start md:items-end gap-4 relative z-10">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <p className="text-slate-400 text-xs font-bold uppercase tracking-widest">
              {isResolved ? "Total Payout" : "Current Jackpot"}
            </p>
          </div>
          <h2 className="text-4xl font-black text-yellow-500 tracking-tight">
            {formatEther(potBalance)} <span className="text-xl text-slate-500 font-medium">ETH</span>
          </h2>

          {/* Using startTime and endTime here to clear linting warnings */}
          <div className="flex items-center gap-2 mt-2 text-slate-500">
            <CalendarDays className="w-3.5 h-3.5" />
            <span className="text-xs font-medium">
              {isNotStarted ? `Starts: ${formatDate(startTime)}` : `Draw: ${formatDate(endTime)}`}
            </span>
          </div>
        </div>

        <div className="text-right w-full md:w-auto pt-4 md:pt-0 border-t md:border-t-0 border-slate-800/50">
          {isResolved ? (
            <div className="animate-in zoom-in slide-in-from-right-4 duration-500 flex flex-col items-end">
              <div className="flex items-center gap-1.5 text-green-400 mb-1">
                <Trophy className="w-4 h-4" />
                <p className="text-[10px] font-black uppercase tracking-widest">Winner Selected</p>
              </div>
              <p className="text-slate-100 font-mono text-sm bg-slate-800/80 px-3 py-1 rounded-lg border border-slate-700">
                {winner?.slice(0, 6)}...{winner?.slice(-4)}
              </p>
            </div>
          ) : isDrawing ? (
            <div className="flex flex-col items-end gap-1">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-yellow-500 rounded-full animate-ping" />
                <p className="text-yellow-500 text-sm font-bold uppercase tracking-tight">Selecting Winner</p>
              </div>
              <p className="text-[10px] text-slate-500">Awaiting VRF Callback...</p>
            </div>
          ) : (
            <div className="flex flex-col items-end">
              <p className="text-slate-500 text-[10px] uppercase font-black tracking-widest mb-1">Lottery Status</p>
              <div
                className={`px-3 py-1 rounded-full text-xs font-bold border ${
                  status === 1
                    ? "bg-green-500/10 border-green-500/20 text-green-400"
                    : "bg-slate-800 border-slate-700 text-slate-400"
                }`}
              >
                {status === 1 ? "LIVE" : "PENDING"}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
