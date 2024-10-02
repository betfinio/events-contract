// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { CoreInterface } from "src/interfaces/CoreInterface.sol";
import { PartnerInterface } from "src/interfaces/PartnerInterface.sol";
import { StakingInterface } from "src/interfaces/StakingInterface.sol";
import { PassInterface } from "src/interfaces/PassInterface.sol";
import { Token } from "src/Token.sol";
import { EventFactory } from "src/EventFactory.sol";
import { Event } from "src/Event.sol";

contract EventTest is Test {
    // create deployed contract instances
    CoreInterface public core;
    Token public token;
    PassInterface public pass;
    PartnerInterface public partner;
    StakingInterface public conservativeStaking;

    // local variables
    address private deployer = vm.envAddress("DEPLOYER");
    address public alice = address(1);

    // game
    EventFactory public game;
    Event public _event;

    function setUp() public virtual {
        // connect to deployed contracts
        core = CoreInterface(vm.envAddress("CORE"));
        token = Token(vm.envAddress("TOKEN"));
        pass = PassInterface(vm.envAddress("PASS"));
        partner = PartnerInterface(vm.envAddress("PARTNER"));
        conservativeStaking = StakingInterface(vm.envAddress("CONSERVATIVE_STAKING"));
        // fork the blockchain
        vm.createSelectFork({ urlOrAlias: "rpc" });
        // deploy the game
        game = new EventFactory(address(conservativeStaking), address(core));

        // register the game
        vm.prank(deployer);
        core.addGame(address(game));

        // create event
        uint256[] memory sides = new uint256[](2);
        sides[0] = 1;
        sides[1] = 2;
        _event = new Event(address(game), sides, block.timestamp, block.timestamp + 1 days, block.timestamp + 2 days);
        game.grantRole(game.REGISTRATOR(), address(this));
        game.addEvent(address(_event));

        // get pass
        getPass(alice);
    }

    function getPass(address member) internal {
        vm.startPrank(deployer);
        pass.mint(member, deployer, deployer);
        assertEq(pass.balanceOf(member), 1);
        vm.stopPrank();
    }

    function getTokens(address member, uint256 amount) internal {
        vm.startPrank(deployer);
        uint256 b = token.balanceOf(member);
        token.transfer(member, amount);
        uint256 a = token.balanceOf(member);
        assertEq(a - b, amount);
        vm.stopPrank();
    }

    function placeBet(address player, uint256 amount, uint256 side) internal returns (address) {
        bytes memory data = abi.encode(address(_event), uint256(side), player);
        vm.startPrank(player);
        token.approve(address(core), amount);
        address bet = partner.placeBet(address(game), amount, data);
        vm.stopPrank();
        return address(bet);
    }

    function placeBetWithError(address player, uint256 amount, uint256 side, bytes memory error) internal {
        bytes memory data = abi.encode(address(_event), uint256(side), player);
        vm.prank(player);
        vm.expectRevert(error);
        partner.placeBet(address(game), amount, data);
    }

    function testConstructor() public virtual {
        assertEq(game.getStaking(), address(conservativeStaking));
        assertEq(game.getFeeType(), 0);
        assertEq(game.getVersion(), block.timestamp);
    }

    function testPlaceBet() public {
        getTokens(alice, 1000 ether);
        assertEq(_event.getBank(), 0);
        placeBet(alice, 1000 ether, 1);
        assertEq(_event.getBank(), 1000 ether);
        assertEq(_event.bankBySide(1), 1000 ether);
        assertEq(_event.bankBySide(2), 0);
        assertEq(_event.getBetsCount(), 1);
        assertEq(_event.getBetsCountBySide(1), 1);
        assertEq(_event.getBetsCountBySide(2), 0);
        assertEq(token.balanceOf(address(_event)), 964 ether);
    }
}
