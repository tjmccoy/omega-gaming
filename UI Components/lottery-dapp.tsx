"use client";

import { useState } from "react";
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
  const { address: connectedAddress } = useAccount();
  const { potBalance, players, isOwner, enter, pickWinner, isEntering, isPicking } = useLottery();

  const { currentTime, isOpen, isClosingSoon, timeRemaining } = useOpenHours();

  const [entryAmount, setEntryAmount] = useState("0.02");
  const [showOwnerPanel, setShowOwnerPanel] = useState(false);

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
      <LotteryHeader address={connectedAddress} />

      <main className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        <PotCard
          potBalance={potBalance}
          currentTime={currentTime}
          isOpen={isOpen}
          isClosingSoon={isClosingSoon}
          timeRemaining={timeRemaining}
        />

        <EnterForm
          entryAmount={entryAmount}
          setEntryAmount={setEntryAmount}
          onEnter={handleEnter}
          disabled={isEntering || isInvalid || !isOpen}
          isEntering={isEntering}
          isInvalid={isInvalid}
          isOpen={isOpen}
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
