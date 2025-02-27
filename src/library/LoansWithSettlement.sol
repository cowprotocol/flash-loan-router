// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanSolverWrapper} from "../interface/IFlashLoanSolverWrapper.sol";
import {IERC20} from "../vendored/IERC20.sol";

library BytesUtil {
    uint256 private constant BYTES_CONTENT_OFFSET = 32;

    /// @dev Allocate a bytes array in memory with arbitrary data in it.
    /// This is cheaper than `new bytes(length)` because it doesn't zero the
    /// content of the array. It is supposed to be used when the newly allocated
    /// memory will be fully overwritten at a later step.
    function allocate(uint256 length) internal pure returns (bytes memory array) {
        // https://docs.soliditylang.org/en/v0.8.26/internals/layout_in_memory.html
        assembly ("memory-safe") {
            array := mload(0x40)
            mstore(array, length)
            mstore(0x40, add(add(array, BYTES_CONTENT_OFFSET), length))
        }
    }

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

    uint256 private constant LOAN_COUNT_SIZE = 32;

    // Expected encoding:
    // Length:  |        32 bytes        ||       arbitrary size       ||  size(LoanRequest)   ||    size(LoanRequest)     |...|  size(LoanRequest)   |
    // Content: |-- number of loans, n --||-- ABI-encoded settlement --||-- n-th LoanRequest --||-- (n-1)-th LoanRequest --|...|-- 1-st LoanRequest --|
    //
    // Loans are stored right to left so that it's easy to pop them in order
    // without having to shift all remaining loans in memory.

    function loansCount(bytes memory loansWithSettlement) internal pure returns (uint256 count) {
        uint256 pointer = loansWithSettlement.memoryPointerToContent();
        assembly ("memory-safe") {
            count := mload(pointer)
        }
    }

    // Note: this function assumes the loan count is at least one
    function popLoanRequest(bytes memory loansWithSettlement) internal pure returns (LoanRequest.Data memory) {
        // Note: memory is never overridden
        // Todo: unchecked?
        uint256 updatedLoansCount = loansCount(loansWithSettlement) - 1;
        uint256 updatedLoansWithSettlementLength =
            loansWithSettlement.length - LoanRequest.ENCODED_LOAN_REQUEST_BYTE_SIZE;
        uint256 loanRequestCountPointer = loansWithSettlement.memoryPointerToContent();
        LoanRequest.EncodedData encodedLoanRequest =
            LoanRequest.EncodedData.wrap(loanRequestCountPointer + updatedLoansWithSettlementLength);

        assembly ("memory-safe") {
            // update array length
            mstore(loansWithSettlement, updatedLoansWithSettlementLength)
            // update loan request count
            mstore(loanRequestCountPointer, updatedLoansCount)
        }

        return encodedLoanRequest.decode();
    }

    function encodeLoansWithSettlement(LoanRequest.Data[] calldata loanRequests, bytes calldata settlement)
        internal
        pure
        returns (bytes memory encodedLoansWithSettlement)
    {
        // todo: unchecked
        encodedLoansWithSettlement = BytesUtil.allocate(
            LOAN_COUNT_SIZE + settlement.length + loanRequests.length * LoanRequest.ENCODED_LOAN_REQUEST_BYTE_SIZE
        );

        // Keep track of the fist yet-unwritten-to byte
        uint256 head = encodedLoansWithSettlement.memoryPointerToContent();
        assembly ("memory-safe") {
            mstore(head, loanRequests.length)
        }

        head += LOAN_COUNT_SIZE;
        assembly ("memory-safe") {
            calldatacopy(head, settlement.offset, settlement.length)
        }

        head += settlement.length;
        for (uint256 i = loanRequests.length; i > 0;) {
            i--;
            LoanRequest.EncodedData encodedLoanRequest = LoanRequest.EncodedData.wrap(head);
            encodedLoanRequest.store(loanRequests[i]);
            head += LoanRequest.ENCODED_LOAN_REQUEST_BYTE_SIZE;
        }
    }

    function destroyAndExtractSettlement(bytes memory loansWithSettlement)
        internal
        pure
        returns (bytes memory settlement)
    {
        // We assume that the input is loans with a settlement, encoded as
        // expected by this library. The settlement data is a subarray of the
        // input: if we accept to override the input data with arbitrary value,
        // we can carve out a valid ABI-encoded bytes array representing the
        // settlement.
        uint256 settlementLength = loansWithSettlement.length - LOAN_COUNT_SIZE
            - loansCount(loansWithSettlement) * LoanRequest.ENCODED_LOAN_REQUEST_BYTE_SIZE;
        // We rely on the fact that LOAN_COUNT_SIZE is 32, exactly the size
        // needed to store the length of a memory array.
        uint256 settlementOffset = loansWithSettlement.memoryPointerToContent();

        assembly ("memory-safe") {
            mstore(settlementOffset, settlementLength)
            settlement := settlementOffset
        }
    }

    function settlementHash(bytes memory loansWithSettlement) internal pure returns (bytes32 hash) {
        // We assume that the input is loans with a settlement, encoded as
        // expected by this library. The settlement data is a subarray of the
        // input: if we accept to override the input data with arbitrary value,
        // we can carve out a valid ABI-encoded bytes array representing the
        // settlement.
        uint256 settlementLength = loansWithSettlement.length - LOAN_COUNT_SIZE
            - loansCount(loansWithSettlement) * LoanRequest.ENCODED_LOAN_REQUEST_BYTE_SIZE;
        // We rely on the fact that LOAN_COUNT_SIZE is 32, exactly the size
        // needed to store the length of a memory array.
        uint256 settlementOffset = loansWithSettlement.memoryPointerToContent();

        assembly ("memory-safe") {
            hash := keccak256(add(settlementOffset, LOAN_COUNT_SIZE), settlementLength)
        }
    }
}
