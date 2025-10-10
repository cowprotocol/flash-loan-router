// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower} from "./interface/IBorrower.sol";
import {ICowSettlement} from "./interface/ICowSettlement.sol";
import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {Loan} from "./library/Loan.sol";
import {LoansWithSettlement} from "./library/LoansWithSettlement.sol";
import {ICowAuthentication} from "./vendored/ICowAuthentication.sol";
import {CowWrapper, GPv2Authentication} from "./vendored/CowWrapper.sol";
import {IERC20} from "./vendored/IERC20.sol";

/// @title Flash-loan Router
/// @author CoW DAO developers
/// @notice Solver contract for CoW Protocol that requests flash loans before
/// executing a settlement. Every CoW Protocol solver can call this
/// contract to borrow the funds needed for executing a settlement.
/// Also implements CowWrapper interface to allow chaining with other wrappers.
contract FlashLoanRouter is IFlashLoanRouter, CowWrapper {
    using LoansWithSettlement for bytes;

    /// @notice Event emitted to indicate that a settlement will be executed
    /// on behalf of the indicated solver.
    /// @param solver The address on behalf of which this contract will execute
    /// the settlement.
    event Settlement(address indexed solver);

    /// @notice Flag address signalling that the router is not currently
    /// preparing or executing a settlement. This is the case at the start or
    /// at the end of the call to `flashLoanAndSettle`.
    IBorrower internal constant READY = IBorrower(address(0));
    /// @notice Flag address signalling that the router is currently in the
    /// process of executing a settlement.
    IBorrower internal constant SETTLING = IBorrower(address(bytes20(keccak256("FlashLoanRouter: settling"))));

    /// @inheritdoc IFlashLoanRouter
    ICowSettlement public immutable settlementContract;
    /// @inheritdoc IFlashLoanRouter
    ICowAuthentication public immutable settlementAuthentication;

    /// @notice This variable has the following possible values:
    /// - `READY` (default), before or after a (successful) settlement
    /// - `SETTLING`, if the flash-loan collection phase terminated and the last
    ///   phase of the settlement with flash loan has started.
    /// - The address of the borrower that is expected to call this contract
    ///   back.
    /// This variable it the main actor responsible for controlling the
    /// execution order of flash loan and final settlement.
    IBorrower internal transient pendingBorrower;
    /// @notice The router expects the borrower to send back some data verbatim.
    /// The hash of the data is stored in this variable for validation.
    bytes32 internal transient pendingDataHash;

    /// @notice Only a solver of CoW Protocol can call this function.
    modifier onlySolver() {
        require(settlementAuthentication.isSolver(msg.sender), "Not a solver");
        _;
    }

    /// @notice The router is waiting for a call back from a specific borrower,
    /// no other addresses should be calling this function.
    modifier onlyPendingBorrower() {
        require(msg.sender == address(pendingBorrower), "Not the pending borrower");
        _;
    }

    /// @param _settlementContract The settlement contract that this router will
    /// be supporting.
    constructor(ICowSettlement _settlementContract)
        CowWrapper(GPv2Authentication(address(_settlementContract.authenticator())))
    {
        settlementContract = _settlementContract;
        settlementAuthentication = ICowAuthentication(_settlementContract.authenticator());
    }

    /// @inheritdoc IFlashLoanRouter
    /// @dev Despite this contract being expected to be a solver, there is no
    /// way for this contract to call itself at `flashLoanAndSettle`.
    function flashLoanAndSettle(Loan.Data[] calldata loans, bytes calldata settlement) external onlySolver {
        require(pendingBorrower == READY, "Another settlement in progress");
        // The event is emitted before the actual settlement is executed to
        // avoid having to carry `msg.sender` up the call stack (and related gas
        // overhead). The contract guarantees that the call reverts if no
        // settlement is executed.
        emit Settlement(msg.sender);
        bytes memory loansWithSettlement = LoansWithSettlement.encode(loans, settlement);
        borrowNextLoan(loansWithSettlement);
        // The following parameter is expected to be set before the final call
        // to `settle()` is executed. This flag being set means that no more
        // calls to `borrowerCallBack` are pending nor possible.
        require(pendingBorrower == SETTLING, "Terminated without settling");
        // We reset the borrower to make it possible to call this function again
        // in the same transaction.
        pendingBorrower = READY;
    }

    /// @inheritdoc IFlashLoanRouter
    /// @dev Note that the contract cannot call itself as a borrower because it
    /// doesn't implement the expected interface.
    function borrowerCallBack(bytes memory loansWithSettlement) external onlyPendingBorrower {
        // When the borrower is called, it's given some extra data that is
        // expected to be passed back here without changes.
        require(loansWithSettlement.hash() == pendingDataHash, "Data from borrower not matching");
        borrowNextLoan(loansWithSettlement);
    }

    /// @notice Takes the input loans with settlements; if none is available, it
    /// calls settle; otherwise, it requests the next loan from the borrower.
    /// @param loansWithSettlement List of loans with settlement to process.
    function borrowNextLoan(bytes memory loansWithSettlement) private {
        if (loansWithSettlement.loanCount() == 0) {
            // We set the borrower to some value different from `READY` or any
            // intermediate borrower address to prevent reentrancy.
            pendingBorrower = SETTLING;
            settle(loansWithSettlement.destroyToSettlement());
        } else {
            (uint256 amount, IBorrower borrower, address lender, IERC20 token) = loansWithSettlement.popLoan();
            pendingBorrower = borrower;
            pendingDataHash = loansWithSettlement.hash();
            borrower.flashLoanAndCallBack(lender, token, amount, loansWithSettlement);
        }
    }

    /// @notice Execute a CoW Protocol settlement.
    /// @param settlement The ABI-encoded call data for a call to `settle()` (as
    /// in `abi.encodeCall`).
    function settle(bytes memory settlement) private {
        require(selector(settlement) == ICowSettlement.settle.selector, "Only settle() is allowed");
        (bool result,) = address(settlementContract).call(settlement);
        require(result, "Settlement reverted");
    }

    /// @notice Extracts the Solidity ABI selector for the specified ABI-encode
    /// call data.
    /// @dev We assume that the input array is a valid bytes array as stored in
    /// memory by Solidity and its content can be read.
    /// @param callData ABI-encoded call data as per `abi.encodeCall`.
    /// @return result The 4 byte function selector of the call encoded in
    /// this interaction (or zero bytes if the data is shorter).
    function selector(bytes memory callData) internal pure returns (bytes4 result) {
        if (callData.length >= 4) {
            // NOTE: Read the first 32 bytes in the array. The value does not
            // need to be shifted since `bytesN` values are left aligned, and
            // the value does not need to be masked since masking occurs when
            // the value is accessed and not stored. The first word of the
            // memory data is the call data length, the content starts in the
            // next word.
            // <https://docs.soliditylang.org/en/v0.8.28/internals/layout_in_memory.html>
            // <https://docs.soliditylang.org/en/v0.8.28/assembly.html#access-to-external-variables-functions-and-libraries>
            // solhint-disable-next-line no-inline-assembly
            // Addition overflow can only happen if the input bytes point to a
            // memory address close to (`type(uint256).max`), which would not be
            // accessible in Solidity without the call running out of gas.
            assembly {
                result := mload(add(callData, 32))
            }
        }
    }

    /// @inheritdoc CowWrapper
    /// @dev Wrapper data format:
    ///      - First 32 bytes: length of ABI-encoded Loan.Data[]
    ///      - Next len bytes: ABI-encoded Loan.Data[]
    ///      - Remaining bytes: passed to _internalSettle (should contain next settlement address)
    function _wrap(bytes calldata settleData, bytes calldata wrapperData) internal override {
        (Loan.Data[] memory loans, bytes calldata remainingWrapperData) = _parseWrapperData(wrapperData);

        // Construct the final settlement call that will be executed after all loans are processed
        // This will call _internalSettle to continue the wrapper chain
        bytes memory finalSettlement = abi.encodeCall(this.internalSettleExternal, (settleData, remainingWrapperData));

        // Call flashLoanAndSettle which will handle the loan processing and eventually call our settlement
        this.flashLoanAndSettle(loans, finalSettlement);
    }

    /// @notice External wrapper for _internalSettle to allow calling from flashLoanAndSettle
    /// @dev This function can only be called by this contract itself
    /// @param settleData The settlement data to pass to the next wrapper/settlement
    /// @param remainingWrapperData The remaining wrapper data for the next wrapper/settlement
    function internalSettleExternal(bytes calldata settleData, bytes calldata remainingWrapperData) external {
        require(msg.sender == address(this), "Only callable by this contract");
        pendingBorrower = SETTLING;
        _internalSettle(settleData, remainingWrapperData);
    }

    /// @inheritdoc CowWrapper
    function parseWrapperData(bytes calldata wrapperData) external pure override returns (bytes calldata) {
        (, wrapperData) = _parseWrapperData(wrapperData);
        return wrapperData;
    }

    /// @notice Internal function to parse wrapper data
    /// @param wrapperData The wrapper data to parse
    /// @return loans The parsed loan data
    /// @return remainingWrapperData The remaining wrapper data after consuming our portion
    function _parseWrapperData(bytes calldata wrapperData)
        internal
        pure
        returns (Loan.Data[] memory loans, bytes calldata remainingWrapperData)
    {
        uint256 loansDataLength = uint256(bytes32(wrapperData[0:32]));
        loans = abi.decode(wrapperData[32:32+loansDataLength], (Loan.Data[]));
        remainingWrapperData = wrapperData[32+loansDataLength:];
    }
}
