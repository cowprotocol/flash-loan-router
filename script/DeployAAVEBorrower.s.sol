// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AaveBorrower} from "../src/AaveBorrower.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {ICowSettlement} from "../src/interface/ICowSettlement.sol";
import "forge-std/Script.sol";
import {EnvReader} from "script/libraries/EnvReader.sol";
import {Utils} from "script/libraries/Utils.sol";

contract DeployAAVEBorrower is Script, EnvReader, Utils {
    constructor() {
        // Initialise contracts
        settlement = addressEnvOrDefault("SETTLEMENT_CONTRACT", DEFAULT_SETTLEMENT_CONTRACT, false);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "Missing or invalid PRIVATE_KEY.");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy router
        ICowSettlement cowSettlement = ICowSettlement(settlement);
        FlashLoanRouter router = new FlashLoanRouter{salt: SALT}(cowSettlement);
        console.log("FlashLoanRouter deployed at:", address(router));

        // Deploy borrower
        AaveBorrower borrower = new AaveBorrower{salt: SALT}(router);
        console.log("AaveBorrower deployed at:", address(borrower));
        
        vm.stopBroadcast();
    }
}
