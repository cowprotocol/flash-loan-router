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

    /// @notice The number of loans in the input.
    /// @param loansWithSettlement The list of loans with settlement.
    /// @return Number of loans in the input.
    function loanCount(Data memory loansWithSettlement) internal pure returns (uint256) {
        return loansWithSettlement.loans.length;
    }

    /// @notice A collision-resistent identifier for the input list of loans
    /// with settlement.
    /// @param loansWithSettlement The list of loans with settlement to hash.
    /// @return A collision-resistent identifier for the input.
    function hash(Data memory loansWithSettlement) internal pure returns (bytes32) {
        return keccak256(abi.encode(loansWithSettlement));
    }

    /// @notice Store the list of loans and the settlement in a format
    /// expected by this library.
    /// @param loans List of requested loans.
    /// @param settlement ABI-encoded settlement call data.
    /// @return An encoded representation of the input parameters.
    function encode(Loan.Data[] calldata loans, bytes calldata settlement) internal pure returns (Data memory) {
        // We invert the order of the input for more efficient popping of the
        // next array element.
        Loan.Data[] memory _loans = new Loan.Data[](loans.length);
        for (uint256 i = 0; i < loans.length; i++) {
            _loans[i] = loans[loans.length - i - 1];
        }
        return Data({settlement: settlement, loans: _loans});
    }

    /// @notice Remove the next loan that is to be processed from the encoded
    /// input data and return its parameter.
    /// @dev The element are popped from the first to the last in the order they
    /// were presented *before encoding*.
    /// @param loansWithSettlement The encoded data from which to remove the
    /// next loan.
    /// @return amount The amount to be borrowed (see `Loan.Data`).
    /// @return borrower The address of the borrower contract (see `Loan.Data`).
    /// @return lender The lender address (see `Loan.Data`).
    /// @return token The token to borrow (see `Loan.Data`).
    function popLoan(Data memory loansWithSettlement)
        internal
        pure
        returns (uint256 amount, IBorrower borrower, address lender, IERC20 token)
    {
        // Note that loans are encoded in reverse order, meaning that the next
        // loan to process is the last of the encoded array.
        uint256 reducedLength = loanCount(loansWithSettlement) - 1;
        Loan.Data[] memory loans = loansWithSettlement.loans;
        amount = loans[reducedLength].amount;
        borrower = loans[reducedLength].borrower;
        lender = loans[reducedLength].lender;
        token = loans[reducedLength].token;

        // Efficiently reduce the size of the loans array.
        assembly ("memory-safe") {
            // The length of a dynamic array is stored at the first slot of the
            // array and followed by the array elements.
            //  Memory is never freed, so the remaining unused memory won't
            // affect the compiler.
            // <https://docs.soliditylang.org/en/v0.8.28/internals/layout_in_memory.html>
            mstore(loans, reducedLength)
        }
    }
}
