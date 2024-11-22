// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract DeTrivia is Ownable, ReentrancyGuard, Pausable {
    // Structs
    struct Question {
        uint256 questionId;
        string questionText;
        string[] options;
        bytes32 answerHash;
        address creator;
        uint256 timestamp;
        bool active;
    }

    // State variables
    mapping(uint256 => Question) public questions;
    uint256 public questionCount;

    mapping(address => bool) public moderators;
    mapping(address => uint256[]) public userQuestions; // Questions created by user
    mapping(address => mapping(uint256 => bool)) public userAttempts; // Track if user attempted question

    // Events
    event QuestionCreated(
        uint256 indexed questionId,
        string questionText,
        address indexed creator,
        uint256 timestamp
    );

    event QuestionDeactivated(
        uint256 indexed questionId,
        address indexed deactivatedBy,
        uint256 timestamp
    );

    event AnswerSubmitted(
        uint256 indexed questionId,
        address indexed player,
        bool isCorrect,
        uint256 timestamp
    );

    event ModeratorAdded(address indexed moderator, uint256 timestamp);
    event ModeratorRemoved(address indexed moderator, uint256 timestamp);

    // Modifiers
    modifier onlyModerator() {
        require(
            moderators[msg.sender] || owner() == msg.sender,
            "Not authorized"
        );
        _;
    }

    modifier questionExists(uint256 _questionId) {
        require(_questionId < questionCount, "Question does not exist");
        require(questions[_questionId].active, "Question is not active");
        _;
    }

    modifier notAttempted(uint256 _questionId) {
        require(!userAttempts[msg.sender][_questionId], "Already attempted");
        _;
    }

    // Constructor
    constructor() Ownable(msg.sender) {
        moderators[msg.sender] = true;
        emit ModeratorAdded(msg.sender, block.timestamp);
    }

    // Administrative functions
    function addModerator(address _moderator) external onlyOwner {
        require(!moderators[_moderator], "Already a moderator");
        moderators[_moderator] = true;
        emit ModeratorAdded(_moderator, block.timestamp);
    }

    function removeModerator(address _moderator) external onlyOwner {
        require(moderators[_moderator], "Not a moderator");
        require(_moderator != owner(), "Cannot remove owner");
        moderators[_moderator] = false;
        emit ModeratorRemoved(_moderator, block.timestamp);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Core functions
    function createQuestion(
        string memory _questionText,
        string[] memory _options,
        bytes32 _answerHash
    ) external whenNotPaused returns (uint256) {
        require(bytes(_questionText).length > 0, "Question text is empty");
        require(_options.length == 4, "Invalid options count");
        require(_answerHash != bytes32(0), "Answer hash cannot be empty");

        uint256 newQuestionId = questionCount;

        questions[newQuestionId] = Question({
            questionId: newQuestionId,
            questionText: _questionText,
            options: _options,
            answerHash: _answerHash,
            creator: msg.sender,
            timestamp: block.timestamp,
            active: true
        });

        userQuestions[msg.sender].push(newQuestionId);
        questionCount++;

        emit QuestionCreated(
            newQuestionId,
            _questionText,
            msg.sender,
            block.timestamp
        );

        return newQuestionId;
    }

    function submitAnswer(
        uint256 _questionId,
        string memory _answer,
        bytes32 _salt
    )
        external
        whenNotPaused
        questionExists(_questionId)
        notAttempted(_questionId)
        nonReentrant
    {
        Question storage question = questions[_questionId];

        // Verify answer
        bytes32 answerHash = keccak256(abi.encodePacked(_answer, _salt));

        bool isCorrect = (answerHash == question.answerHash);

        // Mark as attempted
        userAttempts[msg.sender][_questionId] = true;

        emit AnswerSubmitted(
            _questionId,
            msg.sender,
            isCorrect,
            block.timestamp
        );
    }

    function deactivateQuestion(
        uint256 _questionId
    ) external onlyModerator questionExists(_questionId) {
        questions[_questionId].active = false;
        emit QuestionDeactivated(_questionId, msg.sender, block.timestamp);
    }

    // View functions
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
        )
    {
        Question storage question = questions[_questionId];
        return (
            question.questionText,
            question.options,
            question.creator,
            question.timestamp,
            question.active
        );
    }

    function getQuestionCount() external view returns (uint) {
        return questionCount;
    }

    function getUserQuestions(
        address _user
    ) external view returns (uint256[] memory) {
        return userQuestions[_user];
    }

    function hasAttempted(
        address _user,
        uint256 _questionId
    ) external view returns (bool) {
        return userAttempts[_user][_questionId];
    }
}
