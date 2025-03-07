// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {AaveBorrower} from "../../src/AaveBorrower.sol";
import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";

import {EnvReader} from "script/libraries/EnvReader.sol";

contract DeployAAVEBorrower is Script, EnvReader {
    function run() public virtual {
        deployAAVEBorrower(FlashLoanRouter(address(0)));
    }

    // Deploy AaveBorrower with optional router input or fallback to env
    function deployAAVEBorrower(FlashLoanRouter router) internal returns (AaveBorrower borrower) {
        // Ensure the router address is provided or fallback to the environment variable
        address routerAddress;
        
        if (address(router) != address(0)) {
            routerAddress = address(router);
        } else {
            routerAddress = vm.envAddress("FLASHLOAN_ROUTER_ADDRESS");
        }
        
        vm.startBroadcast();

        // Use the router (either provided or from env variable)
        FlashLoanRouter flashLoanRouter = FlashLoanRouter(routerAddress);
        
        borrower = new AaveBorrower{salt: SALT}(flashLoanRouter);
        console.log("AaveBorrower deployed at:", address(borrower));

        vm.stopBroadcast();
    }
}
