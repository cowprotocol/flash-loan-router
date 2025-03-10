// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {AaveBorrower} from "../../src/AaveBorrower.sol";
import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";

import {Constants} from "script/libraries/Constants.sol";
import {AddressUtils} from "script/libraries/AddressUtils.sol";

contract DeployAAVEBorrower is Script {
    using AddressUtils for address;

    function run() public virtual {
        deployAAVEBorrower(FlashLoanRouter(address(0)));
    }

    function deployAAVEBorrower(FlashLoanRouter router) internal returns (AaveBorrower borrower) {
        address routerAddress;

        address predictedRouterAddress =
            Constants.DETERMINISTIC_DEPLOYER.computeCreate2Address(Constants.SALT, type(FlashLoanRouter).creationCode);

        if (address(router) != address(0)) {
            routerAddress = address(router);
        } else if (predictedRouterAddress.isContract()) {
            routerAddress = predictedRouterAddress;
        }

        vm.startBroadcast();

        FlashLoanRouter flashLoanRouter = FlashLoanRouter(routerAddress);
        require(address(flashLoanRouter.settlementContract()) == Constants.DEFAULT_SETTLEMENT_CONTRACT, "Settlement contract varies in flashLoanRouter");

        borrower = new AaveBorrower{salt: Constants.SALT}(flashLoanRouter);
        console.log("AaveBorrower deployed at:", address(borrower));

        vm.stopBroadcast();
    }
}
