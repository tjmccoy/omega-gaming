import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

export function useLottery() {
  const { address } = useAccount();

  const { data: potBalance } = useScaffoldReadContract({
    contractName: "Lottery",
    functionName: "getPotBalance",
    watch: true,
  });

  const { data: players } = useScaffoldReadContract({
    contractName: "Lottery",
    functionName: "getPlayers",
    watch: true,
  });

  const { data: owner } = useScaffoldReadContract({
    contractName: "Lottery",
    functionName: "owner",
  });

  const { writeContractAsync: enter, isPending: isEntering } = useScaffoldWriteContract({
    contractName: "Lottery",
  });

  const { writeContractAsync: pickWinner, isPending: isPicking } = useScaffoldWriteContract({
    contractName: "Lottery",
  });

  const [isOwner, setIsOwner] = useState(false);
  useEffect(() => {
    if (owner && address) {
      setIsOwner(owner.toLowerCase() === address.toLowerCase());
    } else {
      setIsOwner(false);
    }
  }, [owner, address]);

  return {
    potBalance,
    players,
    owner,
    isOwner,
    enter,
    pickWinner,
    isEntering,
    isPicking,
  };
}
