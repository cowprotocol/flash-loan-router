// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {Constants} from "../libraries/Constants.sol";
import {AaveBorrower} from "src/AaveBorrower.sol";
import {FlashLoanTracker} from "src/FlashLoanTracker.sol";
import {ICowSettlement} from "src/interface/ICowSettlement.sol";

/// @title Deploy FlashLoanTracker
/// @author CoW DAO developers
/// @notice A contract that deploys the flash loan tracker.
contract DeployFlashLoanTracker is Script {
    function run() public virtual {
        deployFlashLoanTracker();
    }

    function deployFlashLoanTracker() internal returns (FlashLoanTracker tracker) {
        ICowSettlement _cowSettlement = ICowSettlement(Constants.DEFAULT_SETTLEMENT_CONTRACT);

        address expectedAddress = vm.computeCreate2Address(
            Constants.SALT, keccak256(abi.encodePacked(type(FlashLoanTracker).creationCode, abi.encode(_cowSettlement)))
        );

        // Only deploy if no code exists at that address
        if (expectedAddress.code.length == 0) {
            vm.broadcast();
            tracker = new FlashLoanTracker{salt: Constants.SALT}(_cowSettlement);
            console.log("FlashLoanTracker has been deployed at:", address(tracker));
        } else {
            tracker = FlashLoanTracker(expectedAddress);
            console.log("FlashLoanTracker was already deployed at:", address(tracker));
        }
    }
}
