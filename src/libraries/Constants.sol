// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Constant state
/// @notice Constant state used by the Mixed Quoter
library Constants {
    /// @dev The length of the bytes encoded address
    uint8 internal constant ADDR_SIZE = 20;

    /// @dev The length of the bytes encoded fee
    uint8 internal constant V3_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded fee
    uint8 internal constant V4_FEE_SIZE = 3;

    /// @dev The length of the bytes encoded tick spacing
    uint8 internal constant TICK_SPACING_SIZE = 3;

    /// @dev The length of the bytes used to represent current hook data bytes size
    uint16 internal constant HOOKDATA_SIZE = 2;

    /// @dev The offset of a single token address (20)
    uint8 internal constant NEXT_V2_POOL_OFFSET = ADDR_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Token (20) = 40
    uint8 internal constant V2_POP_OFFSET = NEXT_V2_POOL_OFFSET + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3)
    uint8 internal constant NEXT_V3_POOL_OFFSET = ADDR_SIZE + V3_FEE_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Fee (3) + Token (20) = 43
    uint8 internal constant V3_POP_OFFSET = NEXT_V3_POOL_OFFSET + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20) + hook data (2)
    uint16 internal constant V4_HOOKDATA_OFFSET = ADDR_SIZE + V4_FEE_SIZE + TICK_SPACING_SIZE + ADDR_SIZE;

    /// @dev The offset of a single token address (20) and pool fee (3) + tick spacing (3) + hooks address (20) + hook data (2)
    uint16 internal constant NEXT_V4_POOL_OFFSET = V4_HOOKDATA_OFFSET + HOOKDATA_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Fee (3) + tick spacing (3) + hooks address (20) + hook data (256) + Token (20) = 322
    uint16 internal constant V4_POP_OFFSET = NEXT_V4_POOL_OFFSET + ADDR_SIZE;

    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint8 internal constant MULTIPLE_POOLS_MIN_LENGTH = 2;

    bytes32 internal constant UNISWAP_V3_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint8 internal constant MINIMUM_VALID_RESPONSE_LENGTH = 92;
}
