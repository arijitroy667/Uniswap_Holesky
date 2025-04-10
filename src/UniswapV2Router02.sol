// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";

contract USDCETHRouter {
    using SafeMath for uint;

    address public factory;
    address public WETH;
    address public USDC;
    address public receiverContract;
    address public owner;
    
    // Events
    event SwappedUSDCForETH(
        address indexed user,
        uint usdcAmount,
        uint ethAmount
    );
    event SwappedETHForUSDC(
        address indexed user,
        uint ethAmount,
        uint usdcAmount
    );

    event ReceiverContractUpdated(
        address indexed oldReceiver,
        address indexed newReceiver
    );

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "USDCETHRouter: EXPIRED");
        _;
    }

    constructor(
        address _factory,
        address _WETH,
        address _USDC,
        address _receiverContract
    ) public {
        require(_factory != address(0), "USDCETHRouter: ZERO_FACTORY");
        require(_WETH != address(0), "USDCETHRouter: ZERO_WETH");
        require(_USDC != address(0), "USDCETHRouter: ZERO_USDC");
        require(_receiverContract != address(0), "NUll receiver contract");
        factory = _factory;
        WETH = _WETH;
        USDC = _USDC;
        receiverContract = _receiverContract;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "USDCETHRouter: NOT_OWNER");
        _;
    }

    function setReceiverContract(address _receiverContract) external onlyOwner {
        require(_receiverContract != address(0), "USDCETHRouter: ZERO_ADDRESS");
        emit ReceiverContractUpdated(receiverContract, _receiverContract);
        receiverContract = _receiverContract;
    }

    // Required for receiving ETH from WETH unwrapping
    function() external payable {
        require(
            msg.sender == WETH || msg.sender == receiverContract,
            "Only accept ETH from WETH or receiver"
        );
    }

    // **** ETH TO USDC ****

    // Convert ETH to USDC
    function swapExactETHForUSDC(
        uint amountOutMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountOut) {
        // Create swap path: ETH → USDC
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        // Calculate expected output amount
        uint[] memory amounts = UniswapV2Library.getAmountsOut(
            factory,
            msg.value,
            path
        );
        require(
            amounts[1] >= amountOutMin,
            "USDCETHRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        // Wrap ETH
        IWETH(WETH).deposit.value(msg.value)();

        // Transfer WETH to pair contract
        address pair = UniswapV2Library.pairFor(factory, WETH, USDC);
        TransferHelper.safeTransfer(WETH, pair, msg.value);

        // Execute the swap
        _swap(amounts, path, to);

        // Emit event
        emit SwappedETHForUSDC(msg.sender, msg.value, amounts[1]);

        return amounts[1];
    }

    // **** USDC TO ETH ****

    // Convert USDC to ETH
    function swapExactUSDCForETH(
        uint amountIn,
        uint amountOutMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountOut) {
        // Create swap path: USDC → ETH
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        // Calculate expected output amount
        uint[] memory amounts = UniswapV2Library.getAmountsOut(
            factory,
            amountIn,
            path
        );
        require(
            amounts[1] >= amountOutMin,
            "USDCETHRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        // Transfer USDC from user to pair
        address pair = UniswapV2Library.pairFor(factory, USDC, WETH);
        TransferHelper.safeTransferFrom(USDC, msg.sender, pair, amountIn);

        // Execute swap to this address
        _swap(amounts, path, address(this));

        // Unwrap WETH to ETH
        IWETH(WETH).withdraw(amounts[1]);

        // Send ETH to recipient
        TransferHelper.safeTransferETH(to, amounts[1]);

        // Emit event
        emit SwappedUSDCForETH(msg.sender, amountIn, amounts[1]);

        return amounts[1];
    }

    // **** QUOTE FUNCTIONS ****

    // Get quote for ETH → USDC
    function getUSDCAmountOut(
        uint ethAmountIn
    ) external view returns (uint usdcAmountOut) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        uint[] memory amounts = UniswapV2Library.getAmountsOut(
            factory,
            ethAmountIn,
            path
        );
        return amounts[1];
    }

    // Get quote for USDC → ETH
    function getETHAmountOut(
        uint usdcAmountIn
    ) external view returns (uint ethAmountOut) {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;
        uint[] memory amounts = UniswapV2Library.getAmountsOut(
            factory,
            usdcAmountIn,
            path
        );
        return amounts[1];
    }

    // **** INTERNAL FUNCTIONS ****

    // Internal swap function
    function _swap(
        uint[] memory amounts,
        address[] memory path,
        address _to
    ) internal {
        (address input, address output) = (path[0], path[1]);
        (address token0, ) = UniswapV2Library.sortTokens(input, output);
        uint amountOut = amounts[1];
        (uint amount0Out, uint amount1Out) = input == token0
            ? (uint(0), amountOut)
            : (amountOut, uint(0));
        IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
            amount0Out,
            amount1Out,
            _to,
            new bytes(0)
        );
    }
}
