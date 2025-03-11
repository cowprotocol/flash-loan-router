// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {FlashLoanRouter} from "src/FlashLoanRouter.sol";
import {ICowSettlement} from "src/interface/ICowSettlement.sol";

import {Constants} from "../libraries/Constants.sol";

/// @title Deploy FlashLoan Router
/// @author CoW DAO developers
/// @notice A contract that deploys a flash loan router contract
contract DeployFlashLoanRouter is Script {
    function run() public virtual {
        deployFlashLoanRouter();
    }

    /**
    * @dev Deploys the FlashLoanRouter contract.
    * 
    * This function deploys the `FlashLoanRouter` contract with a deterministic address 
    * using the `CREATE2` opcode.
    * The contract is initialized with a `cowSettlement` contract, which is fetched 
    * from the `Constants.DEFAULT_SETTLEMENT_CONTRACT`.
    * 
    * The deployment is done using a fixed salt (`Constants.SALT`), ensuring that 
    * the address of the `FlashLoanRouter` is deterministic.
    * The function will log the address of the newly deployed `FlashLoanRouter` 
    * contract for reference.
    * 
    * @return router The deployed `FlashLoanRouter` contract instance.
    * 
    * @notice The deployment of the `FlashLoanRouter` contract will use a fixed 
    *         salt (`Constants.SALT`), to ensure the address 
    *         of the contract is deterministic. If a contract is already deployed at the address, 
    *         this would cause a revert due to a `CREATE2` address collision.
    */
    function deployFlashLoanRouter() internal returns (FlashLoanRouter router) {
        vm.startBroadcast();

        // Deploy FlashLoanRouter
        ICowSettlement cowSettlement = ICowSettlement(Constants.DEFAULT_SETTLEMENT_CONTRACT);
        router = new FlashLoanRouter{salt: Constants.SALT}(cowSettlement);
        console.log("FlashLoanRouter deployed at:", address(router));

        vm.stopBroadcast();
    }
}
