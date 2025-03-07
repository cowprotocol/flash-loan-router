// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";
import {ICowSettlement} from "../../src/interface/ICowSettlement.sol";
import {EnvReader} from "../libraries/EnvReader.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployFlashLoanRouter is Script, EnvReader {
    function run() public virtual {
        deployFlashLoanRouter();
    }

    function deployFlashLoanRouter() internal returns (FlashLoanRouter router) {
        vm.startBroadcast();

        // Deploy FlashLoanRouter
        ICowSettlement cowSettlement = ICowSettlement(DEFAULT_SETTLEMENT_CONTRACT);
        router = new FlashLoanRouter{salt: SALT}(cowSettlement);
        console.log("FlashLoanRouter deployed at:", address(router));

        // Update flashLoanRouter for borrower deployments
        flashLoanRouter = address(router);

        vm.stopBroadcast();
        return router;
    }
}
