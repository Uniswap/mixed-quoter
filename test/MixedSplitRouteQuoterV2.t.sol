//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MixedSplitRouteQuoterV2, IMixedSplitRouteQuoterV2} from "../src/MixedSplitRouteQuoterV2.sol";
import {MockMsgSenderHook} from "@uniswap/v4-periphery/test/mocks/MockMsgSenderHook.sol";

// v4-core
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// solmate
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract QuoterTest is Test, Deployers {
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    // Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    // Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    MixedSplitRouteQuoterV2 quoter;

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;

    PoolKey key01Hook;

    MockERC20[] tokenPath;

    function setUp() public {
        deployFreshManagerAndRouters();
        quoter = new MixedSplitRouteQuoterV2(manager, address(0), address(0));

        // salts are chosen so that address(token0) < address(token1) && address(token1) < address(token2)
        token0 = new MockERC20("Test0", "0", 18);
        vm.etch(address(0x1111), address(token0).code);
        token0 = MockERC20(address(0x1111));
        token0.mint(address(this), 2 ** 128);

        vm.etch(address(0x2222), address(token0).code);
        token1 = MockERC20(address(0x2222));
        token1.mint(address(this), 2 ** 128);

        vm.etch(address(0x3333), address(token0).code);
        token2 = MockERC20(address(0x3333));
        token2.mint(address(this), 2 ** 128);

        // deploy a hook that reads msgSender
        MockMsgSenderHook msgSenderHook = new MockMsgSenderHook();
        address mockMsgSenderHookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));
        vm.etch(mockMsgSenderHookAddr, address(msgSenderHook).code);

        key01Hook = createPoolKey(token0, token1, mockMsgSenderHookAddr);
        setupPool(key01Hook);
    }

    function test_fuzz_mixedQuoter_msgSender(address pranker, bool zeroForOne) public {
        IMixedSplitRouteQuoterV2.QuoteExactInputSingleV4Params memory params = IMixedSplitRouteQuoterV2
            .QuoteExactInputSingleV4Params({
            poolKey: key01Hook,
            zeroForOne: zeroForOne,
            exactAmount: 10000,
            hookData: ZERO_BYTES
        });

        vm.expectEmit(true, true, true, true);
        emit MockMsgSenderHook.BeforeSwapMsgSender(pranker);

        vm.expectEmit(true, true, true, true);
        emit MockMsgSenderHook.AfterSwapMsgSender(pranker);

        vm.prank(pranker);
        quoter.quoteExactInputSingleV4(params);
    }

    function createPoolKey(MockERC20 tokenA, MockERC20 tokenB, address hookAddr)
        internal
        pure
        returns (PoolKey memory)
    {
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)), 3000, 60, IHooks(hookAddr));
    }

    function setupPool(PoolKey memory poolKey) internal {
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        MockERC20(Currency.unwrap(poolKey.currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(poolKey.currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                MIN_TICK,
                MAX_TICK,
                calculateLiquidityFromAmounts(SQRT_PRICE_1_1, MIN_TICK, MAX_TICK, 1000000, 1000000).toInt256(),
                0
            ),
            ZERO_BYTES
        );
    }

    function calculateLiquidityFromAmounts(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
    }
}
