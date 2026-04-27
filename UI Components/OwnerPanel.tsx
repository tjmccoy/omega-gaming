"use client";

import { useState } from "react";
import { LotteryStatus } from "./StatusBar";
import { Loader2, PlusCircle, ShieldCheck, Trophy, Vault } from "lucide-react";
import { formatEther } from "viem";

interface OwnerPanelProps {
  show: boolean;
  toggle: () => void;
  onPick: () => Promise<void>;
  onCreate: (fee: string, start: number, end: number) => Promise<void>;
  isPicking: boolean;
  isCreating: boolean;
  status: LotteryStatus;
  treasuryBalance?: { formatted: string; symbol: string };
  winnerHistory?: any[];
}

export default function OwnerPanel({
  show,
  toggle,
  onPick,
  onCreate,
  isPicking,
  isCreating,
  status,
  treasuryBalance,
  winnerHistory = [],
}: OwnerPanelProps) {
  const [fee, setFee] = useState("0.02");
  const [durationHours, setDurationHours] = useState("24");

  const handleCreate = async () => {
    const start = Math.floor(Date.now() / 1000);
    const end = start + parseInt(durationHours) * 3600;
    await onCreate(fee, start, end);
  };

  // Calculate total fees collected from winner history
  const totalFeesCollected = winnerHistory.reduce((acc, entry) => {
    if (!entry?.totalPot) return acc;
    const pot = BigInt(entry.totalPot);
    const fee = pot - (pot * 98n) / 100n; // 2% treasury cut
    return acc + fee;
  }, 0n);

  return (
    <div className="rounded-2xl border border-red-900/30 bg-red-950/10 overflow-hidden">
      {/* Header */}
      <div className="p-4 flex items-center justify-between cursor-pointer bg-red-950/20" onClick={toggle}>
        <div className="flex items-center gap-2">
          <ShieldCheck className="w-5 h-5 text-red-500" />
          <span className="font-bold text-red-100">Owner Dashboard</span>
        </div>
        <span className="text-[10px] bg-red-500 text-white px-2 py-0.5 rounded-full font-black">ADMIN</span>
      </div>

      {show && (
        <div className="p-6 space-y-8 animate-in slide-in-from-top-4">
          {/* TREASURY SECTION */}
          <div className="space-y-3">
            <h4 className="text-xs font-bold text-red-400 uppercase flex items-center gap-2">
              <Vault className="w-4 h-4" /> Treasury
            </h4>
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-black/30 border border-red-900/20 rounded-xl p-4 space-y-1">
                <p className="text-[10px] text-slate-500 uppercase font-bold">Current Balance</p>
                <p className="text-xl font-black text-white">
                  {!treasuryBalance || parseFloat(treasuryBalance.formatted) === 0
                    ? "0.0000 ETH"
                    : `${parseFloat(treasuryBalance.formatted).toFixed(4)} ${treasuryBalance.symbol}`}
                </p>
              </div>
              <div className="bg-black/30 border border-red-900/20 rounded-xl p-4 space-y-1">
                <p className="text-[10px] text-slate-500 uppercase font-bold">Total Fees Collected</p>
                <p className="text-xl font-black text-white">
                  {winnerHistory.length > 0
                    ? `${parseFloat(formatEther(totalFeesCollected)).toFixed(4)} ETH`
                    : "No history yet"}
                </p>
                <p className="text-[10px] text-slate-600">
                  across {winnerHistory.length} round{winnerHistory.length !== 1 ? "s" : ""}
                </p>
              </div>
            </div>
          </div>

          <div className="border-t border-red-900/20" />

          {/* CREATE NEW ROUND SECTION */}
          <div className="space-y-4">
            <h4 className="text-xs font-bold text-red-400 uppercase flex items-center gap-2">
              <PlusCircle className="w-4 h-4" /> Start New Lottery Round
            </h4>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1">
                <label className="text-[10px] text-slate-500 uppercase font-bold">Entry Fee (ETH)</label>
                <input
                  type="number"
                  value={fee}
                  onChange={e => setFee(e.target.value)}
                  className="w-full bg-black/40 border border-red-900/30 rounded-lg p-2 text-white outline-none focus:border-red-500"
                />
              </div>
              <div className="space-y-1">
                <label className="text-[10px] text-slate-500 uppercase font-bold">Duration (Hours)</label>
                <input
                  type="number"
                  value={durationHours}
                  onChange={e => setDurationHours(e.target.value)}
                  className="w-full bg-black/40 border border-red-900/30 rounded-lg p-2 text-white outline-none focus:border-red-500"
                />
              </div>
            </div>
            <button
              onClick={handleCreate}
              disabled={isCreating}
              className="w-full py-3 bg-red-600 hover:bg-red-500 text-white rounded-xl font-bold flex items-center justify-center gap-2 disabled:opacity-50 transition-colors"
            >
              {isCreating ? <Loader2 className="animate-spin w-4 h-4" /> : <PlusCircle className="w-4 h-4" />}
              Deploy New Round
            </button>
          </div>

          <div className="border-t border-red-900/20" />

          {/* PICK WINNER SECTION */}
          <div>
            <button
              onClick={onPick}
              disabled={isPicking || status !== LotteryStatus.CLOSED}
              className="w-full py-4 bg-slate-800 border border-slate-700 text-white rounded-xl font-bold flex items-center justify-center gap-2 disabled:opacity-30 hover:bg-slate-700 transition-colors"
            >
              <Trophy className="w-5 h-5 text-yellow-500" />
              Pick Winner (Requires VRF)
            </button>
            {status !== LotteryStatus.CLOSED && (
              <p className="text-[10px] text-slate-600 text-center mt-2">Only available when lottery is closed</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
