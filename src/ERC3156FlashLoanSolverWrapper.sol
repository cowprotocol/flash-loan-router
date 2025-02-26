// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8;

import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {FlashLoanSolverWrapper} from "./mixin/FlashLoanSolverWrapper.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {IERC3156FlashBorrower} from "./vendored/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "./vendored/IERC3156FlashLender.sol";

contract ERC3156FlashLoanSolverWrapper is FlashLoanSolverWrapper, IERC3156FlashBorrower {
    /// @notice ERC 3156 requires flash loan lenders to return this value if
    /// execution was successful.
    bytes32 private constant ERC3156_ONFLASHLOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(IFlashLoanRouter _router) FlashLoanSolverWrapper(_router) {}

    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes memory callbackData)
        internal
        override
    {
        bool success = IERC3156FlashLender(lender).flashLoan(this, address(token), amount, callbackData);
        require(success, "Flash loan was unsuccessful");
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(address, address, uint256, uint256, bytes calldata callbackData) external returns (bytes32) {
        flashLoanCallback(callbackData);
        return ERC3156_ONFLASHLOAN_SUCCESS;
    }
}
