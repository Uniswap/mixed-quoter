// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.0;

import {BytesLib} from "lib/universal-router/contracts/modules/uniswap/v3/BytesLib.sol";
import {Constants} from "./Constants.sol";

/// @title Functions for manipulating path data for multihop swaps
library Path {
    using BytesLib for bytes;

    /// @notice Returns true iff the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes calldata path) internal pure returns (bool) {
        return path.length >= Constants.MULTIPLE_V4_POOLS_MIN_LENGTH;
    }

    /// @notice Returns the number of pools in the path
    /// @param path The encoded swap path
    /// @return The number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Ignore the first token address. From then on every fee and token offset indicates a pool.
        return ((path.length - Constants.ADDR_SIZE) / Constants.NEXT_V4_POOL_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return fee The fee level of the pool
    /// @return tokenB The second token of the given pool
    function decodeFirstPool(bytes calldata path) public pure returns (address, uint24, uint24, address, address) {
        return toV4Pool(path);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return fee The fee level of the pool
    /// @return tokenB The second token of the given pool
    function decodeFirstV3Pool(bytes calldata path) public pure returns (address, uint24, address) {
        return path.toPool();
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return fee The fee level of the pool
    /// @return tokenB The second token of the given pool
    function decodeFirstV4Pool(bytes calldata path) public pure returns (address, uint24, uint24, address, address) {
        return toV4Pool(path);
    }

    /// @notice Returns the pool details starting at byte 0
    /// @dev length and overflow checks must be carried out before calling
    /// @param path The input bytes string to slice
    /// @return token0 The address at byte 0
    /// @return fee The uint24 starting at byte 20
    /// @return tickSpacing The uint24 starting at byte 23
    /// @return hooks The address at byte 26
    /// @return token1 The address at byte 46
    function toV4Pool(bytes calldata path) internal pure returns (address token0, uint24 fee, uint24 tickSpacing, address hooks, address token1) {
        if (path.length < Constants.V4_POP_OFFSET) revert BytesLib.SliceOutOfBounds();
        token0 = toAddress(path, 0);
        fee = toUint24(path, Constants.ADDR_SIZE);
        tickSpacing = toUint24(path, Constants.ADDR_SIZE + Constants.V4_FEE_SIZE);
        hooks = toAddress(path, Constants.ADDR_SIZE + Constants.V4_FEE_SIZE + Constants.TICK_SPACING_SIZE);
        token1 = toAddress(path, Constants.NEXT_V4_POOL_OFFSET);
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    function getFirstPool(bytes calldata path) internal pure returns (bytes calldata) {
        return path[:Constants.V4_POP_OFFSET];
    }

    function decodeFirstToken(bytes calldata path) internal pure returns (address tokenA) {
        tokenA = path.toAddress();
    }

    /// @notice Skips a token + fee element
    /// @param path The swap path
    function skipToken(bytes calldata path) internal pure returns (bytes calldata) {
        return path[Constants.NEXT_V4_POOL_OFFSET:];
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, 'toAddress_overflow');
        require(_bytes.length >= _start + 20, 'toAddress_outOfBounds');
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_start + 3 >= _start, 'toUint24_overflow');
        require(_bytes.length >= _start + 3, 'toUint24_outOfBounds');
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }
}
