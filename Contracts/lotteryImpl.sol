// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// IMPORTS
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

// CONTRACT
contract OmegaLottery is VRFConsumerBaseV2Plus
{
    using Strings for uint256;

    // ERRORS
    error InsufficientFunds();
    error InvalidEntryTime();

    error LotteryDNE();
    error LotteryEnded();
    error LotteryNotOpen();
    error LotteryNotStarted();

    error NotEnoughPlayers();
    
   // EVENTS
    event LotteryCreated
    (
        uint256 indexed lotteryId,
        uint256 entryFee,
        uint256 startTime,
        uint256 endTime
    );

    event LotteryEntered
    (
        uint256 indexed lotteryId,
        address indexed playerAddress,
        uint256 playerStake
    );

    // TYPES
    enum LotteryStatus 
    {
        NOT_STARTED,
        OPEN,
        CLOSED,
        DRAWING,
        RESOLVED
    }

    struct Lottery 
    {
        uint256 id;
        uint256 entryFee;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPot;
        LotteryStatus status;
        address winner; // empty until lottery resolves
    }

    // STORAGE
    uint256 public lotteryIdCounter;    // incrementing lottery ID. starts @ 1
    mapping(uint256 => Lottery) internal lotteries; // lotteryId => Lottery 
    mapping(uint256 => address[]) internal lotteryPlayers;  // lotteryId => players

    // CHAINLINK VRF
    uint256 public s_subscriptionId;
    bytes32 public keyHash;

    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    uint32 public numWords;

    mapping(uint256 => uint256) public requestToLottery;    // requestId => lotteryId

    uint256 public lastRequestId;

    constructor( uint256 subscriptionId, address vrfCoordinator, bytes32 _keyHash) VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        s_subscriptionId = subscriptionId;
        keyHash = _keyHash;
        lotteryIdCounter = 1;
    }

    // LOTTERY CREATION
    function createLottery(uint256 entryFee, uint256 startTime, uint256 endTime) external onlyOwner returns (uint256 lotteryId) 
    {
        // enforce rules
        //if (startTime >= endTime) revert InvalidEntryTime();

        lotteryId = lotteryIdCounter++;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = entryFee;
        lottery.startTime = startTime;
        lottery.endTime = endTime;
        lottery.status = LotteryStatus.NOT_STARTED;

        emit LotteryCreated(lotteryId, entryFee, startTime, endTime);
    }

    // JOIN LOTTERY
    function joinLottery(uint256 lotteryId) external payable
    {
        Lottery storage lottery = lotteries[lotteryId];

        // enforce rules
        //if (lotteryId == 0) revert LotteryDNE();
        //if (block.timestamp < lottery.startTime) revert LotteryNotStarted();
        //if (block.timestamp >= lottery.endTime) revert LotteryEnded();
        //if (msg.value < lottery.entryFee) revert InsufficientFunds();
        
        // check lottery state
        //if (lottery.status == LotteryStatus.NOT_STARTED) { lottery.status = LotteryStatus.OPEN; }
        //if (lottery.status != LotteryStatus.OPEN) revert LotteryNotOpen();

        // update lottery state
        lotteryPlayers[lotteryId].push(msg.sender);
        lottery.totalPot += msg.value;

        // send event to frontend
        emit LotteryEntered(lotteryId, msg.sender, msg.value);
    }

    // REQUEST WINNER
    function requestWinner(uint256 lotteryId) external onlyOwner returns(uint256 requestId)
    {
        Lottery storage lottery = lotteries[lotteryId];

        // enforce rules
        //if (block.timestamp < lottery.endTime) revert LotteryNotStarted();
        //if (lottery.status != LotteryStatus.OPEN) revert LotteryNotOpen();

        // modify state
        lottery.status = LotteryStatus.DRAWING;

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest(
            {
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );

        requestToLottery[requestId] = lotteryId;
        lastRequestId = requestId;

        return requestId;
    }

    // FULFILL RANDOM WORDS
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override 
    {
        uint256 lotteryId = requestToLottery[requestId];
        Lottery storage lottery = lotteries[lotteryId];

        require(lottery.status == LotteryStatus.DRAWING, "Not Drawing");

        uint256 numPlayers = lotteryPlayers[lotteryId].length;
        if (numPlayers == 0) revert NotEnoughPlayers();

        uint256 winnerIndex = randomWords[0] % numPlayers;
        address winnerAddress = lotteryPlayers[lotteryId][winnerIndex];

        lottery.winner = winnerAddress;
        lottery.status = LotteryStatus.RESOLVED;

        // basic payout logic -> to be iterated upon
        (bool success, ) = winnerAddress.call{value: lottery.totalPot}("");
        require(success, "Transfer failed");

        // update lottery state
        lotteries[lotteryId].status = LotteryStatus.CLOSED;
    }

    // VIEW FUNCTIONS (for debugging/development)
    function getLottery(uint256 lotteryId) external view returns (Lottery memory)
    {
        return lotteries[lotteryId];
    }
}