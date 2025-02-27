// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8;

import {ICowSettlement} from "./interface/ICowSettlement.sol";
import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {IFlashLoanSolverWrapper} from "./interface/IFlashLoanSolverWrapper.sol";
import {BytesUtil, LoanRequest, LoansWithSettlement} from "./library/LoansWithSettlement.sol";
import {ICowAuthentication} from "./vendored/ICowAuthentication.sol";
import {IERC20} from "./vendored/IERC20.sol";

contract FlashLoanRouter is IFlashLoanRouter {
    using BytesUtil for bytes;
    using LoansWithSettlement for bytes;

    IFlashLoanSolverWrapper NO_PENDING_BORROWER = IFlashLoanSolverWrapper(address(0));

    ICowSettlement public immutable settlementContract;
    ICowAuthentication public immutable settlementAuthentication;

    IFlashLoanSolverWrapper private transient pendingBorrower;
    bytes32 private transient settlementHash;

    modifier onlySolver() {
        // Todo: investigate security implication of self calls.
        require(settlementAuthentication.isSolver(msg.sender), "Only callable by a solver");
        _;
    }

    modifier onlyPendingBorrower() {
        // Todo: investigate security implication of self calls.
        require(msg.sender == address(pendingBorrower), "Only callable by borrower");
        _;
    }

    constructor(ICowSettlement _settlementContract) {
        settlementContract = _settlementContract;
        settlementAuthentication = ICowAuthentication(_settlementContract.authenticator());
    }

    function flashLoanAndSettle(LoanRequest.Data[] calldata loans, bytes calldata settlement) external onlySolver {
        bytes memory encodedLoansWithSettlement = LoansWithSettlement.encodeLoansWithSettlement(loans, settlement);
        settlementHash = encodedLoansWithSettlement.settlementHash();
        borrowNextLoan(encodedLoansWithSettlement);
    }

    function borrowerCallback(bytes memory encodedLoansWithSettlement) external onlyPendingBorrower {
        pendingBorrower = NO_PENDING_BORROWER;
        borrowNextLoan(encodedLoansWithSettlement);
    }

    function borrowNextLoan(bytes memory encodedLoansWithSettlement) private {
        if (encodedLoansWithSettlement.loansCount() == 0) {
            require(encodedLoansWithSettlement.settlementHash() == settlementHash, "Bad settlement hash");
            settle(encodedLoansWithSettlement.destroyAndExtractSettlement());
            settlementHash = 0;
        } else {
            LoanRequest.Data memory loan = encodedLoansWithSettlement.popLoanRequest();
            IFlashLoanSolverWrapper borrower = loan.borrower;
            pendingBorrower = borrower;
            IFlashLoanSolverWrapper.LoanRequest memory loanRequest =
                IFlashLoanSolverWrapper.LoanRequest({token: loan.token, amount: loan.amount});
            borrower.flashLoanAndCallBack(loan.lender, loanRequest, encodedLoansWithSettlement);
        }
    }

    function settle(bytes memory settlement) private {
        require(selector(settlement) == ICowSettlement.settle.selector, "Only settle() is allowed");
        (bool result,) = address(settlementContract).call(settlement);
        // Todo: pass through error message.
        require(result, "Settlement reverted");
    }

    /// @dev Extracts the Solidity ABI selector for the specified interaction.
    ///
    /// @param array Interaction data.
    /// @return result The 4 byte function selector of the call encoded in
    /// this interaction.
    function selector(bytes memory array) private pure returns (bytes4 result) {
        uint256 pointer = array.memoryPointerToContent();
        if (array.length >= 4) {
            // NOTE: Read the first word of memory. The value does not need to
            // be shifted since `bytesN` values are left aligned, and the value
            // does not need to be masked since masking occurs when the value is
            // accessed and not stored:
            // <https://docs.soliditylang.org/en/v0.8.28/abi-spec.html#formal-specification-of-the-encoding>
            // <https://docs.soliditylang.org/en/v0.8.26/assembly.html#access-to-external-variables-functions-and-libraries>
            // solhint-disable-next-line no-inline-assembly
            assembly {
                result := mload(pointer)
            }
        }
    }
}
