// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {
    BytesUtil,
    IERC20,
    IFlashLoanSolverWrapper,
    LoanRequest,
    LoansWithSettlement
} from "src/library/LoansWithSettlement.sol";

import {BytesUtils as TestBytesUtils} from "test/test-lib/BytesUtils.sol";

contract RoundTripEncoder {
    using BytesUtil for bytes;
    using LoanRequest for LoanRequest.EncodedData;

    function allocateToBytes() private pure returns (bytes memory) {
        return new bytes(LoanRequest.ENCODED_LOAN_REQUEST_BYTE_SIZE);
    }

    function allocate() private pure returns (LoanRequest.EncodedData) {
        bytes memory encodedData = allocateToBytes();
        return LoanRequest.EncodedData.wrap(encodedData.memoryPointerToContent());
    }

    function encode(LoanRequest.Data calldata loanRequest) public pure returns (bytes memory encodedData) {
        encodedData = allocateToBytes();
        LoanRequest.EncodedData.wrap(encodedData.memoryPointerToContent()).store(loanRequest);
    }

    function storeAndDecode(LoanRequest.Data calldata loanRequest) external pure returns (LoanRequest.Data memory) {
        LoanRequest.EncodedData encodedLoanRequest = allocate();
        encodedLoanRequest.store(loanRequest);
        return encodedLoanRequest.decode();
    }
}

function someLoanRequest(uint256 salt) pure returns (LoanRequest.Data memory) {
    return LoanRequest.Data({
        amount: uint256(keccak256(bytes.concat("any large number", bytes32(salt)))),
        borrower: IFlashLoanSolverWrapper(address(uint160(bytes20(keccak256("some borrower address"))))),
        lender: address(uint160(bytes20(keccak256("some lender address")))),
        token: IERC20(address(uint160(bytes20(keccak256("some token address")))))
    });
}

contract LoanRequestTest is Test {
    RoundTripEncoder roundTripEncoder;

    function setUp() external {
        roundTripEncoder = new RoundTripEncoder();
    }

    function assertEq(LoanRequest.Data memory lhs, LoanRequest.Data memory rhs) internal pure {
        assertEq(lhs.amount, rhs.amount);
        assertEq(address(lhs.borrower), address(rhs.borrower));
        assertEq(address(lhs.lender), address(rhs.lender));
        assertEq(address(lhs.token), address(rhs.token));
    }

    function test_encodeToExpectedBytestring() external view {
        LoanRequest.Data memory loan = LoanRequest.Data({
            amount: 0x0101010101010101010101010101010101010101010101010101010101010101, // 32 bytes
            borrower: IFlashLoanSolverWrapper(0x0202020202020202020202020202020202020202),
            lender: address(0x0303030303030303030303030303030303030303),
            token: IERC20(address(0x0404040404040404040404040404040404040404))
        });
        bytes memory expectedEncodedBytestring = bytes.concat(
            hex"0101010101010101010101010101010101010101010101010101010101010101",
            hex"0202020202020202020202020202020202020202",
            hex"0303030303030303030303030303030303030303",
            hex"0404040404040404040404040404040404040404"
        );
        assertEq(roundTripEncoder.encode(loan), expectedEncodedBytestring);
    }

    function test_encodeRoundtrip() external view {
        LoanRequest.Data memory data = someLoanRequest(0);
        assertEq(data, roundTripEncoder.storeAndDecode(data));
    }

    function testFuzz_encodeRoundtrip(uint256 amount, address solver, address lender, address token) external view {
        LoanRequest.Data memory data = LoanRequest.Data({
            amount: amount,
            borrower: IFlashLoanSolverWrapper(solver),
            lender: lender,
            token: IERC20(token)
        });
        assertEq(data, roundTripEncoder.storeAndDecode(data));
    }
}

