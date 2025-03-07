// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DeployFlashLoanRouter, FlashLoanRouter} from "./single-deployment/DeployFlashLoanRouter.s.sol";
import {DeployAAVEBorrower, AaveBorrower} from "./single-deployment/DeployAAVEBorrower.s.sol";
import {EnvReader} from "./libraries/EnvReader.sol";

contract DeployAllContracts is DeployFlashLoanRouter, DeployAAVEBorrower {
    function run() public override(DeployFlashLoanRouter, DeployAAVEBorrower) {
        deployAll();
    }

    function deployAll() public returns(FlashLoanRouter flashLoanRouter, AaveBorrower aaveBorrower) {
        flashLoanRouter = deployFlashLoanRouter();
        aaveBorrower = deployAAVEBorrower();

        vm.stopBroadcast();
    }
}
