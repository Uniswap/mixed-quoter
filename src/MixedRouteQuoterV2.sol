// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import {IUniswapV3SwapCallback} from "lib/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {CallbackValidation} from "lib/v3-periphery/contracts/libraries/CallbackValidation.sol";
import {Path} from "lib/v3-periphery/contracts/libraries/Path.sol";
import {PoolAddress} from "lib/v3-periphery/contracts/libraries/PoolAddress.sol";

contract MixedRouterQuoterV2 is IUniswapV3SwapCallback {
    using Path for bytes;

    address public immutable uniswapV4PoolManager;
    address public immutable uniswapV3Poolfactory;
    address public immutable uniswapV2Poolfactory;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    constructor(
        address _uniswapV4PoolManager,
        address _uniswapV3Poolfactory,
        address _uniswapV2Poolfactory
    ) {
        uniswapV4PoolManager = _uniswapV4PoolManager;
        uniswapV3Poolfactory = _uniswapV3Poolfactory;
        uniswapV2Poolfactory = _uniswapV2Poolfactory;
    }

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(uniswapV3Poolfactory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory path
    ) external view override {
        // do nothing
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();
        CallbackValidation.verifyCallback(uniswapV3Poolfactory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        IUniswapV3Pool pool = getPool(tokenIn, tokenOut, fee);
        (uint160 sqrtPriceX96After, int24 tickAfter, , , , , ) = pool.slot0();

        if (isExactInput) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountReceived)
                mstore(add(ptr, 0x20), sqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 96)
            }
        } else {
            // if the cache has been populated, ensure that the full output amount has been received
            if (amountOutCached != 0) require(amountReceived == amountOutCached);
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountToPay)
                mstore(add(ptr, 0x20), sqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 96)
            }
        }
    }
}