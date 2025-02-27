// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ICowAuthentication} from "../vendored/ICowAuthentication.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {ICowSettlement} from "./ICowSettlement.sol";

/// @title Flash-Loan Solver Wrapper Interface
/// @author CoW DAO developers
/// @notice A flash-loan solver wrapper is a solver contract for CoW Protocol
/// that calls a flash-loan lender before executing a settlement to retrieve
/// the funds needed during the settlement execution. A concrete implementation
/// generally awaits for a callback from the lender and executes the settlement
/// in that callback. This interface is implemented by all flash-loan solver
/// we implement, regardless of the concrete mechanism used by the underlying
/// lender.
interface IFlashLoanSolverWrapper {
    /// @notice The representation of a flash-loan request to the lender.
    struct LoanRequest {
        /// @notice The token that is requested in the flash loan.
        IERC20 token;
        /// @notice The amount requested from the lender.
        uint256 amount;
    }

    /// @notice Requests a flash loan with the specified parameters from the
    /// lender and, once the funds have been received, executes the settlement
    /// specified as part of the call. The flash-loan repayment is expected to
    /// take place during the settlement.
    /// @dev The repayment of a flash loan is different based on the protocol.
    /// For example, some expect to retrieve the funds from this borrower
    /// contract through `transferFrom`, while other check the lender balance is
    /// as expected after the flash loan has been processed. The executed
    /// settlement must be built to cater to the needs of the specified lender.
    /// @dev A settlement can be executed at most once in a call. The settlement
    /// data cannot change during execution. Only the settle function can be
    /// called. All of this is also the case if the lender is untrusted.
    /// @param lender The address of the flash-loan lender from which to borrow.
    /// @param loan The parameters describing the requested loan.
    /// @param callbackData The data to send back when calling the router once
    /// the loan is received.
    function flashLoanAndCallBack(
        address lender,
        LoanRequest calldata loan,
        bytes calldata callbackData
    ) external;

    /// @notice Approves the target address to spend the specified token on
    /// behalf of the flash-loan solver wrapper up to the specified amount.
    /// @dev In general, the only way to transfer funds out of this contract is
    /// through a call to this function and a subsequent call to `transferFrom`.
    /// The allowance will be preserved across different transactions.
    /// @param token The token to approve for transferring.
    /// @param target The address that will be allowed to spend the token.
    /// @param amount The amount of tokens to set as the allowance.
    function approve(IERC20 token, address target, uint256 amount) external;

    /// @notice The settlement contract that will be called when a settlement is
    /// executed after a flash loan.
    function settlementContract() external returns (ICowSettlement);
}
