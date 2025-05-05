// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {ERC3156Borrower} from "src/ERC3156Borrower.sol";
import {FlashLoanRouter} from "src/FlashLoanRouter.sol";

import {Constants} from "../libraries/Constants.sol";
import {Asserts} from "../libraries/Asserts.sol";

/// @title Deploy ERC3156 Borrower
/// @author CoW DAO developers
/// @notice A contract that deploys a borrower contract that adds support for
/// ERC-3156 compatible flash loan providers.
contract DeployERC3156Borrower is Script {
    /// @dev Executes the deployment of the `ERC3156Borrower` contract.
    ///
    /// This function calls the `deployERC3156Borrower` method with
    /// the `FlashLoanRouter` address from the environment variable
    /// `FLASHLOAN_ROUTER_ADDRESS`.
    function run() public virtual {
        FlashLoanRouter flashLoanRouter = FlashLoanRouter(
            vm.envAddress("FLASHLOAN_ROUTER_ADDRESS")
        );
        deployERC3156Borrower(flashLoanRouter);
    }

    /// @dev Deploys the ERC3156Borrower contract, ensuring that it is properly initialized
    /// with a valid FlashLoanRouter instance.
    /// The deployment is done using a fixed salt (`Constants.SALT`), ensuring that
    /// the address of the `ERC3156Borrower` is deterministic.
    ///
    /// - The function ensures that the FlashLoanRouter contract is properly deployed,
    ///   i.e., it has the correct settlement contract address (`Constants.DEFAULT_SETTLEMENT_CONTRACT`).
    ///
    /// - If the FlashLoanRouter contract is not deployed at the expected address or the
    ///   settlement contract is incorrect, the deployment will revert.
    ///
    /// @param flashLoanRouter The FlashLoanRouter instance.
    /// @return borrower The deployed ERC3156Borrower contract instance.
    function deployERC3156Borrower(
        FlashLoanRouter flashLoanRouter
    ) internal returns (ERC3156Borrower borrower) {
        Asserts.assertFlashLoanRouter(flashLoanRouter);

        borrower = new ERC3156Borrower{salt: Constants.SALT}(flashLoanRouter);

        // Calculate the CREATE2 address first
        address expectedAddress = vm.computeCreate2Address(
            Constants.SALT,
            keccak256(
                abi.encodePacked(
                    type(ERC3156Borrower).creationCode,
                    abi.encode(flashLoanRouter)
                )
            )
        );

        // Only deploy if no code exists at that address
        if (expectedAddress.code.length == 0) {
            vm.broadcast();
            borrower = new ERC3156Borrower{salt: Constants.SALT}(
                flashLoanRouter
            );
            console.log(
                "ERC3156Borrower has been deployed at:",
                address(borrower)
            );
        } else {
            borrower = ERC3156Borrower(expectedAddress);
            console.log(
                "ERC3156Borrower was already deployed at:",
                address(borrower)
            );
        }
    }
}
