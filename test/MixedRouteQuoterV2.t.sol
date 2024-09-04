// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../src/MixedRouteQuoterV2.sol";
import "../src/interfaces/IMixedRouteQuoterV2.sol";
import {IPoolManager} from "lib/v4-core/src/interfaces/IPoolManager.sol";
import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "lib/v4-core/src/types/PoolKey.sol";

contract MixedRouteQuoterV2Test is Test {
    MixedRouterQuoterV2 public mixedRouterQuoterV2;
    IPoolManager public poolManager;
    address public immutable uniswapV4PoolManager = 0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6;
    address public immutable uniswapV3PoolFactory = 0x0227628f3F023bb0B980b67D528571c95c6DaC1c;
    address public immutable uniswapV2PoolFactory = 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0;

    address V4_SEPOLIA_OP_ADDRESS = 0xc268035619873d85461525F5fDb792dd95982161;
    address V4_SEPOLIA_USDC_ADDRESS = 0xbe2a7F5acecDc293Bf34445A0021f229DD2Edd49;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouterQuoterV2 = new MixedRouterQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
    }

    function test_BasicV4RouteQuote() public {
        uint24 fee = 500;
        uint24 tickSpacing = 10;
        address hooks = address(0);
        // bytes memory path = abi.encodePacked(V4_SEPOLIA_OP_ADDRESS, fee,tickSpacing, hooks, V4_SEPOLIA_USDC_ADDRESS);
        uint256 amountIn = 1000000;

        try mixedRouterQuoterV2.quoteExactInputSingleV4(IMixedRouteQuoterV2.QuoteExactInputSingleV4Params({
            poolKey: PoolKey({
                currency0: Currency.wrap(V4_SEPOLIA_USDC_ADDRESS),
                currency1: Currency.wrap(V4_SEPOLIA_OP_ADDRESS),
                fee: fee,
                tickSpacing: int24(tickSpacing),
                hooks: IHooks(hooks)
            }),
            exactAmount: amountIn,
            sqrtPriceLimitX96: 0,
            hookData: "" // TODO: figure out how to pass in hookData
        })) {
        } catch (bytes memory revertData) {
            console.logString(vm.toString(revertData));
        }
    }
}