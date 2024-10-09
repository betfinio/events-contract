// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.25;

import { BetInterface } from "./interfaces/BetInterface.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Errors:
 * EB00: Invalid constructor arguments
 * EB01: Result must be greater than 0
 */
contract EventBet is BetInterface, Ownable {
    uint256 private immutable created;
    address private immutable player;
    uint256 private immutable amount;
    address private immutable game;
    uint256 private immutable side;

    // 1 - registered
    // 2 - won
    // 3 - lost
    // 4 - refunded
    uint256 private status;
    uint256 private result;

    constructor(address _player, uint256 _amount, address _game, uint256 _side) Ownable(_msgSender()) {
        require(_player != address(0), "EB00");
        require(_amount > 0, "EB00");
        player = _player;
        amount = _amount;
        status = 1;
        game = _game;
        side = _side;
        created = block.timestamp;
    }
    /**
     * @return player - address of player
     */

    function getPlayer() external view override returns (address) {
        return player;
    }

    /**
     * @return amount - amount of bet
     */
    function getAmount() external view override returns (uint256) {
        return amount;
    }

    /**
     * @return result - amount of payout
     */
    function getResult() external view override returns (uint256) {
        return result;
    }

    /**
     * @return status - status of bet
     */
    function getStatus() external view override returns (uint256) {
        return status;
    }

    /**
     * @return game - address of game
     */
    function getGame() external view override returns (address) {
        return game;
    }

    /**
     * @return timestamp - created timestamp of bet
     */
    function getCreated() external view override returns (uint256) {
        return created;
    }

    /**
     * @return data - all data at once (player, game, amount, result, status, created)
     */
    function getBetInfo() external view override returns (address, address, uint256, uint256, uint256, uint256) {
        return (player, game, amount, result, status, created);
    }

    function getSide() external view returns (uint256) {
        return side;
    }

    function setResult(uint256 _result) external onlyOwner {
        require(_result > 0, "EB01");
        result = _result;
        status = 2;
    }

    function setStatus(uint256 _status) external onlyOwner {
        status = _status;
    }
}
