// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma abicoder v2;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title MixedRouteQuoterV1 Interface
/// @notice Supports quoting the calculated amounts for exact input swaps. Is specialized for routes containing a mix of V2 and V3 and V4 liquidity.
/// @notice For each pool also tells you the number of initialized ticks crossed and the sqrt price of the pool after the swap.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
interface IMixedRouteQuoterV2 {
    error UnexpectedRevertBytes(bytes revertData);
    error InsufficientAmountOut();
    error LockFailure();
    error InvalidPoolVersion();

    struct QuoteExactInputSingleV2Params {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
    }

    struct QuoteExactInputSingleV3Params {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    struct QuoteExactInputSingleV4Params {
        PoolKey poolKey;
        bool zeroForOne;
        uint256 exactAmount;
        uint160 sqrtPriceLimitX96;
        bytes hookData;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single V2 pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleV2Params`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// amountIn The desired input amount
    /// @return amountOut The amount of `tokenOut` that would be received
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return initializedTicksCrossed The number of initialized ticks that the swap crossed
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params calldata params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);

    /// @notice Returns the delta amounts for a given exact input swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// poolKey The key for identifying a V4 pool
    /// zeroForOne If the swap is from currency0 to currency1
    /// exactAmount The desired input amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// hookData arbitrary hookData to pass into the associated hooks
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return initializedTicksLoaded The number of initialized ticks that the swap loaded
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingleV4(QuoteExactInputSingleV4Params calldata params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksLoaded, uint256 gasEstimate);

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param poolVersions The version of each pool in the path, encoded as a list of bytes
    /// @param allHookData all abi.encode packed hook data for each pool in the path, encoded as a list of bytes
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each v3 pool in the path, 0 for v2 pools
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each v3 pool in the path, 0 for v2 pools
    /// @return swapGasEstimate The estimate of the gas that the v3 swaps in the path consume
    function quoteExactInput(bytes memory path, bytes memory poolVersions, bytes memory allHookData, uint256 amountIn)
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 swapGasEstimate
        );
}
