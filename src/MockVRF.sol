// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockVRF {

    // Simple implementation of a VRF for local testing, to emulate ChainLink's VRF behaviour

    // Event to log when randomness is generated
    event RandomNumberGenerated(uint256 number, uint256 min, uint256 max);
    
    // Generate a random number between min and max (inclusive)
    function getRandomNumber(uint256 min, uint256 max) public returns (uint256) {
        require(max > min, "Max must be greater than min");
        
        // Generate randomness using block data and nonce
        uint256 randomNumber = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    msg.sender,
                    block.number
                )
            )
        );
        
        // Scale the random number to the desired range
        uint256 result = (randomNumber % (max - min + 1)) + min;
        
        emit RandomNumberGenerated(result, min, max);
        return result;
    }
}