//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contract
 * @author Dann Wee
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is
    VRFConsumerBaseV2 // whenever we inherit from a contract, we need to pass in the constructor arguments
{
    /** Errors */
    error Raffle__NotEnoughEthSent(); // name the error with a prefix with 2 underscores to avoid conflict with other contracts
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    ); // if can be RaffleState raffleState or uint256 raffleState (because enum have indexes)

    /** Type Declarations */
    enum RaffleState {
        OPEN, // index 0
        CALCULATING // index 1
        // index 2
        // index 3
    }

    /** State Variables */
    // Constant Variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // number of block confirmations
    uint32 private constant NUM_WORDS = 1; // number of random numbers

    // Immutable Variables
    uint256 private immutable i_entranceFee; // we don't want to bother editing entrance fee
    // @dev Duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; // Chainlink VRF Coordinator Address
    bytes32 private immutable i_gasLane; // Chainlink VRF KeyHash
    uint64 private immutable i_subscriptionId; // Chainlink VRF Subscription ID
    uint32 private immutable i_callbackGasLimit; // Chainlink VRF Callback Gas Limit

    // Storage Variables
    // what data structure should we use to keep track of all the players? --> Dynamic Arrays
    address payable[] private s_players; // payable address so that we can pay all these players one they enter this lottery
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    )
        VRFConsumerBaseV2(vrfCoordinator) // VRFConsumerBaseV2 is a contract that has a constructor
    {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp; // when we launch this contract, we will basically start the clock
    }

    // Makes sure people buy their tickets with the entrance fee and adds them to the players array
    function enterRaffle() external payable {
        // external is more gas efficient, and we probably don't have any function in this contract that calls it && ticket price being native curency, so function need to be payable
        // require(msg.value >= i_entranceFee, "Not enough ETH sent"); // require statements are less gas efficient than errors
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender)); // allow the address to get native tokens
        // 1. Makes migration easier
        // 2. Makes frontend "indexing" easier

        // anytime we update storage, we want to emit events
        emit EnteredRaffle(msg.sender);
    }

    //When is the winner supposed to be picked?
    /**
     * @dev This is the function that the Chainlink Automation Nodes call to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. THe time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK
     */
    // Therefore, boolean returns true if all conditions are met, otherwise it will return false
    function checkUpKeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval; // block.timestamp is a global variable that is in seconds
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // return the bytes memory as empty
    }

    // Chainlink Nodes in a decentralised context will call this performUpKeep function which will kick off a request to the Chainlink VRF
    // 1. Get a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpKeep(""); // check if it is time to do an UpKeep
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        // check to see if enough time has passed

        // e.g. 1000 - 500 = 500 but interval was 600 seconds
        // e.g. 1200 - 500 = 700 which is more than 600 seconds interval

        // Before we send the request, we are going to set the Raffle State to CALCULATING
        s_raffleState = RaffleState.CALCULATING;
        // 1. Request the RNG
        // 2. Get the random number
        i_vrfCoordinator.requestRandomWords( // the Chainlink VRF Coordinator has this function requestRandomWords()
            i_gasLane, // gas lane
            i_subscriptionId, // id that will be funded with LINK
            REQUEST_CONFIRMATIONS, // number of block confirmations
            i_callbackGasLimit, // make sure we don't overspend
            NUM_WORDS // number of random numbers
        );
    }

    // Wait a while, once the Chainlink Nodes responds, it will respond with this fulfillRandomWords, pick a random winner and reset everything
    // Coding Style: Checks, Effects, Interactions --> Helps to stay Secure and Safe
    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // Checks e.g. Requires or If -> Errors (Start with Checks because it is more gas efficient)

        // Effects (Effect our own contract)
        // s_players = 10
        // rng = 12
        // 12 % 10 = 2 <- whoever is index 2 in the randomWords array will be the winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        // reset the players array, we don't want the new players to get into the lottery for free
        // reset the timer as well
        s_players = new address payable[](0); // we want to reset the array to 0 length
        s_lastTimeStamp = block.timestamp; // reset the timer

        emit PickedWinner(winner);

        // Interactions (Interact with other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }
}
