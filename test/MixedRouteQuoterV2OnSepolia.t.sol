// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";
import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IQuoter} from "@uniswap/v4-periphery/src/interfaces/IQuoter.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {Quoter} from "v4-periphery/src/lens/Quoter.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

contract MixedRouteQuoterV2TestOnSepolia is Test {
    IMixedRouteQuoterV2 public mixedRouterQuoterV2;
    IQuoter public quoter;
    IPoolManager public poolManager;
    address public immutable uniswapV4PoolManager = 0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6;
    address public immutable uniswapV3PoolFactory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address public immutable uniswapV2PoolFactory = 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0;

    address V4_SEPOLIA_OP_ADDRESS = 0xc268035619873d85461525F5fDb792dd95982161;
    address V4_SEPOLIA_USDC_ADDRESS = 0xbe2a7F5acecDc293Bf34445A0021f229DD2Edd49;
    address V4_SEPOLIA_MATIC_ADDRESS = 0x5F1C75abBb24a6e27E44c9055F50f874Dbe9d8dA;
    address V4_SEPOLIA_GRT_ADDRESS = 0x382658f1DCEB66ab4Df85E376b25e3699D6f1D83;
    address V4_SEPOLIA_MNT_ADDRESS = 0x16A6E5A3773bE7255FCf45e7399546F004E86154;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouterQuoterV2 = new MixedRouteQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
        quoter = new Quoter(poolManager);
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

        uint8 poolVersions = uint8(4);
        bytes memory path = abi.encodePacked(
            poolVersions, V4_SEPOLIA_OP_ADDRESS, fee, tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS
        );

        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96After,
            uint32[] memory initializedTicksLoaded,
            uint256 gasEstimate
        ) = mixedRouterQuoterV2.quoteExactInput(path, extraParams, amountIn);
        assertEqUint(amountOut, 9975030024927567);
        assertEqUint(sqrtPriceX96After[0], 79307469706553480188651360835);
        assertEqUint(initializedTicksLoaded[0], 0);
        assertGt(gasEstimate, 0);
    }

    function test_FuzzQuoteExactInput_ZeroForOneTrue(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 10000);
        vm.assume(amountIn < 10000000000000000);

        uint24 fee = 500;
        uint24 tickSpacing = 10;
        address hooks = address(0);
        bytes memory hookData = "0x";
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](1);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: hookData}));

        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams = IMixedRouteQuoterV2.ExtraQuoteExactInputParams({
            nonEncodableData: nonEncodableData
        });
        uint8 poolVersions = uint8(4);
        bytes memory path = abi.encodePacked(
            poolVersions, V4_SEPOLIA_MATIC_ADDRESS, fee, tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS
        );

        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96After,
            uint32[] memory initializedTicksLoaded,
            uint256 gasEstimate
        ) = mixedRouterQuoterV2.quoteExactInput(path, extraParams, amountIn);

        assertGt(gasEstimate, 0);

        PathKey[] memory exactInPathKey = new PathKey[](1);
        exactInPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactInParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_MATIC_ADDRESS),
            path: exactInPathKey,
            exactAmount: uint128(amountIn)
        });

        (
            int128[] memory expectedDeltaAmounts,
            uint160[] memory expectedSqrtPriceX96After,
            uint32[] memory expectedInitializedTicksLoaded
        ) = quoter.quoteExactInput(exactInParams);

        uint256 expectedAmountOut = uint256(uint128(-expectedDeltaAmounts[exactInPathKey.length])); // negate the final delta amount out
        assertEqUint(amountOut, expectedAmountOut);
        assertEqUint(sqrtPriceX96After[0], expectedSqrtPriceX96After[0]);
        assertEqUint(initializedTicksLoaded[0], expectedInitializedTicksLoaded[0]);

        // mixed quoter doesn't support exact out by design, but we can cross check the final amount in will equate the original input amount in,
        // if we call the v4 quoter for the exact out quote. v3 and v4 quoter support exact out quote
        PathKey[] memory exactOutPathKey = new PathKey[](1);
        exactOutPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_MATIC_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactOutParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
            path: exactOutPathKey,
            exactAmount: uint128(expectedAmountOut)
        });

        (int128[] memory expectedDeltaAmountsIn, , ) = quoter.quoteExactOutput(exactOutParams);
        uint256 expectedAmountIn = uint256(uint128(expectedDeltaAmountsIn[0])); // final delta amount in is the positive amount in the first array element
        assertApproxEqAbs(amountIn, expectedAmountIn, 1);
    }

    function test_FuzzQuoteExactInput_ZeroForOneFalse(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 10000);
        vm.assume(amountIn < 10000000000000000);

        uint24 fee = 500;
        uint24 tickSpacing = 10;
        address hooks = address(0);
        bytes memory hookData = "0x";
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](1);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: hookData}));

        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams = IMixedRouteQuoterV2.ExtraQuoteExactInputParams({
            nonEncodableData: nonEncodableData
        });
        uint8 poolVersions = uint8(4);
        bytes memory path = abi.encodePacked(
            poolVersions, V4_SEPOLIA_OP_ADDRESS, fee, tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS
        );

        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96After,
            uint32[] memory initializedTicksLoaded,
            uint256 gasEstimate
        ) = mixedRouterQuoterV2.quoteExactInput(path, extraParams, amountIn);

        assertGt(gasEstimate, 0);

        PathKey[] memory exactInPathKey = new PathKey[](1);
        exactInPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactInParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_OP_ADDRESS),
            path: exactInPathKey,
            exactAmount: uint128(amountIn)
        });

        (
            int128[] memory expectedDeltaAmounts,
            uint160[] memory expectedSqrtPriceX96After,
            uint32[] memory expectedInitializedTicksLoaded
        ) = quoter.quoteExactInput(exactInParams);

        uint256 expectedAmountOut = uint256(uint128(-expectedDeltaAmounts[exactInPathKey.length])); // negate the final delta amount out
        assertEqUint(amountOut, expectedAmountOut);
        assertEqUint(sqrtPriceX96After[0], expectedSqrtPriceX96After[0]);
        assertEqUint(initializedTicksLoaded[0], expectedInitializedTicksLoaded[0]);

        // mixed quoter doesn't support exact out by design, but we can cross check the final amount in will equate the original input amount in,
        // if we call the v4 quoter for the exact out quote. v3 and v4 quoter support exact out quote
        PathKey[] memory exactOutPathKey = new PathKey[](1);
        exactOutPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_OP_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactOutParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
            path: exactOutPathKey,
            exactAmount: uint128(expectedAmountOut)
        });

        (int128[] memory expectedDeltaAmountsIn, , ) = quoter.quoteExactOutput(exactOutParams);
        uint256 expectedAmountIn = uint256(uint128(expectedDeltaAmountsIn[0])); // final delta amount in is the positive amount in the first array element
        assertApproxEqAbs(amountIn, expectedAmountIn, 1);
    }

    function test_FuzzQuoteExactInput_MultiTokenPath(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 10000);
        vm.assume(amountIn < 10000000000000000);

        // GRT -> USDC -> MNT
        uint8 GRT_USDC_poolVersions = uint8(4);
        uint24 GRT_USDC_fee = 500;
        uint24 GRT_USDC_tickspacing = 10;
        address GRT_USDC_hooks = address(0);
        bytes memory GRT_USDC_hookData = "0x";
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](2);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: GRT_USDC_hookData}));

        uint8 USDC_MNT_poolVersions = uint8(4);
        uint24 USDC_MNT_fee = 500;
        uint24 USDC_MNT_tickspacing = 10;
        address USDC_MNT_hooks = address(0);
        bytes memory USDC_MNT_hookData = "0x";
        nonEncodableData[1] = (IMixedRouteQuoterV2.NonEncodableData({hookData: USDC_MNT_hookData}));

        bytes memory path = abi.encodePacked(
            GRT_USDC_poolVersions, V4_SEPOLIA_GRT_ADDRESS, GRT_USDC_fee, GRT_USDC_tickspacing, GRT_USDC_hooks, V4_SEPOLIA_USDC_ADDRESS,
            USDC_MNT_poolVersions, V4_SEPOLIA_USDC_ADDRESS, USDC_MNT_fee, USDC_MNT_tickspacing, USDC_MNT_hooks, V4_SEPOLIA_MNT_ADDRESS
        );
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams = IMixedRouteQuoterV2.ExtraQuoteExactInputParams({
            nonEncodableData: nonEncodableData
        });

        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96After,
            uint32[] memory initializedTicksLoaded,
            uint256 gasEstimate
        ) = mixedRouterQuoterV2.quoteExactInput(path, extraParams, amountIn);

        assertGt(gasEstimate, 0);

        PathKey[] memory exactInPathKey = new PathKey[](2);
        exactInPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
            fee: GRT_USDC_fee,
            tickSpacing: int24(GRT_USDC_tickspacing),
            hooks: IHooks(GRT_USDC_hooks),
            hookData: GRT_USDC_hookData
        });
        exactInPathKey[1] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_MNT_ADDRESS),
            fee: USDC_MNT_fee,
            tickSpacing: int24(USDC_MNT_tickspacing),
            hooks: IHooks(USDC_MNT_hooks),
            hookData: USDC_MNT_hookData
        });

        IQuoter.QuoteExactParams memory exactInParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_GRT_ADDRESS),
            path: exactInPathKey,
            exactAmount: uint128(amountIn)
        });

        (
            int128[] memory expectedDeltaAmounts,
            uint160[] memory expectedSqrtPriceX96After,
            uint32[] memory expectedInitializedTicksLoaded
        ) = quoter.quoteExactInput(exactInParams);

        uint256 expectedAmountOut = uint256(uint128(-expectedDeltaAmounts[exactInPathKey.length])); // negate the final delta amount out
        assertEqUint(amountOut, expectedAmountOut);
        assertEqUint(sqrtPriceX96After[0], expectedSqrtPriceX96After[0]);
        assertEqUint(initializedTicksLoaded[0], expectedInitializedTicksLoaded[0]);
        assertEqUint(sqrtPriceX96After[1], expectedSqrtPriceX96After[1]);
        assertEqUint(initializedTicksLoaded[1], expectedInitializedTicksLoaded[1]);

        // mixed quoter doesn't support exact out by design, but we can cross check the final amount in will equate the original input amount in,
        // if we call the v4 quoter for the exact out quote. v3 and v4 quoter support exact out quote
        PathKey[] memory exactOutPathKey = new PathKey[](2);
        exactOutPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_GRT_ADDRESS),
            fee: GRT_USDC_fee,
            tickSpacing: int24(GRT_USDC_tickspacing),
            hooks: IHooks(GRT_USDC_hooks),
            hookData: GRT_USDC_hookData
        });
        exactOutPathKey[1] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
            fee: USDC_MNT_fee,
            tickSpacing: int24(USDC_MNT_tickspacing),
            hooks: IHooks(USDC_MNT_hooks),
            hookData: USDC_MNT_hookData
        });

        IQuoter.QuoteExactParams memory exactOutParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_MNT_ADDRESS),
            path: exactOutPathKey,
            exactAmount: uint128(expectedAmountOut)
        });

        (int128[] memory expectedDeltaAmountsIn, , ) = quoter.quoteExactOutput(exactOutParams);
        uint256 expectedAmountIn = uint256(uint128(expectedDeltaAmountsIn[0])); // final delta amount in is the positive amount in the first array element
        assertApproxEqAbs(amountIn, expectedAmountIn, 1);
    }
}
