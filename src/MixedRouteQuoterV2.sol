// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BaseV4Quoter} from "@uniswap/v4-periphery/src/base/BaseV4Quoter.sol";
import {QuoterRevert} from "@uniswap/v4-periphery/src/libraries/QuoterRevert.sol";
import {SqrtPriceLimitHelper} from "@uniswap/v4-periphery/src/libraries/SqrtPriceLimitHelper.sol";

import {CallbackValidation} from "./libraries/CallbackValidation.sol";
import {IMixedRouteQuoterV2} from "./interfaces/IMixedRouteQuoterV2.sol";
import {PoolAddress} from "./libraries/PoolAddress.sol";
import {Path} from "./libraries/Path.sol";

contract MixedRouteQuoterV2 is IUniswapV3SwapCallback, IMixedRouteQuoterV2, BaseV4Quoter {
    using Path for bytes;
    using SafeCast for uint256;
    using QuoterRevert for *;
    using SqrtPriceLimitHelper for uint160;

    address public immutable uniswapV3Poolfactory;
    address public immutable uniswapV2Poolfactory;

    constructor(IPoolManager _uniswapV4PoolManager, address _uniswapV3Poolfactory, address _uniswapV2Poolfactory)
        BaseV4Quoter(_uniswapV4PoolManager)
    {
        uniswapV3Poolfactory = _uniswapV3Poolfactory;
        uniswapV2Poolfactory = _uniswapV2Poolfactory;
    }

    /// V3 FUNCTIONS

    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(
            PoolAddress.computeAddress(uniswapV3Poolfactory, PoolAddress.getPoolKey(tokenA, tokenB, fee))
        );
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata path)
        external
        view
        override
    {
        // swaps entirely within 0-liquidity regions are not supported
        if (amount0Delta <= 0 && amount1Delta <= 0) revert NoLiquidityV3();
        (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstV3Pool();
        CallbackValidation.verifyCallback(uniswapV3Poolfactory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 inputAmount, uint256 outputAmount) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        if (isExactInput) {
            outputAmount.revertQuote();
        } else {
            inputAmount.revertQuote();
        }
    }

    /// @inheritdoc IMixedRouteQuoterV2
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params memory params)
        public
        override
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = _getPool(params.tokenIn, params.tokenOut, params.fee);

        uint256 gasBefore = gasleft();
        try pool.swap(
            address(this), // address(0) might cause issues with some tokens
            zeroForOne,
            params.amountIn.toInt256(),
            params.sqrtPriceLimitX96.getSqrtPriceLimit(zeroForOne),
            abi.encodePacked(params.tokenIn, params.fee, params.tokenOut)
        ) {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            amountOut = reason.parseReturnData();
        }
    }

    /// V4 FUNCTIONS

    /// @inheritdoc IMixedRouteQuoterV2
    function quoteExactInputSingleV4(QuoteExactInputSingleV4Params memory params)
        public
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInputSingleV4, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            amountOut = reason.parseReturnData();
        }
    }

    /// @dev quote an ExactInput swap on a pool, then revert with the result
    function _quoteExactInputSingleV4(QuoteExactInputSingleV4Params calldata params)
        public
        selfOnly
        returns (bytes memory)
    {
        BalanceDelta swapDelta = _swap(
            params.poolKey,
            params.zeroForOne,
            -int256(int256(params.exactAmount)),
            params.sqrtPriceLimitX96,
            params.hookData
        );

        // the output delta of a swap is positive
        uint256 amountOut = params.zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
        amountOut.revertQuote();
    }

    /// V2 FUNCTIONS

    /// @inheritdoc IMixedRouteQuoterV2
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        public
        view
        override
        returns (uint256 amountOut)
    {
        (uint256 reserveIn, uint256 reserveOut) =
            UniswapV2Library.getReserves(uniswapV2Poolfactory, params.tokenIn, params.tokenOut);
        return UniswapV2Library.getAmountOut(params.amountIn, reserveIn, reserveOut);
    }

    /// COMBINED ENTRYPOINT

    /// @dev Get the quote for an exactIn swap between an array of V2 and/or V3 pools
    /// @notice To encode a V2 pair within the path, use 0x800000 (hex value of 8388608) for the fee between the two token addresses
    function quoteExactInput(bytes memory path, ExtraQuoteExactInputParams calldata param, uint256 amountIn)
        public
        override
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        // Not the best way to determine number of pools in the encoded path,
        // But since each pool encoding has different bytes for efficient abi.encoding,
        // This is the best way to determine the number of pools in the path
        // We rely on integrator to pass in the hookdata for each pool.
        // In case the pool is hookless, we still expect integrator to pass in the hookdata as 0x
        // This is equivalent of https://github.com/Uniswap/v4-periphery/blob/main/src/lens/Quoter.sol#L66,
        // where caller has to pass each pool's hookData, even if it's 0x, empty.
        uint256 numPools = param.nonEncodableData.length;
        uint8 poolVersion = path.decodePoolVersion();
        for (uint256 i = 0; i < numPools; i++) {
            // move on to the next pool
            if (i != 0) {
                path = path.skipToken(poolVersion);
                poolVersion = path.decodePoolVersion();
            }

            if (poolVersion == uint8(2)) {
                (address tokenIn, address tokenOut) = path.decodeFirstV2Pool();

                amountIn = quoteExactInputSingleV2(
                    QuoteExactInputSingleV2Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn})
                );
            } else if (poolVersion == uint8(4)) {
                bytes memory hookData = param.nonEncodableData[i].hookData;
                (address tokenIn, uint24 fee, uint24 tickSpacing, address hooks, address tokenOut) =
                    path.decodeFirstV4Pool();
                PoolKey memory poolKey = Path.v4PoolToPoolKey(tokenIn, fee, tickSpacing, hooks, tokenOut);

                /// the outputs of prior swaps become the inputs to subsequent ones
                (uint256 _amountOut, uint256 _gasEstimate) = quoteExactInputSingleV4(
                    QuoteExactInputSingleV4Params({
                        poolKey: poolKey,
                        zeroForOne: tokenIn < tokenOut,
                        exactAmount: amountIn,
                        sqrtPriceLimitX96: 0,
                        hookData: hookData
                    })
                );
                gasEstimate += _gasEstimate;
                amountIn = _amountOut;
            } else if (poolVersion == uint8(3)) {
                (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstV3Pool();

                (uint256 _amountOut, uint256 _gasEstimate) = quoteExactInputSingleV3(
                    QuoteExactInputSingleV3Params({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountIn: amountIn,
                        fee: fee,
                        sqrtPriceLimitX96: 0
                    })
                );
                gasEstimate += _gasEstimate;
                amountIn = _amountOut;
            } else {
                revert InvalidPoolVersion(poolVersion);
            }
        }
        // the final amountOut is the amountIn for the "next step" that doesnt exist
        amountOut = amountIn;
    }
}
