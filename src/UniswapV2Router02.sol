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

    address public immutable factory;
    address public immutable WETH;
    address public immutable USDC;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH, address _USDC) public {
        factory = _factory;
        WETH = _WETH;
        USDC = _USDC;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ETH to USDC ****
    function swapExactETHForUSDC(
        uint amountOutMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountOut) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint[] memory amounts = UniswapV2Library.getAmountsOut(
            factory,
            msg.value,
            path
        );
        require(
            amounts[1] >= amountOutMin,
            "Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(
            IWETH(WETH).transfer(
                UniswapV2Library.pairFor(factory, WETH, USDC),
                amounts[0]
            )
        );

        _swap(amounts, path, to);
        return amounts[1];
    }

    // **** USDC to ETH ****
    function swapExactUSDCForETH(
        uint amountIn,
        uint amountOutMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountOut) {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        uint[] memory amounts = UniswapV2Library.getAmountsOut(
            factory,
            amountIn,
            path
        );
        require(
            amounts[1] >= amountOutMin,
            "Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        TransferHelper.safeTransferFrom(
            USDC,
            msg.sender,
            UniswapV2Library.pairFor(factory, USDC, WETH),
            amounts[0]
        );

        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[1]);
        TransferHelper.safeTransferETH(to, amounts[1]);
        return amounts[1];
    }

    // **** SWAP ****
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

    // **** LIBRARY FUNCTIONS ****
    function getAmountOut(uint amountIn) public view returns (uint amountOut) {
        address[] memory path = new address[](2);
        if (amountIn == 0) return 0;

        path[0] = USDC;
        path[1] = WETH;
        return UniswapV2Library.getAmountsOut(factory, amountIn, path)[1];
    }
}
