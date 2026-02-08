// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30; // set the version of solidity that we are using

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract randomNumber is VRFConsumerBaseV2Plus {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus 
    {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists;    // whether a requestId exists
        uint256[] randomWords;  //   result from VRF
    }

    mapping(uint256 => RequestStatus) public s_requests; // requestId --> requestStatus

    uint256 public s_subscriptionId;    // subscription ID for VRF
    uint256[] public requestIds;        // list of past request IDs
    uint256 public lastRequestId;       // ID of the last request
    
    // specifies which gas lane to use (which network we are using. in this case, we are using Ethereum Sepolia)
    // check me out: https://docs.chain.link/vrf/v2-5/supported-networks#ethereum-sepolia-testnet
    bytes32 public keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    // specifies the maximum amount of gas that can be used on a VRF request
    // note: storing each word costs ~20,000 gas, so i've settled on 50k to be safe
    uint32 public callbackGasLimit = 100_000;

    // specifies the amount of words to retrieve per VRF request
    uint32 public numWords = 1;

    // default = 3, can set higher
    uint16 public requestConfirmations = 3;

    constructor(uint256 subscriptionId) VRFConsumerBaseV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B) 
    {
        s_subscriptionId = subscriptionId;
    } 
    
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override 
    {
        require(s_requests[_requestId].exists, "request not found");

        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;

        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(uint256 _requestId) external view returns (bool fulfilled, uint256[] memory randomWords)
    {
        require(s_requests[_requestId].exists, "request not found");

        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    function requestRandomWords(bool enableNativePayment) external onlyOwner returns (uint256 requestId)
    {
        // will revert if subscription is not set & funded
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest(
            {
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: enableNativePayment}))
            })
        );

        s_requests[requestId] = RequestStatus({randomWords: new uint256[](0), exists: true, fulfilled: false});
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }
}