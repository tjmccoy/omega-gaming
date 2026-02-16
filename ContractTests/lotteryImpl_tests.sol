// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "remix_tests.sol";
import "remix_accounts.sol";
import "../Contracts/lotteryImpl.sol";

contract OmegaLotteryTest {

    OmegaLottery lottery;
    address owner;
    address nonOwner;

    uint256 testEntryFee = 1 ether;
    uint256 testStartTime = 1000;
    uint256 testEndTime = 2000;

    function beforeAll() public {
        owner = address(this);
        nonOwner = TestsAccounts.getAccount(1);

        lottery = new OmegaLottery();   // deploy implementation
        lottery.initialize(owner);  // initialize smart contract
    }

    function createLotteryPropertyMappingTest() public {
        uint256 createdId = lottery.createLottery(testEntryFee, testStartTime, testEndTime);

        OmegaLottery.Lottery memory createdLottery = lottery.getLottery(createdId);

        Assert.equal(createdLottery.id, 1, "Lottery ID incorrect");
        Assert.equal(createdLottery.entryFee, testEntryFee, "Entry fee incorrect");
        Assert.equal(createdLottery.startTime, testStartTime, "Start time incorrect");
        Assert.equal(createdLottery.endTime, testEndTime, "End time incorrect");
        Assert.equal(uint(createdLottery.status), uint(OmegaLottery.LotteryStatus.NOT_STARTED), "Status should be NOT_STARTED");
        Assert.equal(createdLottery.totalPot, 0, "Total pot should be zero");
        Assert.equal(createdLottery.winner, address(0), "Winner should be empty");
    }
}