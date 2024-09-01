// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "./interface/IRouterV2.sol";
import "./interface/IWETH.sol";
import "./zk.sol";

contract ZDPc is Ownable2Step {

    using SafeERC20 for IERC20;

    struct Ot{
        address swapper;
        address receiver;
        address token0;
        address token1;
        uint er;//@note 每1单位的目标token价值多少支出token   (a0e * 1 e decimals0) / (a1m * 1 e decimals1) 有18位小数 例如2e10 USDC 换 2e18 eth er = (2e10 * 1e18)/2e18 = 2e10 
        uint ddl;
        bool f;
    }

    struct Order{
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

    IRouterv2 public router;
    IWETH public weth;
    Groth16Verifier public verifier;

    mapping(address => Order[]) public orderbook;
    mapping(address => uint) public feeB;

    modifier onlyAgent {
        require(msg.sender == agent, "only agent can call this function");
        _;
    }

    event OrderStored(address indexed swapper,uint indexed index, address token0, address token1, uint indexed er, uint ddl, bool f);
    event FeeDeposit(address indexed swapper, uint indexed fee);
    event FeeWithdrawn(address indexed swapper, uint indexed fee);
    event OrderExecuted(address swapper, uint indexed index, address token0, address token1, uint indexed er, uint indexed ddl, bool f);
    event FeeTaken(address indexed swapper, uint indexed fee);
    event profitTaken(uint indexed fee);
    event OrderCancelled(address swapper, uint indexed index, address token0, address token1, uint indexed er, uint indexed ddl, bool f);

    constructor(address _owner, address payable _router, address _agent, address _weth) Ownable(_owner){
        require(_agent != address(0));
        require(_router != address(0));
        // _transferOwnership(_owner);
        router = IRouterv2(_router);
        agent = _agent;
        weth = IWETH(payable(_weth));
        verifier = new Groth16Verifier();
    }

    function setAgent(address _agent) external onlyOwner {
        agent = _agent;
    }


    function storeOrder(Order memory oBar) external {
        require(!oBar.t.f, "already executed");
        require(block.timestamp < oBar.t.ddl, "order expired");
        require(oBar.t.token0 != oBar.t.token1, "token0 == token1");
        require(oBar.t.receiver != address(0), "receiver must be non-zero address");
        require(oBar.t.er != 0, "exchangeRate must be non-zero value");
        require(oBar.t.swapper == msg.sender, "only swapper can store order");

        uint index;
        index = orderbook[oBar.t.swapper].length;
        orderbook[oBar.t.swapper].push(oBar);

        emit OrderStored(msg.sender, index, oBar.t.token0, oBar.t.token1, oBar.t.er, oBar.t.ddl, oBar.t.f);
    }

    function getOrders(address swapper) external view returns(Order[] memory){
        return orderbook[swapper];
    }

    function getOrder(address swapper, uint index) external view returns(Order memory){
        return orderbook[swapper][index];
    }

    function depositForFeeOrSwap(address swapper)external payable{
        require(msg.value > 0, "deposit must be non-zero value");
        require(swapper != address(0), "swapper must be non-zero address");

        feeB[swapper] += msg.value;

        emit FeeDeposit(swapper, msg.value);
    }

    function withdrawFee(uint amount) public {
        require(amount > 0);
        require(feeB[msg.sender] >= amount, "not enough fee to take");

        feeB[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");

        emit FeeWithdrawn(msg.sender, amount);
    }

    function withdrawAllFee() public {
        uint amount = feeB[msg.sender];
        withdrawFee(amount);
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
        external payable onlyAgent{

            Order memory oBar = orderbook[swapper][index];
            address receiver = oBar.t.receiver;

            require(path.length > 0);
            require(oBar.t.token0 == path[0].from , "token0 mismatch");
            require(oBar.t.token1 == path[path.length - 1].to , "token1 mismatch");
            require(oBar.t.er <= (a0e * 1 ether) / (a1m), "bad exchangeRate");
            require(!oBar.t.f, "already executed");
            require(block.timestamp <= oBar.t.ddl, "order expired");

            uint256[4] memory signals;
            signals[0] = uint256(uint128(oBar.HOsF));
            signals[1] = uint256(uint128(oBar.HOsE));
            signals[2] = a0e;
            signals[3] = a1m;

            require(
                    verifier.verifyProof(
                        _proofA, _proofB, _proofC, signals
                    ),
                    "Proof is not valid"
                );
            

            if(oBar.t.token0 == address(0)) {
                require(feeB[oBar.t.swapper] >= gasFee + a0e);
                feeB[oBar.t.swapper] -= a0e;

                weth.deposit{value:a0e}();
                weth.approve(address(router), a0e);

                path[0].from = address(weth);
            }else{
                IERC20(path[0].from).safeTransferFrom(swapper, address(this), a0e);
                IERC20(path[0].from).approve(address(router), a0e);
            }

            if(oBar.t.token1 == address(0)) {
                path[0].to = address(weth);
            }

            if(_type == OrderType.ExactETHForTokens){
                router.swapExactETHForTokens{value : a0e}(a1m, path, receiver, oBar.t.ddl);
            } else if(_type == OrderType.ExactTokensForETH){
                router.swapExactTokensForETH(a0e, a1m, path, receiver, oBar.t.ddl);
            }

            if(_type == OrderType.ExactETHForTokensFot){
                router.swapExactETHForTokensSupportingFeeOnTransferTokens{value : a0e}(a1m, path, receiver, oBar.t.ddl);
            } else if(_type == OrderType.ExactTokensForETHFot){
                router.swapExactTokensForETHSupportingFeeOnTransferTokens(a0e, a1m, path, receiver, oBar.t.ddl);
            }

            if(_type == OrderType.ExactTokensForTokens){
                router.swapExactTokensForTokens(a0e, a1m, path, receiver, oBar.t.ddl);
            } else if(_type == OrderType.ExactTokensForTokensFot){
                router.swapExactTokensForTokensSupportingFeeOnTransferTokens(a0e, a1m, path, receiver, oBar.t.ddl);
            }


            orderbook[swapper][index].t.f = true;
            takeFeeInternal(oBar.t.swapper, gasFee);
            emit OrderExecuted(oBar.t.swapper, index, oBar.t.token0, oBar.t.token1, oBar.t.er, oBar.t.ddl, oBar.t.f);
    }

    function takeFeeInternal(address swapper, uint gasFee) internal {
        //@note 链下脚本获取该比交易的费用，使用参数传递收取多少gasFee --- web3py和web3js 都有 estimateGas api
        require(gasFee <= 0.075 ether);//@note 要一个上限，防止脚本作恶
        require(feeB[swapper] >= gasFee, "not enough fee to take");
        feeB[swapper] -= gasFee;
        feeB[owner()] += gasFee;

        emit FeeTaken(swapper, gasFee);
    }


    function cancelOrder(uint index, bool takeFee) external {
        require(!orderbook[msg.sender][index].t.f, "already executed");
        require(orderbook[msg.sender][index].t.receiver != address(0), "order does not exist");

        Order memory tempOrder;
        uint len = orderbook[msg.sender].length;
        tempOrder = orderbook[msg.sender][len - 1];
        orderbook[msg.sender][len - 1] = orderbook[msg.sender][index];
        orderbook[msg.sender][index] = tempOrder;
        orderbook[msg.sender].pop();

        if(orderbook[msg.sender].length == 0 && takeFee){
            withdrawAllFee();
        }

        emit OrderCancelled(msg.sender, index, tempOrder.t.token0, tempOrder.t.token1, tempOrder.t.er, tempOrder.t.ddl, tempOrder.t.f);
    }

    function profit() external onlyOwner{
        withdrawAllFee();
    }

}

