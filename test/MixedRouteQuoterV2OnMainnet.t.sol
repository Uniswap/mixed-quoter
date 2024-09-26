// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMixedRouteQuoterV1} from "@uniswap/swap-router-contracts/contracts/interfaces/IMixedRouteQuoterV1.sol";
import {IMixedRouteQuoterV2} from "../src/interfaces/IMixedRouteQuoterV2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract MixedRouteQuoterV2TestOnMainnet is Test {
    IMixedRouteQuoterV1 public mixedRouteQuoterV1;
    IMixedRouteQuoterV2 public mixedRouteQuoterV2;
    IPoolManager public poolManager;
    address public immutable uniswapV4PoolManager = address(0); // uniswap v4 pool manager is not deployed on mainnet as of now (Sept 6 2024)
    address public immutable uniswapV3PoolFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public immutable uniswapV2PoolFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address WTAO = 0x77E06c9eCCf2E797fd462A92B6D7642EF85b0A44;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address OPSEC = 0x6A7eFF1e2c355AD6eb91BEbB5ded49257F3FED98;

    // This is v2 pool fee bitmask used in mixed route quoter v1
    uint24 private constant flagBitmask = 8388608;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        poolManager = IPoolManager(uniswapV4PoolManager);
        mixedRouteQuoterV1 = IMixedRouteQuoterV1(0x84E44095eeBfEC7793Cd7d5b57B7e401D7f1cA2E); // We use deployed address of MixedRouteQuoterV1 on mainnet for testing
        mixedRouteQuoterV2 = new MixedRouteQuoterV2(poolManager, uniswapV3PoolFactory, uniswapV2PoolFactory);
    }

    function test_FuzzQuoteExactInput_MultiTokenPath_IncludeFOT(uint256 amountIn) public {
        // make the tests mean something (a non-small input) bc otherwise everything rounds to 0
        vm.assume(amountIn > 10000);
        vm.assume(amountIn < 10000000000000000);

        uint24 WTAO_WETH_v3Fee = 10000;

        bytes memory mixedRouteQuoterV1Path = abi.encodePacked(WTAO, WTAO_WETH_v3Fee, WETH, flagBitmask, OPSEC);

        uint256 gasBeforeQuoteMixedQuoterV1 = gasleft();
        (uint256 amountOut,,, uint256 v3SwapGasEstimate) =
            mixedRouteQuoterV1.quoteExactInput(mixedRouteQuoterV1Path, amountIn);

        uint256 gasAfterQuoteMixedQuoterV1 = gasleft();

        uint8 v3ProtocolVersion = uint8(3);
        uint8 v3FeeShift = 20;
        uint24 WTAO_WETH_encodedV3Fee = (uint24(v3ProtocolVersion) << v3FeeShift) + WTAO_WETH_v3Fee;
        uint8 WETH_OPSEC_encodedV2Fee = uint8(2) << 4;
        bytes memory mixedRouteQuoterV2Path =
            abi.encodePacked(WTAO, WTAO_WETH_encodedV3Fee, WETH, WETH_OPSEC_encodedV2Fee, OPSEC);

        IMixedRouteQuoterV2.NonEncodableData[] memory nonEncodableData = new IMixedRouteQuoterV2.NonEncodableData[](2);
        nonEncodableData[0] = (IMixedRouteQuoterV2.NonEncodableData({hookData: "0x"}));
        nonEncodableData[1] = (IMixedRouteQuoterV2.NonEncodableData({hookData: "0x"}));
        IMixedRouteQuoterV2.ExtraQuoteExactInputParams memory extraParams =
            IMixedRouteQuoterV2.ExtraQuoteExactInputParams({nonEncodableData: nonEncodableData});

        uint256 gasBeforeQuoteMixedQuoterV2 = gasleft();
        (uint256 amountOutV2, uint256 swapGasEstimateV2) =
            mixedRouteQuoterV2.quoteExactInput(mixedRouteQuoterV2Path, extraParams, amountIn);
        uint256 gasAfterQuoteMixedQuoterV2 = gasleft();

        assertEqUint(amountOut, amountOutV2);

        // Due to mixed quoter v2 having more compact protocol version + fee tier encoding for v2,
        // Overall gas cost of mixed quoter v2 should always be less than mixed quoter v1
        assertLt(swapGasEstimateV2, v3SwapGasEstimate);
        assertLt(
            gasBeforeQuoteMixedQuoterV2 - gasAfterQuoteMixedQuoterV2,
            gasBeforeQuoteMixedQuoterV1 - gasAfterQuoteMixedQuoterV1
        );
    }
}
