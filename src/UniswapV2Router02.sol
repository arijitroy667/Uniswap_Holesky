// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/SafeMath.sol";

contract UniswapV2VaultReceiverRouter {
    using SafeMath for uint;

    address public immutable factory;
    address public immutable WETH;
    address public immutable USDC;
    
    address public immutable vaultContract;
    address public immutable receiverContract;
    
    // Events
    event SwappedUSDCForETH(uint usdcAmount, uint ethAmount);
    event SwappedETHForUSDC(uint ethAmount, uint usdcAmount);
    event SwapFailed(uint amount, string reason);

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        _;
    }
    
    modifier onlyVault() {
        require(msg.sender == vaultContract, "Only vault can call");
        _;
    }
    
    modifier onlyReceiver() {
        require(msg.sender == receiverContract, "Only receiver can call");
        _;
    }

    constructor(
        address _factory,
        address _WETH,
        address _USDC,
        address _vaultContract,
        address _receiverContract
    ) public {
        require(_factory != address(0), "Invalid factory address");
        require(_WETH != address(0), "Invalid WETH address");
        require(_USDC != address(0), "Invalid USDC address");
        require(_vaultContract != address(0), "Invalid Vault address");
        require(_receiverContract != address(0), "Invalid Receiver address");
        
        factory = _factory;
        WETH = _WETH;
        USDC = _USDC;
        vaultContract = _vaultContract;
        receiverContract = _receiverContract;
    }

    receive() external payable {
        // Only accept ETH from WETH or receiver contract
        require(
            msg.sender == WETH || msg.sender == receiverContract,
            "Only accept ETH from WETH or receiver"
        );
    }

    // Takes USDC from vault, swaps to ETH, sends ETH to receiver
    function takeAndSwapUSDC(
        uint usdcAmount,
        uint amountOutMin,
        uint deadline
    ) external onlyVault ensure(deadline) returns (uint amountOut) {
        require(usdcAmount > 0, "No USDC to swap");
        
        // Transfer USDC from vault to this contract
        TransferHelper.safeTransferFrom(USDC, vaultContract, address(this), usdcAmount);
        
        // Create the swap path: USDC → WETH
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;
        
        // Approve router to spend USDC
        TransferHelper.safeApprove(USDC, address(this), usdcAmount);
        
        try {
            // Get expected amounts out
            uint[] memory amounts = UniswapV2Library.getAmountsOut(factory, usdcAmount, path);
            require(amounts[1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");
            
            // Transfer USDC to pair
            TransferHelper.safeTransferFrom(
                USDC,
                address(this),
                UniswapV2Library.pairFor(factory, USDC, WETH),
                usdcAmount
            );
            
            // Perform the swap
            _swap(amounts, path, address(this));
            
            // Convert WETH to ETH
            amountOut = amounts[1];
            IWETH(WETH).withdraw(amountOut);
            
            // Send ETH to receiver
            (bool success, ) = receiverContract.call{value: amountOut}("");
            require(success, "ETH transfer failed");
            
            emit SwappedUSDCForETH(usdcAmount, amountOut);
            return amountOut;
        } catch Error(string memory reason) {
            // If swap fails, return USDC to vault
            TransferHelper.safeTransfer(USDC, vaultContract, usdcAmount);
            emit SwapFailed(usdcAmount, reason);
            revert(reason);
        }
    }
    
    // Takes ETH from receiver, swaps to USDC, sends USDC to vault
    function swapAllETHForUSDC(
        uint amountOutMin,
        uint deadline
    ) external payable onlyReceiver ensure(deadline) returns (uint amountOut) {
        uint ethAmount = msg.value;
        require(ethAmount > 0, "No ETH to swap");
        
        // Create the swap path: WETH → USDC
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        
        // Get expected amounts out
        uint[] memory amounts = UniswapV2Library.getAmountsOut(factory, ethAmount, path);
        require(amounts[1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");
        
        // Convert ETH to WETH
        IWETH(WETH).deposit{value: ethAmount}();
        
        // Transfer WETH to pair
        assert(
            IWETH(WETH).transfer(
                UniswapV2Library.pairFor(factory, WETH, USDC),
                ethAmount
            )
        );
        
        // Perform the swap, send output directly to vault
        _swap(amounts, path, vaultContract);
        
        amountOut = amounts[1];
        emit SwappedETHForUSDC(ethAmount, amountOut);
        return amountOut;
    }
    
    // Core swap functionality
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
    
    // Recovery functions
    function recoverUSDC() external onlyVault {
        uint usdcBalance = IERC20(USDC).balanceOf(address(this));
        if (usdcBalance > 0) {
            TransferHelper.safeTransfer(USDC, vaultContract, usdcBalance);
        }
    }
    
    function recoverETH() external onlyVault {
        uint ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = vaultContract.call{value: ethBalance}("");
            require(success, "ETH recovery failed");
        }
    }
    
    // View functions
    function getExpectedETHForUSDC(uint usdcAmount) external view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;
        uint[] memory amounts = UniswapV2Library.getAmountsOut(factory, usdcAmount, path);
        return amounts[1];
    }
    
    function getExpectedUSDCForETH(uint ethAmount) external view returns (uint) {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        uint[] memory amounts = UniswapV2Library.getAmountsOut(factory, ethAmount, path);
        return amounts[1];
    }
}