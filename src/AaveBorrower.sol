// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {Borrower} from "./mixin/Borrower.sol";
import {IAaveFlashLoanSimpleReceiver} from "./vendored/IAaveFlashLoanSimpleReceiver.sol";
import {IAavePool} from "./vendored/IAavePool.sol";
import {IERC20} from "./vendored/IERC20.sol";

/// @title Aave Borrower
/// @author CoW DAO developers
/// @notice A borrower contract for the flash-loan router that adds support for
/// Aave protocol.
contract AaveBorrower is Borrower, IAaveFlashLoanSimpleReceiver {
    /// @param _router The router supported by this contract.
    constructor(IFlashLoanRouter _router) Borrower(_router) {}

    /// @inheritdoc Borrower
    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        override
    {
        // For documentation on the call parameters, see:
        // <https://aave.com/docs/developers/smart-contracts/pool#write-methods-flashloansimple-input-parameters>
        IAaveFlashLoanSimpleReceiver receiverAddress = this;
        address asset = address(token);
        bytes calldata params = callBackData;
        // Referral supply is currently inactive
        uint16 referralCode = 0;
        IAavePool(lender).flashLoanSimple(address(receiverAddress), asset, amount, params, referralCode);
    }

    /// @inheritdoc IAaveFlashLoanSimpleReceiver
    function executeOperation(address, uint256, uint256, address, bytes calldata callBackData)
        external
        returns (bool)
    {
        flashLoanCallBack(callBackData);
        return true;
    }
}
