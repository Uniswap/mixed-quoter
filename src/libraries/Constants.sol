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
}
