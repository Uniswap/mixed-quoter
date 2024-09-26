// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import "./MockPath.sol";

contract TestPath is Test {
    MockPath pathlib;

    function setUp() public {
        pathlib = new MockPath();
    }

    function test_toUint8() public {
        bytes memory input = hex"11223344556677889900";
        assertEq(pathlib.toUint8(input, 0), 0x11);
        assertEq(pathlib.toUint8(input, 1), 0x22);
        assertEq(pathlib.toUint8(input, 2), 0x33);
        assertEq(pathlib.toUint8(input, 3), 0x44);
        assertEq(pathlib.toUint8(input, 4), 0x55);
        assertEq(pathlib.toUint8(input, 5), 0x66);
        assertEq(pathlib.toUint8(input, 6), 0x77);
        assertEq(pathlib.toUint8(input, 7), 0x88);
        assertEq(pathlib.toUint8(input, 8), 0x99);
        assertEq(pathlib.toUint8(input, 9), 0x00);

        vm.expectRevert();
        pathlib.toUint8(input, 10);
    }

    function test_toUint24() public {
        bytes memory input = hex"11223344556677889900";
        assertEq(pathlib.toUint24(input, 0), 0x112233);
        assertEq(pathlib.toUint24(input, 1), 0x223344);
        assertEq(pathlib.toUint24(input, 2), 0x334455);
        assertEq(pathlib.toUint24(input, 3), 0x445566);
        assertEq(pathlib.toUint24(input, 4), 0x556677);
        assertEq(pathlib.toUint24(input, 5), 0x667788);
        assertEq(pathlib.toUint24(input, 6), 0x778899);
        assertEq(pathlib.toUint24(input, 7), 0x889900);

        vm.expectRevert();
        pathlib.toUint24(input, 8);
    }

    function test_toAddress() public {
        bytes memory input = hex"112233445566778899001122334455667788990011223344556677889900";
        assertEq(pathlib.toAddress(input, 0), 0x1122334455667788990011223344556677889900);
        assertEq(pathlib.toAddress(input, 1), 0x2233445566778899001122334455667788990011);
        assertEq(pathlib.toAddress(input, 2), 0x3344556677889900112233445566778899001122);
        assertEq(pathlib.toAddress(input, 3), 0x4455667788990011223344556677889900112233);
        assertEq(pathlib.toAddress(input, 4), 0x5566778899001122334455667788990011223344);
        assertEq(pathlib.toAddress(input, 5), 0x6677889900112233445566778899001122334455);
        // skip some
        assertEq(pathlib.toAddress(input, 9), 0x0011223344556677889900112233445566778899);
        assertEq(pathlib.toAddress(input, 10), 0x1122334455667788990011223344556677889900);

        vm.expectRevert();
        pathlib.toAddress(input, 11);
    }
}
