// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Constant state
/// @notice Constant state used by the Mixed Quoter
library Constants {
    /// @dev The length of the bytes encoded address
    uint256 internal constant ADDR_SIZE = 20;

    /// @dev The length of the bytes encoded fee
    uint256 internal constant V3_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded fee
    uint256 internal constant V4_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded tick spacing
    uint256 internal constant TICK_SPACING_SIZE = 3;

    /// @dev The offset of a single token address (20) and pool fee (3)
    uint256 internal constant NEXT_V3_POOL_OFFSET = ADDR_SIZE + V3_FEE_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20)
    uint256 internal constant NEXT_V4_POOL_OFFSET = ADDR_SIZE + V4_FEE_SIZE + TICK_SPACING_SIZE + ADDR_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Fee (3) + tick spacing (3) + hooks address (20) + Token (20) = 66
    uint256 internal constant V4_POP_OFFSET = NEXT_V4_POOL_OFFSET + ADDR_SIZE;

    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint256 internal constant MULTIPLE_V4_POOLS_MIN_LENGTH = V4_POP_OFFSET + NEXT_V4_POOL_OFFSET;

    bytes32 internal constant UNISWAP_V3_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @dev Value to bit mask with path fee to determine if V2 or V3 route
    // max V3 fee:           000011110100001001000000 (24 bits)
    // mask:       1 << 23 = 100000000000000000000000 = decimal value 8388608
    uint24 internal constant v2FlagBitmask = 8388608;

    // mask:       1 << 22 = 10000000000000000000000 = decimal value 4194304
    uint24 internal constant v4FlagBitmask = 4194304;

    /// @dev min valid reason is 6-words long (192 bytes)
    /// @dev int128[2] includes 32 bytes for offset, 32 bytes for length, and 32 bytes for each element
    /// @dev Plus sqrtPriceX96After padded to 32 bytes and initializedTicksLoaded padded to 32 bytes
    uint256 internal constant MINIMUM_VALID_RESPONSE_LENGTH = 192;
}
