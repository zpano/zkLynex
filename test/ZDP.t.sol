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
            a0e: 1e18,
            a1m: 1500000000000000,
            salt: keccak256("123") //keccak256(0x1234)
        });
        bytes32 h = keccak256(abi.encode(os));
        bytes16 HF;
        bytes16 HE;
        assembly {
            HF := h
            HE := shl(128, h)
        }
        console.logBytes16(HF);
        console.logBytes16(HE);

        ZDPc.Order memory order =
            ZDPc.Order({t: ot, HOsF: 0x58ed6fef81098ffaf5311b5d2a881d1b, HOsE: 0xf1de7e4b62c5929c57cff833cff56e77});

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
            0x02275df15a325da0af10110f01ae0f656d969f552d4cfcc2fd32f8891f509b70,
            0x164584f6e92a117543b76e7de79dcf07908b1ff3d62d7fc5442b34367d531be6
        ];
        proofB = [
            [
                0x213bd523cabcdb8a2e2e8160be3b9918ff3bad613afd74087c5ea4ba538b51a0,
                0x28dbce86d75c085c2e6e596a4022ecb509c0a2155b9e78fbbb3c588057505de9
            ],
            [
                0x305053af13c21ae5b411dd1fcb17fa13fb6d427cf05f70a7b32cc8c226ce278b,
                0x103f13eea4daa504c268c675b101ca021f846dda5ffd1baa361517bc7f7597c0
            ]
        ];
        proofC = [
            0x0538c60f46074a82a5365ca55e5db2e6cee2b15010bae38802fc6c422a62dab7,
            0x158af614bcb92d091c196730d0e0e5c182dffda094d8289d92fd562823a20bba
        ];
        signals = [
            uint256(0x0000000000000000000000000000000058ed6fef81098ffaf5311b5d2a881d1b),
            0x00000000000000000000000000000000f1de7e4b62c5929c57cff833cff56e77,
            0x0000000000000000000000000000000000000000000000000de0b6b3a7640000,
            0x0000000000000000000000000000000000000000000000000005543df729c000
        ];
        //invalid proof

        //------swap forward-------
        vm.startPrank(agent);
        zdp.swapForward(
            proofA, proofB, proofC, swapper, 0, 1e18, 1500000000000000, 0.0075 ether, ZDPc.OrderType.ExactInput
        );
        vm.stopPrank();
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
