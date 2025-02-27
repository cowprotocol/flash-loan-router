// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanSolverWrapper} from "../interface/IFlashLoanSolverWrapper.sol";
import {IERC20} from "../vendored/IERC20.sol";

library BytesUtil {
    uint256 private constant BYTES_CONTENT_OFFSET = 32;

    function memoryPointerToArray(bytes memory array) internal pure returns (uint256 ref) {
        assembly ("memory-safe") {
            // The fist word is the overall length of the memory vector, the
            // second is the start of the content.
            ref := array
        }
    }

    function memoryPointerToContent(bytes memory array) internal pure returns (uint256 ref) {
        // Arrays allocated by Solidity cannot cause an overflow, since a
        // transaction would run out of gas long before reaching the length
        // needed for an overflow. Arrays that were manually allocated through
        // assembly may cause an overflow, but any attempt to read or write to
        // them would cause an out-of-gas revert.
        unchecked {
            ref = memoryPointerToArray(array) + BYTES_CONTENT_OFFSET;
        }
    }
}

library LoanRequest {
    struct Data {
        /// @notice The amount requested from the lender.
        uint256 amount;
        IFlashLoanSolverWrapper borrower;
        address lender;
        /// @notice The token that is requested in the flash loan.
        IERC20 token;
    }

    // Pointer to data in memory.
    // We'd rather use the bytes vector directly, but this is currently not
    // supported by the Solidity compiler.
    type EncodedData is uint256;

    // Encoding:
    // Length:  |  32 bytes  ||   20 bytes   ||  20 bytes  ||  20 bytes  |
    // Content: |-- amount --||-- borrower --||-- lender --||-- token  --|

    // note: -12 because addresses are zero-padded to the left and mload/mstore
    // work on groups of 32 bytes.
    uint256 private constant OFFSET_BORROWER = 32 - 12;
    uint256 private constant OFFSET_LENDER = 32 + 1 * 20 - 12;
    uint256 private constant OFFSET_TOKEN = 32 + 2 * 20 - 12;
    uint256 internal constant ENCODED_LOAN_REQUEST_BYTE_SIZE = 32 + 3 * 20;

    function store(EncodedData encodedLoanRequest, Data calldata loanRequest) internal pure {
        uint256 amount = loanRequest.amount;
        IFlashLoanSolverWrapper borrower = loanRequest.borrower;
        address lender = loanRequest.lender;
        IERC20 token = loanRequest.token;

        assembly ("memory-safe") {
            // Note: addresses are right-aligned, memory is written to starting
            // from the end and overwriting the address left-side padding.
            mstore(add(encodedLoanRequest, OFFSET_TOKEN), token)
            mstore(add(encodedLoanRequest, OFFSET_LENDER), lender)
            mstore(add(encodedLoanRequest, OFFSET_BORROWER), borrower)
            // offset is zero
            mstore(encodedLoanRequest, amount)
        }
    }

    function decode(EncodedData loanRequest) internal pure returns (Data memory) {
        uint256 amount;
        IFlashLoanSolverWrapper borrower;
        address lender;
        IERC20 token;

        assembly ("memory-safe") {
            // note: values don't need to be masked since masking occurs when
            // the value is accessed and not stored
            amount := mload(loanRequest)
            borrower := mload(add(loanRequest, OFFSET_BORROWER))
            lender := mload(add(loanRequest, OFFSET_LENDER))
            token := mload(add(loanRequest, OFFSET_TOKEN))
        }

        return LoanRequest.Data({borrower: borrower, lender: lender, token: token, amount: amount});
    }
}

library LoansWithSettlement {
    using LoanRequest for LoanRequest.Data;
    using LoanRequest for LoanRequest.EncodedData;
    using BytesUtil for bytes;

    struct Data {
        bytes settlement;
        LoanRequest.Data[] loans;
    }

    uint256 private constant LOAN_COUNT_SIZE = 32;

    function loansCount(Data memory loansWithSettlement) internal pure returns (uint256) {
        return loansWithSettlement.loans.length;
    }

    // Note: this function assumes the loan count is at least one
    function popLoanRequest(Data memory loansWithSettlement) internal pure returns (LoanRequest.Data memory loan) {
        uint256 reducedLength = loansWithSettlement.loans.length - 1;
        LoanRequest.Data[] memory loans = loansWithSettlement.loans;
        loan = loans[reducedLength];

        assembly ("memory-safe") {
            // update array length
            mstore(loans, reducedLength)
        }
    }

    function encodeLoansWithSettlement(LoanRequest.Data[] calldata loanRequests, bytes calldata settlement)
        internal
        pure
        returns (Data memory)
    {
        return Data({settlement: settlement, loans: loanRequests});
    }

    function destroyAndExtractSettlement(Data memory loansWithSettlement)
        internal
        pure
        returns (bytes memory settlement)
    {
        return loansWithSettlement.settlement;
    }
}
