// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {BoopTheSnoot} from "../src/BoopTheSnoot.sol";

contract BoopTheSnootScript is Script {
    BoopTheSnoot public boopTheSnoot;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    // Network configurations
    struct NetworkConfig {
        uint256 chainId;
        string rpcUrl;
    }

    mapping(string => NetworkConfig) public networks;

    constructor() {
        // Berachain Testnet (Artio)
        networks["berachain-testnet"] = NetworkConfig({chainId: 80085, rpcUrl: "https://artio.rpc.berachain.com"});

        // Berachain Mainnet (when available)
        networks["berachain-mainnet"] = NetworkConfig({
            chainId: 80086, // Note: Update this when mainnet is live
            rpcUrl: "https://mainnet.rpc.berachain.com" // Update when available
        });
    }

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address updater = vm.envAddress("UPDATER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy contract
        boopTheSnoot = new BoopTheSnoot();

        // Setup roles
        boopTheSnoot.grantRole(ADMIN_ROLE, admin);
        boopTheSnoot.grantRole(UPDATER_ROLE, updater);

        vm.stopBroadcast();

        console.log("BoopTheSnoot deployed to:", address(boopTheSnoot));
        console.log("Admin role granted to:", admin);
        console.log("Updater role granted to:", updater);
    }
}
