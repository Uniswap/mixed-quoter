// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma abicoder v2;

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolTicksCounter} from "./libraries/PoolTicksCounter.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";

import {UniswapV2Library} from "@uniswap/universal-router/contracts/modules/uniswap/v2/UniswapV2Library.sol";
import {CallbackValidation} from "./libraries/CallbackValidation.sol";
import {IMixedRouteQuoterV2} from "./interfaces/IMixedRouteQuoterV2.sol";
import {PoolAddress} from "./libraries/PoolAddress.sol";
import {V4PoolTicksCounter} from "./libraries/V4PoolTicksCounter.sol";
import {Path} from "./libraries/Path.sol";
import {Constants} from "./libraries/Constants.sol";

contract MixedRouteQuoterV2 is IUniswapV3SwapCallback, IMixedRouteQuoterV2, SafeCallback {
    using PoolIdLibrary for PoolKey;
    using Path for bytes;
    using SafeCast for uint256;
    using PoolTicksCounter for IUniswapV3Pool;
    using StateLibrary for IPoolManager;

    address public immutable uniswapV3Poolfactory;
    address public immutable uniswapV2Poolfactory;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    constructor(IPoolManager _uniswapV4PoolManager, address _uniswapV3Poolfactory, address _uniswapV2Poolfactory)
        SafeCallback(_uniswapV4PoolManager)
    {
        uniswapV3Poolfactory = _uniswapV3Poolfactory;
        uniswapV2Poolfactory = _uniswapV2Poolfactory;
    }

    function getPool(address tokenA, address tokenB, uint24 fee) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(
            PoolAddress.computeAddress(uniswapV3Poolfactory, PoolAddress.getPoolKey(tokenA, tokenB, fee))
        );
    }

    /// @dev Given an amountIn, fetch the reserves of the V2 pair and get the amountOut
    function getPairAmountOut(uint256 amountIn, address tokenIn, address tokenOut)
        private
        returns (uint256 amount1Out, uint256 gasEstimate)
    {
        address pair =
            UniswapV2Library.pairFor(uniswapV2Poolfactory, Constants.UNISWAP_V3_POOL_INIT_CODE_HASH, tokenIn, tokenOut);
        address to = pair;
        uint256 gasBefore = gasleft();
        IUniswapV2Pair(pair).swap(amountIn, amount1Out, to, "");
        gasEstimate = gasBefore - gasleft();

        return (amount1Out, gasEstimate);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata path)
        public
        view
        override
    {
        // do nothing
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstV3Pool();
        CallbackValidation.verifyCallback(uniswapV3Poolfactory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        IUniswapV3Pool pool = getPool(tokenIn, tokenOut, fee);
        (uint160 sqrtPriceX96After, int24 tickAfter,,,,,) = pool.slot0();

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
        returns (uint256 amount, uint160 sqrtPriceX96After, int24 tickAfter)
    {
        if (reason.length != 0x60) {
            if (reason.length < 0x44) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint160, int24));
    }

    function handleV3Revert(bytes memory reason, IUniswapV3Pool pool, uint256 gasEstimate)
        private
        view
        returns (uint256 amount, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256)
    {
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore,,,,,) = pool.slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = pool.countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    /// @dev parse revert bytes from a single-pool quote
    function handleV4Revert(bytes memory reason, uint256 gasEstimate)
        private
        pure
        returns (uint256 amount, uint160 sqrtPriceX96After, uint32 initializedTicksLoaded, uint256)
    {
        reason = validateRevertReason(reason);
        (amount, sqrtPriceX96After, initializedTicksLoaded) = abi.decode(reason, (uint256, uint160, uint32));

        return (amount, sqrtPriceX96After, initializedTicksLoaded, gasEstimate);
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        assembly ("memory-safe") {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    /// @dev check revert bytes and pass through if considered valid; otherwise revert with different message
    function validateRevertReason(bytes memory reason) private pure returns (bytes memory) {
        if (reason.length < Constants.MINIMUM_VALID_RESPONSE_LENGTH) {
            revert UnexpectedRevertBytes(reason);
        }
        return reason;
    }

    /// @dev Fetch an exactIn quote for a V3 Pool on chain
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params memory params)
        public
        override
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        uint256 gasBefore = gasleft();
        try pool.swap(
            address(this), // address(0) might cause issues with some tokens
            zeroForOne,
            params.amountIn.toInt256(),
            params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1)
                : params.sqrtPriceLimitX96,
            abi.encodePacked(params.tokenIn, params.fee, params.tokenOut)
        ) {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            return handleV3Revert(reason, pool, gasEstimate);
        }
    }

    /// @dev Fetch an exactIn quote for a V4 Pool on chain
    function quoteExactInputSingleV4(QuoteExactInputSingleV4Params memory params)
        public
        override
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksLoaded, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInputSingleV4, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            return handleV4Revert(reason, gasEstimate);
        }
    }

    /// @dev quote an ExactInput swap on a pool, then revert with the result
    function _quoteExactInputSingleV4(QuoteExactInputSingleV4Params calldata params) public returns (bytes memory) {
        (, int24 tickBefore,,) = poolManager.getSlot0(params.poolKey.toId());

        (BalanceDelta deltas, uint160 sqrtPriceX96After, int24 tickAfter) = _swap(
            params.poolKey,
            params.zeroForOne,
            -int256(int256(params.exactAmount)),
            params.sqrtPriceLimitX96,
            params.hookData
        );

        uint256 amountOut = uint256(int256(deltas.amount0()));

        uint32 initializedTicksLoaded =
            V4PoolTicksCounter.countInitializedTicksLoaded(poolManager, params.poolKey, tickBefore, tickAfter);
        bytes memory result = abi.encode(amountOut, sqrtPriceX96After, initializedTicksLoaded);
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    /// @dev Execute a swap and return the amounts delta, as well as relevant pool state
    /// @notice if amountSpecified < 0, the swap is exactInput, otherwise exactOutput
    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata hookData
    ) private returns (BalanceDelta deltas, uint160 sqrtPriceX96After, int24 tickAfter) {
        deltas = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: _sqrtPriceLimitOrDefault(sqrtPriceLimitX96, zeroForOne)
            }),
            hookData
        );
        // only exactOut case
        if (amountOutCached != 0 && amountOutCached != uint128(zeroForOne ? deltas.amount1() : deltas.amount0())) {
            revert InsufficientAmountOut();
        }
        (sqrtPriceX96After, tickAfter,,) = poolManager.getSlot0(poolKey.toId());
    }

    /// @dev return either the sqrtPriceLimit from user input, or the max/min value possible depending on trade direction
    function _sqrtPriceLimitOrDefault(uint160 sqrtPriceLimitX96, bool zeroForOne) private pure returns (uint160) {
        return sqrtPriceLimitX96 == 0
            ? zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            : sqrtPriceLimitX96;
    }

    /// @dev Fetch an exactIn quote for a V2 pair on chain
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        public
        override
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        (amountOut, gasEstimate) = getPairAmountOut(params.amountIn, params.tokenIn, params.tokenOut);
    }

    /// @dev Get the quote for an exactIn swap between an array of V2 and/or V3 pools
    /// @notice To encode a V2 pair within the path, use 0x800000 (hex value of 8388608) for the fee between the two token addresses
    function quoteExactInput(bytes memory path, ExtraQuoteExactInputParams calldata param, uint256 amountIn)
        public
        override
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        // Not the best way to determine number of pools in the encoded path,
        // But since each pool encoding has different bytes for efficient abi.encoding,
        // This is the best way to determine the number of pools in the path
        // We rely on integrator to pass in the hookdata for each pool.
        // In case the pool is hookless, we still expect integrator to pass in the hookdata as 0x
        // This is equivalent of https://github.com/Uniswap/v4-periphery/blob/main/src/lens/Quoter.sol#L66,
        // where caller has to pass each pool's hookData, even if it's 0x, empty.
        uint256 numPools = param.nonEncodableData.length;
        sqrtPriceX96AfterList = new uint160[](numPools);
        initializedTicksCrossedList = new uint32[](numPools);

        uint256 i = 0;
        while (true) {
            uint8 poolVersion = path.decodePoolVersion();

            if (poolVersion == uint8(2)) {
                (address tokenIn, address tokenOut) = path.decodeFirstV2Pool();

                (uint256 _amountOut, uint256 _gasEstimate) = quoteExactInputSingleV2(
                    QuoteExactInputSingleV2Params({tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn})
                );
                amountIn = _amountOut;
                gasEstimate += _gasEstimate;
            } else if (poolVersion == uint8(4)) {
                bytes memory hookData = param.nonEncodableData[i].hookData;
                (
                    address tokenIn,
                    uint24 fee,
                    uint24 tickSpacing,
                    address hooks,
                    address tokenOut
                ) = path.decodeFirstV4Pool();
                PoolKey memory poolKey = Path.v4PoolToPoolKey(tokenIn, fee, tickSpacing, hooks, tokenOut);

                /// the outputs of prior swaps become the inputs to subsequent ones
                (uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed, uint256 _gasEstimate)
                = quoteExactInputSingleV4(
                    QuoteExactInputSingleV4Params({
                        poolKey: poolKey,
                        zeroForOne: tokenIn < tokenOut,
                        exactAmount: amountIn,
                        sqrtPriceLimitX96: 0,
                        hookData: hookData
                    })
                );
                sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
                initializedTicksCrossedList[i] = _initializedTicksCrossed;
                gasEstimate += _gasEstimate;
                amountIn = _amountOut;
            } else if (poolVersion == uint8(3)) {
                (address tokenIn, uint24 fee, address tokenOut) = path.decodeFirstV3Pool();

                (uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed, uint256 _gasEstimate)
                = quoteExactInputSingleV3(
                    QuoteExactInputSingleV3Params({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountIn: amountIn,
                        fee: fee,
                        sqrtPriceLimitX96: 0
                    })
                );
                sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
                initializedTicksCrossedList[i] = _initializedTicksCrossed;
                gasEstimate += _gasEstimate;
                amountIn = _amountOut;
            } else {
                revert InvalidPoolVersion();
            }

            i++;

            /// decide whether to continue or terminate
            if (numPools > i) {
                path = path.skipToken(poolVersion);
            } else {
                return (amountIn, sqrtPriceX96AfterList, initializedTicksCrossedList, gasEstimate);
            }
        }
    }
}
