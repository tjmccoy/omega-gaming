"use client";

import { Users as UsersIcon } from "lucide-react";

interface PlayersListProps {
  players?: readonly string[];
  connectedAddress?: string | null;
}

export default function PlayersList({ players, connectedAddress }: PlayersListProps) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-900 p-6 shadow-lg">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-slate-800 flex items-center justify-center">
            <UsersIcon className="w-4 h-4 text-slate-400" />
          </div>
          <h3 className="font-semibold text-lg text-white">Current Players</h3>
        </div>
        <span className="text-xs font-medium text-slate-400 bg-slate-800 px-3 py-1 rounded-full">
          {players?.length || 0} participants
        </span>
      </div>

      <div className="h-[200px] overflow-y-auto pr-2 custom-scrollbar rounded-lg bg-slate-950/50 border border-slate-800/50 p-2">
        {!players || players.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-slate-600 space-y-2">
            <UsersIcon className="w-8 h-8 opacity-20" />
            <p>No players yet. Be the first!</p>
          </div>
        ) : (
          <div className="space-y-2">
            {players.map((player: string, index: number) => (
              <div
                key={index}
                className="flex items-center justify-between py-3 px-4 rounded-lg bg-slate-900 border border-slate-800 hover:border-slate-700 transition-colors"
              >
                <div className="flex items-center gap-3">
                  <span className="text-xs text-slate-500 font-mono w-6">#{index + 1}</span>
                  <span className="font-mono text-sm text-slate-300">
                    {player.slice(0, 6)}...{player.slice(-4)}
                  </span>
                </div>
                {connectedAddress && player.toLowerCase() === connectedAddress.toLowerCase() && (
                  <span className="text-[10px] uppercase font-bold text-green-500 bg-green-500/10 px-2 py-0.5 rounded">
                    You
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
