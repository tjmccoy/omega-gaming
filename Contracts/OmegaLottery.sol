// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// IMPORTS
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

// CONTRACT
contract OmegaLottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface
{
    using Strings for uint256;

    // Treasury Address
    address _treasuryAddress;

    // ERRORS
    error InsufficientFunds();
    error InvalidEntryTime();
    error InvalidTreasuryAddress();

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

    event WinnerSelected
    (
        uint256 indexed lotteryId,
        address indexed winnerAddress
    );

    event WinnerPaid
    (
        uint256 indexed lotteryId,
        address indexed winnerAddress,
        uint256 winnerPayout,
        uint256 treasuryFee,
        uint256 totalPot
    );

    event TreasuryUpdated
    (
        address oldTreasury,
        address newTreasury
    );

    // TYPES
    enum LotteryStatus 
    {
        NOT_STARTED,    // 0
        OPEN,           // 1
        CLOSED,         // 2
        DRAWING,        // 3
        RESOLVED        // 4
    }

    struct Lottery 
    {
        uint256 id;
        uint256 entryFee;   // expressed in WEI = To convert Wei to ETH, divide the number of Wei by 10^18
        uint256 startTime;
        uint256 endTime;
        uint256 totalPot;
        LotteryStatus status;
        address winner;     // empty until lottery resolves
        uint256 randomValue;    // store VRF response on chain so that it is auditable
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
    
    constructor(uint256 subscriptionId, address vrfCoordinator, bytes32 _keyHash) VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        s_subscriptionId = subscriptionId;
        keyHash = _keyHash;

        lotteryIdCounter = 1;
        callbackGasLimit = 200_000;
        requestConfirmations = 3;
        numWords = 1;
    }
    
    // LOTTERY CREATION
    function createLottery(uint256 entryFee, uint256 startTime, uint256 endTime) external onlyOwner returns (uint256 lotteryId) 
    {
        // enforce rules
        if (startTime >= endTime) revert InvalidEntryTime();

        lotteryId = lotteryIdCounter++;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = entryFee;
        lottery.startTime = startTime;
        lottery.endTime = endTime;
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
    function _requestWinner(uint256 lotteryId) internal returns(uint256 requestId)
    {
        Lottery storage lottery = lotteries[lotteryId];

        // enforce rules
        if (block.timestamp < lottery.endTime) revert LotteryNotEnded();
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
        uint256 lotteryId = requestToLottery[requestId];    // get the lotteryId by the requestId
        Lottery storage lottery = lotteries[lotteryId];     // lottery object

        // CHECKS
        require(lottery.status == LotteryStatus.DRAWING, "Invalid state");

        // EFFECTS
        uint256 randomValue = randomWords[0];
        lottery.randomValue = randomValue;

        selectWinner(lotteryId);

        lottery.status = LotteryStatus.RESOLVED;
        delete requestToLottery[requestId]; // keep storage clean and prevents replay attacks

        // INTERACTIONS
        payWinner(lotteryId);
    }

    // SELECT WINNER
    function selectWinner(uint256 lotteryId) internal returns(address winnerAddress)
    {
        Lottery storage lottery = lotteries[lotteryId];     // lottery object

        uint256 numPlayers = lotteryPlayers[lotteryId].length; // store number of players
        if (numPlayers == 0) revert NotEnoughPlayers(); // make sure we have >= 1 player

        uint256 winnerIndex = lottery.randomValue % numPlayers;
        winnerAddress = lotteryPlayers[lotteryId][winnerIndex];

        lottery.winner = winnerAddress;

        emit WinnerSelected(lotteryId, winnerAddress);
    }
    
    // PAY WINNER
    function payWinner(uint256 lotteryId) internal 
    {
        Lottery storage lottery = lotteries[lotteryId];
        address winnerAddress = lottery.winner;
        uint256 totalPot = lottery.totalPot;
        uint256 winnerCut = (totalPot * 98) / 100;
        uint256 treasuryCut = totalPot - winnerCut;

        (bool winnerCall, ) = winnerAddress.call{value: winnerCut}("");
        require(winnerCall, "Winner transfer failed");

        (bool treasuryCall, ) = _treasuryAddress.call{value: treasuryCut}("");
        require(treasuryCall, "Treasury transfer failed");

        emit WinnerPaid(lotteryId, winnerAddress, winnerCut, treasuryCut, totalPot);
    }

    // REQUEST WINNER
    function requestWinner(uint256 lotteryId) external onlyOwner returns(uint256)
    {
        return _requestWinner(lotteryId);
    }

    // CHAINLINK AUTOMATION
    function checkUpkeep(bytes calldata) external view override returns(bool upkeepNeeded, bytes memory performData)
    {
        uint256 currentLotteryId = lotteryIdCounter - 1;

        if (currentLotteryId == 0) { return (false, bytes("")); }

        Lottery memory lottery = lotteries[currentLotteryId];

        bool timePassed = block.timestamp >= lottery.endTime;
        bool isOpen = lottery.status == LotteryStatus.OPEN;
        bool hasPlayers = lotteryPlayers[currentLotteryId].length > 0;

        upkeepNeeded = (timePassed && isOpen && hasPlayers);    // if true, performUpkeep fires off
        performData = abi.encode(currentLotteryId);             // data to be used in performUpkeep
    }

    function performUpkeep(bytes calldata performData) external override
    {
        uint256 lotteryId = abi.decode(performData, (uint256));

        Lottery storage lottery = lotteries[lotteryId];

        bool timePassed = block.timestamp >= lottery.endTime;
        bool isOpen = lottery.status == LotteryStatus.OPEN;
        bool hasPlayers = lotteryPlayers[lotteryId].length > 0;

        if (!(timePassed && isOpen && hasPlayers)) {
            revert("Upkeep not needed");
        }

        _requestWinner(lotteryId);
    }
    
    // TREASURY
    function setTreasury(address newTreasury) external onlyOwner 
    {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();

        emit TreasuryUpdated(_treasuryAddress, newTreasury);
        _treasuryAddress = newTreasury;
    }

    // VIEW FUNCTIONS (for debugging/development)
    function getLottery(uint256 lotteryId) external view returns (Lottery memory lottery)
    {
        return lotteries[lotteryId];
    }

    function getLotteryStatusById(uint256 lotteryId) external view returns (LotteryStatus status)
    {
        return lotteries[lotteryId].status;
    }

    function getTreasuryAddress() external view returns (address)
    {
        return _treasuryAddress;
    }

    function getPlayersByLotteryId(uint256 lotteryId) external view returns (address[] memory players)
    {
        return lotteryPlayers[lotteryId];
    }
}