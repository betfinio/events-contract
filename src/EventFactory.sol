// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { CoreInterface } from "./interfaces/CoreInterface.sol";
import { GameInterface } from "./interfaces/GameInterface.sol";
import { EventInterface } from "./EventInterface.sol";
import { FactoryInterface } from "./FactoryInterface.sol";

/**
 * Errors:
 * EF01 - Invalid event
 * EF02 - Caller is not core
 * EF03 - Transfer failed
 */
contract EventFactory is GameInterface, FactoryInterface, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant REGISTRATOR = keccak256("REGISTRATOR");

    uint256 private immutable created;
    address private immutable staking;
    CoreInterface private immutable core;
    IERC20 private immutable token;

    mapping(address _event => bool exists) public isEvent;

    event EventCreated(address indexed eventAddress);
    event BetCreated(address indexed bet, address indexed _event);

    constructor(address _staking, address _core) {
        created = block.timestamp;
        staking = _staking;
        core = CoreInterface(_core);
        token = IERC20(CoreInterface(_core).token());
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function getAddress() external view returns (address) {
        return address(this);
    }

    // for most games - creation timestamp of the game
    function getVersion() external view returns (uint256) {
        return created;
    }

    // 0 - fee from player's bet, 1 - fee from core's balance
    function getFeeType() external pure returns (uint256) {
        return 0;
    }

    // address to send fee to
    function getStaking() external view returns (address) {
        return staking;
    }

    // function to call when placing bet
    function placeBet(address player, uint256 amount, bytes calldata data) external returns (address betAddress) {
        // check if caller is core
        require(msg.sender == address(core), "EF02");
        // decode data
        (address _event,,) = abi.decode(data, (address, uint256, address));
        // check is event is valid
        require(isEvent[_event], "EF01");
        // calculate tokens to send
        uint256 fee = (amount * core.fee()) / 10_000;
        require(token.transfer(_event, amount - fee), "EF03");
        address bet = EventInterface(_event).placeBet(player, amount, data);
        emit BetCreated(bet, _event);
        return bet;
    }

    function addEvent(address _event) external onlyRole(REGISTRATOR) {
        isEvent[_event] = true;
        emit EventCreated(_event);
    }

    function getToken() external view override returns (address) {
        return core.token();
    }

    function getCore() external view override returns (address) {
        return address(core);
    }
}
