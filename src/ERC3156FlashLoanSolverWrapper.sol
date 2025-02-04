// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8;

import {ICowSettlement} from "./interface/ICowSettlement.sol";
import {TransientStorageArray} from "./mixin/TransientStorageArray.sol";
import {ICowAuthentication} from "./vendored/ICowAuthentication.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {IERC3156FlashBorrower} from "./vendored/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "./vendored/IERC3156FlashLender.sol";

contract ERC3156FlashLoanSolverWrapper is IERC3156FlashBorrower, TransientStorageArray {
    struct LoanRequest {
        IERC20 token;
        uint256 amount;
    }

    /// @notice ERC 3156 requires flash loan lenders to return this value if
    /// execution was successful.
    bytes32 private constant ERC3156_ONFLASHLOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice The contract that will be called when the flash-loan contract
    /// calls back to this contract.
    ICowSettlement public immutable settlementContract;
    ICowAuthentication public immutable settlementAuthentication;

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

    function flashLoanAndSettle(IERC3156FlashLender lender, LoanRequest calldata loan, bytes calldata settlement)
        external
        onlySolver
    {
        require(selector(settlement) == ICowSettlement.settle.selector, "Only settle() is allowed");
        require(transientStorageArrayLength() == 0, "Pending settlement");
        storeToTransientStorageArray(settlement);
        bool success = lender.flashLoan(this, address(loan.token), loan.amount, hex"");
        require(success, "Flash loan was unsuccessful");
        // We clear the transient storage again in case `onFlashLoan` wasn't
        // called by the lender contract.
        clearTransientStorageArray();
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(address, address, uint256, uint256, bytes calldata) external returns (bytes32) {
        bytes memory settlement = readTransientStorageArray();
        require(settlement.length > 0, "No settlement pending");
        clearTransientStorageArray();
        (bool result,) = address(settlementContract).call(settlement);
        // Todo: pass through error message.
        require(result, "Settlement reverted");
        return ERC3156_ONFLASHLOAN_SUCCESS;
    }

    // Note: loan payback is handled differently depending on the flash loan
    // protocol. Some expect `onFlashLoan` to transfer funds back; some take
    // care of transfering the funds back themselves. We let solvers specify
    // an arbitrary approval target to allow for the latter way of retrieving
    // funds. An approval is also the only way to pull funds out of this
    // contract. Flash loaning the native token is not supported.
    function approve(IERC20 token, address target, uint256 amount) external onlySettlementContract {
        // Todo: safeApprove alternative
        require(token.approve(target, amount), "Approval failed");
    }

    /// @dev Extracts the Solidity ABI selector for the specified interaction.
    ///
    /// @param callData Interaction data.
    /// @return result The 4 byte function selector of the call encoded in
    /// this interaction.
    function selector(bytes calldata callData) internal pure returns (bytes4 result) {
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
