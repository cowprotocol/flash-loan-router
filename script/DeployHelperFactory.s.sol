// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {OrderHelper} from "src/helper/OrderHelper.sol";
import {OrderHelperFactory} from "src/helper/OrderHelperFactory.sol";

/// @title Deploy Helper Factory
/// @author CoW DAO developers
/// @notice A deployment contract that deploys the helper and it's factory.
contract DeployHelperFactoryContracts is Script {
    address public constant GNOSIS_AAVE_LENDING_POOL = 0xb50201558B00496A145fE76f7424749556E326D8;
    address public constant MAINNET_AAVE_LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    function run() public {
        vm.startBroadcast();
        address _aaveLendingPool = block.chainid == 1 ? MAINNET_AAVE_LENDING_POOL : GNOSIS_AAVE_LENDING_POOL;

        OrderHelper _orderHelper = new OrderHelper();
        OrderHelperFactory _factory = new OrderHelperFactory(address(_orderHelper), _aaveLendingPool);

        vm.stopBroadcast();

        console.log("OrderHelper implementation deployed at:", address(_orderHelper));
        console.log("OrderHelperFactory deployed at:", address(_factory));
    }
}
