// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/ZDP-C.sol";
import "../src/zk.sol";

contract ZDPScript is Script {
    address router = 0xE233D75Ce6f04C04610947188DEC7C55790beF3b;
    address owner = 0xE233D75Ce6f04C04610947188DEC7C55790beF3b; // Set actual owner address
    address agent = 0xE233D75Ce6f04C04610947188DEC7C55790beF3b; // Set actual agent address

    function run() public {
        vm.startBroadcast();

        Groth16Verifier verifier = new Groth16Verifier();
        console.log("Groth16Verifier deployed to:", address(verifier));
        ZDPc zdp = new ZDPc(agent, payable(router), address(verifier), owner);

        vm.stopBroadcast();

        console.log("ZDP deployed to:", address(zdp));
    }
}