contract LoanWithSettlementEncoder {
    using BytesUtil for bytes;
    using LoansWithSettlement for bytes;
    using LoanRequest for LoanRequest.EncodedData;

    function encode(LoanRequest.Data[] calldata loanRequests, bytes calldata settlement)
        external
        pure
        returns (bytes memory)
    {
        return LoansWithSettlement.encodeLoansWithSettlement(loanRequests, settlement);
    }

    function encodeAndCountLoanRequests(LoanRequest.Data[] calldata loanRequests, bytes calldata settlement)
        external
        pure
        returns (uint256)
    {
        bytes memory encodedLoansWithSettlement =
            LoansWithSettlement.encodeLoansWithSettlement(loanRequests, settlement);
        return encodedLoansWithSettlement.loansCount();
    }

    function encodeAndPopLoanRequest(LoanRequest.Data[] calldata loanRequests, bytes calldata settlement)
        external
        pure
        returns (LoanRequest.Data memory loanRequest)
    {
        bytes memory encodedLoansWithSettlement =
            LoansWithSettlement.encodeLoansWithSettlement(loanRequests, settlement);
        loanRequest = encodedLoansWithSettlement.popLoanRequest();
        require(
            encodedLoansWithSettlement.loansCount() == loanRequests.length - 1, "popped length does not decrease by one"
        );
    }

    function encodeAndExtractSettlement(LoanRequest.Data[] calldata loanRequests, bytes calldata settlement)
        external
        pure
        returns (bytes memory)
    {
        bytes memory encodedLoansWithSettlement =
            LoansWithSettlement.encodeLoansWithSettlement(loanRequests, settlement);
        return encodedLoansWithSettlement.destroyAndExtractSettlement();
    }

    function popLoanRequest(bytes memory encodedLoansWithSettlement)
        external
        pure
        returns (bytes memory, LoanRequest.Data memory)
    {
        LoanRequest.Data memory loanRequest = encodedLoansWithSettlement.popLoanRequest();
        return (encodedLoansWithSettlement, loanRequest);
    }

    function extractSettlement(bytes memory encodedLoansWithSettlement) external pure returns (bytes memory) {
        return encodedLoansWithSettlement.destroyAndExtractSettlement();
    }
}

