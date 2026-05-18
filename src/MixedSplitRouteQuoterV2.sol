// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {V2Library} from "./libraries/V2Library.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BaseV4Quoter} from "@uniswap/v4-periphery/src/base/BaseV4Quoter.sol";
import {QuoterRevert} from "@uniswap/v4-periphery/src/libraries/QuoterRevert.sol";
import {Locker} from "@uniswap/v4-periphery/src/libraries/Locker.sol";
import {IMsgSender} from "@uniswap/v4-periphery/src/interfaces/IMsgSender.sol";

import {V3CallbackValidation} from "./libraries/V3CallbackValidation.sol";
import {IMixedSplitRouteQuoterV2} from "./interfaces/IMixedSplitRouteQuoterV2.sol";
import {V3PoolAddress} from "./libraries/V3PoolAddress.sol";
import {Path} from "./libraries/Path.sol";

contract MixedSplitRouteQuoterV2 is IUniswapV3SwapCallback, IMixedSplitRouteQuoterV2, IMsgSender, BaseV4Quoter {
    using Path for bytes;
    using SafeCast for uint256;
    using QuoterRevert for *;

    address public immutable uniswapV3Poolfactory;
    address public immutable uniswapV2Poolfactory;

    constructor(IPoolManager _uniswapV4PoolManager, address _uniswapV3Poolfactory, address _uniswapV2Poolfactory)
        BaseV4Quoter(_uniswapV4PoolManager)
    {
        uniswapV3Poolfactory = _uniswapV3Poolfactory;
        uniswapV2Poolfactory = _uniswapV2Poolfactory;
    }

    modifier setMsgSender() {
        Locker.set(msg.sender);
        _; // execute the function
        Locker.set(address(0)); // reset the locker
    }

    /// V3 FUNCTIONS

    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(
            V3PoolAddress.computeAddress(uniswapV3Poolfactory, V3PoolAddress.getPoolKey(tokenA, tokenB, fee))
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
        V3CallbackValidation.verifyCallback(uniswapV3Poolfactory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 inputAmount, uint256 outputAmount) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        if (isExactInput) {
            outputAmount.revertQuote();
        } else {
            inputAmount.revertQuote();
        }
    }

    /// @inheritdoc IMixedSplitRouteQuoterV2
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
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1,
            abi.encodePacked(params.tokenIn, params.fee, params.tokenOut)
        ) {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            amountOut = reason.parseQuoteAmount();
        }
    }

    /// V4 FUNCTIONS

    /// @inheritdoc IMixedSplitRouteQuoterV2
    function quoteExactInputSingleV4(QuoteExactInputSingleV4Params memory params)
        public
        setMsgSender
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInputSingleV4, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            amountOut = reason.parseQuoteAmount();
        }
    }

    /// @dev quote an ExactInput swap on a pool, then revert with the result
    function _quoteExactInputSingleV4(QuoteExactInputSingleV4Params calldata params)
        public
        selfOnly
        returns (bytes memory)
    {
        BalanceDelta swapDelta =
            _swap(params.poolKey, params.zeroForOne, -int256(int256(params.exactAmount)), params.hookData);

        // the output delta of a swap is positive
        uint256 amountOut = params.zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
        amountOut.revertQuote();
    }

    /// V2 FUNCTIONS

    /// @inheritdoc IMixedSplitRouteQuoterV2
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        public
        view
        override
        returns (uint256 amountOut)
    {
        (uint256 reserveIn, uint256 reserveOut) =
            V2Library.getReserves(uniswapV2Poolfactory, params.tokenIn, params.tokenOut);
        return V2Library.getAmountOut(params.amountIn, reserveIn, reserveOut);
    }

    /// COMBINED ENTRYPOINT

    /// @inheritdoc IMixedSplitRouteQuoterV2
    /// @dev Get the quote for an exactIn swap between an array of V2 and/or V3 pools
    /// @notice To encode a V2 pair within the path, use 0x800000 (hex value of 8388608) for the fee between the two token addresses
    function quoteExactInput(bytes calldata path, ExtraQuoteExactInputParams calldata param, uint256 amountIn)
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
        uint8 protocolVersion = path.decodeProtocolVersion();
        for (uint256 i = 0; i < numPools; i++) {
            // move on to the next pool
            if (i != 0) {
                path = path.skipToken(protocolVersion);
                protocolVersion = path.decodeProtocolVersion();
            }

            if (protocolVersion == uint8(2)) {
                (address tokenIn, address tokenOut) = path.decodeFirstV2Pool();

                amountIn = quoteExactInputSingleV2(
                    QuoteExactInputSingleV2Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn})
                );
            } else if (protocolVersion == uint8(4)) {
                bytes calldata hookData = param.nonEncodableData[i].hookData;
                (address tokenIn, uint24 fee, uint24 tickSpacing, address hooks, address tokenOut) =
                    path.decodeFirstV4Pool();
                PoolKey memory poolKey = Path.v4PoolToPoolKey(tokenIn, fee, tickSpacing, hooks, tokenOut);

                /// the outputs of prior swaps become the inputs to subsequent ones
                (uint256 _amountOut, uint256 _gasEstimate) = quoteExactInputSingleV4(
                    QuoteExactInputSingleV4Params({
                        poolKey: poolKey,
                        zeroForOne: tokenIn < tokenOut,
                        exactAmount: amountIn,
                        hookData: hookData
                    })
                );
                gasEstimate += _gasEstimate;
                amountIn = _amountOut;
            } else if (protocolVersion == uint8(3)) {
                (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstV3Pool();

                (uint256 _amountOut, uint256 _gasEstimate) = quoteExactInputSingleV3(
                    QuoteExactInputSingleV3Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn, fee: fee})
                );
                gasEstimate += _gasEstimate;
                amountIn = _amountOut;
            } else if (protocolVersion == uint8(0)) {
                // increase the gas estimate by the worst case erc20-transfer cost (cold sstore)
                gasEstimate += 20_000;
                // no change to amountIn
            } else {
                revert InvalidProtocolVersion(protocolVersion);
            }
        }
        // the final amountOut is the amountIn for the "next step" that doesnt exist
        amountOut = amountIn;
    }

    /// @inheritdoc IMixedSplitRouteQuoterV2
    function quoteExactInputSplit(SplitNode[] calldata route)
        public
        override
        returns (uint256 amountOut, uint256[] memory amountsOut, uint256 gasEstimate)
    {
        uint256 n = route.length;
        amountsOut = new uint256[](n);
        // Accumulates amounts forwarded to each node by upstream nodes
        uint256[] memory pendingAmounts = new uint256[](n);

        for (uint256 i = 0; i < n; i++) {
            SplitNode calldata node = route[i];
            uint256 nodeInput = node.amountIn + pendingAmounts[i];

            // Skip nodes that received no input; their amountsOut entry stays 0
            if (nodeInput == 0) continue;

            // Quote this single pool hop
            uint8 protocolVersion = node.path.decodeProtocolVersion();
            uint256 nodeOutput;

            if (protocolVersion == uint8(2)) {
                (address tokenIn, address tokenOut) = node.path.decodeFirstV2Pool();
                nodeOutput = quoteExactInputSingleV2(
                    QuoteExactInputSingleV2Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: nodeInput})
                );
            } else if (protocolVersion == uint8(4)) {
                (address tokenIn, uint24 fee, uint24 tickSpacing, address hooks, address tokenOut) =
                    node.path.decodeFirstV4Pool();
                PoolKey memory poolKey = Path.v4PoolToPoolKey(tokenIn, fee, tickSpacing, hooks, tokenOut);
                (uint256 legOut, uint256 legGas) = quoteExactInputSingleV4(
                    QuoteExactInputSingleV4Params({
                        poolKey: poolKey,
                        zeroForOne: tokenIn < tokenOut,
                        exactAmount: nodeInput,
                        hookData: node.hookData
                    })
                );
                nodeOutput = legOut;
                gasEstimate += legGas;
            } else if (protocolVersion == uint8(3)) {
                (address tokenIn, uint24 fee, address tokenOut) = node.path.decodeFirstV3Pool();
                (uint256 legOut, uint256 legGas) = quoteExactInputSingleV3(
                    QuoteExactInputSingleV3Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: nodeInput, fee: fee})
                );
                nodeOutput = legOut;
                gasEstimate += legGas;
            } else if (protocolVersion == uint8(0)) {
                // wrap/unwrap: no price impact, pass through
                gasEstimate += 20_000;
                nodeOutput = nodeInput;
            } else {
                revert InvalidProtocolVersion(protocolVersion);
            }

            amountsOut[i] = nodeOutput;

            // Distribute output to downstream nodes
            SplitOutputTarget[] calldata targets = node.outputs;
            uint256 totalBps = 0;
            uint256 totalAllocated = 0;

            for (uint256 j = 0; j < targets.length; j++) {
                if (targets[j].targetIndex <= i) revert InvalidSplitTarget();
                totalBps += targets[j].bps;
                if (totalBps > 10_000) revert InvalidSplitBPS();

                uint256 allocated;
                if (j == targets.length - 1 && totalBps == 10_000) {
                    // Last target at 100% total: give it the exact remainder to absorb rounding dust
                    allocated = nodeOutput - totalAllocated;
                } else {
                    allocated = nodeOutput * targets[j].bps / 10_000;
                }
                pendingAmounts[targets[j].targetIndex] += allocated;
                totalAllocated += allocated;
            }

            // Any output not forwarded downstream goes to the final accumulator
            amountOut += nodeOutput - totalAllocated;
        }
    }

    /// @inheritdoc IMsgSender
    function msgSender() external view returns (address) {
        return Locker.get();
    }
}
