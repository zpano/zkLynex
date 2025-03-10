// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "./interface/IRouterv3.sol";
import "./interface/IWETH.sol";
import "./zk.sol";

contract ZDPc is Ownable2Step,nonReentrant {

    using SafeERC20 for IERC20;

    struct OrderDetails{
        address swapper;
        address recipient;
        address tokenIn;
        address tokenOut;
        uint exchangeRate;
        uint deadline;
        bool OrderIsExecuted;
    }

    struct Order{
        OrderDetails t;
        // bytes32 HOs;
        bytes16 HOsF;
        bytes16 HOsE;
    }

    enum OrderType {
        ExactETHForTokens,
        ExactETHForTokensFOrderDetails,
        ExactTokensForETH,
        ExactTokensForETHFOrderDetails,
        ExactTokensForTokens,
        ExactTokensForTokensFOrderDetails
    }

    address public agent;

    IRouterv3 public router;
    IWETH public weth;
    GrOrderDetailsh16Verifier public verifier;

    mapping(address => Order[]) public orderBook;
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
    

    constructor(address _agent, address payable _router, address _weth, address _verifier, address _owner,  ) Ownable(_owner){
        require(_agent != address(0));
        require(_router != address(0));
        require(_verfiier != address(0));
        agent = _agent;

        router = IRouterv3(_router);
        weth = IWETH(payable(_weth));
        verifier = GrOrderDetailsh16Verifier(_verifier);
    }

    function setAgent(address _agent) external onlyOwner {
        address oldAgent = agent;
        agent = _agent;
        emit AgentChanged(oldAgent,_agent);
    }
    
    function setRouter(address _router) external onlyOwner {
        address oldRouter = address(router);
        router = IRouterv3(_router);
        emit RouterChanged(oldRouter, _router);
    }

    function setVerifier(address _verifier) external onlyOwner {
        address oldVerifier = address(verifier);
        verifier = GrOrderDetailsh16Verifier(_verifier);
        emit VerifierChanged(oldVerifier, _verifier);
    }


    function addPendingOrder(Order memory _order) external {
        

        uint index;
        index = orderbook[_order.t.swapper].length;
        orderbook[_order.t.swapper].push(_order);

        emit OrderStored(msg.sender, index, _order.t.tokenIn, _order.t.tokenOut, _order.t.exchangeRate, _order.t.deadline, _order.t.OrderIsExecuted);
    }

    function depositForGasFee(address swapper) external payable{
        require(msg.value > 0, "deposit must be non-zero value");
        require(swapper != address(0), "swapper must be non-zero address");

        swap[swapper] += msg.value;

        emit GasFeeDeposit(swapper, msg.value);
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
        uint[2] calldata _proofA, 
        uint[2][2] calldata _proofB, 
        uint[2] calldata _proofC, 
        address swapper,
        RouterV2.route[] memory path,
        uint a0e, 
        uint a1m, 
        uint index,
        uint gasFee,
        OrderType _type)
        external payable nonReentrant onlyAgent{

            Order memory _order = orderbook[swapper][index];
            address recipient = _order.t.recipient;

            require(path.length > 0);
            require(_order.t.tokenIn == path[0].from , "tokenIn mismatch");
            require(_order.t.tokenOut == path[path.length - 1].to , "tokenOut mismatch");
            require(_order.t.exchangeRate <= (a0e * 1 ether) / (a1m), "bad exchangeRate");
            require(!_order.t.OrderIsExecuted, "already executed");
            require(block.timestamp <= _order.t.deadline, "order expired");

            uint256[4] memory signals;
            signals[0] = uint256(uint128(_order.HOsF));
            signals[1] = uint256(uint128(_order.HOsE));
            signals[2] = a0e;
            signals[3] = a1m;

            require(
                    verifier.verifyProof(
                        _proofA, _proofB, _proofC, signals
                    ),
                    "Proof is nOrderDetails valid"
                );
            

            if(_order.t.tokenIn == address(0)) {
                require(gasfee[_order.t.swapper] >= gasFee + a0e);
                gasfee[_order.t.swapper] -= a0e;

                weth.deposit{value:a0e}();
                weth.approve(address(router), a0e);

                path[0].from = address(weth);
            }else{
                IERC20(path[0].from).safeTransferFrom(swapper, address(this), a0e);
                IERC20(path[0].from).approve(address(router), a0e);
            }

            if(_order.t.tokenOut == address(0)) {
                path[0].to = address(weth);
            }

            if(_type == OrderType.ExactETHForTokens){
                router.swapExactETHForTokens{value : a0e}(a1m, path, recipient, _order.t.deadline);
            } else if(_type == OrderType.ExactTokensForETH){
                router.swapExactTokensForETH(a0e, a1m, path, recipient, _order.t.deadline);
            }

            if(_type == OrderType.ExactETHForTokensFOrderDetails){
                router.swapExactETHForTokensSupportingFeeOnTransferTokens{value : a0e}(a1m, path, recipient, _order.t.deadline);
            } else if(_type == OrderType.ExactTokensForETHFOrderDetails){
                router.swapExactTokensForETHSupportingFeeOnTransferTokens(a0e, a1m, path, recipient, _order.t.deadline);
            }

            if(_type == OrderType.ExactTokensForTokens){
                router.swapExactTokensForTokens(a0e, a1m, path, recipient, _order.t.deadline);
            } else if(_type == OrderType.ExactTokensForTokensFOrderDetails){
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(a0e, a1m, path, recipient, _order.t.deadline);
            }


            orderbook[swapper][index].t.OrderIsExecuted = true;
            takeFeeInternal(_order.t.swapper, gasFee);
            emit OrderExecuted(_order.t.swapper, index, _order.t.tokenIn, _order.t.tokenOut, _order.t.exchangeRate, _order.t.deadline, _order.t.OrderIsExecuted);
    }

    function takeFeeInternal(address swapper, uint gasFeeAmount) internal {
        //@nOrderDetailse The off-chain script retrieves the fee for this transaction, using parameters to pass how much gasFee is charged --- bOrderDetailsh web3py and web3js have the estimateGas API
        require(gasFeeAmount <= 0.075 ether, "gasFee is too high");//@nOrderDetailse Set an upper limit to prevent the script from being malicious
        require(gasfee[swapper] >= gasFeeAmount, "does not have enough fee to take");
        gasfee[swapper] -= gasFeeAmount;
        gasfee[owner()] += gasFeeAmount;

        emit FeeTaken(swapper, gasFee);
    }


    function cancelOrder(uint index, bool takeFee) external {
        require(!orderbook[msg.sender][index].t.OrderIsExecuted, "already executed");
        require(orderbook[msg.sender][index].t.recipient != address(0), "recipient does not exist");

        Order memory tempOrder;
        uint len = orderbook[msg.sender].length;
        tempOrder = orderbook[msg.sender][len - 1];
        orderbook[msg.sender][len - 1] = orderbook[msg.sender][index];
        orderbook[msg.sender][index] = tempOrder;
        orderbook[msg.sender].pop();

        if(orderbook[msg.sender].length == 0 && takeFee){
            withdrawAllFee();
        }

        emit OrderCancelled(msg.sender, index, tempOrder.t.tokenIn, tempOrder.t.tokenOut, tempOrder.t.exchangeRate, tempOrder.t.deadline, tempOrder.t.OrderIsExecuted);
    }

    function checkOrderAvailability(Order _order) external view returns(bool){
        require(!_order.t.OrderIsExecuted, "already executed");
        require(block.timestamp <= _order.t.deadline, "order expired");
        require(_order.t.tokenIn != _order.t.tokenOut, "tokenIn == tokenOut");
        require(_order.t.recipient != address(0), "recipient must be non-zero address");
        require(_order.t.exchangeRate != 0, "exchangeRate must be non-zero value");
        require(_order.t.swapper == msg.sender, "only swapper can store order");
    }

}

