// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.25;

import { Script } from "forge-std/src/Script.sol";
import { console } from "forge-std/src/console.sol";
import { EventFactory } from "src/EventFactory.sol";
import { Event, CoreInterface } from "src/Event.sol";

contract EventDeployer is Script {
    uint256 public deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address public core = address(vm.envAddress("CORE"));

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        EventFactory factory = new EventFactory(vm.envAddress("CONSERVATIVE_STAKING"), core);
        CoreInterface(core).addGame(address(factory));

        factory.grantRole(factory.REGISTRATOR(), address(vm.addr(deployerPrivateKey)));

        uint256[] memory sides = new uint256[](2);
        sides[0] = 1;
        sides[1] = 2;
        Event _event = new Event(address(factory), sides, block.timestamp, 1_730_286_000, 1_730_372_400);
        factory.addEvent(address(_event));
        console.log(address(factory));
        console.log(address(_event));
    }
}
