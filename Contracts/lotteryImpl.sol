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
    error LotteryNotEnded();
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
        uint256 entryFee;   // expressed in WEI = To convert Wei to ETH, divide the number of Wei by 10^18
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
    // END CHAINLINK VRF

    constructor(/*uint256 subscriptionId, address vrfCoordinator, bytes32 _keyHash*/) VRFConsumerBaseV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B/*vrfCoordinator*/)
    {
        s_subscriptionId = 5381939440800401583750118558724030775370857736705249184581988840504175043599; //subscriptionId;
        keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; //_keyHash;
        lotteryIdCounter = 1;
        callbackGasLimit = 100_000;
        requestConfirmations = 3;
        numWords = 1;
    }

    // LOTTERY CREATION
    function createLottery(uint256 entryFee/*, uint256 startTime, uint256 endTime*/) external onlyOwner returns (uint256 lotteryId) 
    {
        // enforce rules
        //if (startTime >= endTime) revert InvalidEntryTime();

        lotteryId = lotteryIdCounter++;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = entryFee;
        lottery.startTime = block.timestamp;        // placeholder for testing
        lottery.endTime = block.timestamp + 300;    // placeholder for testing -> 5 min after it starts
        lottery.status = LotteryStatus.NOT_STARTED;

        emit LotteryCreated(lotteryId, entryFee, lottery.startTime, lottery.endTime);
    }

    // JOIN LOTTERY
    function joinLottery(uint256 lotteryId) external payable
    {
        Lottery storage lottery = lotteries[lotteryId];

        // enforce rules
        if (lotteryId == 0) revert LotteryDNE();
        if (block.timestamp < lottery.startTime) revert LotteryNotStarted();
        if (block.timestamp >= lottery.endTime) revert LotteryEnded();
        if (msg.value < lottery.entryFee) revert InsufficientFunds();
        
        // check lottery state
        if (lottery.status == LotteryStatus.NOT_STARTED) { lottery.status = LotteryStatus.OPEN; }
        if (lottery.status != LotteryStatus.OPEN) revert LotteryNotOpen();

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
        //if (block.timestamp < lottery.endTime) revert LotteryNotEnded();
        if (lottery.status != LotteryStatus.OPEN) revert LotteryNotOpen();

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
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
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

        //require(lottery.status == LotteryStatus.DRAWING, "Not Drawing"); dont think i need this
 
        uint256 numPlayers = lotteryPlayers[lotteryId].length;
        if (numPlayers == 0) revert NotEnoughPlayers();

        uint256 winnerIndex = randomWords[0] % numPlayers;
        address winnerAddress = lotteryPlayers[lotteryId][winnerIndex];

        lottery.winner = winnerAddress;

        // basic payout logic -> to be iterated upon
        (bool success, ) = winnerAddress.call{value: lottery.totalPot}("");
        require(success, "Transfer failed");

        // update lottery state
        lotteries[lotteryId].status = LotteryStatus.RESOLVED;
    }

    // VIEW FUNCTIONS (for debugging/development)
    function getLottery(uint256 lotteryId) external view returns (Lottery memory)
    {
        return lotteries[lotteryId];
    }

    function getLotteryStatusById(uint256 lotteryId) external view returns (LotteryStatus status)
    {
        return lotteries[lotteryId].status;
    }
}