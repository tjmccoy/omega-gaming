"use client";

import { useEffect, useState } from "react";
import EnterForm from "./EnterForm";
import LotteryHeader from "./LotteryHeader";
import OwnerPanel from "./OwnerPanel";
import PlayersList from "./PlayersList";
import PotCard from "./PotCard";
import { parseEther } from "viem";
import { useAccount } from "wagmi";
import { useLottery } from "~~/hooks/useLottery";
import { useOpenHours } from "~~/hooks/useOpenHours";

export default function LotteryDapp() {
  const [mounted, setMounted] = useState(false);
  const { address: connectedAddress } = useAccount();
  const { potBalance, players, isOwner, enter, pickWinner, isEntering, isPicking } = useLottery();

  // isInitialized is our secret weapon against flickering
  const { currentTime, isOpen, isClosingSoon, timeRemaining, isInitialized } = useOpenHours();

  const [entryAmount, setEntryAmount] = useState("0.02");
  const [showOwnerPanel, setShowOwnerPanel] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const isInvalid = Number(entryAmount) < 0.01 || isNaN(Number(entryAmount));

  const handleEnter = async () => {
    try {
      await enter({ functionName: "enter", value: parseEther(entryAmount) });
    } catch (e) {
      console.error(e);
    }
  };

  const handlePickWinner = async () => {
    try {
      await pickWinner({ functionName: "chooseWinner" });
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-50 font-sans selection:bg-yellow-500/30">
      <LotteryHeader address={mounted ? connectedAddress : undefined} />

      <main className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        {/* Status Section */}
        <div className="min-h-[82px]">
          {!isInitialized ? (
            // The Skeleton: Shown while calculating the true state
            <div className="w-full h-[74px] bg-slate-900/40 rounded-xl border border-slate-800 animate-pulse flex items-center px-4">
              <div className="w-2.5 h-2.5 rounded-full bg-slate-700 mr-4" />
              <div className="flex-1 space-y-2">
                <div className="h-2 w-20 bg-slate-700 rounded" />
                <div className="h-3 w-32 bg-slate-800 rounded" />
              </div>
            </div>
          ) : (
            // The Real Card: Transitions in only when the status is 100% certain
            <div className="animate-in fade-in duration-300">
              <PotCard
                potBalance={potBalance}
                currentTime={currentTime}
                isOpen={!!isOpen}
                isClosingSoon={isClosingSoon}
                timeRemaining={timeRemaining}
              />
            </div>
          )}
        </div>

        <EnterForm
          entryAmount={entryAmount}
          setEntryAmount={setEntryAmount}
          onEnter={handleEnter}
          // Strict check: disable button if not initialized or if closed
          disabled={!isInitialized || isEntering || isInvalid || !isOpen}
          isEntering={isEntering}
          isInvalid={isInvalid}
          isOpen={!!isOpen}
        />

        <PlayersList players={players} connectedAddress={connectedAddress} />

        {isOwner && (
          <OwnerPanel
            show={showOwnerPanel}
            toggle={() => setShowOwnerPanel(b => !b)}
            onPick={handlePickWinner}
            isPicking={isPicking}
            hasPlayers={!!players && players.length > 0}
          />
        )}
      </main>
    </div>
  );
}
