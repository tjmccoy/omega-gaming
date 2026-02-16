// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// IMPORTS
import {Initializable}      from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable}    from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// CONTRACT
contract OmegaLottery is Initializable, UUPSUpgradeable, OwnableUpgradeable
{
    using Strings for uint256;

    // ERRORS
    error InvalidEntryTime();

   // EVENTS
    event LotteryCreated
    (
        uint256 indexed lotteryId,
        uint256 entryFee,
        uint256 startTime,
        uint256 endTime
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
    uint256[45] private __gap;  // reserved storage gap for future updates

    
    // INITIALIZER -> runs exactly once (one-time setup, part of UUPS)
    function initialize(address initialOwner) external initializer 
    {
        __Ownable_init(initialOwner);   // sets contract owner
        __UUPSUpgradeable_init();

        lotteryIdCounter = 1;
    }

    // LOTTERY CREATION
    function createLottery(uint256 entryFee, uint256 startTime, uint256 endTime) external onlyOwner returns (uint256 lotteryId) 
    {
        if (startTime >= endTime) revert InvalidEntryTime();

        lotteryId = lotteryIdCounter++;

        Lottery storage lottery = lotteries[lotteryId];
        lottery.id = lotteryId;
        lottery.entryFee = entryFee;
        lottery.startTime = startTime;
        lottery.endTime = endTime;
        lottery.status = LotteryStatus.NOT_STARTED;

        emit LotteryCreated
        (
            lotteryId,
            entryFee,
            startTime,
            endTime
        );
    }

    // JOIN LOTTERY
    function joinLottery(uint256 lotteryId) external payable
    {
        Lottery storage lottery = lotteries[lotteryId];

        require(msg.value >=  lottery.entryFee, string.concat("Entry fee (eth): ", lottery.entryFee.toString()));
        require(lottery.status == LotteryStatus.OPEN, "Lottery is not yet joinable.");

        lotteryPlayers[lotteryId].push(msg.sender);
    }

    // VIEW FUNCTIONS (for debugging/development)
    function getLottery(uint256 lotteryId) external view returns (Lottery memory)
    {
        return lotteries[lotteryId];
    }

    // UUPS
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
