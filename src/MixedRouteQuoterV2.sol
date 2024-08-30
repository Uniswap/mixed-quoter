// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniswapV3SwapCallback} from "../lib/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {PeripheryImmutableState} from "../lib/v3-periphery/contracts/base/PeripheryImmutableState.sol";

contract MixedRouterQuoterV2 is IUniswapV3SwapCallback, PeripheryImmutableState {
    address public immutable uniswapV2Poolfactory;

    constructor(
        address _uniswapV3Poolfactory,
        address _uniswapV2Poolfactory,
        address _WETH9
    ) PeripheryImmutableState(_uniswapV3Poolfactory, _WETH9) {
        uniswapV2Poolfactory = _uniswapV2Poolfactory;
    }
}