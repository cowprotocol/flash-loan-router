// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {AaveBorrower} from "../../src/AaveBorrower.sol";

import {DeployFlashLoanRouter, FlashLoanRouter} from "./DeployFlashLoanRouter.s.sol";

import {Constants} from "script/libraries/Constants.sol";

contract DeployAAVEBorrower is Script, DeployFlashLoanRouter {
    function run() public virtual override(DeployFlashLoanRouter) {
        deployAAVEBorrower(FlashLoanRouter(address(0)));
    }

    function deployAAVEBorrower(FlashLoanRouter router) internal returns (AaveBorrower borrower) {
        address routerAddress = address(router) != address(0) ? address(router) : address(newFlashLoanRouter());

        vm.startBroadcast();

        FlashLoanRouter flashLoanRouter = FlashLoanRouter(routerAddress);
        require(address(flashLoanRouter.settlementContract()) == Constants.DEFAULT_SETTLEMENT_CONTRACT, "Settlement contract varies in flashLoanRouter");

        borrower = new AaveBorrower{salt: Constants.SALT}(flashLoanRouter);
        console.log("AaveBorrower deployed at:", address(borrower));

        vm.stopBroadcast();
    }
}
