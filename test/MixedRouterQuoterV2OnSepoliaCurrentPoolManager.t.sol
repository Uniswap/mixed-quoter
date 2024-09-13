// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IQuoter} from "@uniswap/v4-periphery/src/interfaces/IQuoter.sol";
import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";
import {Quoter} from "v4-periphery/src/lens/Quoter.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract MixedRouteQuoterV2TestOnSepolia is Test {
    IMixedRouteQuoterV2 public mixedRouteQuoterV2;
    IQuoter public quoter;
    IPoolManager public poolManager;

    address public immutable uniswapV4PoolManager = 0xE8E23e97Fa135823143d6b9Cba9c699040D51F70;
    address public immutable uniswapV3PoolFactory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address public immutable uniswapV2PoolFactory = 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0;

    address V4_SEPOLIA_A_ADDRESS = 0x0275C79896215a790dD57F436E1103D4179213be;
    address V4_SEPOLIA_B_ADDRESS = 0x1a6990C77cFBBA398BeB230Dd918e28AAb71EEC2;
    uint8 public v4FeeShift = 20;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouteQuoterV2 = new MixedRouteQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
        quoter = new Quoter(poolManager);
    }

    function test_FuzzQuoteExactInput_ZeroForOneTrue(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 10000);
        vm.assume(amountIn < 10000000000000000);

        uint24 fee = 3000;
        uint24 tickSpacing = 60;
        address hooks = address(0);
        bytes memory hookData = "0x";
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](1);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: hookData}));

        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams =
            IMixedRouteQuoterV2.ExtraQuoteExactInputParams({nonEncodableData: nonEncodableData});
        uint8 poolVersions = uint8(4);
        uint24 encodedFee = (uint24(poolVersions) << v4FeeShift) + fee;
        bytes memory path = abi.encodePacked(V4_SEPOLIA_A_ADDRESS, encodedFee, tickSpacing, hooks, V4_SEPOLIA_B_ADDRESS);

        (uint256 amountOut, uint256 gasEstimate) = mixedRouteQuoterV2.quoteExactInput(path, extraParams, amountIn);

        assertGt(gasEstimate, 0);

        PathKey[] memory exactInPathKey = new PathKey[](1);
        exactInPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_B_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactInParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_A_ADDRESS),
            path: exactInPathKey,
            exactAmount: uint128(amountIn)
        });

        (uint256 expectedAmountOut,) = quoter.quoteExactInput(exactInParams);

        assertEqUint(amountOut, expectedAmountOut);

        // mixed quoter doesn't support exact out by design, but we can cross check the final amount in will equate the original input amount in,
        // if we call the v4 quoter for the exact out quote. v3 and v4 quoter support exact out quote
        PathKey[] memory exactOutPathKey = new PathKey[](1);
        exactOutPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(V4_SEPOLIA_A_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactOutParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(V4_SEPOLIA_B_ADDRESS),
            path: exactOutPathKey,
            exactAmount: uint128(expectedAmountOut)
        });

        (uint256 expectedAmountIn,) = quoter.quoteExactOutput(exactOutParams);
        assertApproxEqAbs(amountIn, expectedAmountIn, 1);
    }
}
