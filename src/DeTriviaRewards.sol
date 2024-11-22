// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DeTriviaRewards is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    ERC20Burnable public immutable dtrtToken;
    IERC20 private immutable dtrtTokenInterface;

    struct Prize {
        string name;
        string description;
        uint256 cost;
        uint256 remainingSupply;
        bool active;
    }

    mapping(uint256 => Prize) public prizes;
    uint256 public prizeCount;

    event PrizeAdded(
        uint256 indexed prizeId,
        string name,
        uint256 cost,
        uint256 supply
    );
    event PrizeUpdated(
        uint256 indexed prizeId,
        string name,
        uint256 cost,
        uint256 supply
    );
    event PrizeRedeemed(
        uint256 indexed prizeId,
        address indexed user,
        uint256 timestamp
    );
    event PrizeDeactivated(uint256 indexed prizeId);

    constructor(address _dtrtToken) {
        dtrtToken = ERC20Burnable(_dtrtToken);
        dtrtTokenInterface = IERC20(_dtrtToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function addPrize(
        string memory name,
        string memory description,
        uint256 cost,
        uint256 supply
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(cost > 0, "Cost must be greater than 0");
        require(supply > 0, "Supply must be greater than 0");

        uint256 prizeId = prizeCount;
        prizes[prizeId] = Prize({
            name: name,
            description: description,
            cost: cost,
            remainingSupply: supply,
            active: true
        });

        prizeCount++;
        emit PrizeAdded(prizeId, name, cost, supply);
        return prizeId;
    }

    function updatePrize(
        uint256 prizeId,
        string memory name,
        string memory description,
        uint256 cost,
        uint256 supply
    ) external onlyRole(ADMIN_ROLE) {
        require(prizeId < prizeCount, "Prize does not exist");
        require(prizes[prizeId].active, "Prize is not active");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(cost > 0, "Cost must be greater than 0");
        require(supply > 0, "Supply must be greater than 0");

        Prize storage prize = prizes[prizeId];
        prize.name = name;
        prize.description = description;
        prize.cost = cost;
        prize.remainingSupply = supply;

        emit PrizeUpdated(prizeId, name, cost, supply);
    }

    function deactivatePrize(uint256 prizeId) external onlyRole(ADMIN_ROLE) {
        require(prizeId < prizeCount, "Prize does not exist");
        require(prizes[prizeId].active, "Prize already inactive");

        prizes[prizeId].active = false;
        emit PrizeDeactivated(prizeId);
    }

    function redeemPrize(uint256 prizeId) external nonReentrant {
        Prize storage prize = prizes[prizeId];
        require(prizeId < prizeCount, "Prize does not exist");
        require(prize.active, "Prize is not active");
        require(prize.remainingSupply > 0, "Prize out of stock");

        uint256 cost = prize.cost;
        require(dtrtTokenInterface.balanceOf(msg.sender) >= cost, "Insufficient tokens");

        // Transfer tokens to this contract and burn them
        dtrtTokenInterface.safeTransferFrom(msg.sender, address(this), cost);
        dtrtToken.burn(cost);

        // Update prize supply
        prize.remainingSupply--;

        emit PrizeRedeemed(prizeId, msg.sender, block.timestamp);
    }

    function getPrize(
        uint256 prizeId
    )
        external
        view
        returns (
            string memory name,
            string memory description,
            uint256 cost,
            uint256 remainingSupply,
            bool active
        )
    {
        require(prizeId < prizeCount, "Prize does not exist");
        Prize storage prize = prizes[prizeId];
        return (
            prize.name,
            prize.description,
            prize.cost,
            prize.remainingSupply,
            prize.active
        );
    }

    function getAllPrizes() external view returns (Prize[] memory) {
        Prize[] memory allPrizes = new Prize[](prizeCount);
        for (uint256 i = 0; i < prizeCount; i++) {
            allPrizes[i] = prizes[i];
        }
        return allPrizes;
    }
}