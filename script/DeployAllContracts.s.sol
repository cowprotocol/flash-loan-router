// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

import {AaveBorrower, DeployAAVEBorrower} from "./single-deployment/DeployAAVEBorrower.s.sol";
import {DeployFlashLoanRouter, FlashLoanRouter} from "./single-deployment/DeployFlashLoanRouter.s.sol";

/// @title Deploy All Contracts
/// @author CoW DAO developers
/// @notice A deployment contract that deploys both
/// `FlashLoanRouter` and `AaveBorrower` contracts.
contract DeployAllContracts is DeployFlashLoanRouter, DeployAAVEBorrower {
    function run() public override(DeployFlashLoanRouter, DeployAAVEBorrower) {
        deployAll();
    }

    /// @dev Deploys both FlashLoanRouter and AaveBorrower contracts.
    /// It first deploys the FlashLoanRouter and then passes it to deployAAVEBorrower to deploy the AaveBorrower.
    /// @return flashLoanRouter The deployed FlashLoanRouter contract instance.
    /// @return aaveBorrower The deployed AaveBorrower contract instance.
    function deployAll() public returns (FlashLoanRouter flashLoanRouter, AaveBorrower aaveBorrower) {
        flashLoanRouter = deployFlashLoanRouter();
        aaveBorrower = deployAAVEBorrower(flashLoanRouter);
    }
}
