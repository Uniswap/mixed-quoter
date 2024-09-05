// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.0;

import {BytesLib} from "@uniswap/universal-router/contracts/modules/uniswap/v3/BytesLib.sol";
import {Constants} from "./Constants.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title Functions for manipulating path data for multihop swaps
library Path {
    using BytesLib for bytes;

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    function decodePoolVersion(bytes memory path) internal pure returns (uint8 poolVersion) {
        if (path.length < Constants.POOL_VERSION_SIZE) revert BytesLib.SliceOutOfBounds();
        uint8 bitMaskedPoolVersion = toUint8(path, 0) & Constants.POOL_VERSION_BITMASK;
        if (bitMaskedPoolVersion == uint8(2)) {
            return uint8(2);
        } else if (bitMaskedPoolVersion == uint8(3)) {
            return uint8(3);
        } else if (bitMaskedPoolVersion == uint8(0)) {
            return uint8(4);
        } else {
            revert("invalid_pool_version");
        }
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return tokenB The second token of the given pool
    function decodeFirstV2Pool(bytes memory path) internal pure returns (address tokenA, address tokenB) {
        if (path.length < Constants.V2_POP_OFFSET) revert BytesLib.SliceOutOfBounds();
        tokenA = toAddress(path, Constants.POOL_VERSION_SIZE);
        tokenB = toAddress(path, Constants.NEXT_V2_POOL_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return fee The fee level of the pool
    /// @return tokenB The second token of the given pool
    function decodeFirstV3Pool(bytes memory path) internal pure returns (address tokenA, uint24 fee, address tokenB) {
        if (path.length < Constants.V3_POP_OFFSET) revert BytesLib.SliceOutOfBounds();
        tokenA = toAddress(path, Constants.POOL_VERSION_SIZE);
        fee = toUint24(path, Constants.POOL_VERSION_SIZE + Constants.ADDR_SIZE);
        tokenB = toAddress(path, Constants.NEXT_V3_POOL_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenIn The address at byte 0
    /// @return fee The uint24 starting at byte 20
    /// @return tickSpacing The uint24 starting at byte 23
    /// @return hooks The address at byte 26
    /// @return tokenOut The address at byte 47
    function decodeFirstV4Pool(bytes memory path)
        internal
        pure
        returns (
            address tokenIn,
            uint24 fee,
            uint24 tickSpacing,
            address hooks,
            address tokenOut
        )
    {
        if (path.length < Constants.V4_POP_OFFSET) revert BytesLib.SliceOutOfBounds();
        tokenIn = toAddress(path, Constants.POOL_VERSION_SIZE);
        fee = toUint24(path, Constants.POOL_VERSION_SIZE + Constants.ADDR_SIZE);
        tickSpacing = toUint24(path, Constants.POOL_VERSION_SIZE + Constants.ADDR_SIZE + Constants.V4_FEE_SIZE);
        hooks = toAddress(path, Constants.POOL_VERSION_SIZE + Constants.ADDR_SIZE + Constants.V4_FEE_SIZE + Constants.TICK_SPACING_SIZE);
        tokenOut = toAddress(path, Constants.NEXT_V4_POOL_OFFSET);
    }

    /// @notice v4 pool convert to pool key
    /// @dev length and overflow checks must be carried out before calling
    /// @param token0 The address at byte 0
    /// @param fee The uint24 starting at byte 20
    /// @param tickSpacing The uint24 starting at byte 23
    /// @param hooks The address at byte 26
    /// @param token1 The address at byte 46
    /// @return PoolKey
    function v4PoolToPoolKey(address token0, uint24 fee, uint24 tickSpacing, address hooks, address token1)
        internal
        pure
        returns (PoolKey memory)
    {
        (address tokenIn, address tokenOut) = token0 < token1 ? (token0, token1) : (token1, token0);
        Currency currency0 = Currency.wrap(tokenIn);
        Currency currency1 = Currency.wrap(tokenOut);
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks)
        });
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return slice(path, 0, Constants.V4_POP_OFFSET);
    }

    function decodeFirstToken(bytes memory path) internal pure returns (address tokenA) {
        tokenA = toAddress(path, 0);
    }

    /// @notice Skips a token + fee element
    /// @param path The swap path
    function skipToken(bytes memory path, uint8 poolVersion) internal pure returns (bytes memory) {
        if (poolVersion == uint8(2)) {
            return slice(path, Constants.NEXT_V2_POOL_OFFSET, path.length - Constants.NEXT_V2_POOL_OFFSET);
        } else if (poolVersion == uint8(3)) {
            return slice(path, Constants.NEXT_V3_POOL_OFFSET, path.length - Constants.NEXT_V3_POOL_OFFSET);
        } else if (poolVersion == uint8(4)) {
            return slice(path, Constants.NEXT_V4_POOL_OFFSET, path.length - Constants.NEXT_V4_POOL_OFFSET);
        } else {
            revert("invalid_pool_version");
        }
    }

    function skipHookData(bytes memory allHookData, bytes memory hookData) internal pure returns (bytes memory) {
        return slice(allHookData, hookData.length, allHookData.length - hookData.length);
    }

    function slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_start + _length >= _start, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } { mstore(mc, mload(cc)) }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, "toAddress_overflow");
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_start + 3 >= _start, "toUint24_overflow");
        require(_bytes.length >= _start + 3, "toUint24_outOfBounds");
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }

    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_start + 1 >= _start, "toUint8_overflow");
        require(_bytes.length >= _start + 1, "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }
}
