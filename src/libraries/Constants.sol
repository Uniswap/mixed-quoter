// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Constant state
/// @notice Constant state used by the Mixed Quoter
library Constants {
    /// @dev The length of the bytes encoded pool version
    uint8 internal constant POOL_VERSION_SIZE = 1;

    /// @dev The bitmask for the pool version, used to determine the pool version
    /// 0000011 is the bit mask. we only need 2 bits, because we have 3 pool versions to distinguish
    /// If pool version is 2, 0000011 & 00000010 = 00000010
    /// If pool version is 3, 0000011 & 00000011 = 00000011
    /// If pool version is 4, 0000011 & 00000100 = 00000000
    uint8 internal constant POOL_VERSION_BITMASK = 2;

    /// @dev The length of the bytes encoded address
    uint8 internal constant ADDR_SIZE = 20;

    /// @dev The length of the bytes encoded fee
    uint8 internal constant V3_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded fee
    uint8 internal constant V4_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded tick spacing
    uint8 internal constant TICK_SPACING_SIZE = 3;

    /// @dev The offset of a single token address (20)
    uint8 internal constant NEXT_V2_POOL_OFFSET = POOL_VERSION_SIZE + ADDR_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Token (20) = 40
    uint8 internal constant V2_POP_OFFSET = NEXT_V2_POOL_OFFSET + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3)
    uint8 internal constant NEXT_V3_POOL_OFFSET = POOL_VERSION_SIZE + ADDR_SIZE + V3_FEE_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Fee (3) + Token (20) = 43
    uint8 internal constant V3_POP_OFFSET = NEXT_V3_POOL_OFFSET + ADDR_SIZE;

    /// @dev The offset of pool version (1) + a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20) = 46
    uint8 internal constant NEXT_V4_POOL_OFFSET =
        POOL_VERSION_SIZE + ADDR_SIZE + V4_FEE_SIZE + TICK_SPACING_SIZE + ADDR_SIZE;

    /// @dev The offset of pool version (1) + a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20) + token address (20) = 67
    uint8 internal constant V4_POP_OFFSET = NEXT_V4_POOL_OFFSET + ADDR_SIZE;

    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint8 internal constant MULTIPLE_POOLS_MIN_LENGTH = 2;

    bytes32 internal constant UNISWAP_V3_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint8 internal constant MINIMUM_VALID_RESPONSE_LENGTH = 92;
}
