// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {IPoolManager} from "lib/v4-core/src/interfaces/IPoolManager.sol";
import {MixedSplitRouteQuoterV2} from "../src/MixedSplitRouteQuoterV2.sol";

contract DeployQuoter is Script {
    function setUp() public {}

    function run(address poolManager, address v3Factory, address v2Factory)
        public
        returns (MixedSplitRouteQuoterV2 state)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // forge script --broadcast --sig 'run(address, address, address)' --rpc-url <RPC_URL> --verify script/DeployQuoter.s.sol:DeployQuoter <POOL_MANAGER_ADDR> <V3_FACTORY_ADDRESS> <V2_FACTORY_ADDRESS>
        state = new MixedSplitRouteQuoterV2(IPoolManager(poolManager), v3Factory, v2Factory);
        console2.log("MixedSplitRouteQuoterV2", address(state));
        console2.log("PoolManager", address(state.poolManager()));

        vm.stopBroadcast();
    }
}
