// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {Utils} from "script/libraries/Utils.sol";
import {EnvReader} from "script/libraries/EnvReader.sol";
import { ICowSettlement } from "../src/interface/ICowSettlement.sol";
import { IBorrower } from "../src/interface/IBorrower.sol";
import { FlashLoanRouter } from "../src/FlashLoanRouter.sol";
import { AaveBorrower } from "../src/AaveBorrower.sol";

contract DeployAAVEBorrower is Script, EnvReader, Utils {
    constructor() {
        // Initialise contracts
        settlement = addressEnvOrDefault("SETTLEMENT_CONTRACT", DEFAULT_SETTLEMENT_CONTRACT);
        console.log("Settlement contract at %s.", settlement);
        require(settlement != address(0), "Invalid settlement contract address.");
        assertHasCode(settlement, "no code at expected settlement contract");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "Missing or invalid PRIVATE_KEY.");

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy router
        ICowSettlement cowSettlement = ICowSettlement(settlement);
        FlashLoanRouter router = new FlashLoanRouter(cowSettlement);
        console.log("FlashLoanRouter deployed at:", address(router));
        
        // Deploy borrower
        AaveBorrower aaveBorrower = new AaveBorrower(router);
        console.log("AaveBorrower deployed at:", address(aaveBorrower));
        
        IBorrower borrower = IBorrower(aaveBorrower);
        require(borrower.settlementContract() == cowSettlement, "Settlement contract incorrectly set");
        require(borrower.router() == router, "Router contract incorrectly set");

        vm.stopBroadcast();
    }
}
