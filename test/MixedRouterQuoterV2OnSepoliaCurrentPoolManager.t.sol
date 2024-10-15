// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IQuoter} from "@uniswap/v4-periphery/src/interfaces/IQuoter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";
import {Quoter} from "v4-periphery/src/lens/Quoter.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract MixedRouteQuoterV2TestOnSepolia is Test {
    IQuoterV2 public v3QuoterV2;
    IMixedRouteQuoterV2 public mixedRouteQuoterV2;
    IQuoter public quoter;
    IPoolManager public poolManager;

    address public immutable uniswapV4PoolManager = 0xE8E23e97Fa135823143d6b9Cba9c699040D51F70;
    address public immutable uniswapV3PoolFactory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address public immutable uniswapV2PoolFactory = 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0;
    address public immutable v3QuoterV2Address = 0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3;

    address V4_NATIVE_ADDRESS = address(0);
    address SEPOLIA_WETH_ADDRESS = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address SEPOLIA_USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address SEPOLIA_UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    uint8 public v4FeeShift = 20;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouteQuoterV2 = new MixedRouteQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
        v3QuoterV2 = IQuoterV2(v3QuoterV2Address);
        quoter = new Quoter(poolManager);
    }

    function test_FuzzQuoteExactInput_ZeroForOneTrue(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 1000000000);
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
        uint8 protocolVersion = uint8(4);
        uint24 encodedFee = (uint24(protocolVersion) << v4FeeShift) + fee;
        bytes memory path = abi.encodePacked(SEPOLIA_WETH_ADDRESS, encodedFee, tickSpacing, hooks, SEPOLIA_USDC_ADDRESS);

        (uint256 amountOut, uint256 gasEstimate) = mixedRouteQuoterV2.quoteExactInput(path, extraParams, amountIn);

        assertGt(gasEstimate, 0);

        PathKey[] memory exactInPathKey = new PathKey[](1);
        exactInPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(SEPOLIA_USDC_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactInParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(SEPOLIA_WETH_ADDRESS),
            path: exactInPathKey,
            exactAmount: uint128(amountIn)
        });

        (uint256 expectedAmountOut,) = quoter.quoteExactInput(exactInParams);

        assertEqUint(amountOut, expectedAmountOut);

        // mixed quoter doesn't support exact out by design, but we can cross check the final amount in will equate the original input amount in,
        // if we call the v4 quoter for the exact out quote. v3 and v4 quoter support exact out quote
        PathKey[] memory exactOutPathKey = new PathKey[](1);
        exactOutPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(SEPOLIA_WETH_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactOutParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(SEPOLIA_USDC_ADDRESS),
            path: exactOutPathKey,
            exactAmount: uint128(expectedAmountOut)
        });

        (uint256 expectedAmountIn,) = quoter.quoteExactOutput(exactOutParams);

        // V4 quoter exact out cannot get back to the original amountIn, but seems to be v4 quoter issue only
        // https://app.warp.dev/block/1EWePTvdTYQ2XPmyDkJu38
        // assertApproxEqAbs(amountIn, expectedAmountIn, 1);
    }

    function test_FuzzQuoteExactInput_MultiTokenPath_NoFOT(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 1000000000);
        vm.assume(amountIn < 10000000000000000);

        uint24 fee = 3000;
        uint24 tickSpacing = 60;
        address hooks = address(0);
        bytes memory hookData = "0x";
        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](2);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: hookData}));
        nonEncodableData[1] = (IMixedRouteQuoterV2.NonEncodableData({hookData: hookData}));

        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams =
                            IMixedRouteQuoterV2.ExtraQuoteExactInputParams({nonEncodableData: nonEncodableData});
        uint8 protocolVersion = uint8(4);
        uint24 encodedFee = (uint24(protocolVersion) << v4FeeShift) + fee;
        uint8 v3ProtocolVersion = uint8(3);
        uint24 encodedV3Fee = (uint24(v3ProtocolVersion) << v4FeeShift) + fee;
        console.log(encodedV3Fee);
        bytes memory path = abi.encodePacked(SEPOLIA_WETH_ADDRESS, encodedFee, tickSpacing, hooks, SEPOLIA_USDC_ADDRESS, encodedV3Fee, SEPOLIA_UNI_ADDRESS);

        (uint256 amountOut, uint256 gasEstimate) = mixedRouteQuoterV2.quoteExactInput(path, extraParams, amountIn);

        assertGt(gasEstimate, 0);

        PathKey[] memory exactInPathKey = new PathKey[](1);
        exactInPathKey[0] = PathKey({
            intermediateCurrency: Currency.wrap(SEPOLIA_USDC_ADDRESS),
            fee: fee,
            tickSpacing: int24(tickSpacing),
            hooks: IHooks(hooks),
            hookData: hookData
        });

        IQuoter.QuoteExactParams memory exactInParams = IQuoter.QuoteExactParams({
            exactCurrency: Currency.wrap(SEPOLIA_WETH_ADDRESS),
            path: exactInPathKey,
            exactAmount: uint128(amountIn)
        });

        (uint256 intermediateAmountOut,) = quoter.quoteExactInput(exactInParams);

        bytes memory v3QuoterV2Path = abi.encodePacked(SEPOLIA_USDC_ADDRESS, fee, SEPOLIA_UNI_ADDRESS);
        (uint256 expectedAmountOut,,,) = v3QuoterV2.quoteExactInput(v3QuoterV2Path, intermediateAmountOut);

        assertEqUint(amountOut, expectedAmountOut);
    }
}