contract LoansWithSettlementTest is Test {
    using LoansWithSettlement for bytes;

    LoanWithSettlementEncoder loanWithSettlementEncoder;

    function setUp() external {
        loanWithSettlementEncoder = new LoanWithSettlementEncoder();
    }

    function assertEq(LoanRequest.Data memory lhs, LoanRequest.Data memory rhs, string memory extraString)
        internal
        pure
    {
        if (bytes(extraString).length > 0) {
            extraString = string.concat(", ", extraString);
        }
        assertEq(lhs.amount, rhs.amount, string.concat("amount not matching", extraString));
        assertEq(address(lhs.borrower), address(rhs.borrower), string.concat("solver not matching", extraString));
        assertEq(address(lhs.lender), address(rhs.lender), string.concat("lender not matching", extraString));
        assertEq(address(lhs.token), address(rhs.token), string.concat("token not matching", extraString));
    }

    function assertEq(LoanRequest.Data memory lhs, LoanRequest.Data memory rhs) internal pure {
        assertEq(lhs, rhs, "");
    }

    function test_encodedBytestringMatches() external view {
        LoanRequest.Data[] memory loans = new LoanRequest.Data[](2);
        loans[0] = LoanRequest.Data({
            amount: 0x0101010101010101010101010101010101010101010101010101010101010101, // 32 bytes
            borrower: IFlashLoanSolverWrapper(0x0202020202020202020202020202020202020202),
            lender: address(0x0303030303030303030303030303030303030303),
            token: IERC20(address(0x0404040404040404040404040404040404040404))
        });
        loans[1] = LoanRequest.Data({
            amount: 0x1111111111111111111111111111111111111111111111111111111111111111, // 32 bytes
            borrower: IFlashLoanSolverWrapper(0x1212121212121212121212121212121212121212),
            lender: address(0x1313131313131313131313131313131313131313),
            token: IERC20(address(0x1414141414141414141414141414141414141414))
        });
        bytes memory settlement =
            hex"2021222324252627282920212223242526272829202122232425262728292021222324252627282920212223242526272829"; // 50 bytes

        bytes memory expectedEncodedBytestring = bytes.concat(
            hex"0000000000000000000000000000000000000000000000000000000000000002", // loan length, 32 bytes
            // settlement
            hex"2021222324252627282920212223242526272829202122232425262728292021222324252627282920212223242526272829",
            // second loan
            hex"1111111111111111111111111111111111111111111111111111111111111111",
            hex"1212121212121212121212121212121212121212",
            hex"1313131313131313131313131313131313131313",
            hex"1414141414141414141414141414141414141414",
            // first loan
            hex"0101010101010101010101010101010101010101010101010101010101010101",
            hex"0202020202020202020202020202020202020202",
            hex"0303030303030303030303030303030303030303",
            hex"0404040404040404040404040404040404040404"
        );

        bytes memory encodedBytestring = loanWithSettlementEncoder.encode(loans, settlement);
        assertEq(encodedBytestring, expectedEncodedBytestring);
    }

    function test_encodedDataHasExpectedLoanCount() external view {
        uint256 expectedLoanCount = 10;
        LoanRequest.Data[] memory loans = new LoanRequest.Data[](expectedLoanCount);
        bytes memory settlement = new bytes(42);
        uint256 loanCount = loanWithSettlementEncoder.encodeAndCountLoanRequests(loans, settlement);
        assertEq(loanCount, expectedLoanCount);
    }

    function test_encodedDataPopsExpectedLoan() external view {
        uint256 expectedLoanCount = 1;
        LoanRequest.Data[] memory loans = new LoanRequest.Data[](expectedLoanCount);
        LoanRequest.Data memory expectedLoan = someLoanRequest(0);
        loans[0] = expectedLoan;
        bytes memory settlement = new bytes(42);
        LoanRequest.Data memory loanRequest = loanWithSettlementEncoder.encodeAndPopLoanRequest(loans, settlement);
        assertEq(expectedLoan, loanRequest);
    }

    function test_encodedDataReturnsSettlement() external view {
        uint256 expectedLoanCount = 1;
        LoanRequest.Data[] memory loans = new LoanRequest.Data[](expectedLoanCount);
        bytes memory expectedSettlement = new bytes(42);
        bytes memory settlement = loanWithSettlementEncoder.encodeAndExtractSettlement(loans, expectedSettlement);
        assertEq(settlement, expectedSettlement);
    }

    /// This test is identical to `popAllExternallyAndCheckSettlement`,
    /// except that popLoanRequest and extractSettlement operations are
    /// performed internally by writing over the same memory in the same
    /// call.
    function popAllInternallyAndCheckSettlement(uint256 loanCount, uint256 settlementSize) private view {
        LoanRequest.Data[] memory loans = new LoanRequest.Data[](loanCount);
        for (uint256 i = 0; i < loanCount; i++) {
            loans[i] = someLoanRequest(i);
        }
        bytes memory settlement = TestBytesUtils.sequentialByteArrayOfSize(settlementSize);
        bytes memory encodedLoansWithSettlement = loanWithSettlementEncoder.encode(loans, settlement);

        assertEq(encodedLoansWithSettlement.loansCount(), loans.length);

        LoanRequest.Data memory poppedLoan;
        for (uint256 i = 0; i < loanCount; i++) {
            // Internal library operation
            poppedLoan = encodedLoansWithSettlement.popLoanRequest();
            assertEq(poppedLoan, loans[i], string.concat("at index i=", vm.toString(i)));
            assertEq(
                encodedLoansWithSettlement.loansCount(),
                loans.length - i - 1,
                string.concat("loan count does not match at index i=", vm.toString(i))
            );
        }
        // Internal library operation
        bytes memory extractedSettlement = encodedLoansWithSettlement.destroyAndExtractSettlement();
        assertEq(extractedSettlement, settlement, "settlement does not match");
    }

    /// This test is identical to `popAllInternallyAndCheckSettlement`, except
    /// that popLoanRequest and extractSettlement operations are performed
    /// externally by calling another contract that uses the memory in another
    /// context to perform all operations. Moreover, internal memory is
    /// internally reallocated after each operation, which decreases the chance
    /// that the test passes only because some theoretically inaccessible
    /// memory location has been accessed and still happens to store the right
    /// content.
    function popAllExternallyAndCheckSettlement(uint256 loanCount, uint256 settlementSize) private view {
        LoanRequest.Data[] memory loans = new LoanRequest.Data[](loanCount);
        for (uint256 i = 0; i < loanCount; i++) {
            loans[i] = someLoanRequest(i);
        }
        bytes memory settlement = TestBytesUtils.sequentialByteArrayOfSize(settlementSize);
        bytes memory encodedLoansWithSettlement = loanWithSettlementEncoder.encode(loans, settlement);

        assertEq(encodedLoansWithSettlement.loansCount(), loans.length);

        LoanRequest.Data memory poppedLoan;
        for (uint256 i = 0; i < loanCount; i++) {
            // External call
            (encodedLoansWithSettlement, poppedLoan) =
                loanWithSettlementEncoder.popLoanRequest(encodedLoansWithSettlement);
            assertEq(poppedLoan, loans[i], string.concat("at index i=", vm.toString(i)));
            assertEq(
                encodedLoansWithSettlement.loansCount(),
                loans.length - i - 1,
                string.concat("loan count does not match at index i=", vm.toString(i))
            );
        }
        // External call
        bytes memory extractedSettlement = loanWithSettlementEncoder.extractSettlement(encodedLoansWithSettlement);
        assertEq(extractedSettlement, settlement, "settlement does not match");
    }

    function test_popAllInternallyAndCheckSettlement() external view {
        popAllInternallyAndCheckSettlement(42, 1337);
    }

    function test_popAllInternallyAndCheckSettlement2() external view {
        popAllInternallyAndCheckSettlement(0, 1337);
    }

    function test_popAllInternallyAndCheckSettlement3() external view {
        popAllInternallyAndCheckSettlement(42, 0);
    }

    function test_popAllExternallyAndCheckSettlement() external view {
        popAllExternallyAndCheckSettlement(42, 1337);
    }

    function test_popAllExternallyAndCheckSettlement2() external view {
        popAllExternallyAndCheckSettlement(0, 1337);
    }

    function test_popAllExternallyAndCheckSettlement3() external view {
        popAllExternallyAndCheckSettlement(42, 0);
    }
}
