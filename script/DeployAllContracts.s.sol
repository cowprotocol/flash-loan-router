// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

import {AaveBorrower, DeployAAVEBorrower} from "./single-deployment/DeployAAVEBorrower.s.sol";

import {DeployERC3156Borrower, ERC3156Borrower} from "./single-deployment/DeployERC3156Borrower.s.sol";
import {DeployFlashLoanRouter, FlashLoanRouter} from "./single-deployment/DeployFlashLoanRouter.s.sol";

/// @title Deploy All Contracts
/// @author CoW DAO developers
/// @notice A deployment contract that deploys all contracts.
contract DeployAllContracts is DeployFlashLoanRouter, DeployAAVEBorrower, DeployERC3156Borrower {
    function run() public override(DeployFlashLoanRouter, DeployAAVEBorrower, DeployERC3156Borrower) {
        deployAll();
    }

    /// @dev Deploys both FlashLoanRouter and AaveBorrower contracts.
    /// It first deploys the FlashLoanRouter and then passes it to deployAAVEBorrower to deploy the AaveBorrower.
    /// @return flashLoanRouter The deployed FlashLoanRouter contract instance.
    /// @return aaveBorrower The deployed AaveBorrower contract instance.
    /// @return erc3156Borrower The deployed ERC3156Borrower contract instance.
    function deployAll()
        public
        returns (FlashLoanRouter flashLoanRouter, AaveBorrower aaveBorrower, ERC3156Borrower erc3156Borrower)
    {
        // Deploy FlashLoanRouter
        flashLoanRouter = deployFlashLoanRouter();

        // Deploy borrowers
        aaveBorrower = deployAAVEBorrower(flashLoanRouter);
        erc3156Borrower = deployERC3156Borrower(flashLoanRouter);
    }
}
