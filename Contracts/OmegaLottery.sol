// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// IMPORTS
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

// CONTRACT
contract OmegaLottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard
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

    // Lottery Creation Automation
    uint256 public immutable lotteryDuration;
    uint256 public immutable defaultEntryFee;
    
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

    event RefundedPlayer
    (
        uint256 indexed lotteryId, 
        address indexed player, 
        uint256 amount
    );

    event LotteryStatusUpdated
    (
        uint256 indexed lotteryId,
        LotteryStatus lotteryStatus
    );

    // TYPES
    enum LotteryStatus 
    {
        OPEN,           // 0
        DRAWING,        // 1
        RESOLVED        // 2
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
        uint256 requestId;
    }

    // STORAGE
    uint256 public lotteryIdCounter;    // incrementing lottery ID. starts @ 1
    mapping(uint256 => Lottery) internal lotteries; // lotteryId => Lottery 
    mapping(uint256 => address[]) internal lotteryPlayers;  // lotteryId => players
    mapping(uint256 => mapping(address => uint256)) internal playerStakes;

    // CHAINLINK VRF
    uint256 public s_subscriptionId;
    bytes32 public keyHash;

    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    uint32 public numWords;

    mapping(uint256 => uint256) public requestToLottery;    // requestId => lotteryId
    uint256 public lastRequestId;
    
    constructor(address treasuryAddress, uint256 subscriptionId, address vrfCoordinator, bytes32 _keyHash, uint256 _defaultEntryFee, uint256 _lotteryDuration) VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        _treasuryAddress = treasuryAddress;

        s_subscriptionId = subscriptionId;
        keyHash = _keyHash;

        lotteryIdCounter = 1;
        callbackGasLimit = 200_000;
        requestConfirmations = 3;
        numWords = 1;

        defaultEntryFee = _defaultEntryFee;
        lotteryDuration = _lotteryDuration;

        // immediately create first lottery
        _createLotteryWithDuration();
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
        if (lottery.status != LotteryStatus.OPEN) revert LotteryNotOpen();

        // update lottery state
        lotteryPlayers[lotteryId].push(msg.sender);
        lottery.totalPot += msg.value;

        // keep track of how much each player deposits in case of refund
        playerStakes[lotteryId][msg.sender] += msg.value;

        // send event to frontend
        emit LotteryEntered(lotteryId, msg.sender, msg.value);
    }
    
    // LOTTERY CREATION
    function _createLotteryWithDuration() internal {
        uint256 lotteryId = lotteryIdCounter++;

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + lotteryDuration;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = defaultEntryFee;
        lottery.startTime = startTime;
        lottery.endTime = endTime;
        lottery.status = LotteryStatus.OPEN;

        emit LotteryStatusUpdated(lotteryId, lottery.status);
        emit LotteryCreated(lotteryId, defaultEntryFee, startTime, endTime);
    }

    // REQUEST WINNER
    function _requestWinner(uint256 lotteryId) internal
    {
        Lottery storage lottery = lotteries[lotteryId];

        // modify state
        lottery.status = LotteryStatus.DRAWING;
        emit LotteryStatusUpdated(lotteryId, lottery.status);

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
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
        lottery.requestId = requestId;  // used to verify VRF response on-chain
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
        emit LotteryStatusUpdated(lotteryId, lottery.status);

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
        delete lotteryPlayers[lotteryId];

        _createLotteryWithDuration();
    }

    // CHAINLINK AUTOMATION
    function checkUpkeep(bytes calldata) external view override returns(bool upkeepNeeded, bytes memory performData)
    {
        uint256 currentLotteryId = lotteryIdCounter - 1;

        if (currentLotteryId == 0) { return (false, bytes("")); }

        Lottery memory lottery = lotteries[currentLotteryId];

        bool timePassed = block.timestamp >= lottery.endTime;
        bool isOpen = lottery.status == LotteryStatus.OPEN;

        upkeepNeeded = (timePassed && isOpen);    // if true, performUpkeep fires off
        performData = abi.encode(currentLotteryId); // data to be used in performUpkeep
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 lotteryId = abi.decode(performData, (uint256));

        Lottery storage lottery = lotteries[lotteryId];

        bool timePassed = block.timestamp >= lottery.endTime;
        bool isOpen = lottery.status == LotteryStatus.OPEN;

        if (!(timePassed && isOpen)) {
            revert("Upkeep not needed");
        }

        uint256 playerCount = lotteryPlayers[lotteryId].length;

        // automatically rollover if no players joined the lottery
        if (playerCount == 0) {
            lottery.status = LotteryStatus.RESOLVED;

            _createLotteryWithDuration();
            return;
        }

        // otherwise, request randomness
        _requestWinner(lotteryId);
    }
    
    // TREASURY
    function setTreasury(address newTreasury) external onlyOwner 
    {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();

        emit TreasuryUpdated(_treasuryAddress, newTreasury);
        _treasuryAddress = newTreasury;
    }

    // VIEW FUNCTIONS
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
    
    // Returns all VRF-related data for a given lottery so users can independently verify the randomness used to select the winner. 
    // Including:
    // requestId (to locate the fulfillment transaction and proof on-chain), 
    // randomValue, 
    // & the VRF configuration parameters used for the request.
    function getRandomnessDetails(uint256 lotteryId) external view returns (uint256 requestId, uint256 randomValue, bytes32 vrfKeyHash, uint256 subscriptionId)
    {
        Lottery memory lottery = lotteries[lotteryId];
        return (lottery.requestId, lottery.randomValue, keyHash, s_subscriptionId);
    }

    // ADMIN INTERVENTION (WIP)
    // REFUND ALL
    function refundAll(uint256 lotteryId) external onlyOwner nonReentrant {
        Lottery storage lottery = lotteries[lotteryId];

        if (lottery.status == LotteryStatus.OPEN) revert LotteryNotEnded();
        if (lottery.status == LotteryStatus.RESOLVED) revert LotteryEnded();

        address[] storage players = lotteryPlayers[lotteryId];
        uint256 playerCount = players.length;

        require(playerCount > 0, "No players to refund");

        lottery.status = LotteryStatus.RESOLVED; // prevent reentry

        for (uint256 i = 0; i < playerCount; i++) {
            address player = players[i];
            uint256 stake = playerStakes[lotteryId][player];

            if (stake > 0) {
                playerStakes[lotteryId][player] = 0;

                (bool success, ) = player.call{value: stake}("");
                require(success, "Refund failed");

                emit RefundedPlayer(lotteryId, player, stake);
            }
        }

        delete lotteryPlayers[lotteryId];
        lottery.totalPot = 0;

        //_createLotteryWithDuration();
    }
}