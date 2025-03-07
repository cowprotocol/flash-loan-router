// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {EnvReader} from "./libraries/EnvReader.sol";
import {AaveBorrower, DeployAAVEBorrower} from "./single-deployment/DeployAAVEBorrower.s.sol";
import {DeployFlashLoanRouter, FlashLoanRouter} from "./single-deployment/DeployFlashLoanRouter.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployAllContracts is DeployFlashLoanRouter, DeployAAVEBorrower {
    function run() public override(DeployFlashLoanRouter, DeployAAVEBorrower) {
        deployAll();
    }

    function deployAll() public returns (FlashLoanRouter flashLoanRouter, AaveBorrower aaveBorrower) {
        flashLoanRouter = deployFlashLoanRouter();
        aaveBorrower = deployAAVEBorrower();

        vm.stopBroadcast();
    }
}
