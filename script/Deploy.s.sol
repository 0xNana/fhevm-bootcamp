// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {FHECounter} from "../src/FHECounter.sol";

/// @title Deploy
/// @notice Forge script to deploy the FHECounter contract.
///
/// Usage:
///   # Local (with mock FHE):
///   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
///
///   # Sepolia (real FHE):
///   forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
contract DeployScript is Script {
    function run() public {
        vm.startBroadcast();

        FHECounter counter = new FHECounter();
        console.log("FHECounter deployed at:", address(counter));

        vm.stopBroadcast();
    }
}
