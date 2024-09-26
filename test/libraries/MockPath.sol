// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0;

import "../../src/libraries/Path.sol";

// Mock contract to enable external calls to the Path library, so the calls use calldata
contract MockPath {
    using Path for bytes;

    function toAddress(bytes calldata _bytes, uint256 _start) external pure returns (address result) {
        return _bytes.toAddress(_start);
    }

    function toUint24(bytes calldata _bytes, uint256 _start) external pure returns (uint24 result) {
        return _bytes.toUint24(_start);
    }

    function toUint8(bytes calldata _bytes, uint256 _start) external pure returns (uint8 result) {
        return _bytes.toUint8(_start);
    }
}
