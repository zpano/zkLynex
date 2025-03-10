// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "./interface/ISwapRouter.sol";
import "./interface/IWETH.sol";
import "./zk.sol";

contract ZDPc is Ownable2Step {
    using SafeERC20 for IERC20;

    struct Ot {
        address swapper;
        address receiver;
        address token0;
        address token1;
        uint256 exchangeRate; //@note How much of the spent token is needed for each unit of the target token (a0e * 1e^decimals0) / (a1m * 1e^decimals1) has 18 decimal places. For example, 2e10 USDC for 2e18 ETH would result in: exchangeRate = (2e10 * 1e18) / 2e18 = 2e10."
        uint256 ddl;
        bool executed;
    }

    struct Order {
        Ot t;
        // bytes32 HOs;
        bytes16 HOsF;
        bytes16 HOsE;
    }

    enum OrderType {
        ExactETHForTokens,
        ExactETHForTokensFot,
        ExactTokensForETH,
        ExactTokensForETHFot,
        ExactTokensForTokens,
        ExactTokensForTokensFot
    }

    address public agent;

    ISwapRouter public router;
    IWETH public weth;
    Groth16Verifier public verifier;

    mapping(address => Order[]) public orderbook;
    mapping(address => uint256) public feeB;

    modifier onlyAgent() {
        require(msg.sender == agent, "only agent can call this function");
        _;
    }

    event OrderStored(
        address indexed swapper,
        uint256 indexed index,
        address token0,
        address token1,
        uint256 indexed exchangeRate,
        uint256 ddl,
        bool executed
    );
    event FeeDeposit(address indexed swapper, uint256 indexed fee);
    event FeeWithdrawn(address indexed swapper, uint256 indexed fee);
    event OrderExecuted(
        address swapper,
        uint256 indexed index,
        address token0,
        address token1,
        uint256 indexed exchangeRate,
        uint256 indexed ddl,
        bool executed
    );
    event FeeTaken(address indexed swapper, uint256 indexed fee);
    event profitTaken(uint256 indexed fee);
    event OrderCancelled(
        address swapper,
        uint256 indexed index,
        address token0,
        address token1,
        uint256 indexed exchangeRate,
        uint256 indexed ddl,
        bool executed
    );

    constructor(address _owner, address payable _router, address _agent, address _weth) Ownable(_owner) {
        require(_agent != address(0));
        require(_router != address(0));
        // _transferOwnership(_owner);
        router = ISwapRouter(_router);
        agent = _agent;
        weth = IWETH(payable(_weth));
        verifier = new Groth16Verifier();
    }

    function setAgent(address _agent) external onlyOwner {
        agent = _agent;
    }

    function storeOrder(Order memory oBar) external {
        require(!oBar.t.executed, "already executed");
        require(block.timestamp < oBar.t.ddl, "order expired");
        require(oBar.t.token0 != oBar.t.token1, "token0 == token1");
        require(oBar.t.receiver != address(0), "receiver must be non-zero address");
        require(oBar.t.exchangeRate != 0, "exchangeRate must be non-zero value");
        require(oBar.t.swapper == msg.sender, "only swapper can store order");

        uint256 index;
        index = orderbook[oBar.t.swapper].length;
        orderbook[oBar.t.swapper].push(oBar);

        emit OrderStored(
            msg.sender, index, oBar.t.token0, oBar.t.token1, oBar.t.exchangeRate, oBar.t.ddl, oBar.t.executed
        );
    }

    function getOrders(address swapper) external view returns (Order[] memory) {
        return orderbook[swapper];
    }

    function getOrder(address swapper, uint256 index) external view returns (Order memory) {
        return orderbook[swapper][index];
    }

    function depositForFeeOrSwap(address swapper) external payable {
        require(msg.value > 0, "deposit must be non-zero value");
        require(swapper != address(0), "swapper must be non-zero address");

        feeB[swapper] += msg.value;

        emit FeeDeposit(swapper, msg.value);
    }

    function withdrawFee(uint256 amount) public {
        require(amount > 0);
        require(feeB[msg.sender] >= amount, "not enough fee to take");

        feeB[msg.sender] -= amount;
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        emit FeeWithdrawn(msg.sender, amount);
    }

    function withdrawAllFee() public {
        uint256 amount = feeB[msg.sender];
        withdrawFee(amount);
    }

    function swapForward(
        uint256[2] calldata _proofA,
        uint256[2][2] calldata _proofB,
        uint256[2] calldata _proofC,
        address swapper,
        uint256 a0e,
        uint256 a1m,
        uint256 index,
        uint256 gasFee,
        OrderType _type
    ) external payable onlyAgent {
        Order memory oBar = orderbook[swapper][index];
        address receiver = oBar.t.receiver;
        address tokenIn = oBar.t.token0;
        address tokenOut = oBar.t.token1;
        //      require(path.length > 0);
        //      require(oBar.t.token0 == path[0].from, "token0 mismatch");
        //      require(oBar.t.token1 == path[path.length - 1].to, "token1 mismatch");
        require(oBar.t.exchangeRate <= (a0e * 1 ether) / (a1m), "bad exchangeRate");
        require(!oBar.t.executed, "already executed");
        require(block.timestamp <= oBar.t.ddl, "order expired");

        uint256[4] memory signals;
        signals[0] = uint256(uint128(oBar.HOsF));
        signals[1] = uint256(uint128(oBar.HOsE));
        signals[2] = a0e;
        signals[3] = a1m;

        require(verifier.verifyProof(_proofA, _proofB, _proofC, signals), "Proof is not valid");

        if (tokenIn == address(0)) {
            require(feeB[oBar.t.swapper] >= gasFee + a0e, "insufficient fee balance");
            feeB[oBar.t.swapper] -= a0e;
            weth.deposit{value: a0e}();
            weth.approve(address(router), a0e);
            tokenIn = address(weth);
        } else {
            IERC20(tokenIn).safeTransferFrom(swapper, address(this), a0e);
            IERC20(tokenIn).approve(address(router), a0e);
        }

        if (tokenOut == address(0)) {
            tokenOut = address(weth);
        }

        if (_type == OrderType.ExactETHForTokens || _type == OrderType.ExactETHForTokensFot) {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn, // should be address(weth) after conversion
                tokenOut: tokenOut,
                fee: 3000,
                recipient: receiver,
                deadline: oBar.t.ddl,
                amountIn: a0e,
                amountOutMinimum: a1m,
                sqrtPriceLimitX96: 0
            });
            router.exactInputSingle{value: a0e}(params);
        } else if (_type == OrderType.ExactTokensForETH || _type == OrderType.ExactTokensForETHFot) {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut, // tokenOut should be address(weth) after conversion if originally ETH
                fee: 3000,
                recipient: receiver,
                deadline: oBar.t.ddl,
                amountIn: a0e,
                amountOutMinimum: a1m,
                sqrtPriceLimitX96: 0
            });
            router.exactInputSingle(params);
        } else if (_type == OrderType.ExactTokensForTokens || _type == OrderType.ExactTokensForTokensFot) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, uint24(3000), tokenOut),
                recipient: receiver,
                deadline: oBar.t.ddl,
                amountIn: a0e,
                amountOutMinimum: a1m
            });
            router.exactInput(params);
        }

        orderbook[swapper][index].t.executed = true;
        takeFeeInternal(oBar.t.swapper, gasFee);
        emit OrderExecuted(
            oBar.t.swapper, index, oBar.t.token0, oBar.t.token1, oBar.t.exchangeRate, oBar.t.ddl, oBar.t.executed
        );
    }

    function takeFeeInternal(address swapper, uint256 gasFee) internal {
        //@note The off-chain script retrieves the fee for this transaction, using parameters to pass how much gasFee is charged --- both web3py and web3js have the estimateGas API
        require(gasFee <= 0.075 ether); //@note Set an upper limit to prevent the script from being malicious
        require(feeB[swapper] >= gasFee, "not enough fee to take");
        feeB[swapper] -= gasFee;
        feeB[owner()] += gasFee;

        emit FeeTaken(swapper, gasFee);
    }

    function cancelOrder(uint256 index, bool takeFee) external {
        require(!orderbook[msg.sender][index].t.executed, "already executed");
        require(orderbook[msg.sender][index].t.receiver != address(0), "order does not exist");

        Order memory tempOrder;
        uint256 len = orderbook[msg.sender].length;
        tempOrder = orderbook[msg.sender][len - 1];
        orderbook[msg.sender][len - 1] = orderbook[msg.sender][index];
        orderbook[msg.sender][index] = tempOrder;
        orderbook[msg.sender].pop();

        if (orderbook[msg.sender].length == 0 && takeFee) {
            withdrawAllFee();
        }

        emit OrderCancelled(
            msg.sender,
            index,
            tempOrder.t.token0,
            tempOrder.t.token1,
            tempOrder.t.exchangeRate,
            tempOrder.t.ddl,
            tempOrder.t.executed
        );
    }

    function profit() external onlyOwner {
        withdrawAllFee();
    }
}
