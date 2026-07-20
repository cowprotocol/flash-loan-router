// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {Borrower} from "./mixin/Borrower.sol";
import {IBalancerFlashLoanRecipient, IBalancerVault} from "./vendored/IBalancerV3Vault.sol";
import {IERC20} from "./vendored/IERC20.sol";

contract BalancerV3Borrower is Borrower, IBalancerFlashLoanRecipient {
    address private expectedLender;

    error AlreadyBorrowing();

    constructor(IFlashLoanRouter _router) Borrower(_router) {}

    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        override
    {
        if (expectedLender != address(0)) revert AlreadyBorrowing();
        expectedLender = lender;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBalancerVault(lender).flashLoan(this, tokens, amounts, callBackData);
    }

    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external override {
        require(msg.sender == expectedLender, "BalancerV3Borrower: unexpected lender");
        require(tokens.length == 1, "BalancerV3Borrower: only single token supported");
        require(amounts.length == 1 && feeAmounts.length == 1, "BalancerV3Borrower: invalid flash loan arrays");

        expectedLender = address(0);

        flashLoanCallBack(userData);

        IERC20 token = tokens[0];
        uint256 amount = amounts[0];
        uint256 fee = feeAmounts[0];
        require(token.transfer(msg.sender, amount + fee), "BalancerV3Borrower: repayment failed");
    }
}
