// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// IMPORTS
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// CONTRACT
contract OmegaLottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard
{
    using Strings for uint256;

    // Treasury Address
    address _treasuryAddress;
    uint256 _winnerCut;

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
    error RequestNotTimedOut();

    // Lottery Creation Automation
    uint256 public immutable _lotteryDuration;
    uint256 public immutable _defaultEntryFee;
    
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
        address indexed user,
        uint256 amount
    );

    event LotteryRefunded
    (
        uint256 indexed lotteryId,
        uint256 requestId
    );

    event LotteryStatusUpdated
    (
        uint256 indexed lotteryId,
        LotteryStatus lotteryStatus,
        uint256 timestamp
    );

    event RandomnessRequested
    (   
        uint256 indexed lotteryId,
        uint256 requestId
    );

    event RefundFailed
    (
        uint256 indexed lotteryId,
        address indexed user,
        uint256 amount
    );

    event RefundIssued
    (
        uint256 indexed lotteryId, 
        address indexed user, 
        uint256 amount
    );

    event WinnerCutUpdated
    (
        uint256 oldAmount,
        uint256 newAmount
    );

    event WinnerPaid
    (
        uint256 indexed lotteryId,
        address indexed user,
        uint256 payout,
        uint256 fee,
        uint256 totalPot
    );

    event WinnerSelected
    (
        uint256 indexed lotteryId,
        address indexed user
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
    mapping(uint256 => mapping(address => uint256)) internal activePlayerStakes;    // lotteryId => address => stake
    mapping(uint256 => mapping(address => uint256)) internal playerTickets;
    mapping(uint256 => uint256) internal totalTickets;

    // CHAINLINK VRF
    uint256 public s_subscriptionId;
    bytes32 public _keyHash;

    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    uint32 public numWords;

    uint256 allowableVrfDelay = 10 minutes;

    mapping(uint256 => uint256) public requestToLottery;    // requestId => lotteryId
    uint256 public lastRequestId;
    
    constructor(address treasuryAddress, uint256 subscriptionId, address vrfCoordinator, bytes32 keyHash, uint256 defaultEntryFee, uint256 lotteryDuration, uint256 winnerCut) VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        _treasuryAddress = treasuryAddress;

        s_subscriptionId = subscriptionId;
        _keyHash = keyHash;

        lotteryIdCounter = 1;
        callbackGasLimit = 1_000_000;
        requestConfirmations = 3;
        numWords = 1;

        _defaultEntryFee = defaultEntryFee;
        _lotteryDuration = lotteryDuration;
        _winnerCut = winnerCut;
        
        // immediately create first lottery
        _createLottery();
    }

    // JOIN LOTTERY
    function joinLottery(uint256 lotteryId) external payable 
    {
        Lottery storage lottery = lotteries[lotteryId];

        if (lotteryId == 0) revert LotteryDNE();
        if (block.timestamp < lottery.startTime) revert LotteryNotStarted();
        if (block.timestamp >= lottery.endTime) revert LotteryEnded();
        if (msg.value < lottery.entryFee) revert InsufficientFunds();
        if (lottery.status != LotteryStatus.OPEN) revert LotteryNotOpen();

        if (msg.value % lottery.entryFee != 0) revert InsufficientFunds();

        uint256 tickets = msg.value / lottery.entryFee;

        if (activePlayerStakes[lotteryId][msg.sender] == 0) {
            lotteryPlayers[lotteryId].push(msg.sender);
        }

        playerTickets[lotteryId][msg.sender] += tickets;
        totalTickets[lotteryId] += tickets;

        lottery.totalPot += msg.value;
        activePlayerStakes[lotteryId][msg.sender] += msg.value;

        emit LotteryEntered(lotteryId, msg.sender, msg.value);
    }
    
    // LOTTERY CREATION
    function _createLottery() internal 
    {
        uint256 lotteryId = lotteryIdCounter++;

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + _lotteryDuration;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = _defaultEntryFee;
        lottery.startTime = startTime;
        lottery.endTime = endTime;
        lottery.status = LotteryStatus.OPEN;

        emit LotteryCreated(lotteryId, _defaultEntryFee, startTime, endTime);
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
                keyHash: _keyHash,
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

        delete requestToLottery[requestId]; // keep storage clean and prevents replay attacks

        // INTERACTIONS
        _payWinner(lotteryId);
    }

    function _selectWinner(uint256 lotteryId) internal returns (address winnerAddress) 
    {
        Lottery storage lottery = lotteries[lotteryId];

        uint256 ticketCount = totalTickets[lotteryId];
        if (ticketCount == 0) revert NotEnoughPlayers();

        uint256 winningTicket = lottery.randomValue % ticketCount;
        uint256 cumulativeTickets = 0;

        address[] storage players = lotteryPlayers[lotteryId];

        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];

            cumulativeTickets += playerTickets[lotteryId][player];

            if (winningTicket < cumulativeTickets) {
                winnerAddress = player;
                lottery.winner = winnerAddress;

                emit WinnerSelected(lotteryId, winnerAddress);
                return winnerAddress;
            }
        }

        revert NotEnoughPlayers();
    }
    
    // PAY WINNER
    function _payWinner(uint256 lotteryId) internal nonReentrant
    {
        Lottery storage lottery = lotteries[lotteryId];
        address winnerAddress = lottery.winner;
        uint256 totalPot = lottery.totalPot;
        uint256 winnerCut = (totalPot * _winnerCut) / 100;
        uint256 treasuryCut = totalPot - winnerCut;

        (bool winnerCall, ) = winnerAddress.call{value: winnerCut}("");
        require(winnerCall, "Winner transfer failed");

        (bool treasuryCall, ) = _treasuryAddress.call{value: treasuryCut}("");
        require(treasuryCall, "Treasury transfer failed");

        emit WinnerPaid(lotteryId, winnerAddress, winnerCut, treasuryCut, totalPot);
        delete lotteryPlayers[lotteryId];

        lottery.status = LotteryStatus.RESOLVED;
        emit LotteryStatusUpdated(lotteryId, lottery.status, block.timestamp);

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

    function performUpkeep(bytes calldata performData) external override nonReentrant 
    {
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

        uint256 playerCount = totalTickets[lotteryId];

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

    // REFUND ALL
    function _refundAll(uint256 lotteryId) internal nonReentrant 
    {
        Lottery storage lottery = lotteries[lotteryId];
        uint256 requestId = lottery.requestId;

        // make sure lottery is stuck in DRAWING...
        if (lottery.status == LotteryStatus.OPEN) revert LotteryNotEnded();
        if (lottery.status == LotteryStatus.RESOLVED) revert LotteryEnded();
        if (block.timestamp < lottery.vrfRequestTime + allowableVrfDelay) revert RequestNotTimedOut();

        address[] storage players = lotteryPlayers[lotteryId];
        uint256 playerCount = players.length;

        for (uint256 i = 0; i < playerCount; i++) 
        {
            address player = players[i];
            uint256 stake = activePlayerStakes[lotteryId][player];

            if (stake > 0) {
                activePlayerStakes[lotteryId][player] = 0;

                (bool success, ) = player.call{value: stake}("");
                
                if (!success) 
                {
                    emit RefundFailed(lotteryId, player, stake);
                } else 
                {
                    emit RefundIssued(lotteryId, player, stake);
                }
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

    function setWinnerCut(uint256 winnerCut) external 
    {
        // note: this sets the % of the pot that the winner of the lottery will receive.
        // for example, winnerCut = 90 => winner takes 90%, treasury takes 10%
        //                        = 95 => winner takes 95%, treasury takes 5%
        uint256 oldCut = _winnerCut;
        _winnerCut = winnerCut;
        
        emit WinnerCutUpdated(oldCut, winnerCut);
    }

    // VIEW FUNCTIONS

    // Returns all VRF-related data for a given lottery so users can independently verify the randomness used to select the winner. 
    // Including:
    // requestId (to locate the fulfillment transaction and proof on-chain), 
    // randomValue, 
    // & the VRF configuration parameters used for the request.
    function getRandomnessDetails(uint256 lotteryId) external view returns (uint256 requestId, uint256 randomValue, bytes32 vrfKeyHash, uint256 subscriptionId)
    {
        Lottery memory lottery = lotteries[lotteryId];
        return (lottery.requestId, lottery.randomValue, _keyHash, s_subscriptionId);
    }

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

    function getStakeByUserAddress(uint256 lotteryId, address user) external view returns (uint256)
    {
        return activePlayerStakes[lotteryId][user];
    }

    function getWinnerCut() external view returns (uint256)
    {
        return _winnerCut;
    }
}