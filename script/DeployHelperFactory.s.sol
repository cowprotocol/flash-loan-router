// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

import {OrderHelper} from "src/helper/OrderHelper.sol";
import {OrderHelperFactory} from "src/helper/OrderHelperFactory.sol";

/// @title Deploy Helper Factory
/// @author CoW DAO developers
/// @notice A deployment contract that deploys the helper and it's factory.
contract DeployHelperFactoryContracts is Script {
    function run() public {
        vm.startBroadcast();

        OrderHelper orderHelper = new OrderHelper();
        OrderHelperFactory factory = new OrderHelperFactory(address(orderHelper));

        vm.stopBroadcast();
    }
}
