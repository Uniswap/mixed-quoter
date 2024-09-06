// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IMixedRouteQuoterV1} from "@uniswap/swap-router-contracts/contracts/interfaces/IMixedRouteQuoterV1.sol";
import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";

contract MixedRouteQuoterV2TestOnMainnet is Test {
    IMixedRouteQuoterV1 public mixedRouteQuoterV1;
    IMixedRouteQuoterV2 public mixedRouteQuoterV2;
    IPoolManager public poolManager;
    address public immutable uniswapV4PoolManager = address(0); // uniswap v4 pool manager is not deployed on mainnet as of now (Sept 6 2024)
    address public immutable uniswapV3PoolFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public immutable uniswapV2PoolFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouteQuoterV1 = IMixedRouteQuoterV1(0x84E44095eeBfEC7793Cd7d5b57B7e401D7f1cA2E); // We use deployed address of MixedRouteQuoterV1 on mainnet for testing
        mixedRouteQuoterV2 = new MixedRouteQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
    }
}
