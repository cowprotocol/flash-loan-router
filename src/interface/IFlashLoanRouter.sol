// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {LoanRequest} from "../library/LoansWithSettlement.sol";
import {ICowAuthentication} from "../vendored/ICowAuthentication.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {ICowSettlement} from "./ICowSettlement.sol";

/// @title Flash-Loan Router
interface IFlashLoanRouter {
    function flashLoanAndSettle(LoanRequest.Data[] calldata loans, bytes calldata settlement) external;

    function borrowerCallback(bytes calldata encodedLoansWithSettlement) external;

    /// @notice The settlement contract that will be called when a settlement is
    /// executed after a flash loan.
    function settlementContract() external returns (ICowSettlement);

    /// @notice The contract responsible to determine which address is an
    /// authorized solver for CoW Protocol.
    function settlementAuthentication() external returns (ICowAuthentication);
}
