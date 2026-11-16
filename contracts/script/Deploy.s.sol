// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {MapAccountFactory} from "../src/MapAccountFactory.sol";
import {MapNFT} from "../src/MapNFT.sol";
import {RunNFT} from "../src/RunNFT.sol";

contract Deploy is Script {
    /// @dev Người broadcast trở thành owner (moderator) của MapNFT.
    function run() external returns (MapNFT nft, MapAccountFactory factory, RunNFT runNft) {
        vm.startBroadcast();
        nft = new MapNFT();
        factory = new MapAccountFactory();
        runNft = new RunNFT();
        vm.stopBroadcast();

        console.log("MapNFT deployed at:", address(nft));
        console.log("MapAccountFactory deployed at:", address(factory));
        console.log("RunNFT deployed at:", address(runNft));
    }
}
