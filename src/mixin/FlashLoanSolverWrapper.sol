// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8;

import {ICowSettlement} from "../interface/ICowSettlement.sol";
import {IFlashLoanRouter} from "../interface/IFlashLoanRouter.sol";
import {IFlashLoanSolverWrapper} from "../interface/IFlashLoanSolverWrapper.sol";
import {ICowAuthentication} from "../vendored/ICowAuthentication.sol";
import {IERC20} from "../vendored/IERC20.sol";

abstract contract FlashLoanSolverWrapper is IFlashLoanSolverWrapper {
    bytes32 constant NO_DATA = bytes32(0);

    IFlashLoanRouter public immutable router;
    /// @inheritdoc IFlashLoanSolverWrapper
    ICowSettlement public immutable settlementContract;

    bytes32 internal transient callbackDataHash;

    modifier onlySettlementContract() {
        require(msg.sender == address(settlementContract), "Only callable in a settlement");
        _;
    }

    modifier onlyRouter() {
        require(msg.sender == address(router), "Only callable in a settlement");
        _;
    }

    constructor(IFlashLoanRouter _router) {
        router = _router;
        settlementContract = _router.settlementContract();
    }

    /// @inheritdoc IFlashLoanSolverWrapper
    function flashLoanAndCallBack(
        address lender,
        LoanRequest calldata loan,
        bytes32 _callbackDataHash,
        bytes calldata callbackData
    ) external onlyRouter {
        require(callbackDataHash == NO_DATA, "Pending callback");
        callbackDataHash = _callbackDataHash;
        triggerFlashLoan(lender, loan.token, loan.amount, callbackData);
        // We clear the callback hash in case `onFlashLoan` wasn't called by
        // the lender contract.
        callbackDataHash = NO_DATA;
    }

    /// @inheritdoc IFlashLoanSolverWrapper
    function approve(IERC20 token, address target, uint256 amount) external onlySettlementContract {
        // Todo: safeApprove alternative
        require(token.approve(target, amount), "Approval failed");
    }

    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes memory callbackData)
        internal
        virtual;

    function flashLoanCallback(bytes memory callbackData) internal {
        require(keccak256(callbackData) == callbackDataHash, "Callback data hash not matching");
        callbackDataHash = NO_DATA;
        router.borrowerCallback(callbackData);
    }
}
