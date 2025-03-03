// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower} from "../interface/IBorrower.sol";
import {IERC20} from "../vendored/IERC20.sol";

/// @title Loan-request Library
/// @author CoW DAO developers
/// @notice A library describing a flash-loan request by the flash-loan router
/// and providing related utility functions.
library Loan {
    /// @notice The representation of a flash-loan request by the flash-loan
    /// router.
    struct Data {
        /// @notice The amount of funds requested from the lender.
        uint256 amount;
        /// @notice The contract that directly requests the flash loan from the
        /// lender and eventually calls back the router.
        IBorrower borrower;
        /// @notice The contract that loans out the funds to the borrower.
        address lender;
        /// @notice The token that is requested in the flash loan.
        IERC20 token;
    }
}
