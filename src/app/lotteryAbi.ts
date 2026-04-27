export const LOTTERY_ABI = [
  {
    inputs: [{ internalType: "uint256", name: "lotteryId", type: "uint256" }],
    name: "getLottery",
    outputs: [
      {
        components: [
          { name: "id", type: "uint256" },
          { name: "entryFee", type: "uint256" },
          { name: "startTime", type: "uint256" },
          { name: "endTime", type: "uint256" },
          { name: "totalPot", type: "uint256" },
          { name: "status", type: "uint8" },
          { name: "winner", type: "address" },
          { name: "randomValue", type: "uint256" },
        ],
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;