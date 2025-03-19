// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

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
    * @notice The FlashLoanRouter contract address is generated using `CREATE2` 
    *         with a deterministic salt (e.g., `new FlashLoanRouter{salt: Constants.SALT}(cowSettlement)`), 
    *         and the simulation of `AaveBorrower` deployment will revert with a `CREATE2` 
    *         collision error when deploying all contracts, if there is already 
    *         an existing contract at the same address.
    *         This issue is avoided by passing the address directly as an environment 
    *         variable (`FLASHLOAN_ROUTER_ADDRESS`).
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
