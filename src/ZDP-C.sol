// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./interface/ISwapRouter.sol";
import "./interface/IWETH.sol";
import "./zk.sol";

contract ZDPc is Ownable2Step, ReentrancyGuard {

    using SafeERC20 for IERC20;

    struct OrderDetails {
        address swapper;
        address recipient;
        address tokenIn;
        address tokenOut;
        uint exchangeRate;
        uint deadline;
        bool OrderIsExecuted;
        bool isMultiPath;     // Flag to indicate if this is a multi-path order
        bytes encodedPath;    // Encoded path for multi-hop swaps
    }

    struct Order {
        OrderDetails t;
        bytes16 HOsF;
        bytes16 HOsE;
    }
    enum OrderType {
        ExactInput,
        ExactOnput
    }

    address public agent;

    ISwapRouter public router;
    IWETH public weth;
    Groth16Verifier public verifier;

    mapping(address => Order[]) public orderbook;
    mapping(address => uint) public gasfee;

    modifier onlyAgent {
        require(msg.sender == agent, "only agent can call this function");
        _;
    }

    event AgentChanged(address indexed oldAgent, address indexed newAgent);
    event RouterChanged(address indexed oldRouter, address indexed newRouter);
    event VerifierChanged(address indexed oldVerifier, address indexed newVerifier);
    event OrderStored(address indexed swapper,uint indexed index, address tokenIn, address tokenOut, uint  exchangeRate, uint deadline, bool OrderIsExecuted);
    event OrderExecuted(address swapper, uint indexed index, address tokenIn, address tokenOut, uint  exchangeRate, uint deadline, bool OrderIsExecuted);
    event OrderCancelled(address swapper, uint indexed index, address tokenIn, address tokenOut, uint  exchangeRate, uint deadline, bool OrderIsExecuted);
    event FeeDeposit(address indexed swapper, uint indexed fee);
    event FeeWithdrawn(address indexed swapper, uint indexed fee);
    event FeeTaken(address indexed swapper, uint indexed fee);
    event TakenFeeWithdrawn(address indexed owner, uint indexed fee);
    

    constructor(address _agent, address payable _router, address _weth, address _verifier, address _owner) Ownable(_owner){
        require(_agent != address(0));
        require(_router != address(0));
        require(_verifier != address(0));
        agent = _agent;

        router = ISwapRouter(_router);
        weth = IWETH(payable(_weth));
        verifier = Groth16Verifier(_verifier);
    }

    function setAgent(address _agent) external onlyOwner {
        address oldAgent = agent;
        agent = _agent;
        emit AgentChanged(oldAgent,_agent);
    }
    
    function setRouter(address _router) external onlyOwner {
        address oldRouter = address(router);
        router = ISwapRouter(_router);
        emit RouterChanged(oldRouter, _router);
    }

    function setVerifier(address _verifier) external onlyOwner {
        address oldVerifier = address(verifier);
        verifier = Groth16Verifier(_verifier);
        emit VerifierChanged(oldVerifier, _verifier);
    }


    function addPendingOrder(Order memory _order) external {
        //@todo check order
        checkOrder(_order);
        require(!_order.t.OrderIsExecuted, "cannot be executed");
        uint index = orderbook[_order.t.swapper].length;
        orderbook[_order.t.swapper].push(_order);

        emit OrderStored(msg.sender, index, _order.t.tokenIn, _order.t.tokenOut, _order.t.exchangeRate, _order.t.deadline, _order.t.OrderIsExecuted);
    }

    function depositForGasFee(address swapper) external payable{
        require(msg.value > 0, "deposit must be non-zero value");
        require(swapper != address(0), "swapper must be non-zero address");

        gasfee[swapper] += msg.value;

        emit FeeDeposit(swapper, msg.value);
    }

    function withdrawGasFee(uint amount) public nonReentrant {
        require(amount > 0);
        require(gasfee[msg.sender] >= amount, "No enough fee to take");

        gasfee[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        emit FeeWithdrawn(msg.sender, amount);
    }

    function withdrawTakenFee() external onlyOwner {
        uint amount = gasfee[owner()];

        gasfee[owner()] = 0;
        (bool success, ) = owner().call{value: amount}("");
        require(success, "transfer failed");

        emit TakenFeeWithdrawn(owner(), amount);
    }
    
    function swapForward(
        uint256[2] calldata _proofA,
        uint256[2][2] calldata _proofB,
        uint256[2] calldata _proofC,
        address swapper,
        uint256 index,
        uint256 a0e,
        uint256 a1m,
        uint256 _gasFee,
        OrderType _type
    ) external payable onlyAgent {
        Order memory pendingOrder = orderbook[swapper][index];
        address recipient = pendingOrder.t.recipient;
        address tokenIn = pendingOrder.t.tokenIn;
        address tokenOut = pendingOrder.t.tokenOut;

        //      require(path.length > 0);
        //      require(pendingOrder.t.tokenIn == path[0].from, "tokenIn mismatch");
        //      require(pendingOrder.t.tokenOut == path[path.length - 1].to, "tokenOut mismatch");
        require(pendingOrder.t.exchangeRate <= (a0e * 1 ether) / (a1m), "bad exchangeRate");
        require(!pendingOrder.t.OrderIsExecuted, "already executed");
        require(block.timestamp <= pendingOrder.t.deadline, "order expired");

        uint256[4] memory signals;
        signals[0] = uint256(uint128(pendingOrder.HOsF));
        signals[1] = uint256(uint128(pendingOrder.HOsE));
        signals[2] = a0e;
        signals[3] = a1m;

        require(verifier.verifyProof(_proofA, _proofB, _proofC, signals), "Proof is not valid");

        if (tokenIn == address(0)) {
            require(gasfee[pendingOrder.t.swapper] >= _gasFee + a0e, "insufficient fee balance");
            gasfee[pendingOrder.t.swapper] -= a0e;
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
                recipient: recipient,
                deadline: pendingOrder.t.deadline,
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
                recipient: recipient,
                deadline: pendingOrder.t.deadline,
                amountIn: a0e,
                amountOutMinimum: a1m,
                sqrtPriceLimitX96: 0
            });
            router.exactInputSingle(params);
        } else if (_type == OrderType.ExactTokensForTokens || _type == OrderType.ExactTokensForTokensFot) {
            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, uint24(3000), tokenOut),
                recipient: recipient,
                deadline: pendingOrder.t.deadline,
                amountIn: a0e,
                amountOutMinimum: a1m
            });
            router.exactInput(params);
        }

        orderbook[swapper][index].t.OrderIsExecuted = true;
        takeFeeInternal(pendingOrder.t.swapper, _gasFee);
        emit OrderExecuted(
            pendingOrder.t.swapper, index, pendingOrder.t.tokenIn, pendingOrder.t.tokenOut, pendingOrder.t.exchangeRate, pendingOrder.t.deadline, pendingOrder.t.OrderIsExecuted
        );
    }

    function takeFeeInternal(address swapper, uint gasFeeAmount) internal {
        //@nOrderDetailse The off-chain script retrieves the fee for this transaction, using parameters to pass how much gasFee is charged --- bOrderDetailsh web3py and web3js have the estimateGas API
        require(gasFeeAmount <= 0.075 ether, "gasFee is too high");//@nOrderDetailse Set an upper limit to prevent the script from being malicious
        require(gasfee[swapper] >= gasFeeAmount, "does not have enough fee to take");
        gasfee[swapper] -= gasFeeAmount;
        gasfee[owner()] += gasFeeAmount;

        emit FeeTaken(swapper, gasFeeAmount);
    }


    function cancelOrder(uint index) external {
        require(!orderbook[msg.sender][index].t.OrderIsExecuted, "already executed");
        require(orderbook[msg.sender][index].t.recipient != address(0), "recipient does not exist");

        Order memory tempOrder;
        uint len = orderbook[msg.sender].length;
        tempOrder = orderbook[msg.sender][len - 1];
        orderbook[msg.sender][len - 1] = orderbook[msg.sender][index];
        orderbook[msg.sender][index] = tempOrder;
        orderbook[msg.sender].pop();
        //@todo need auto withdraw fee?
        // if(orderbook[msg.sender].length == 0 && takeFee){
        //     withdrawAllFee();
        // }

        emit OrderCancelled(msg.sender, index, tempOrder.t.tokenIn, tempOrder.t.tokenOut, tempOrder.t.exchangeRate, tempOrder.t.deadline, tempOrder.t.OrderIsExecuted);
    }

    function checkOrder(Order memory _order) internal view returns(bool){
        require(block.timestamp < _order.t.deadline, "order expired");
        require(_order.t.tokenIn != _order.t.tokenOut, "tokenIn == tokenOut");
        require(_order.t.recipient != address(0), "recipient must be non-zero address");
        require(_order.t.exchangeRate != 0, "exchangeRate must be non-zero value");
        require(_order.t.swapper == msg.sender, "only swapper can store order");
        return true;
    }

}

