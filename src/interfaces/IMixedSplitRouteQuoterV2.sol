// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;
pragma abicoder v2;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title IMixedSplitRouteQuoterV2 Interface
/// @notice Supports quoting the calculated amounts for exact input swaps. Is specialized for routes containing a mix of V2 and V3 and V4 liquidity.
/// @notice Supports DAG-style split routes: each pool node can forward fractions of its output to any later node in the route array.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
interface IMixedSplitRouteQuoterV2 {
    error InvalidProtocolVersion(uint256 protocolVersion);
    error NoLiquidityV3();
    /// @notice Thrown when the cumulative bps for a node's outputs exceeds 10_000
    error InvalidSplitBPS();
    /// @notice Thrown when a SplitOutputTarget.targetIndex is not strictly greater than the current node's index
    error InvalidSplitTarget();

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
    }

    struct QuoteExactInputSingleV4Params {
        PoolKey poolKey;
        bool zeroForOne;
        uint256 exactAmount;
        bytes hookData;
    }

    struct NonEncodableData {
        bytes hookData;
    }

    struct ExtraQuoteExactInputParams {
        NonEncodableData[] nonEncodableData;
    }

    /// @notice Declares that a fraction of a node's output should be forwarded to a downstream node
    /// @param targetIndex The index in the route array that receives the forwarded amount.
    ///                    Must be strictly greater than the current node's index.
    /// @param bps The fraction of this node's output to forward, in basis points (out of 10_000).
    struct SplitOutputTarget {
        uint256 targetIndex;
        uint256 bps;
    }

    /// @notice A single pool node in a split route DAG
    /// @param path The encoded single-pool-hop path (tokenIn + fee/version encoding + tokenOut).
    ///             Uses the same V2/V3/V4 byte encoding as quoteExactInput, but for exactly one pool.
    /// @param hookData Hook data for this pool. Required for V4 pools with hooks; pass empty bytes for V2/V3.
    /// @param amountIn Initial input amount for this node. Set to the desired input for source nodes;
    ///                 set to 0 for nodes that receive all their input from upstream nodes via outputs.
    /// @param outputs How to distribute this node's output to downstream nodes.
    ///                The cumulative bps across all entries must not exceed 10_000.
    ///                Any remainder (10_000 - sum(bps)) is added to the final amountOut accumulator.
    ///                Pass an empty array to send all output directly to the final accumulator.
    struct SplitNode {
        bytes path;
        bytes hookData;
        uint256 amountIn;
        SplitOutputTarget[] outputs;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single V2 pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleV2Params`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// amountIn The desired input amount
    /// @return amountOut The amount of `tokenOut` that would be received
    function quoteExactInputSingleV2(QuoteExactInputSingleV2Params memory params)
        external
        view
        returns (uint256 amountOut);

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingleV3(QuoteExactInputSingleV3Params calldata params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the delta amounts for a given exact input swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// poolKey The key for identifying a V4 pool
    /// zeroForOne If the swap is from currency0 to currency1
    /// exactAmount The desired input amount
    /// hookData arbitrary hookData to pass into the associated hooks
    /// @return amountOut The amount of `tokenOut` that would be received
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingleV4(QuoteExactInputSingleV4Params calldata params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param param the remaining non abi encodable data
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return gasEstimate The estimate of the gas that the v3 and v4 swaps in the path consume
    function quoteExactInput(bytes memory path, ExtraQuoteExactInputParams calldata param, uint256 amountIn)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    /// @notice Quotes an exact-input swap through a DAG of pool nodes, returning per-node output breakdowns.
    /// @dev    Nodes are processed in array order. Each node's total input is its own amountIn plus
    ///         any amounts forwarded to it from earlier nodes via SplitOutputTarget entries.
    ///         After quoting a node, its output is distributed: each SplitOutputTarget receives
    ///         `nodeOutput * bps / 10_000` of the output, forwarded to pendingAmounts[targetIndex].
    ///         The last SplitOutputTarget when cumulative bps equals 10_000 receives the exact remaining
    ///         nodeOutput (absorbing rounding dust). Any output not forwarded to a downstream node
    ///         (because cumulative bps < 10_000, or outputs is empty) is added to the final amountOut.
    ///         Nodes with zero total input are skipped (their amountsOut entry will be 0).
    ///
    ///         Example — Pool A output split 40/60 into Pool C and Pool B:
    ///           route[0] = SplitNode(poolA, amountIn=1000, outputs=[{index:1, bps:4000},{index:2, bps:6000}])
    ///           route[1] = SplitNode(poolC, amountIn=0,    outputs=[])   // receives 40% of A's output → final
    ///           route[2] = SplitNode(poolB, amountIn=0,    outputs=[])   // receives 60% of A's output → final
    ///           amountsOut = [A_output, C_output, B_output]
    ///
    /// @param route Flat array of SplitNode entries; targetIndex in each SplitOutputTarget must be
    ///              strictly greater than the node's own index, or InvalidSplitTarget is thrown.
    /// @return amountsOut Per-node output amounts in route order; amountsOut[i] is the output of route[i].
    /// @return gasEstimate Cumulative gas estimate across all V3 and V4 swaps.
    function quoteExactInputSplit(SplitNode[] calldata route)
        external
        returns (uint256[] memory amountsOut, uint256 gasEstimate);
}
