// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {IPoolManager} from "lib/v4-core/src/interfaces/IPoolManager.sol";
import {MixedRouteQuoterV2} from "../src/MixedRouteQuoterV2.sol";

contract DeployQuoter is Script {
    function setUp() public {}

    function run(address poolManager, address v3Factory, address v2Factory) public returns (MixedRouteQuoterV2 state) {
        vm.startBroadcast();

        // forge script --broadcast --sig 'run(address, address, address)' --rpc-url <RPC_URL> --private-key <PRIV_KEY> --verify script/DeployQuoter.s.sol:DeployQuoter <POOL_MANAGER_ADDR> <V3_FACTORY_ADDRESS> <V2_FACTORY_ADDRESS>
        state = new MixedRouteQuoterV2(IPoolManager(poolManager), v3Factory, v2Factory);
        console2.log("MixedRouteQuoterV2", address(state));
        console2.log("PoolManager", address(state.poolManager()));

        vm.stopBroadcast();
    }
}
