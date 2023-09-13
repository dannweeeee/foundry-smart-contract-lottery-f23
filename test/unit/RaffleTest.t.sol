//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdCheats} from "lib/forge-std/src/StdCheats.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitialisesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // enum is a type, so we can use it as a return type
    }

    //////////////////
    // Enter Raffle //
    //////////////////

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    // Testing Event Functions
    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        // expectEmit function
        vm.expectEmit(true, false, false, false, address(raffle)); // checkTopic1, checkTopic2, checkTopic3, checkData (unindexed parameter), address of emitter
        // we emit the event we expect to see
        emit EnteredRaffle(PLAYER);
        // we perform the function call
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // can set block time with vm.warp
        // can set block number with vm.roll
        vm.warp(block.timestamp + interval + 1); // + 1 to make sure we are absolutely over the interval
        vm.roll(block.number + 1); // to do an extra block
        raffle.performUpkeep(""); // the vrfCoordinator contract is expecting our call

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector); // the next real call will revert
        vm.prank(PLAYER); // the next real call will be pretended to be with the player
        raffle.enterRaffle{value: entranceFee}();
    }

    //////////////////
    // Check Upkeep //
    //////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1); // + 1 to make sure we are absolutely over the interval
        vm.roll(block.number + 1); // to do an extra block

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(!upkeepNeeded); // assert not upkeepNeeded (false)
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // + 1 to make sure we are absolutely over the interval
        vm.roll(block.number + 1); // to do an extra block
        raffle.performUpkeep(""); // we will be in the CALCULATING state

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(!upkeepNeeded); // assert not upkeepNeeded (false)
    }

    // testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed (implemented and passes)
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1); // - 1 to make sure we are absolutely under the interval
        vm.roll(block.number + 1); // to do an extra block
        raffle.checkUpKeep(""); // we will be in the OPEN state

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(!upkeepNeeded); // assert not upkeepNeeded (false)
    }

    // testCheckUpkeepReturnsTrueWhenParametersAreGood
    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // + 1 to make sure we are absolutely over the interval
        vm.roll(block.number + 1); // to do an extra block

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(upkeepNeeded); // assert upkeepNeeded (true)
    }

    ////////////////////
    // Perform Upkeep //
    ////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // + 1 to make sure we are absolutely over the interval
        vm.roll(block.number + 1); // to do an extra block

        // Act / Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public skipFork {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        ); // need to make sure it is also reverting its parameters
        raffle.performUpkeep(""); // expect this to fail with the following parameters in the revert message
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // + 1 to make sure we are absolutely over the interval
        vm.roll(block.number + 1); // to do an extra block
        _;
    }

    // What if i need to test using the output of an event?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange -> is in the modifier already
        // Act -> we want to capture this RequestedRaffleWinner emit requestId
        vm.recordLogs(); // automatically save all the log outputs into a data structure that we can view
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); // get all the logs that were emitted
        // figure out where in this array, our requested raffleWinner is being emitted
        // we know that the event RequestedRaffleWinner is the second event emitted
        bytes32 requestId = entries[1].topics[1]; // all logs are recorded in bytes32 in foundry
        // entries[0] is the event in the vrfCoordinatorMock contract, entries[1] is the second event which is RequestedRaffleWinner
        // topic[0] refers to the entire event

        Raffle.RaffleState rState = raffle.getRaffleState();

        // Assert
        assert(uint256(requestId) > 0); // this will not hold true
        assert(uint256(rState) == 1);
    }

    ////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier skipFork() {
        // only run on local chain Anvil and not when we are fork testing
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledOnlyAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        // Arrange -> try to have the mock call fulfillRandomWords and fail
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords( // we should expect this to fail because no matter what, performUpkeep has to be called first
            randomRequestId, // foundry will create a random number for this, and call this test many times with many random numbers
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        // this will be our full test
        // we will enter the lottery a couple of times
        // we will move the time up so that checkUpkeep returns true
        // we will performUpkeep
        // we will kick off a request to return a random number
        // we will pretend to be the chainlinkvrf and respond and call fulfillRandomWords (on our mock chain we dont have chainlink vrf, but on actual chain, our testFulfillRandomWordsCanOnlyBeCalledOnlyAfterPerformUpkeep wouldnt work because we are not the vrfCoordinatorV2Mock)

        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1; // since we have the modifier, we already have 1 person who entered the raffle
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); // address(1) then address(2) so on and so forth
            hoax(player, STARTING_USER_BALANCE); // hoax sets up a prank and gives some ether
            raffle.enterRaffle{value: entranceFee}(); // entering the raffle
        }

        uint256 previousTimeStamp = raffle.getLastTimeStamp(); // we want to record the previous timestamp
        uint256 prize = entranceFee * (additionalEntrants + 1); // we want to record the total prize

        vm.recordLogs(); // record the logs
        raffle.performUpkeep(""); // call performUpkeep to kick off the request to the chainlink nodes
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        // pretend to be chainlinkvrf to get random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords( // we should expect this to fail because no matter what, performUpkeep has to be called first
            uint256(requestId), // cast bytes32 into uint256 because Vm.log casts everything into bytes32
            address(raffle)
        );

        // Assert (not best practice to have so many asserts in one test, best is to have 1 assert per test)
        assert(uint256(raffle.getRaffleState()) == 0); // check that the raffle state is OPEN (because it is resetted to be OPEN)
        assert(raffle.getRecentWinner() != address(0)); // we check to see if a winner was picked
        assert(raffle.getLengthOfPlayers() == 0); // we check to see if the array was reset to 0
        assert(previousTimeStamp < raffle.getLastTimeStamp()); // we check to see if the block timing was updated
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        ); // we check to see if the winner got the STARTING_USER_BALANCE + prize - entranceFee
    }
}
