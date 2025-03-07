// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AaveBorrower} from "../../src/AaveBorrower.sol";
import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";
import {EnvReader} from "script/libraries/EnvReader.sol";

contract DeployAAVEBorrower is Script, EnvReader {
    function run() public virtual {
        deployAAVEBorrower();
    }

    function deployAAVEBorrower() internal returns (AaveBorrower borrower) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "Missing or invalid PRIVATE_KEY.");

        // Ensure the router address is provided
        address routerAddress = addressEnvOrDefault("FLASHLOAN_ROUTER_ADDRESS", flashLoanRouter);
        require(routerAddress != address(0), "Missing or invalid FLASHLOAN_ROUTER_ADDRESS.");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy borrower using existing router
        FlashLoanRouter router = FlashLoanRouter(routerAddress);
        borrower = new AaveBorrower{salt: SALT}(router);
        console.log("AaveBorrower deployed at:", address(borrower));

        vm.stopBroadcast();
    }
}
