// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "hardhat/console.sol";

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Callee {
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

interface ILendingPool {
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;
}

contract LiquidationOperator is IUniswapV2Callee {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address constant LIQUIDATION_TARGET = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;

    IUniswapV2Factory immutable factory;
    address pairAddress;

    constructor() {
        factory = IUniswapV2Factory(UNISWAP_FACTORY);
    }

    function operate() external {
        address wethUsdtPair = factory.getPair(WETH, USDT);
        require(wethUsdtPair != address(0), "Pair not found");
        
        pairAddress = wethUsdtPair;
        
        address token0 = IUniswapV2Pair(wethUsdtPair).token0();
        address token1 = IUniswapV2Pair(wethUsdtPair).token1();
        
        uint256 usdtAmount = 1750000 * 1e6;
        uint256 amount0Out = token0 == USDT ? usdtAmount : 0;
        uint256 amount1Out = token1 == USDT ? usdtAmount : 0;
        
        bytes memory data = abi.encode(WETH);
        IUniswapV2Pair(wethUsdtPair).swap(amount0Out, amount1Out, address(this), data);
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata) external override {
        require(msg.sender == pairAddress, "Unauthorized");
        require(sender == address(this), "Sender mismatch");
        
        uint256 usdtBorrowed = amount0 > 0 ? amount0 : amount1;
        
        _safeApprove(USDT, AAVE_LENDING_POOL, type(uint256).max);
        
        ILendingPool(AAVE_LENDING_POOL).liquidationCall(
            WBTC,
            USDT,
            LIQUIDATION_TARGET,
            usdtBorrowed,
            false
        );
        
        uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
        
        address wbtcWethPair = factory.getPair(WBTC, WETH);
        _safeTransfer(WBTC, wbtcWethPair, wbtcBalance);
        
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(wbtcWethPair).getReserves();
        address token0 = IUniswapV2Pair(wbtcWethPair).token0();
        
        uint256 wethOut;
        if (token0 == WBTC) {
            wethOut = _getAmountOut(wbtcBalance, reserve0, reserve1);
            IUniswapV2Pair(wbtcWethPair).swap(0, wethOut, address(this), new bytes(0));
        } else {
            wethOut = _getAmountOut(wbtcBalance, reserve1, reserve0);
            IUniswapV2Pair(wbtcWethPair).swap(wethOut, 0, address(this), new bytes(0));
        }

        uint256 wethAmountToRepay;
        {
            (uint112 reserve0Usdt, uint112 reserve1Usdt, ) = IUniswapV2Pair(pairAddress).getReserves();
            address token0Usdt = IUniswapV2Pair(pairAddress).token0();
            
            if (token0Usdt == USDT) {
                wethAmountToRepay = _getAmountIn(usdtBorrowed, reserve1Usdt, reserve0Usdt);
            } else {
                wethAmountToRepay = _getAmountIn(usdtBorrowed, reserve0Usdt, reserve1Usdt);
            }
        }
        
        _safeTransfer(WETH, pairAddress, wethAmountToRepay);
        
        uint256 wethFinal = IERC20(WETH).balanceOf(address(this));
        if (wethFinal > 0) {
            IWETH(WETH).withdraw(wethFinal);
        }
        
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            payable(tx.origin).transfer(ethBalance);
        }
    }

    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, "Insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, "Insufficient output amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
    
    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _safeApprove(address token, address spender, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Approve failed");
    }

    receive() external payable {}
}