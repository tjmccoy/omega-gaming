// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// IMPORTS
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
    error RequestNotTimedOut();

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

    event LotteryStatusUpdated
    (
        uint256 indexed lotteryId,
        LotteryStatus lotteryStatus,
        uint256 timestamp
    );

    event LotteryEntered
    (
        uint256 indexed lotteryId,
        address indexed user,
        uint256 amount
    );

    event LotteryRefunded
    (
        uint256 indexed lotteryId,
        uint256 requestId
    );

    event WinnerSelected
    (
        uint256 indexed lotteryId,
        address indexed user
    );

    event WinnerPaid
    (
        uint256 indexed lotteryId,
        address indexed user,
        uint256 payout,
        uint256 fee,
        uint256 totalPot
    );

    event RefundIssued
    (
        uint256 indexed lotteryId, 
        address indexed user, 
        uint256 amount
    );

    event RandomnessRequested
    (   
        uint256 indexed lotteryId,
        uint256 requestId
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
        uint256 vrfRequestTime;
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

    uint256 allowableVrfDelay = 10 minutes;

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
        _createLottery();
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
    function _createLottery() internal {
        uint256 lotteryId = lotteryIdCounter++;

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + lotteryDuration;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = defaultEntryFee;
        lottery.startTime = startTime;
        lottery.endTime = endTime;
        lottery.status = LotteryStatus.OPEN;

        emit LotteryCreated(lotteryId, defaultEntryFee, startTime, endTime);
        emit LotteryStatusUpdated(lotteryId, lottery.status, block.timestamp);
    }

    // REQUEST WINNER
    function _requestWinner(uint256 lotteryId) internal
    {
        Lottery storage lottery = lotteries[lotteryId];

        // modify state
        lottery.status = LotteryStatus.DRAWING;
        emit LotteryStatusUpdated(lotteryId, lottery.status, block.timestamp);

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

        emit RandomnessRequested(lotteryId, requestId);

        requestToLottery[requestId] = lotteryId;
        lastRequestId = requestId;
        lottery.requestId = requestId;  // used to verify VRF response on-chain
        lottery.vrfRequestTime = block.timestamp;
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

        _selectWinner(lotteryId);

        lottery.status = LotteryStatus.RESOLVED;
        emit LotteryStatusUpdated(lotteryId, lottery.status, block.timestamp);

        delete requestToLottery[requestId]; // keep storage clean and prevents replay attacks

        // INTERACTIONS
        _payWinner(lotteryId);
    }

    // SELECT WINNER
    function _selectWinner(uint256 lotteryId) internal returns(address winnerAddress)
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
    function _payWinner(uint256 lotteryId) internal 
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

        _createLottery();
    }

    // CHAINLINK AUTOMATION
    function checkUpkeep(bytes calldata) external view override returns(bool upkeepNeeded, bytes memory performData)
    {
        uint256 currentLotteryId = lotteryIdCounter - 1;

        if (currentLotteryId == 0) { return (false, bytes("")); }

        Lottery memory lottery = lotteries[currentLotteryId];

        bool readyToDraw = (lottery.status == LotteryStatus.OPEN) && (block.timestamp >= lottery.endTime);
        bool vrfTimedOut = (lottery.status == LotteryStatus.DRAWING) && (block.timestamp >= lottery.vrfRequestTime + allowableVrfDelay);

        upkeepNeeded = (readyToDraw || vrfTimedOut);    // if true, performUpkeep fires off
        performData = abi.encode(currentLotteryId); // data to be used in performUpkeep
    }

    function performUpkeep(bytes calldata performData) external override nonReentrant {
        uint256 lotteryId = abi.decode(performData, (uint256));

        Lottery storage lottery = lotteries[lotteryId];

        if (lottery.status == LotteryStatus.DRAWING)
        {
            if(block.timestamp < lottery.vrfRequestTime + allowableVrfDelay)
            {
                revert("Upkeep not needed");
            } 
            
            _refundAll(lotteryId);
            return;
        }

        bool timePassed = block.timestamp >= lottery.endTime;
        bool isOpen = lottery.status == LotteryStatus.OPEN;

        if (!(timePassed && isOpen)) 
        {
            revert("Upkeep not needed");
        }

        uint256 playerCount = lotteryPlayers[lotteryId].length;

        // automatically rollover if no players joined the lottery
        if (playerCount == 0) {
            lottery.status = LotteryStatus.RESOLVED;
            emit LotteryStatusUpdated(lotteryId, lottery.status, block.timestamp);

            _createLottery();
            return;
        }

        // otherwise, request randomness
        _requestWinner(lotteryId);
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

    // REFUND ALL
    function _refundAll(uint256 lotteryId) internal {
        Lottery storage lottery = lotteries[lotteryId];
        uint256 requestId = lottery.requestId;

        // make sure lottery is stuck in DRAWING...
        if (lottery.status == LotteryStatus.OPEN) revert LotteryNotEnded();
        if (lottery.status == LotteryStatus.RESOLVED) revert LotteryEnded();
        if (block.timestamp < lottery.vrfRequestTime + allowableVrfDelay) revert RequestNotTimedOut();

        address[] storage players = lotteryPlayers[lotteryId];
        uint256 playerCount = players.length;

        for (uint256 i = 0; i < playerCount; i++) {
            address player = players[i];
            uint256 stake = playerStakes[lotteryId][player];

            if (stake > 0) {
                playerStakes[lotteryId][player] = 0;

                (bool success, ) = player.call{value: stake}("");
                require(success, "Refund failed");

                emit RefundIssued(lotteryId, player, stake);
            }
        }

        lottery.status = LotteryStatus.RESOLVED;
        lottery.totalPot = 0;

        emit LotteryStatusUpdated(lotteryId, lottery.status, block.timestamp);

        delete lotteryPlayers[lotteryId];
        delete requestToLottery[requestId];

        emit LotteryRefunded(lotteryId, requestId);

        // create the next lottery
        _createLottery();
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

    // TESTING ONLY
    function setSubscriptionId(uint256 _subscriptionId) external onlyOwner
    {
        s_subscriptionId = _subscriptionId;
    }
}