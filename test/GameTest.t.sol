// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeTrivia} from "../src/DeTrivia.sol";
import {DeTriviaGame} from "../src/DeTriviaGame.sol";
import {MockVRF} from "../src/MockVRF.sol";
import {DTRT} from "../src/DTRT.sol";

contract GameTest is Test {
    DeTriviaGame public game;
    DeTrivia public trivia;
    DeTriviaRewardToken public token;
    MockVRF public vrf;

    address public owner;
    address public player;
    
    // Constants for testing
    bytes32 constant SALT = bytes32("test_salt");
    string constant CORRECT_ANSWER = "Option A";
    uint256 constant QUESTIONS_PER_GAME = 3;
    
    function setUp() public {
        owner = address(this);
        player = makeAddr("player");
        vm.deal(player, 100 ether);

        // Deploy all contracts
        token = new DeTriviaRewardToken(owner);
        trivia = new DeTrivia();
        vrf = new MockVRF();
        game = new DeTriviaGame(address(trivia), address(token), address(vrf));

        // Grant minting rights to game contract
        token.grantRole(keccak256("MINTER_ROLE"), address(game));

        // Create the minimum number of questions needed
        _createTestQuestions(QUESTIONS_PER_GAME);
    }

    function _createTestQuestions(uint256 numQuestions) internal {
        string[] memory options = new string[](4);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";
        options[3] = "Option D";

        // Hash the correct answer with our test salt
        bytes32 answerHash = keccak256(abi.encodePacked(CORRECT_ANSWER, SALT));

        // Create the specified number of questions
        for(uint256 i = 0; i < numQuestions; i++) {
            string memory questionText = string(abi.encodePacked(
                "Test Question #", vm.toString(i + 1)
            ));
            trivia.createQuestion(questionText, options, answerHash);
        }
    }

    function test_CompleteGameFlow() public {
        // Start recording logs
        vm.recordLogs();
        
        // 1. Start as player
        vm.startPrank(player);

        // 2. Start the game
        game.startGame();
        
        // Verify game started
        (,uint256 gamesPlayed,,,, bool canPlay) = game.getPlayerStats(player);
        assertEq(gamesPlayed, 1, "Should have started one game");
        assertFalse(canPlay, "Should not be able to play again today");

        // 3. Play through all questions
        for(uint256 i = 0; i < QUESTIONS_PER_GAME; i++) {
            // Get current question
            (uint256 questionId, string memory questionText, string[] memory options) = 
                game.getCurrentQuestion();
            
            // Verify question data
            assertGt(bytes(questionText).length, 0, "Question text should not be empty");
            assertEq(options.length, 4, "Should have 4 options");
            
            // Submit answer with our known correct answer and salt
            game.submitAnswer(CORRECT_ANSWER, SALT);
        }

        // 4. Verify game completion and rewards
        (
            ,
            uint256 totalGames,
            uint256 correctAnswers,
            uint256 tokensEarned,
            uint256 weekScore,
        ) = game.getPlayerStats(player);

        // Check final stats
        assertEq(totalGames, 1, "Should have played one game");
        assertEq(correctAnswers, QUESTIONS_PER_GAME, "Should have all answers correct");
        assertEq(tokensEarned, QUESTIONS_PER_GAME * game.rewardPerCorrectAnswer(), "Should have earned correct tokens");
        assertEq(weekScore, QUESTIONS_PER_GAME * 100, "Week score should be correct"); // 100 points per correct answer

        // 5. Check token balance
        uint256 expectedTokens = QUESTIONS_PER_GAME * game.rewardPerCorrectAnswer();
        assertEq(token.balanceOf(player), expectedTokens, "Should have received correct number of tokens");

        // 6. Verify leaderboard position
        (address[] memory leaders, uint256[] memory scores,) = game.getCurrentWeekLeaderboard();
        assertEq(leaders[0], player, "Player should be top of leaderboard");
        assertEq(scores[0], QUESTIONS_PER_GAME * 100, "Should have correct leaderboard score");

        vm.stopPrank();

        // 7. Fast forward to end of week and distribute rewards
        uint256 currentWeek = game.getCurrentWeek();
        vm.warp(game.getWeekEnd(currentWeek) + 1);
        
        game.distributeWeeklyRewards(currentWeek);

        // 8. Verify weekly rewards
        uint256 finalBalance = token.balanceOf(player);
        assertGt(finalBalance, expectedTokens, "Should have received weekly rewards");

        // Print game flow details
        console.log("Game Flow Summary:");
        console.log("Total Games Played:", totalGames);
        console.log("Correct Answers:", correctAnswers);
        console.log("Tokens Earned (gameplay):", tokensEarned);
        console.log("Week Score:", weekScore);
        console.log("Final Token Balance:", finalBalance);
    }

    function test_CannotPlayTwice() public {
        vm.startPrank(player);
        
        // First game should succeed
        game.startGame();
        
        // Second game should fail
        vm.expectRevert("Already played today. Try again tomorrow!");
        game.startGame();
        
        vm.stopPrank();
    }

    function test_CanPlayNextDay() public {
        vm.startPrank(player);
        
        // Play first game
        game.startGame();
        for(uint256 i = 0; i < QUESTIONS_PER_GAME; i++) {
            game.submitAnswer(CORRECT_ANSWER, SALT);
        }
        
        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Should be able to play again
        game.startGame();
        
        // Verify second game started
        (,uint256 gamesPlayed,,,,) = game.getPlayerStats(player);
        assertEq(gamesPlayed, 2, "Should have played two games");
        
        vm.stopPrank();
    }
}