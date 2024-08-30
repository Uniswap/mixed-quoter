// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <=0.8.20;
pragma abicoder v2;

import {IUniswapV3SwapCallback} from "lib/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SafeCast} from "lib/v3-core/contracts/libraries/SafeCast.sol";
import {TickMath} from "lib/v3-core/contracts/libraries/TickMath.sol";
import {CallbackValidation} from "lib/v3-periphery/contracts/libraries/CallbackValidation.sol";
import {Path} from "lib/v3-periphery/contracts/libraries/Path.sol";
import {PoolAddress} from "lib/v3-periphery/contracts/libraries/PoolAddress.sol";
import {PoolTicksCounter} from "lib/v3-periphery/contracts/libraries/PoolTicksCounter.sol";

import {UniswapV2Library} from './libraries/UniswapV2Library.sol';
import {IMixedRouteQuoterV2} from "./interfaces/IMixedRouteQuoterV2.sol";

contract MixedRouterQuoterV2 is IUniswapV3SwapCallback, IMixedRouteQuoterV2 {
    using Path for bytes;
    using SafeCast for uint256;
    using PoolTicksCounter for IUniswapV3Pool;

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

    /// @dev Given an amountIn, fetch the reserves of the V2 pair and get the amountOut
    function getPairAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) private view returns (uint256) {
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(uniswapV2Poolfactory, tokenIn, tokenOut);
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
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

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(bytes memory reason)
    private
    pure
    returns (
        uint256 amount,
        uint160 sqrtPriceX96After,
        int24 tickAfter
    )
    {
        if (reason.length != 0x60) {
            if (reason.length < 0x44) revert('Unexpected error');
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint160, int24));
    }

    function handleV3Revert(
        bytes memory reason,
        IUniswapV3Pool pool,
        uint256 gasEstimate
    )
    private
    view
    returns (
        uint256 amount,
        uint160 sqrtPriceX96After,
        uint32 initializedTicksCrossed,
        uint256
    )
    {
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , , , ) = pool.slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = pool.countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    /// @dev Fetch an exactIn quote for a V3 Pool on chain
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params memory params)
    public
    override
    returns (
        uint256 amountOut,
        uint160 sqrtPriceX96After,
        uint32 initializedTicksCrossed,
        uint256 gasEstimate
    )
    {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        uint256 gasBefore = gasleft();
        try
        pool.swap(
            address(this), // address(0) might cause issues with some tokens
            zeroForOne,
            params.amountIn.toInt256(),
            params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            abi.encodePacked(params.tokenIn, params.fee, params.tokenOut)
        )
        {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            return handleV3Revert(reason, pool, gasEstimate);
        }
    }
}