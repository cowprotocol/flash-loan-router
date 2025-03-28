// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {AaveBorrower} from "src/AaveBorrower.sol";
import {FlashLoanRouter} from "src/FlashLoanRouter.sol";

import {Constants} from "../libraries/Constants.sol";

/// @title Deploy Aave Borrower
/// @author CoW DAO developers
/// @notice A contract that deploys a borrower contract that adds support for
/// Aave protocol.
contract DeployAAVEBorrower is Script {
    /// @dev Executes the deployment of the `AaveBorrower` contract.
    ///
    /// This function calls the `deployAAVEBorrower` method with
    /// the `FlashLoanRouter` address from the environment variable
    /// `FLASHLOAN_ROUTER_ADDRESS`.
    function run() public virtual {
        FlashLoanRouter flashLoanRouter = FlashLoanRouter(vm.envAddress("FLASHLOAN_ROUTER_ADDRESS"));
        deployAAVEBorrower(flashLoanRouter);
    }

    /// @dev Deploys the AaveBorrower contract, ensuring that it is properly initialized
    /// with a valid FlashLoanRouter instance.
    /// The deployment is done using a fixed salt (`Constants.SALT`), ensuring that
    /// the address of the `AaveBorrower` is deterministic.
    ///
    /// - The function ensures that the FlashLoanRouter contract is properly deployed,
    ///   i.e., it has the correct settlement contract address (`Constants.DEFAULT_SETTLEMENT_CONTRACT`).
    ///
    /// - If the FlashLoanRouter contract is not deployed at the expected address or the
    ///   settlement contract is incorrect, the deployment will revert.
    ///
    /// @param flashLoanRouter The FlashLoanRouter instance.
    /// @return borrower The deployed AaveBorrower contract instance.
    function deployAAVEBorrower(FlashLoanRouter flashLoanRouter) internal returns (AaveBorrower borrower) {
        require(
            address(flashLoanRouter.settlementContract()) == Constants.DEFAULT_SETTLEMENT_CONTRACT,
            "Settlement contract varies in flashLoanRouter"
        );

        vm.broadcast();
        borrower = new AaveBorrower{salt: Constants.SALT}(flashLoanRouter);

        console.log("AaveBorrower deployed at:", address(borrower));
    }
}
