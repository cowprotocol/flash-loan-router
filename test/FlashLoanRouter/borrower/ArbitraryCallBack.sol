// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20, IFlashLoanRouter} from "src/interface/IFlashLoanRouter.sol";

import {NoOpBorrower} from "./NoOp.sol";

/// @dev A minimal borrower contract that ignores all input values and returns
/// some fixed call data that can been set with another call.
contract ArbitraryCallBackBorrower is NoOpBorrower {
    bytes callBackData;

    constructor(IFlashLoanRouter _router) NoOpBorrower(_router) {}

    function setCallBack(bytes calldata _callBackData) external {
        callBackData = _callBackData;
    }

    function flashLoanAndCallBack(address, IERC20, uint256, bytes calldata) external override {
        router.borrowerCallBack(callBackData);
    }
}
