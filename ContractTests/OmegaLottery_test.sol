// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "remix_tests.sol";
import "remix_accounts.sol";
import "Contracts/OmegaLottery.sol";

contract OmegaLotteryTest {

    OmegaLottery lottery;

    address acc0;
    address acc1;
    address acc2;

    uint256 constant ENTRY_FEE = 1 ether;

    function beforeAll() public {
        acc0 = TestsAccounts.getAccount(0); // owner
        acc1 = TestsAccounts.getAccount(1);
        acc2 = TestsAccounts.getAccount(2);

        lottery = new OmegaLottery(
            1,                  // dummy subscriptionId
            address(this),      // dummy VRF coordinator
            bytes32("keyhash")  // dummy keyhash
        );
    }

    /*//////////////////////////////////////////////////////////////
                            LOTTERY CREATION
    //////////////////////////////////////////////////////////////*/

    function testCreateLottery() public {
        uint256 start = block.timestamp + 10;
        uint256 end = block.timestamp + 100;

        uint256 lotteryId = lottery.createLottery(ENTRY_FEE, start, end);

        OmegaLottery.Lottery memory lotteryObj = lottery.getLottery(lotteryId);

        Assert.equal(lotteryId, 1, "Lottery ID should be 1");
        Assert.equal(lotteryObj.entryFee, ENTRY_FEE, "Entry Fee should == 1 ether");
    }

    function testInvalidTimeReverts() public {
        try lottery.createLottery(ENTRY_FEE, 100, 50) {
            Assert.ok(false, "Should have reverted");
        } catch {
            Assert.ok(true, "Reverted as expected");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            TREASURY
    //////////////////////////////////////////////////////////////*/

    function testSetTreasury() public {
        lottery.setTreasury(acc1);
        address treasury = lottery.getTreasuryAddress();
        Assert.equal(treasury, acc1, "Treasury not updated");
    }

    function testSetTreasuryRevertZero() public {
        try lottery.setTreasury(address(0)) {
            Assert.ok(false, "Should revert");
        } catch {
            Assert.ok(true, "Reverted as expected");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            JOIN LOTTERY
    //////////////////////////////////////////////////////////////*/

    function testJoinLottery() public payable {
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 500;

        uint256 id = lottery.createLottery(0, start, end);

        lottery.joinLottery{value: 0}(id);

        address[] memory players = lottery.getPlayersByLotteryId(id);

        Assert.equal(players.length, 1, "Player not added");
        Assert.equal(players[0], address(this), "Incorrect player");
    }

    function testJoinLotteryInsufficientFunds() public {
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 500;

        uint256 id = lottery.createLottery(ENTRY_FEE, start, end);

        try lottery.joinLottery{value: 0.5 ether}(id) {
            Assert.ok(false, "Should revert for insufficient funds");
        } catch {
            Assert.ok(true, "Reverted as expected");
        }
    }

    function testJoinBeforeStartReverts() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 200;

        uint256 id = lottery.createLottery(ENTRY_FEE, start, end);

        try lottery.joinLottery{value: ENTRY_FEE}(id) {
            Assert.ok(false, "Should revert before start");
        } catch {
            Assert.ok(true, "Reverted as expected");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CHECK UPKEEP
    //////////////////////////////////////////////////////////////*/

    function testCheckUpkeepFalseWhenNoPlayers() public {
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1;

        lottery.createLottery(ENTRY_FEE, start, end);

        (bool upkeep,) = lottery.checkUpkeep("");

        Assert.equal(upkeep, false, "Upkeep should be false without players");
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testLotteryStatusDefault() public {
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 100;

        uint256 id = lottery.createLottery(ENTRY_FEE, start, end);

        OmegaLottery.LotteryStatus status = lottery.getLotteryStatusById(id);

        Assert.equal(uint(status), 0, "Should be NOT_STARTED");
    }
}