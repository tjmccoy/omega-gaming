// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;    // set solidity version

contract Lottery {

    address public owner;   // the person who deployed the contract
    address payable[] public players;   // array of players who have entered the lottery (NOTE: we use the payable modifier for any addresses who can receive payment/eth)
    uint public lotteryId;
    mapping (uint => address payable) public pastWinners;
    
    constructor()
    {
        owner = msg.sender;   // owner state variable = address of the deployer of the contract
        lotteryId = 0;
    }

    function enter() public payable
    {
        require(msg.value > .01 ether); // enforces that the user is betting > .01 eth

        players.push(payable(msg.sender));   // in this context, msg.sender is the address of the person who invoked this function
    }

    function getRandomNumber() public view returns (uint)
    {
        // pseudo-random number generation using the keccak256 hashing algorithm
            // note: abi.encodePacked is the easiest way to concatenate two strings
        return uint(keccak256(abi.encodePacked(owner, block.timestamp)));
    }

    function chooseWinner() public ownerOnly 
    {
        uint index = getRandomNumber() % players.length;
        
        (bool success, ) = players[index].call{value: address(this).balance}("");
        require(success, "Transfer failed.");

        // increment lotteryId and pastWinners log (NOTE: make sure you update state AFTER eth transfers to protect against re-entry attacks)
        pastWinners[lotteryId] = players[index];
        lotteryId++;

        // reset the state of the contract by creating a new players array of length 0
        players = new address payable[](0);
    }

    // helper functions:
    function getPotBalance() public view returns (uint) {
        return address(this).balance;
    }
    function getPlayers() public view returns (address payable[] memory)
    {
        return players;
    }
    function getWinnerByLotteryId(uint gameId) public view returns (address payable)
    {
        return pastWinners[gameId];
    }

    // custom modifier(s)
    modifier ownerOnly() 
    {
        require(msg.sender == owner);
        _;  // this says: run whatever code follows the modifier
    }
}