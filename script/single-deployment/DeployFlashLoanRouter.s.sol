// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {FlashLoanRouter} from "src/FlashLoanRouter.sol";
import {ICowSettlement} from "src/interface/ICowSettlement.sol";

import {Constants} from "../libraries/Constants.sol";

contract DeployFlashLoanRouter is Script {
    function run() public virtual {
        deployFlashLoanRouter();
    }

    function deployFlashLoanRouter() internal returns (FlashLoanRouter router) {
        vm.startBroadcast();

        // Deploy FlashLoanRouter
        router = newFlashLoanRouter();

        vm.stopBroadcast();
    }

    function newFlashLoanRouter() internal returns (FlashLoanRouter router) {
        ICowSettlement cowSettlement = ICowSettlement(Constants.DEFAULT_SETTLEMENT_CONTRACT);
        router = new FlashLoanRouter{salt: Constants.SALT}(cowSettlement);
        console.log("FlashLoanRouter deployed at:", address(router));
    }
}
