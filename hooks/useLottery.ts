import { useCallback, useEffect, useState } from "react";
import { OMEGA_LOTTERY_ABI } from "../constants/abi";
import { decodeEventLog, keccak256, parseEther, toBytes } from "viem";
import { useAccount, useBalance, usePublicClient, useReadContract, useWriteContract } from "wagmi";

const CONTRACT_ADDRESS = "0x256aA1F20fEFd5d8E8A4Eab916af17A36323eC97";

// Your Alchemy API key & base URL for Sepolia
const ALCHEMY_API_KEY = process.env.NEXT_PUBLIC_ALCHEMY_API_KEY!;
const ALCHEMY_URL = `https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}`;

// Contract deployment block (hex). Find on Etherscan by looking up tx:
// 0x2afcac3ae887629545ae6096978c885a3291d62baa31a5d05c42d71bcef9eeed
const CONTRACT_DEPLOY_BLOCK = "0x9DC513"; // ← update this with the new deployment block

// keccak256 of the WinnerPaid event signature — used to filter eth_getLogs.
// toBytes() converts the string to a Uint8Array which is what keccak256 expects.
const WINNER_PAID_TOPIC = keccak256(toBytes("WinnerPaid(uint256,address,uint256,uint256)"));

export const useLottery = (lotteryId: bigint) => {
  const { address: connectedAddress } = useAccount();
  const publicClient = usePublicClient();
  const [winnerHistory, setWinnerHistory] = useState<any[]>([]);

  // READS
  const { data: lotteryData, refetch: refetchLottery } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: OMEGA_LOTTERY_ABI,
    functionName: "getLottery",
    args: [lotteryId],
  });

  const { data: players, refetch: refetchPlayers } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: OMEGA_LOTTERY_ABI,
    functionName: "getPlayersByLotteryId",
    args: [lotteryId],
  });

  // isLoading is critical here — without it, isOwner resolves to `false` on
  // first render because ownerAddress is still undefined while the RPC call
  // is in flight. Adding isOwnerLoading to the memo prevents that false negative.
  const { data: ownerAddress, isLoading: isOwnerLoading } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: OMEGA_LOTTERY_ABI,
    functionName: "owner",
  });

  const { data: treasuryAddress } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: OMEGA_LOTTERY_ABI,
    functionName: "getTreasuryAddress",
  });

  const { data: treasuryBalance } = useBalance({
    address: treasuryAddress as `0x${string}`,
    query: {
      enabled: !!treasuryAddress && treasuryAddress !== "0x0000000000000000000000000000000000000000",
    },
  });

  // WRITES
  const { writeContractAsync: joinTx, isPending: isJoining } = useWriteContract();
  const { writeContractAsync: requestTx, isPending: isRequesting } = useWriteContract();
  const { writeContractAsync: createTx, isPending: isCreating } = useWriteContract();

  const joinLottery = async (amount: string) => {
    return await joinTx({
      address: CONTRACT_ADDRESS,
      abi: OMEGA_LOTTERY_ABI,
      functionName: "joinLottery",
      args: [lotteryId],
      value: parseEther(amount),
    });
  };

  const requestWinner = async () => {
    return await requestTx({
      address: CONTRACT_ADDRESS,
      abi: OMEGA_LOTTERY_ABI,
      functionName: "requestWinner",
      args: [lotteryId],
    });
  };

  const createNewLottery = async (fee: string, start: number, end: number) => {
    return await createTx({
      address: CONTRACT_ADDRESS,
      abi: OMEGA_LOTTERY_ABI,
      functionName: "createLottery",
      args: [parseEther(fee), BigInt(start), BigInt(end)],
    });
  };

  // HISTORY — fetched directly via Alchemy's eth_getLogs to bypass thirdweb's
  // 1,000-block RPC limit and get the full history from contract deployment.
  const fetchHistory = useCallback(async () => {
    try {
      const response = await fetch(ALCHEMY_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "eth_getLogs",
          params: [
            {
              address: CONTRACT_ADDRESS,
              topics: [WINNER_PAID_TOPIC],
              fromBlock: CONTRACT_DEPLOY_BLOCK,
              toBlock: "latest",
            },
          ],
        }),
      });

      const json = await response.json();

      if (json.error) {
        console.warn("Alchemy getLogs error:", json.error);
        setWinnerHistory([]);
        return;
      }

      const rawLogs: any[] = json.result ?? [];

      const formattedHistory = rawLogs
        .map(log => {
          try {
            const decoded = decodeEventLog({
              abi: OMEGA_LOTTERY_ABI,
              eventName: "WinnerPaid",
              data: log.data,
              topics: log.topics,
            });
            const args = decoded.args as any;
            return {
              lotteryId: args.lotteryId,
              winnerAddress: args.winnerAddress,
              winnerPayout: args.winnerPayout,
              totalPot: args.totalPot,
            };
          } catch {
            return null;
          }
        })
        .filter(Boolean)
        .reverse();

      setWinnerHistory(formattedHistory);
    } catch (error) {
      console.warn("History fetch failed:", error);
      setWinnerHistory([]);
    }
  }, []);

  // OWNER CHECK — plain derived value, no useMemo.
  // useMemo was caching a stale `false` from before ownerAddress loaded.
  const isOwner =
    !isOwnerLoading &&
    !!connectedAddress &&
    !!ownerAddress &&
    connectedAddress.toLowerCase() === (ownerAddress as string).toLowerCase();

  useEffect(() => {
    fetchHistory();
  }, [fetchHistory]);

  const refetchAll = () => {
    refetchLottery();
    refetchPlayers();
  };

  return {
    lotteryData,
    players: (players as readonly string[]) || [],
    winnerHistory,
    treasuryBalance,
    isOwner,
    isOwnerLoading,
    isJoining,
    isRequesting,
    isCreating,
    joinLottery,
    requestWinner,
    createNewLottery,
    refetchHistory: fetchHistory,
    refetchAll,
  };
};
