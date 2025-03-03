// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower} from "../interface/IBorrower.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {Loan} from "./Loan.sol";

/// @title Loans-with-settlement Library
/// @author CoW DAO developers
/// @notice A library describing a settlement through the flash-loan router and
/// providing related utility functions.
library LoansWithSettlement {
    /// @notice A list of loans to request plus the settlement to be executed
    /// once all funds have been lent.
    struct Data {
        /// @notice List of loans to request, in **reverse** order of execution.
        Loan.Data[] loans;
        /// @notice The (ABI-encoded) settlement to be executed once the
        /// funds from all loans have been made available.
        bytes settlement;
    }
}
