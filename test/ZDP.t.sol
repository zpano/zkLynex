// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "../src/ZDP-C.sol";

interface ERC20mint {
    function mint() external;
}

contract ZDPTest is Test {
    address owner = makeAddr("owner");
    address agent = makeAddr("agent");
    address router = 0x1cB193aE57149a4f03C20860C2aC45AC05E29159;
    address swapper = makeAddr("swapper");
    address ETH = 0xce830D0905e0f7A9b300401729761579c5FB6bd6; //ERC20-ETH
    address BTC = 0x1E0D871472973c562650E991ED8006549F8CBEfc; //ERC20-BTC
    Groth16Verifier verify;
    ZDPc zdp;

    struct Os {
        uint256 a0e;
        uint256 a1m;
        bytes32 salt;
    }

    function setUp() public {
        vm.createSelectFork("https://og-testnet-evm.itrocket.net");
        verify = new Groth16Verifier();
        zdp = new ZDPc(agent, payable(router), address(verify), owner);
    }

    function testStoreOrder() public {
        vm.startPrank(swapper);
        ZDPc.OrderDetails memory ot = ZDPc.OrderDetails({
            swapper: swapper,
            recipient: address(0x1234),
            tokenIn: ETH,
            tokenOut: BTC, //usdc
            exchangeRate: 166e18,
            deadline: block.timestamp + 1 weeks,
            OrderIsExecuted: false,
            isMultiPath: false,
            encodedPath: new bytes(0)
        });

        Os memory os = Os({a0e: 1e18, a1m: 1500 * 1e6, salt: keccak256("123")});
        console.logBytes(abi.encode(os));
        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly {
            HF := h
            HE := shl(128, h)
        }

        ZDPc.Order memory order = ZDPc.Order({t: ot, HOsF: HF, HOsE: HE});

        zdp.addPendingOrder(order);
        ZDPc.Order memory orderStored = zdp.getOrder(swapper, 0);
        assertEq(orderStored.t.tokenIn, ot.tokenIn);
        assertEq(orderStored.t.tokenOut, ot.tokenOut);
        assertEq(orderStored.t.swapper, ot.swapper);
        assertEq(orderStored.t.recipient, ot.recipient);
        assertEq(orderStored.t.exchangeRate, ot.exchangeRate);
        assertEq(orderStored.t.deadline, ot.deadline);
        assertEq(orderStored.t.OrderIsExecuted, ot.OrderIsExecuted);
        assertEq(orderStored.t.isMultiPath, ot.isMultiPath);
        assertEq(orderStored.t.encodedPath, ot.encodedPath);
        assertEq(orderStored.HOsF, order.HOsF);
        assertEq(orderStored.HOsE, order.HOsE);
    }

    function testSwapForward() public {
        //------store order-------
        vm.startPrank(swapper);
        ZDPc.OrderDetails memory ot = ZDPc.OrderDetails({
            swapper: swapper,
            recipient: address(0x1234),
            tokenIn: ETH,
            tokenOut: BTC, //usdc
            exchangeRate: 166e18,
            deadline: block.timestamp + 1 weeks,
            OrderIsExecuted: false,
            isMultiPath: false,
            encodedPath: new bytes(0)
        });

        Os memory os = Os({
            a0e: 1000000000000000000,
            a1m: 1500000000000000,
            salt: 0x04e604787cbf194841e7b68d7cd28786f6c9a0a3ab9f8b0a0e87cb4387ab0107
        });
        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly {
            HF := h
            HE := shl(128, h)
        }

        ZDPc.Order memory order =
            ZDPc.Order({t: ot, HOsF: HF, HOsE: HE});

        zdp.addPendingOrder(order);

        //------deposit fee-------
        vm.deal(swapper, 1000 ether);
        zdp.depositForGasFee{value: 10 ether}(swapper);
        assertEq(zdp.gasfee(swapper), 10 ether);

        //-------mint token--------
        ERC20mint(ETH).mint();
        IERC20(ETH).approve(address(zdp), 1e18);
        vm.stopPrank();

        vm.stopPrank();

        uint256[2] memory proofA;
        uint256[2][2] memory proofB;
        uint256[2] memory proofC;

        uint256[4] memory signals;

        proofA = [
            0x04694c7ee2d7d5f486b0701867225d904b12bf64ef4d75e11c547523319d170e,
            0x2cf83f4ddc33aa4203343c116281d8cd6f6342531dd6af7843ce344bb5a711c2
        ];
        proofB = [
            [
                0x2ec367aecf8fb8b6f6f10822b8f2f626aabfa621398e137f147483f658091d31,
                0x292fceff7a700d586756d57c8f6ddf050e0497b47b9d2e7a3179b6d42425000a
            ],
            [
                0x17df5f1b40fbd5004e2307095102ffe4d0ce0e2ef10fd2bd1dbe9a797bfc11e3,
                0x169a8d10d7d826e98ff8d9166c5c627a2ea64b4f70afec635e57f87123983492
            ]
        ];
        proofC = [
            0x21add50213c1894a819c8c5854da0e3948a49512ed7815c793ff8772de675886,
            0x0f681e2576f40c464c93a038bee85213baf1d149d2691aa3519589e8db53db4e
        ];
        signals = [
            uint256(0x000000000000000000000000000000003b072a65d64ed9f6e5fcb05c0db08ab3),
            0x00000000000000000000000000000000bb47b19096cbd22af098d64e5573f466,
            0x0000000000000000000000000000000000000000000000000de0b6b3a7640000,
            0x0000000000000000000000000000000000000000000000000005543df729c000
        ];

        //------swap forward-------
        vm.startPrank(agent);
        zdp.swapForward(
            proofA, proofB, proofC, swapper, 0, 1000000000000000000, 1500000000000000, 0.0075 ether, ZDPc.OrderType.ExactInput
        );
        vm.stopPrank();

        assertEq(IERC20(ETH).balanceOf(swapper), 9 ether);
        assert(IERC20(BTC).balanceOf(address(0x1234)) > 1500000000000000);
        ZDPc.OrderDetails memory otStored = zdp.getOrder(swapper, 0).t;
        assertEq(otStored.OrderIsExecuted, true);
    }

    function testSetAgent() public {
        address newAgent = makeAddr("newAgent");

        // Call the setAgent function
        vm.startPrank(owner);
        zdp.setAgent(newAgent);
        vm.stopPrank();

        // Assert the new agent is set correctly
        assertEq(zdp.agent(), newAgent, "Agent should be updated.");
    }

    function testSetRouter() public {
        address newRouter = makeAddr("newRouter");

        // Call the setRouter function
        vm.startPrank(owner);
        zdp.setRouter(newRouter);
        vm.stopPrank();

        // Assert the router is updated correctly
        assertEq(address(zdp.router()), newRouter, "Router should be updated.");
    }

    function testSetVerifier() public {
        address newVerifier = makeAddr("newVerifier");

        // Call the setVerifier function
        vm.startPrank(owner);
        zdp.setVerifier(newVerifier);
        vm.stopPrank();

        // Assert the verifier is updated correctly
        assertEq(address(zdp.verifier()), newVerifier, "Verifier should be updated.");
    }

    function testDeposit() public {
        uint256 amount = 1000 ether;
        vm.deal(swapper, amount);
        vm.startPrank(swapper);

        zdp.depositForGasFee{value: amount}(swapper);
        assertEq(zdp.gasfee(swapper), amount);
    }

    function testWithdraw() public {
        uint256 amount = 1000 ether;
        vm.deal(swapper, amount);
        vm.startPrank(swapper);

        zdp.depositForGasFee{value: amount}(swapper);
        assertEq(zdp.gasfee(swapper), amount);

        zdp.withdrawGasFee(amount);
        assertEq(zdp.gasfee(swapper), 0 ether);
        assertEq(swapper.balance, amount);
    }

    function testCancelOrder() public {
        vm.startPrank(swapper);

        //------store order-------
        ZDPc.OrderDetails memory ot = ZDPc.OrderDetails({
            swapper: swapper,
            recipient: address(0x1234),
            tokenIn: ETH,
            tokenOut: BTC, //usdc
            exchangeRate: 166e18,
            deadline: block.timestamp + 1 weeks,
            OrderIsExecuted: false,
            isMultiPath: false,
            encodedPath: new bytes(0)
        });

        Os memory os = Os({a0e: 1e18, a1m: 1500 * 1e6, salt: keccak256("123")});

        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly {
            HF := h
            HE := shl(128, h)
        }

        ZDPc.Order memory order = ZDPc.Order({t: ot, HOsF: HF, HOsE: HE});

        zdp.addPendingOrder(order);

        vm.deal(swapper, 1000 ether);
        vm.startPrank(swapper);

        //------deposit fee-------
        zdp.depositForGasFee{value: 1000 ether}(swapper);
        assertEq(zdp.gasfee(swapper), 1000 ether);
        assertEq(zdp.getOrders(swapper).length, 1);

        //------cancel order-------
        zdp.cancelOrder(0);

        assertEq(zdp.getOrders(swapper).length, 0);
    }

    function testVerify() public view {
        uint256[2] memory proofA;
        uint256[2][2] memory proofB;
        uint256[2] memory proofC;

        uint256[4] memory signals;

        proofA = [
            0x2bb9bca84688fe8e0212a8ec428c149e8ae8755430d9f204eb3abcf60b4a2c64,
            0x0487b8802cddbba2c034f34d44abcdc736b0ae765d484970aafa5d7f5894b954
        ];
        proofB = [
            [
                0x2660150c4f134a7031907f2e86a2f712509064233977ada79e4b02a58ad01a46,
                0x226cd7958dfbcf90977427f8ed663887281446d6e1f8f1b3752e541ab30d7d9b
            ],
            [
                0x026bf76744f5731241180b33a13813c494db8ae6cc9ec7187290a54a690341bd,
                0x295718da03915af249695c7e8af37a221dbbc8873823f5e01d6cfd4b3a088491
            ]
        ];
        proofC = [
            0x15238b7d582d1986f1498359db678f86fd9876a9ea3780d0932cb8b8755c9b66,
            0x0343923d38378f15f5d6d4545b516c2731e984aeec72f2f2262e0bc2532677ce
        ];
        signals = [
            uint256(0x00000000000000000000000000000000fe68ccb98cf12cb40ce6db4ea1040db2),
            0x0000000000000000000000000000000080fca98f10f980255dbc64ca54d5d78a,
            0x0000000000000000000000000000000000000000000000000000000000cdae90,
            0x000000000000000000000000000000000000000000000000000000000063bd12
        ];
        assertEq(verify.verifyProof(proofA, proofB, proofC, signals), true);
    }
}
