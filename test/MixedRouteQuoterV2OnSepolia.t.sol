// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";
import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract MixedRouteQuoterV2TestOnSepolia is Test {
    IMixedRouteQuoterV2 public mixedRouterQuoterV2;
    IPoolManager public poolManager;
    address public immutable uniswapV4PoolManager = 0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6;
    address public immutable uniswapV3PoolFactory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address public immutable uniswapV2PoolFactory = 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0;

    address V4_SEPOLIA_OP_ADDRESS = 0xc268035619873d85461525F5fDb792dd95982161;
    address V4_SEPOLIA_USDC_ADDRESS = 0xbe2a7F5acecDc293Bf34445A0021f229DD2Edd49;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouterQuoterV2 = new MixedRouteQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
    }

    function test_QuoteExactInputSingleV4() public {
        uint24 fee = 500;
        bool zeroForOne = false;
        uint24 tickSpacing = 10;
        address hooks = address(0);
        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        uint256 amountIn = 10000000000000000;

        (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksLoaded, uint256 gasEstimate) =
        mixedRouterQuoterV2.quoteExactInputSingleV4(
            IMixedRouteQuoterV2.QuoteExactInputSingleV4Params({
                poolKey: PoolKey({
                    currency0: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
                    currency1: Currency.wrap(V4_SEPOLIA_OP_ADDRESS),
                    fee: fee,
                    tickSpacing: int24(tickSpacing),
                    hooks: IHooks(hooks)
                }),
                zeroForOne: zeroForOne,
                exactAmount: amountIn,
                sqrtPriceLimitX96: 0,
                hookData: "0x" // TODO: figure out how to pass in hookData
            })
        );
        assertEqUint(amountOut, 9975030024927567);
        assertEqUint(sqrtPriceX96After, 79307469706553480188651360835);
        assertEqUint(initializedTicksLoaded, 0);
        assertGt(gasEstimate, 0);
    }

    function test_QuoteExactInput() public {
        uint24 fee = 500;
        uint24 tickSpacing = 10;
        address hooks = address(0);
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](1);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: "0x"}));

        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams = IMixedRouteQuoterV2.ExtraQuoteExactInputParams({
            nonEncodableData: nonEncodableData
        });
        uint256 amountIn = 10000000000000000;

        bytes memory path = abi.encodePacked(
            V4_SEPOLIA_OP_ADDRESS, fee, tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS
        );
        bytes memory poolVersions = abi.encodePacked(uint8(4));

        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96After,
            uint32[] memory initializedTicksLoaded,
            uint256 gasEstimate
        ) = mixedRouterQuoterV2.quoteExactInput(path, poolVersions, extraParams, amountIn);
        assertEqUint(amountOut, 9975030024927567);
        assertEqUint(sqrtPriceX96After[0], 79307469706553480188651360835);
        assertEqUint(initializedTicksLoaded[0], 0);
        assertGt(gasEstimate, 0);
    }

    function test_FuzzQuoteExactInput(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 10000);
        vm.assume(amountIn < 10000000000000000);

        uint24 fee = 500;
        uint24 tickSpacing = 10;
        address hooks = address(0);
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](1);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: "0x"}));

        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams = IMixedRouteQuoterV2.ExtraQuoteExactInputParams({
            nonEncodableData: nonEncodableData
        });

        bytes memory path = abi.encodePacked(
            V4_SEPOLIA_OP_ADDRESS, fee, tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS
        );
        bytes memory poolVersions = abi.encodePacked(uint8(4));

        (uint256 amountOut, , , uint256 gasEstimate) = mixedRouterQuoterV2.quoteExactInput(path, poolVersions, extraParams, amountIn);
        assertGt(amountOut, 0);
        assertGt(gasEstimate, 0);
    }
}
