// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8;

import {ICowSettlement} from "../interface/ICowSettlement.sol";
import {IFlashLoanSolverWrapper} from "../interface/IFlashLoanSolverWrapper.sol";
import {ICowAuthentication} from "../vendored/ICowAuthentication.sol";
import {IERC20} from "../vendored/IERC20.sol";

abstract contract FlashLoanSolverWrapper is IFlashLoanSolverWrapper {
    /// @inheritdoc IFlashLoanSolverWrapper
    ICowSettlement public immutable settlementContract;
    /// @inheritdoc IFlashLoanSolverWrapper
    ICowAuthentication public immutable settlementAuthentication;

    bool internal transient inFlight;

    modifier onlySettlementContract() {
        require(msg.sender == address(settlementContract), "Only callable in a settlement");
        _;
    }

    modifier onlySolver() {
        // Todo: investigate security implication of self calls.
        require(settlementAuthentication.isSolver(msg.sender), "Only callable by a solver");
        _;
    }

    constructor(ICowSettlement _settlementContract) {
        settlementContract = _settlementContract;
        settlementAuthentication = ICowAuthentication(_settlementContract.authenticator());
    }

    /// @inheritdoc IFlashLoanSolverWrapper
    function flashLoanAndSettle(address lender, LoanRequest calldata loan, bytes calldata settlement)
        external
        onlySolver
    {
        require(selector(settlement) == ICowSettlement.settle.selector, "Only settle() is allowed");
        require(!inFlight, "Pending settlement");
        inFlight = true;
        triggerFlashLoan(lender, loan.token, loan.amount, settlement);
        // We clear the in-flight status in case `onFlashLoan` wasn't called by
        // the lender contract.
        inFlight = false;
    }

    /// @inheritdoc IFlashLoanSolverWrapper
    function approve(IERC20 token, address target, uint256 amount) external onlySettlementContract {
        // Todo: safeApprove alternative
        require(token.approve(target, amount), "Approval failed");
    }

    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes memory settlement) internal virtual;

    function flashLoanCallback(bytes memory settlement) internal {
        require(inFlight, "No settlement pending");
        inFlight = false;
        (bool result,) = address(settlementContract).call(settlement);
        // Todo: pass through error message.
        require(result, "Settlement reverted");
    }

    /// @dev Extracts the Solidity ABI selector for the specified interaction.
    ///
    /// @param callData Interaction data.
    /// @return result The 4 byte function selector of the call encoded in
    /// this interaction.
    function selector(bytes calldata callData) private pure returns (bytes4 result) {
        if (callData.length >= 4) {
            // NOTE: Read the first word of the calldata. The value does not
            // need to be shifted since `bytesN` values are left aligned, and
            // the value does not need to be masked since masking occurs when
            // the value is accessed and not stored:
            // <https://docs.soliditylang.org/en/v0.8.28/abi-spec.html#formal-specification-of-the-encoding>
            // <https://docs.soliditylang.org/en/v0.8.26/assembly.html#access-to-external-variables-functions-and-libraries>
            // solhint-disable-next-line no-inline-assembly
            assembly {
                result := calldataload(callData.offset)
            }
        }
    }
}
