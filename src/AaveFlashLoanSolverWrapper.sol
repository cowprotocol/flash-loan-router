// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8;

import {ICowSettlement} from "./interface/ICowSettlement.sol";
import {FlashLoanSolverWrapper} from "./mixin/FlashLoanSolverWrapper.sol";
import {IAaveFlashLoanReceiver} from "./vendored/IAaveFlashLoanReceiver.sol";
import {IAavePool} from "./vendored/IAavePool.sol";
import {IERC20} from "./vendored/IERC20.sol";

contract AaveFlashLoanSolverWrapper is FlashLoanSolverWrapper, IAaveFlashLoanReceiver {
    constructor(ICowSettlement _settlementContract) FlashLoanSolverWrapper(_settlementContract) {}

    function triggerFlashLoan(address lender, IERC20 token, uint256 amount) internal override {
        // For documentation on the call parameters, see:
        // <https://aave.com/docs/developers/smart-contracts/pool#write-methods-flashloan-input-parameters>
        IAaveFlashLoanReceiver receiverAddress = this;
        address[] memory assets = new address[](1);
        assets[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory interestRateModes = new uint256[](1);
        // Don't open any debt, just revert if funds can't be transferred from the receiver.
        interestRateModes[0] = 0;
        // The next value is technically unused, since `interestRateMode` is 0.
        address onBehalfOf = address(this);
        bytes memory params = hex"";
        // Referral supply is currently inactive
        uint16 referralCode = 0;
        IAavePool(lender).flashLoan(
            address(receiverAddress), assets, amounts, interestRateModes, onBehalfOf, params, referralCode
        );
    }

    /// @inheritdoc IAaveFlashLoanReceiver
    function executeOperation(address[] calldata, uint256[] calldata, uint256[] calldata, address, bytes calldata)
        external
        returns (bool)
    {
        flashLoanCallback();
        return true;
    }
}
