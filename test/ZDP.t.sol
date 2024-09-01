// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/ZDP-C.sol";

contract ZDPTest is Test {
    address owner = makeAddr("owner");
    address agent = makeAddr("agent");
    address router = 0x610D2f07b7EdC67565160F587F37636194C34E74;
    address swapper = makeAddr("swapper");
    ZDPc zdp;

    struct Os{
        uint a0e;
        uint a1m;
        bytes32 salt;
    }

    function setUp() public {
        vm.createSelectFork("https://rpc.linea.build");
        zdp = new ZDPc(owner, payable(router), agent, 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);
    }

    function testStoreOrder() public {
        vm.startPrank(swapper);
        ZDPc.Ot memory ot = ZDPc.Ot({
            swapper: swapper,
            receiver: address(0x1234),
            token0: address(0),
            token1: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),//usdc
            er: 5e26,
            ddl: block.timestamp + 1 weeks,
            f: false
        });

        Os memory os = Os({
            a0e: 1e18,
            a1m: 1500 * 1e6,
            salt: keccak256("123")
        });

        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly{
            HF := h
            HE := shl(128, h)
      }

        ZDPc.Order memory order = ZDPc.Order({
            t: ot,
            HOsF: HF,
            HOsE: HE
        });

        zdp.storeOrder(order);

        ZDPc.Order memory orderStored = zdp.getOrder(swapper,0);
        assertEq(orderStored.t.token1, ot.token1);
        assertEq(orderStored.t.token0, ot.token0);
        assertEq(orderStored.t.swapper, ot.swapper);
        assertEq(orderStored.t.receiver, ot.receiver);
        assertEq(orderStored.t.er, ot.er);
        assertEq(orderStored.t.ddl, ot.ddl);
        assertEq(orderStored.t.f, ot.f);
        assertEq(orderStored.HOsF, order.HOsF);
        assertEq(orderStored.HOsE, order.HOsE);
    }

    function testDeposit()public{
        vm.deal(swapper, 1000 ether);
        vm.startPrank(swapper);

        zdp.depositForFeeOrSwap{value: 1000 ether}(swapper);
        assertEq(zdp.feeB(swapper), 1000 ether);
    }

    function testWithdraw()public{
        vm.deal(swapper, 1000 ether);
        vm.startPrank(swapper);

        zdp.depositForFeeOrSwap{value: 1000 ether}(swapper);
        assertEq(zdp.feeB(swapper), 1000 ether);

        zdp.withdrawAllFee();
        assertEq(zdp.feeB(swapper), 0 ether);
        assertEq(swapper.balance, 1000 ether);
    }

    function testCancelOrder()public{
        vm.startPrank(swapper);

        //------store order-------
        ZDPc.Ot memory ot = ZDPc.Ot({
            swapper: swapper,
            receiver: address(0x1234),
            token0: address(0),
            token1: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),//usdc
            er: 5e26,
            ddl: block.timestamp + 1 weeks,
            f: false
        });

        Os memory os = Os({
            a0e: 1e18,
            a1m: 1500 * 1e6,
            salt: keccak256("123")
        });

        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly{
            HF := h
            HE := shl(128, h)
      }

        ZDPc.Order memory order = ZDPc.Order({
            t: ot,
            HOsF: HF,
            HOsE: HE
        });

        zdp.storeOrder(order);

        vm.deal(swapper, 1000 ether);
        vm.startPrank(swapper);

        //------deposit fee-------
        zdp.depositForFeeOrSwap{value: 1000 ether}(swapper);
        assertEq(zdp.feeB(swapper), 1000 ether);

        //------cancel order-------
        zdp.cancelOrder(0, true);


        assertEq(zdp.getOrders(swapper).length, 0);
        assertEq(zdp.feeB(swapper), 0 ether);
        assertEq(swapper.balance, 1000 ether);
    }

    function testSwapForwardETHforTokens()public{
        vm.startPrank(swapper);
         //------store order-------
        ZDPc.Ot memory ot = ZDPc.Ot({
            swapper: swapper,
            receiver: address(0x1234),
            token0: address(0),
            token1: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),//usdc
            er: 5e26,
            ddl: block.timestamp + 1 weeks,
            f: false
        });

        Os memory os = Os({
            a0e: 1e18,
            a1m: 1500 * 1e6,
            salt: bytes32(0x04e604787cbf194841e7b68d7cd28786f6c9a0a3ab9f8b0a0e87cb4387ab0107)//keccak256("123")
        });

        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly{
            HF := h
            HE := shl(128, h)
      }

        ZDPc.Order memory order = ZDPc.Order({
            t: ot,
            HOsF: HF,
            HOsE: HE
        });

        zdp.storeOrder(order);

        vm.deal(swapper, 1000 ether);

        //------deposit fee-------
        zdp.depositForFeeOrSwap{value: 1000 ether}(swapper);
        assertEq(zdp.feeB(swapper), 1000 ether);

        vm.stopPrank();

        uint[2] memory proofA;
        uint[2][2] memory proofB;
        uint[2] memory proofC;

        uint256[4] memory signals;

        proofA = [0x28584ac2b6ed510163e2d88c95edb2588a3f946df5683c251dea919b6c4571d9, 0x227938b7f9a6d603db7ecd3b760b817cd08874eaa07f7a0a5d760153390a4aff];
        proofB = [[0x02a8124b48e18847112e565826943e26a405410a7583e4383eb466d1103329d6, 0x233a06644a9f4bf5bccfca2fe6d4fff8cff46d17667e41aa86abc83088257719],[0x285dc5b892c7a34146c5fbf49b8be1308698fa9a96d517dc892b71797ea19a76, 0x16209b306f79bb0a5263c4957ed6236b2db98e235620240ef31486ccf0d267db]];
        proofC = [0x184f3859a4f3377d7d1ecc87eb453f5c9dac09ddbd744c8121ea609e0ea9f37c, 0x1a8d273d8efa7c3bf7344b138cdf5abe71553ef2a70e8f7ab1c6efb1eba38650];
        signals = [uint(0x000000000000000000000000000000008e672d8224f8243233773effeafc3dba), 0x000000000000000000000000000000000daabdd16bf8a7a9b47ee89f19a81b86, 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000, 0x0000000000000000000000000000000000000000000000000000000059682f00];

        //------swap forward-------

        RouterV2.route[] memory route = new RouterV2.route[](1);
        route[0] = RouterV2.route({
            from: address(0),
            to: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),
            stable: false
        });

        vm.startPrank(agent);
        zdp.swapForward(proofA,proofB, proofC,swapper, route, 1e18, 1500 * 1e6, 0, 0.0075 ether, ZDPc.OrderType.ExactETHForTokens);
        vm.stopPrank();

        assertEq(zdp.getOrder(swapper,0).t.f, true);
        assertEq(zdp.feeB(swapper), 1000 ether - 0.0075 ether - 1 ether);
        assertEq(zdp.feeB(owner), 0.0075 ether);
        assertGt(IERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff).balanceOf(ot.receiver), 1500 * 1e6);
    }

    function testFee()public{
        testSwapForwardETHforTokens();
        vm.prank(owner);
        zdp.profit();
        assertEq(owner.balance, 0.0075 ether);
    }

    function testSwapForwardTokensForEth()public{
        vm.startPrank(swapper);
         //------store order-------
        ZDPc.Ot memory ot = ZDPc.Ot({
            swapper: swapper,
            receiver: address(0x1234),
            token0: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),
            token1: address(0),
            er: 3500000000,
            ddl: block.timestamp + 1 weeks,
            f: false
        });

        Os memory os = Os({
            a0e: 3500 * 1e6,
            a1m: 1 ether,
            salt: bytes32(0x04e604787cbf194841e7b68d7cd28786f6c9a0a3ab9f8b0a0e87cb4387ab0107)//keccak256("123")
        });

        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly{
            HF := h
            HE := shl(128, h)
      }

        ZDPc.Order memory order = ZDPc.Order({
            t: ot,
            HOsF: HF,
            HOsE: HE
        });

        zdp.storeOrder(order);

        deal(0x176211869cA2b568f2A7D4EE941E073a821EE1ff, swapper, 3500 * 1e6);
        vm.deal(swapper, 1 ether);
        IERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff).approve(address(zdp), os.a0e);

        zdp.depositForFeeOrSwap{value: 1 ether}(swapper);
        vm.stopPrank();

        uint[2] memory proofA;
        uint[2][2] memory proofB;
        uint[2] memory proofC;

        uint256[4] memory signals;

        proofA = [0x2e32b304540a29bd4565cf0f05ce91185f5169d31f587dd54422770840ad0891, 0x18f60105f988df13a8f05c51573fd2144e76fb7a458eac1d389579ad5aba7b36];
        proofB = [[0x2d62f6bb13902994ed124bfb2a4bd89b930103df59207144df3457f56a24cc4d, 0x2accd4fed60583c66b522e9c00ccf9909bd08ffda0f57c79fdd92c50e6c429ff],[0x1810d68fa4b345d4f7cda9d75ded617dee86707e40fc715fb082e9e40f190811, 0x1f15565bde89a2e26afe29ef2672db3c12a78cf7310b6576b82559a77b2d5f80]];
        proofC = [0x296151d59a7ae91d94fb5dc29af210a2b87939fe79d573ea07ff56c1014322df, 0x296bb26c5c714e6b101f036fdd99c23628e19358f71bc76e6f1b98a2deef7670];
        signals = [uint(0x000000000000000000000000000000004cc64708a9896889bf3ab93ab032ad48),0x00000000000000000000000000000000fd33ca9f16b65a6c528541a790b7946c,0x00000000000000000000000000000000000000000000000000000000d09dc300,0x0000000000000000000000000000000000000000000000000de0b6b3a7640000];

        //------swap forward-------

        RouterV2.route[] memory route = new RouterV2.route[](1);
        route[0] = RouterV2.route({
            from: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),
            to: address(0),
            stable: false
        });

        vm.startPrank(agent);
        zdp.swapForward(proofA,proofB, proofC,swapper, route, 3500 * 1e6, 1e18, 0, 0.0075 ether, ZDPc.OrderType.ExactTokensForETH);
        vm.stopPrank();

        assertEq(zdp.getOrder(swapper,0).t.f, true);
        assertEq(zdp.feeB(swapper), 1 ether - 0.0075 ether);
        assertEq(zdp.feeB(owner), 0.0075 ether);
        assertGe(ot.receiver.balance, 1 ether);
    }

    function testSwapForwardTokensForTokens()public{
        vm.startPrank(swapper);
         //------store order-------
        ZDPc.Ot memory ot = ZDPc.Ot({
            swapper: swapper,
            receiver: address(0x1234),
            token0: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),
            token1: address(zdp.weth()),
            er: 3500000000,
            ddl: block.timestamp + 1 weeks,
            f: false
        });

        Os memory os = Os({
            a0e: 3500 * 1e6,
            a1m: 1 ether,
            salt: bytes32(0x04e604787cbf194841e7b68d7cd28786f6c9a0a3ab9f8b0a0e87cb4387ab0107)//keccak256("123")
        });

        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly{
            HF := h
            HE := shl(128, h)
      }

        ZDPc.Order memory order = ZDPc.Order({
            t: ot,
            HOsF: HF,
            HOsE: HE
        });

        zdp.storeOrder(order);

        deal(0x176211869cA2b568f2A7D4EE941E073a821EE1ff, swapper, 3500 * 1e6);
        vm.deal(swapper, 1 ether);
        IERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff).approve(address(zdp), os.a0e);

        zdp.depositForFeeOrSwap{value: 1 ether}(swapper);
        vm.stopPrank();

        uint[2] memory proofA;
        uint[2][2] memory proofB;
        uint[2] memory proofC;

        uint256[4] memory signals;

        proofA = [0x2e32b304540a29bd4565cf0f05ce91185f5169d31f587dd54422770840ad0891, 0x18f60105f988df13a8f05c51573fd2144e76fb7a458eac1d389579ad5aba7b36];
        proofB = [[0x2d62f6bb13902994ed124bfb2a4bd89b930103df59207144df3457f56a24cc4d, 0x2accd4fed60583c66b522e9c00ccf9909bd08ffda0f57c79fdd92c50e6c429ff],[0x1810d68fa4b345d4f7cda9d75ded617dee86707e40fc715fb082e9e40f190811, 0x1f15565bde89a2e26afe29ef2672db3c12a78cf7310b6576b82559a77b2d5f80]];
        proofC = [0x296151d59a7ae91d94fb5dc29af210a2b87939fe79d573ea07ff56c1014322df, 0x296bb26c5c714e6b101f036fdd99c23628e19358f71bc76e6f1b98a2deef7670];
        signals = [uint(0x000000000000000000000000000000004cc64708a9896889bf3ab93ab032ad48),0x00000000000000000000000000000000fd33ca9f16b65a6c528541a790b7946c,0x00000000000000000000000000000000000000000000000000000000d09dc300,0x0000000000000000000000000000000000000000000000000de0b6b3a7640000];

        //------swap forward-------

        RouterV2.route[] memory route = new RouterV2.route[](1);
        route[0] = RouterV2.route({
            from: address(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),
            to: address(zdp.weth()),
            stable: false
        });

        vm.startPrank(agent);
        zdp.swapForward(proofA,proofB, proofC,swapper, route, 3500 * 1e6, 1e18, 0, 0.0075 ether, ZDPc.OrderType.ExactTokensForTokens);
        vm.stopPrank();

        assertEq(zdp.getOrder(swapper,0).t.f, true);
        assertEq(zdp.feeB(swapper), 1 ether - 0.0075 ether);
        assertEq(zdp.feeB(owner), 0.0075 ether);
        assertGe(zdp.weth().balanceOf(ot.receiver),1 ether);
    }

    function testVerify()public{
        Groth16Verifier verify;
        verify = new Groth16Verifier();
        uint[2] memory proofA;
        uint[2][2] memory proofB;
        uint[2] memory proofC;

        uint256[4] memory signals;

        proofA = [0x2bb9bca84688fe8e0212a8ec428c149e8ae8755430d9f204eb3abcf60b4a2c64, 0x0487b8802cddbba2c034f34d44abcdc736b0ae765d484970aafa5d7f5894b954];
        proofB = [[0x2660150c4f134a7031907f2e86a2f712509064233977ada79e4b02a58ad01a46, 0x226cd7958dfbcf90977427f8ed663887281446d6e1f8f1b3752e541ab30d7d9b],[0x026bf76744f5731241180b33a13813c494db8ae6cc9ec7187290a54a690341bd, 0x295718da03915af249695c7e8af37a221dbbc8873823f5e01d6cfd4b3a088491]];
        proofC = [0x15238b7d582d1986f1498359db678f86fd9876a9ea3780d0932cb8b8755c9b66, 0x0343923d38378f15f5d6d4545b516c2731e984aeec72f2f2262e0bc2532677ce];
        signals = [uint(0x00000000000000000000000000000000fe68ccb98cf12cb40ce6db4ea1040db2),0x0000000000000000000000000000000080fca98f10f980255dbc64ca54d5d78a,0x0000000000000000000000000000000000000000000000000000000000cdae90,0x000000000000000000000000000000000000000000000000000000000063bd12];
        assertEq(verify.verifyProof(proofA, proofB, proofC, signals), true);
    }

}
