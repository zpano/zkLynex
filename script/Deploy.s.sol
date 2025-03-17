// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/ZDP-C.sol";
import "../src/zk.sol";

contract ZDPScript is Script {
    address router = 0xE233D75Ce6f04C04610947188DEC7C55790beF3b;
    address owner = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf; // Set actual owner address
    address agent = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf; // Set actual agent address

    function run() public {
        vm.startBroadcast(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf);

        Groth16Verifier verifier = new Groth16Verifier();
        console.log("Groth16Verifier deployed to:", address(verifier));
        ZDPc zdp = new ZDPc(agent, payable(router), address(verifier), owner);

        vm.stopBroadcast();

        // console.log("ZDP deployed to:", address(zdp));
    }
}
