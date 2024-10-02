// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { EventInterface } from "./EventInterface.sol";
import { EventBet } from "./EventBet.sol";
import { FactoryInterface } from "./FactoryInterface.sol";
import { CoreInterface } from "./interfaces/CoreInterface.sol";

/**
 * Errors:
 * E01 - Invalid event
 * E02 - Event has not started
 * E03 - Event has ended
 * E04 - Caller is not factory
 * E05 - Event has not finished
 * E06 - Winner is not known
 * E07 - Invalid time range
 * E08 - Invalid side
 * E09 - To big step
 * E10 - Invalid count of sides
 * E11 - Refund/Distribute/Settle is not possible
 * E12 - Transfer failed
 */
contract Event is EventInterface, Ownable {
    using SafeERC20 for IERC20;

    FactoryInterface public immutable factory;

    uint256 public immutable fee;
    IERC20 public immutable token;

    uint256 public start; // start time where bets are accepted
    uint256 public end; // end time where bets are accepted
    uint256 public finish; // time when event is finished and results are acceptable
    uint256 private bank;

    uint256 public winnerSide = 0; // winner is not known

    // 0 - not found,
    // 1 - registered
    // 20 - distributed
    // 21 - distributed partly
    // 22 - has to be distributed
    // 30 - refunded
    // 31 - refunded partly
    // 32 - has to be refunded
    uint256 public status = 0;

    uint256[] private sides;
    address[] public bets; // array of all bets

    mapping(uint256 side => address[] bets) public betsBySide; // array of bets by side (side => bets[])
    mapping(uint256 side => uint256 bank) public bankBySide; // bank by side (side => bank)
    mapping(uint256 side => bool exists) public isSide; // side => bool (is side valid)

    uint256 public constant CALC_STEP = 100;
    uint256 public offset = 0;
    uint256 private distributed = 0;
    uint256 private settled = 0;

    event BetCreated(address indexed bet, address indexed player, uint256 indexed side);
    event WinnerCalculated(uint256 indexed side);
    event Refunded();

    constructor(
        address _factory,
        uint256[] memory _sides,
        uint256 _start,
        uint256 _end,
        uint256 _finish
    )
        Ownable(_msgSender())
    {
        require(_start < _end, "E07");
        require(_end < _finish, "E07");
        require(_sides.length > 1, "E10");
        // save input values
        factory = FactoryInterface(_factory);
        sides = _sides;
        start = _start;
        end = _end;
        finish = _finish;
        status = 1;
        fee = CoreInterface(factory.getCore()).fee();
        // save token for gas optimization
        token = IERC20(factory.getToken());
        // mark all sides as valid
        for (uint256 i = 0; i < _sides.length; i++) {
            require(_sides[i] > 0, "E08");
            isSide[_sides[i]] = true;
        }
    }

    function placeBet(address, uint256 amount, bytes calldata data) external returns (address) {
        // check if caller is factory
        require(msg.sender == address(factory), "E04");
        // decode data
        (address _event, uint256 _side, address _player) = abi.decode(data, (address, uint256, address));
        // check if event is valid
        require(_event == address(this), "E01");
        // check if event started
        require(block.timestamp >= start, "E02");
        // check if event has ended
        require(block.timestamp <= end, "E03");
        // check if side is valid
        require(isSide[_side], "E08");
        // create new bet with player from data: INTENDED!
        EventBet bet = new EventBet(_player, amount, address(factory), _side);
        // increment bank
        bank += amount;
        // increment side bank
        bankBySide[_side] += amount;
        // append bet to bets
        bets.push(address(bet));
        // append bet to betsBySide
        betsBySide[_side].push(address(bet));
        emit BetCreated(address(bet), _player, _side);
        return address(bet);
    }

    function determineWinner(uint256 side) external onlyOwner {
        // check if event has finished
        require(block.timestamp >= finish, "E05");
        // check if status is valid
        require(status == 1, "E06");
        // check if side is valid
        require(isSide[side], "E08");
        // check if bank is not empty
        if (bankBySide[side] == 0) {
            // set status to be refunded
            status = 32;
            return;
        }
        status = 22;
        winnerSide = side;
        emit WinnerCalculated(side);
    }

    function _distribute(uint256 _offset, uint256 limit) internal {
        // save variable
        uint256 winner = winnerSide;
        // calculate bank to distribute
        uint256 eventBank = bank - (bank * fee) / 10_000;

        for (uint256 i = _offset; i < _offset + limit; i++) {
            if (i >= betsBySide[winner].length) break;
            EventBet bet = EventBet(betsBySide[winner][i]);
            if (bet.getStatus() == 1) {
                // increment distributed
                distributed += 1;
                status = distributed == betsBySide[winner].length ? 20 : 21;
                // calculate win amount
                uint256 amount = bet.getAmount();
                uint256 winAmount = (amount * eventBank) / bankBySide[winner];
                // set result
                bet.setResult(winAmount);
                // transfer tokens
                require(token.transfer(bet.getPlayer(), winAmount), "E12");
            }
        }
    }

    function _settle(uint256 _offset, uint256 limit) internal {
        // save variable
        uint256 winner = winnerSide;
        for (uint256 i = _offset; i < _offset + limit; i++) {
            if (i >= bets.length) break;
            EventBet bet = EventBet(bets[i]);
            if (bet.getStatus() == 1 && bet.getSide() != winner) {
                bet.setStatus(3);
            }
        }
    }

    function _refund(uint256 step) internal {
        // Remaining bets to process
        uint256 remainingBets = bets.length - offset;
        // calculate the actual step
        uint256 actualStep = step;
        if (actualStep > remainingBets) {
            // Adjust step to match the number of remaining bets
            actualStep = remainingBets;
        }
        uint256 _offset = offset;
        // Update the refund offset
        offset += actualStep;
        // Check if all bets have been refunded
        if (offset >= bets.length) {
            // All refunds completed
            status = 30;
        } else {
            // Partly refunded
            status = 31;
        }
        // start refunding
        for (uint256 i = _offset; i < _offset + actualStep; i++) {
            // save bet to variable
            EventBet bet = EventBet(bets[i]);
            // Ensure not already refunded
            if (bet.getStatus() != 4) {
                // mark bet as refunded
                bet.setStatus(4);
                // calculate amount to refund
                uint256 amount = bet.getAmount();
                uint256 refundAmount = amount - (amount * fee) / 10_000;
                // transfer tokens
                require(token.transfer(bet.getPlayer(), refundAmount), "E12");
            }
        }
        if (status == 30) {
            emit Refunded();
        }
    }

    function refundNextByStep(uint256 step) public {
        // Ensure the contract is in a refundable state
        require(status == 31 || status == 32, "E11");
        // Ensure the step is not zero or negative
        require(step > 0, "E09");
        // Ensure the step is not larger than the total number of bets
        require(step <= bets.length, "E09");
        // execute refund
        _refund(step);
    }

    function refundNext() external {
        // execute refund with predefined step
        refundNextByStep(CALC_STEP);
    }

    function distribute(uint256 _offset, uint256 _limit) external {
        require(status == 22 || status == 21, "E11");
        _distribute(_offset, _limit);
    }

    function settle(uint256 _offset, uint256 _limit) external {
        require(status == 20 || status == 21 || status == 22, "E11");
        _settle(_offset, _limit);
    }

    function getSides() external view returns (uint256[] memory) {
        return sides;
    }

    function getBetsCount() external view returns (uint256) {
        return bets.length;
    }

    function getBetsCountBySide(uint256 side) external view returns (uint256) {
        return betsBySide[side].length;
    }

    function getSideBank(uint256 side) external view returns (uint256) {
        return bankBySide[side];
    }

    function getBank() external view returns (uint256) {
        return bank;
    }
}
