// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BoopTheSnoot} from "../src/BoopTheSnoot.sol";

contract BoopTheSnootScript is Script {
    BoopTheSnoot public boopTheSnoot;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        boopTheSnoot = new BoopTheSnoot();

        vm.stopBroadcast();
    }
}
