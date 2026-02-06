// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract lotteryV3 is
    VRFConsumerBaseV2Plus,
    ReentrancyGuard
{
    /* ========== LOTTERY STATE ========== */

    address payable[] public players;
    mapping(uint256 => address payable) public pastWinners;

    uint256 public lotteryId;

    /* ========== VRF CONFIG ========== */

    uint256 public subscriptionId;
    bytes32 public keyHash;

    uint32 public callbackGasLimit = 100_000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;

    uint256 public lastRequestId;
    bool public drawing;

    /* ========== EVENTS ========== */

    event Entered(address player);
    event RandomnessRequested(uint256 requestId);
    event WinnerPicked(uint256 lotteryId, address winner, uint256 amount);

    /* ========== RECEIVE ETH ========== */
    receive() external payable {}

    /* ========== CONSTRUCTOR ========== */

    // NOTE: this is hard coded for testing efficiency (TEMP)

    /*
    constructor(
        uint256 _subId,
        address _coordinator,
        bytes32 _keyHash
    )
        VRFConsumerBaseV2Plus(_coordinator)
    {
        subscriptionId = _subId;
        keyHash = _keyHash;
    }
    */
     constructor(
        /*
        uint256 _subId,
        address _coordinator,
        bytes32 _keyHash
        */
    )
        VRFConsumerBaseV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B)
    {
        subscriptionId = 5381939440800401583750118558724030775370857736705249184581988840504175043599;
        keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    }

    /* ========== ENTER LOTTERY ========== */

    function enter() external payable {
        require(!drawing, "Drawing in progress");
        require(msg.value >= 0.01 ether, "Min 0.01 ETH");

        players.push(payable(msg.sender));

        emit Entered(msg.sender);
    }

    /* ========== REQUEST RANDOMNESS ========== */
    // owner starts draw

    function chooseWinner() external onlyOwner returns (uint256 requestId) {
        require(players.length >= 2, "Need at least 2 players");
        require(!drawing, "Already drawing");

        drawing = true;

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        lastRequestId = requestId;

        emit RandomnessRequested(requestId);
    }

    /* ========== VRF CALLBACK (WINNER SELECTED HERE) ========== */

    function fulfillRandomWords(uint256 _requestId, uint256[] calldata randomWords) internal override nonReentrant
    {
        require(_requestId == lastRequestId, "Invalid request");
        require(players.length >= 2, "Not enough players");

        uint256 index = randomWords[0] % players.length;

        address payable winner = players[index];
        uint256 prize = address(this).balance;

        // Update state BEFORE external call
        pastWinners[lotteryId] = winner;
        lotteryId++;

        delete players;
        drawing = false;

        emit WinnerPicked(lotteryId - 1, winner, prize);

        // External call last
        (bool success, ) = winner.call{value: prize}("");
        require(success, "Transfer failed");
    }

    /* ========== VIEW HELPERS ========== */

    function getPlayers() external view returns (address payable[] memory) {
        return players;
    }

    function getPotBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getWinnerByLotteryId(uint256 id) external view returns (address payable)
    {
        return pastWinners[id];
    }

    function setCallbackGasLimit(uint32 gasLimit) external onlyOwner {
        callbackGasLimit = gasLimit;
    }

    function setConfirmations(uint16 conf) external onlyOwner {
        requestConfirmations = conf;
    }
}