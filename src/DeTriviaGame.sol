// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDeTrivia {
    function getQuestionCount() external view returns (uint256);
    function getQuestion(
        uint256 _questionId
    )
        external
        view
        returns (
            string memory questionText,
            string[] memory options,
            address creator,
            uint256 timestamp,
            bool active
        );
    function hasAttempted(
        address _user,
        uint256 _questionId
    ) external view returns (bool);
    function submitAnswer(
        uint256 _questionId,
        string memory _answer,
        bytes32 _salt
    ) external;
}

interface IRewardToken {
    function mint(address to, uint256 amount) external;
}

interface IMockVRF {
    function getRandomNumber(
        uint256 min,
        uint256 max
    ) external returns (uint256);
}

contract DeTriviaGame is Ownable, ReentrancyGuard {
    IDeTrivia public DeTriviaContract;
    IRewardToken public rewardToken;
    IMockVRF public mockVRF;

    // Game configuration
    uint256 public questionsPerGame = 3;
    uint256 public rewardPerCorrectAnswer = 1 * 10 ** 18; // 1 DTRT token per correct answer
    uint256 public constant DAILY_COOLDOWN = 1 days;
    uint256 public constant WEEK_DURATION = 1 weeks;

    // Weekly rewards configuration
    uint256 public constant REWARDS_TOP_PLAYERS = 3;
    uint256[] public weeklyRewardAmounts = [
        50 * 10 ** 18, // 1st place: 50 DTRT
        25 * 10 ** 18, // 2nd place: 25 DTRT
        10 * 10 ** 18 // 3rd place: 10 DTRT
    ];

    // Game state
    struct Game {
        uint256[] questionIds;
        uint256 currentQuestionIndex;
        uint256 correctAnswers;
        uint256 startTime;
        bool isActive;
    }

    struct PlayerStats {
        uint256 lastPlayedDay;
        uint256 totalGamesPlayed;
        uint256 totalCorrectAnswers;
        uint256 totalTokensEarned;
        uint256 currentWeekScore;
        uint256 lastUpdatedWeek;
    }

    struct WeeklyLeaderboard {
        address[] topPlayers;
        uint256[] topScores;
        bool rewardsDistributed;
        uint256 weekNumber;
    }

    mapping(address => Game) public playerGames;
    mapping(address => PlayerStats) public playerStats;
    mapping(uint256 => WeeklyLeaderboard) public weeklyLeaderboards;

    // Events
    event GameStarted(address indexed player, uint256 timestamp);
    event AnswerSubmitted(
        address indexed player,
        uint256 questionId,
        bool isCorrect,
        uint256 timestamp
    );
    event GameEnded(
        address indexed player,
        uint256 questionsAttempted,
        uint256 correctAnswers,
        uint256 tokensAwarded,
        uint256 timestamp
    );
    event WeeklyRewardsDistributed(
        uint256 indexed weekNumber,
        address[] winners,
        uint256[] rewards
    );
    event LeaderboardUpdated(
        uint256 indexed weekNumber,
        address player,
        uint256 score,
        uint256 rank
    );

    constructor(
        address _DeTriviaContract,
        address _rewardToken,
        address _mockVRF
    ) Ownable(msg.sender) {
        DeTriviaContract = IDeTrivia(_DeTriviaContract);
        rewardToken = IRewardToken(_rewardToken);
        mockVRF = IMockVRF(_mockVRF);
    }

    // Modifiers
    modifier gameNotInProgress() {
        require(!playerGames[msg.sender].isActive, "Game already in progress");
        _;
    }

    modifier gameInProgress() {
        require(playerGames[msg.sender].isActive, "No active game found");
        _;
    }

    modifier canPlayToday() {
        require(
            !hasPlayedToday(msg.sender),
            "Already played today. Try again tomorrow!"
        );
        _;
    }

    // Helper functions
    function getCurrentWeek() public view returns (uint256) {
        return block.timestamp / WEEK_DURATION;
    }

    function getWeekStart(uint256 weekNumber) public pure returns (uint256) {
        return weekNumber * WEEK_DURATION;
    }

    function getWeekEnd(uint256 weekNumber) public pure returns (uint256) {
        return (weekNumber + 1) * WEEK_DURATION - 1;
    }

    function getCurrentDayStart() public view returns (uint256) {
        return block.timestamp - (block.timestamp % DAILY_COOLDOWN);
    }

    function hasPlayedToday(address player) public view returns (bool) {
        return playerStats[player].lastPlayedDay == getCurrentDayStart();
    }

    function getTimeUntilNextGame(
        address player
    ) public view returns (uint256) {
        if (!hasPlayedToday(player)) {
            return 0;
        }
        uint256 nextAvailableTime = playerStats[player].lastPlayedDay +
            DAILY_COOLDOWN;
        return
            nextAvailableTime > block.timestamp
                ? nextAvailableTime - block.timestamp
                : 0;
    }

    function isNewWeek(address player) internal view returns (bool) {
        return playerStats[player].lastUpdatedWeek < getCurrentWeek();
    }

    // Core gameplay functions
    function startGame() external nonReentrant gameNotInProgress canPlayToday {
        uint256 totalQuestions = DeTriviaContract.getQuestionCount();
        require(
            totalQuestions >= questionsPerGame,
            "Not enough questions available"
        );

        uint256[] memory selectedQuestions = new uint256[](questionsPerGame);
        uint256[] memory usedIndices = new uint256[](totalQuestions);
        uint256 selectedCount = 0;

        while (selectedCount < questionsPerGame) {
            uint256 randomIndex = mockVRF.getRandomNumber(
                0,
                totalQuestions - 1
            );

            if (usedIndices[randomIndex] == 0) {
                (, , , , bool active) = DeTriviaContract.getQuestion(
                    randomIndex
                );
                if (
                    active &&
                    !DeTriviaContract.hasAttempted(msg.sender, randomIndex)
                ) {
                    selectedQuestions[selectedCount] = randomIndex;
                    usedIndices[randomIndex] = 1;
                    selectedCount++;
                }
            }
        }

        playerGames[msg.sender] = Game({
            questionIds: selectedQuestions,
            currentQuestionIndex: 0,
            correctAnswers: 0,
            startTime: block.timestamp,
            isActive: true
        });

        playerStats[msg.sender].lastPlayedDay = getCurrentDayStart();
        playerStats[msg.sender].totalGamesPlayed++;

        emit GameStarted(msg.sender, block.timestamp);
    }

    function getCurrentQuestion()
        external
        view
        gameInProgress
        returns (
            uint256 questionId,
            string memory questionText,
            string[] memory options
        )
    {
        Game storage game = playerGames[msg.sender];
        questionId = game.questionIds[game.currentQuestionIndex];
        (questionText, options, , , ) = DeTriviaContract.getQuestion(
            questionId
        );
    }

    function submitAnswer(
        string memory _answer,
        bytes32 _salt
    ) external gameInProgress nonReentrant {
        Game storage game = playerGames[msg.sender];
        uint256 currentQuestionId = game.questionIds[game.currentQuestionIndex];

        DeTriviaContract.submitAnswer(currentQuestionId, _answer, _salt);

        // In production, implement proper answer verification
        bool isCorrect = true;

        if (isCorrect) {
            game.correctAnswers++;
            playerStats[msg.sender].totalCorrectAnswers++;
        }

        emit AnswerSubmitted(
            msg.sender,
            currentQuestionId,
            isCorrect,
            block.timestamp
        );

        game.currentQuestionIndex++;
        if (game.currentQuestionIndex >= questionsPerGame) {
            _endGame();
        }
    }

    function _endGame() internal {
        Game storage game = playerGames[msg.sender];
        require(game.isActive, "Game not active");

        uint256 currentWeek = getCurrentWeek();
        uint256 gameScore = game.correctAnswers * 100;

        if (isNewWeek(msg.sender)) {
            playerStats[msg.sender].currentWeekScore = 0;
            playerStats[msg.sender].lastUpdatedWeek = currentWeek;
        }

        playerStats[msg.sender].currentWeekScore += gameScore;
        _updateLeaderboard(
            msg.sender,
            playerStats[msg.sender].currentWeekScore,
            currentWeek
        );

        uint256 tokensToAward = game.correctAnswers * rewardPerCorrectAnswer;
        if (tokensToAward > 0) {
            rewardToken.mint(msg.sender, tokensToAward);
            playerStats[msg.sender].totalTokensEarned += tokensToAward;
        }

        emit GameEnded(
            msg.sender,
            questionsPerGame,
            game.correctAnswers,
            tokensToAward,
            block.timestamp
        );
        game.isActive = false;
    }

    function _updateLeaderboard(
        address player,
        uint256 score,
        uint256 weekNumber
    ) internal {
        WeeklyLeaderboard storage leaderboard = weeklyLeaderboards[weekNumber];

        if (leaderboard.weekNumber != weekNumber) {
            leaderboard.weekNumber = weekNumber;
            leaderboard.topPlayers = new address[](REWARDS_TOP_PLAYERS);
            leaderboard.topScores = new uint256[](REWARDS_TOP_PLAYERS);
            leaderboard.rewardsDistributed = false;
        }

        uint256 position = REWARDS_TOP_PLAYERS;
        for (uint256 i = 0; i < REWARDS_TOP_PLAYERS; i++) {
            if (score > leaderboard.topScores[i]) {
                position = i;
                break;
            }
        }

        if (position < REWARDS_TOP_PLAYERS) {
            for (uint256 i = REWARDS_TOP_PLAYERS - 1; i > position; i--) {
                leaderboard.topPlayers[i] = leaderboard.topPlayers[i - 1];
                leaderboard.topScores[i] = leaderboard.topScores[i - 1];
            }

            leaderboard.topPlayers[position] = player;
            leaderboard.topScores[position] = score;

            emit LeaderboardUpdated(weekNumber, player, score, position);
        }
    }

    function distributeWeeklyRewards(
        uint256 weekNumber
    ) external nonReentrant onlyOwner {
        require(block.timestamp > getWeekEnd(weekNumber), "Week not ended yet");

        WeeklyLeaderboard storage leaderboard = weeklyLeaderboards[weekNumber];
        require(!leaderboard.rewardsDistributed, "Rewards already distributed");
        require(
            leaderboard.weekNumber == weekNumber,
            "No leaderboard for this week"
        );

        address[] memory winners = new address[](REWARDS_TOP_PLAYERS);
        uint256[] memory rewards = new uint256[](REWARDS_TOP_PLAYERS);

        for (
            uint256 i = 0;
            i < REWARDS_TOP_PLAYERS && i < leaderboard.topPlayers.length;
            i++
        ) {
            address winner = leaderboard.topPlayers[i];
            if (winner != address(0)) {
                uint256 reward = weeklyRewardAmounts[i];
                rewardToken.mint(winner, reward);
                winners[i] = winner;
                rewards[i] = reward;
            }
        }

        leaderboard.rewardsDistributed = true;
        emit WeeklyRewardsDistributed(weekNumber, winners, rewards);
    }

    // View functions
    function getWeeklyLeaderboard(
        uint256 weekNumber
    )
        external
        view
        returns (
            address[] memory players,
            uint256[] memory scores,
            bool rewardsDistributed
        )
    {
        WeeklyLeaderboard storage leaderboard = weeklyLeaderboards[weekNumber];
        return (
            leaderboard.topPlayers,
            leaderboard.topScores,
            leaderboard.rewardsDistributed
        );
    }

    function getCurrentWeekLeaderboard()
        external
        view
        returns (
            address[] memory players,
            uint256[] memory scores,
            bool rewardsDistributed
        )
    {
        return this.getWeeklyLeaderboard(getCurrentWeek());
    }

    function getPlayerStats(
        address player
    )
        external
        view
        returns (
            uint256 lastPlayedDay,
            uint256 totalGamesPlayed,
            uint256 totalCorrectAnswers,
            uint256 totalTokensEarned,
            uint256 currentWeekScore,
            bool canPlayToday
        )
    {
        PlayerStats storage stats = playerStats[player];
        return (
            stats.lastPlayedDay,
            stats.totalGamesPlayed,
            stats.totalCorrectAnswers,
            stats.totalTokensEarned,
            stats.currentWeekScore,
            !hasPlayedToday(player)
        );
    }

    // Admin functions
    function setQuestionsPerGame(uint256 _questionsPerGame) external onlyOwner {
        require(_questionsPerGame > 0, "Invalid questions per game");
        questionsPerGame = _questionsPerGame;
    }

    function setRewardPerCorrectAnswer(
        uint256 _rewardPerCorrectAnswer
    ) external onlyOwner {
        rewardPerCorrectAnswer = _rewardPerCorrectAnswer;
    }

    function setWeeklyRewardAmounts(
        uint256[] calldata _amounts
    ) external onlyOwner {
        require(
            _amounts.length == REWARDS_TOP_PLAYERS,
            "Invalid rewards array length"
        );
        weeklyRewardAmounts = _amounts;
    }
}
