// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { CoreInterface } from "src/interfaces/CoreInterface.sol";
import { Token } from "src/Token.sol";
import { EventFactory } from "src/EventFactory.sol";
import { Event } from "src/Event.sol";
import { EventBet } from "src/EventBet.sol";

contract EventUnitTest is Test {
    address public staking = address(555);
    address public core = address(777);

    address public alice = address(1);
    address public bob = address(2);
    address public carol = address(3);
    address public dave = address(4);

    EventFactory public _eventFactory;
    Event public _event;

    Token public token = new Token(address(this));

    function setUp() public {
        vm.mockCall(address(core), abi.encodeWithSelector(CoreInterface.token.selector), abi.encode(address(token)));
        vm.mockCall(address(core), abi.encodeWithSelector(CoreInterface.fee.selector), abi.encode(uint256(360)));
        _eventFactory = new EventFactory(staking, core);
        uint256[] memory sides = new uint256[](2);
        sides[0] = 1;
        sides[1] = 2;
        _event = new Event(
            address(_eventFactory), sides, block.timestamp, block.timestamp + 1 days, block.timestamp + 2 days
        );
        _eventFactory.grantRole(_eventFactory.REGISTRATOR(), address(this));
        _eventFactory.addEvent(address(_event));
    }

    function testConstructor() public virtual {
        assertEq(address(_event.factory()), address(_eventFactory));
        assertEq(_event.start(), block.timestamp);
        assertEq(_event.end(), block.timestamp + 1 days);
        assertEq(_event.getSides().length, 2);
    }

    function testConstructor_fail() public {
        vm.warp(1_000_000);
        uint256[] memory sides = new uint256[](2);
        sides[0] = 1;
        sides[1] = 2;

        vm.expectRevert(bytes("E07"));
        _event = new Event(
            address(_eventFactory), sides, block.timestamp, block.timestamp - 1 days, block.timestamp + 2 days
        );

        vm.expectRevert(bytes("E07"));
        _event = new Event(
            address(_eventFactory), sides, block.timestamp, block.timestamp + 1 days, block.timestamp + 1 minutes
        );

        sides = new uint256[](1);
        sides[0] = 1;
        vm.expectRevert(bytes("E10"));
        _event = new Event(
            address(_eventFactory), sides, block.timestamp, block.timestamp + 1 days, block.timestamp + 2 days
        );
    }

    function testPlaceBet() public {
        assertEq(_event.getBank(), 0);
        placeBet(alice, 1000 ether, 1);
        assertEq(_event.getBank(), 1000 ether);
        assertEq(_event.getSideBank(1), 1000 ether);
        assertEq(_event.getSideBank(2), 0);
        assertEq(_event.getBetsCount(), 1);
        assertEq(_event.getBetsCountBySide(1), 1);
        assertEq(_event.getBetsCountBySide(2), 0);
        assertEq(token.balanceOf(address(_event)), 964 ether);
    }

    function placeBet(address player, uint256 amount, uint256 side) internal returns (address) {
        bytes memory data = abi.encode(address(_event), uint256(side), player);
        token.transfer(address(_eventFactory), (amount * 9640) / 10_000);
        vm.prank(core);
        address bet = _eventFactory.placeBet(player, amount, data);
        return address(bet);
    }

    function placeBetWithError(address player, uint256 amount, uint256 side, bytes memory error) internal {
        bytes memory data = abi.encode(address(_event), uint256(side), player);
        token.transfer(address(_eventFactory), (amount * 9640) / 10_000);
        vm.prank(core);
        vm.expectRevert(error);
        _eventFactory.placeBet(player, amount, data);
    }

    function testDetermineWinner_simple() public {
        assertEq(_event.getBank(), 0);
        address betA = placeBet(alice, 1000 ether, 1);
        address betB = placeBet(bob, 1000 ether, 2);

        assertEq(_event.getBank(), 2000 ether);
        assertEq(_event.getSideBank(1), 1000 ether);
        assertEq(_event.getSideBank(2), 1000 ether);
        assertEq(token.balanceOf(address(_event)), 1928 ether);
        assertEq(_event.status(), 1);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(bytes("E05"));
        _event.determineWinner(1);

        vm.warp(block.timestamp + 2 days);
        _event.determineWinner(1);
        assertEq(_event.status(), 22);
        _event.distribute(0, 100);
        _event.settle(0, 100);
        assertEq(_event.status(), 20);

        assertEq(token.balanceOf(alice), 1928 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(_event)), 0);

        assertEq(EventBet(betA).getStatus(), 2);
        assertEq(EventBet(betB).getStatus(), 3);
    }

    function testDetermineWinner_wrongSide() public {
        assertEq(_event.getBank(), 0);
        placeBet(alice, 1000 ether, 1);
        placeBet(bob, 1000 ether, 2);

        assertEq(_event.getBank(), 2000 ether);
        assertEq(_event.getSideBank(1), 1000 ether);
        assertEq(_event.getSideBank(2), 1000 ether);
        assertEq(token.balanceOf(address(_event)), 1928 ether);

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(bytes("E08"));
        _event.determineWinner(5);
    }

    function testRefund_hasNotPerformed() public {
        assertEq(_event.getBank(), 0);
        address betA = placeBet(alice, 1000 ether, 1);
        address betB = placeBet(bob, 1000 ether, 1);

        assertEq(_event.getBank(), 2000 ether);
        assertEq(_event.getSideBank(1), 2000 ether);
        assertEq(_event.getSideBank(2), 0);
        assertEq(token.balanceOf(address(_event)), 1928 ether);

        vm.warp(block.timestamp + 2 days + 2 seconds);
        _event.determineWinner(2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(_event)), 1928 ether);

        assertEq(EventBet(betA).getStatus(), 1);
        assertEq(EventBet(betB).getStatus(), 1);
        assertEq(_event.status(), 32);
    }

    function testRefund_refundNext() public {
        assertEq(_event.getBank(), 0);

        uint256 fee = 360;
        uint256 placedBets = 101;
        uint256 betAmount = 1000 ether;
        uint256 totalTokens = placedBets * betAmount;
        uint256 totalTokensWithFee = totalTokens - (totalTokens * fee) / 10_000;
        address[] memory bets = new address[](placedBets);

        for (uint256 i = 0; i < placedBets; i++) {
            bets[i] = placeBet(alice, betAmount, 1);
        }

        assertEq(_event.getBank(), totalTokens);
        assertEq(_event.getSideBank(1), totalTokens);
        assertEq(_event.getSideBank(2), 0);
        assertEq(token.balanceOf(address(_event)), totalTokensWithFee);

        vm.warp(block.timestamp + 2 days + 2 seconds);
        _event.determineWinner(2);
        assertEq(token.balanceOf(alice), 0);

        assertEq(token.balanceOf(address(_event)), totalTokensWithFee);
        _event.refundNext();

        assertEq(EventBet(bets[0]).getStatus(), 4);
        assertEq(EventBet(bets[99]).getStatus(), 4);
        assertEq(token.balanceOf(alice), totalTokensWithFee - 964 ether);

        assertEq(EventBet(bets[100]).getStatus(), 1);
        assertEq(_event.status(), 31);
        _event.refundNext();
        assertEq(token.balanceOf(alice), totalTokensWithFee);
        assertEq(token.balanceOf(address(_event)), 0);
        assertEq(EventBet(bets[100]).getStatus(), 4);
        assertEq(_event.status(), 30);
        vm.expectRevert(bytes("E11"));
        _event.refundNext();
    }

    function testRefund_refundNextByStep() public {
        assertEq(_event.getBank(), 0);

        uint256 fee = 360;
        uint256 placedBets = 101;
        uint256 betAmount = 1000 ether;
        uint256 totalTokens = placedBets * betAmount;
        uint256 totalTokensWithFee = totalTokens - (totalTokens * fee) / 10_000;
        address[] memory bets = new address[](placedBets);

        for (uint256 i = 0; i < placedBets; i++) {
            bets[i] = placeBet(alice, betAmount, 1);
        }

        assertEq(_event.getBank(), totalTokens);
        assertEq(_event.getSideBank(1), totalTokens);
        assertEq(_event.getSideBank(2), 0);
        assertEq(token.balanceOf(address(_event)), totalTokensWithFee);

        vm.warp(block.timestamp + 2 days + 2 seconds);
        _event.determineWinner(2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(_event.status(), 32);
        assertEq(token.balanceOf(address(_event)), totalTokensWithFee);
        _event.refundNextByStep(1);

        assertEq(EventBet(bets[0]).getStatus(), 4);
        assertEq(EventBet(bets[99]).getStatus(), 1);
        assertEq(EventBet(bets[100]).getStatus(), 1);
        assertEq(_event.status(), 31);
        vm.expectEmit();
        _event.refundNextByStep(100);
        assertEq(EventBet(bets[100]).getStatus(), 4);
        assertEq(_event.status(), 30);

        vm.expectRevert(bytes("E11"));
        _event.refundNext();
    }

    function testRefund_refundNextByStepStepBiggerThanDiff() public {
        assertEq(_event.getBank(), 0);

        uint256 fee = 360;
        uint256 placedBets = 101;
        uint256 betAmount = 1000 ether;
        uint256 totalTokens = placedBets * betAmount;
        uint256 totalTokensWithFee = totalTokens - (totalTokens * fee) / 10_000;
        address[] memory bets = new address[](placedBets);

        for (uint256 i = 0; i < placedBets; i++) {
            bets[i] = placeBet(alice, betAmount, 1);
        }

        assertEq(_event.getBank(), totalTokens);
        assertEq(_event.getSideBank(1), totalTokens);
        assertEq(_event.getSideBank(2), 0);
        assertEq(token.balanceOf(address(_event)), totalTokensWithFee);

        vm.warp(block.timestamp + 2 days + 2 seconds);
        _event.determineWinner(2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(_event.status(), 32);
        assertEq(token.balanceOf(address(_event)), totalTokensWithFee);
        _event.refundNextByStep(1);

        assertEq(EventBet(bets[0]).getStatus(), 4);
        assertEq(EventBet(bets[99]).getStatus(), 1);
        assertEq(EventBet(bets[100]).getStatus(), 1);
        assertEq(_event.status(), 31);
        _event.refundNextByStep(100);
        assertEq(EventBet(bets[100]).getStatus(), 4);
        assertEq(_event.status(), 30);

        vm.expectRevert(bytes("E11"));
        _event.refundNext();
    }

    function testPlaceBet_wrong() public {
        assertEq(_event.getBank(), 0);
        placeBetWithError(alice, 1000 ether, 5, bytes("E08"));
    }

    function testBonus() public {
        placeBet(alice, 1000 ether, 1);
        placeBet(bob, 2000 ether, 1);

        vm.warp(block.timestamp + 2 days);
        _event.determineWinner(1);
		_event.distribute(0, 100);
        assertEq(token.balanceOf(alice), 914 ether + 75 ether);
        assertEq(token.balanceOf(bob), 1828 ether + 75 ether);
    }
}
