// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {Borrower} from "./mixin/Borrower.sol";
import {IAaveFlashLoanReceiver} from "./vendored/IAaveFlashLoanReceiver.sol";
import {IAavePool} from "./vendored/IAavePool.sol";
import {ICowAuthentication} from "./vendored/ICowAuthentication.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {SafeERC20} from "./vendored/SafeERC20.sol";
import {CowWrapper, GPv2Authentication} from "./vendored/CowWrapper.sol";

/// @title Aave Borrower
/// @author CoW DAO developers
/// @notice A borrower contract for the flash-loan router that adds support for
/// Aave protocol.
contract AaveBorrower is Borrower, CowWrapper, IAaveFlashLoanReceiver {
    using SafeERC20 for IERC20;

    /// @param _router The router supported by this contract.
    /// @param _authentication The CoW Protocol authentication contract.
    constructor(IFlashLoanRouter _router, ICowAuthentication _authentication)
        Borrower(_router)
        CowWrapper(GPv2Authentication(address(_authentication)))
    {}

    /// @inheritdoc Borrower
    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        override
    {
        // For documentation on the call parameters, see:
        // <https://aave.com/docs/developers/smart-contracts/pool#write-methods-flashloan-input-parameters>
        IAaveFlashLoanReceiver receiverAddress = this;
        address[] memory assets = new address[](1);
        assets[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory interestRateModes = new uint256[](1);
        // Don't open any debt position, just revert if funds can't be
        // transferred from this contract.
        interestRateModes[0] = 0;
        // The next value is technically unused, since `interestRateMode` is 0.
        address onBehalfOf = address(this);
        bytes calldata params = callBackData;
        // Referral supply is currently inactive
        uint16 referralCode = 0;
        IAavePool(lender).flashLoan(
            address(receiverAddress), assets, amounts, interestRateModes, onBehalfOf, params, referralCode
        );
    }

    /// @inheritdoc CowWrapper
    function _wrap(bytes calldata settleData, bytes calldata wrapperData) internal override {
        uint256 len = uint256(bytes32(wrapperData[0:32]));
        (address lender, address[] memory assets, uint256[] memory amounts) = abi.decode(wrapperData[32:32+len], (address, address[], uint256[]));
        wrapperData = wrapperData[32+len:];

        IAaveFlashLoanReceiver receiverAddress = this;
        
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = abi.encode(settleData, wrapperData);

        uint16 referralCode = 0;
        IAavePool(lender).flashLoan(
            address(receiverAddress), assets, amounts, interestRateModes, onBehalfOf, params, referralCode
        );
    }

    /// @inheritdoc IAaveFlashLoanReceiver
    function executeOperation(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata callBackData
    ) external returns (bool) {
        bytes calldata settleData;
        bytes calldata wrapperData;

        assembly {
            // callBackData is encoded as (bytes, bytes)
            // First 32 bytes: offset to first bytes
            // Next 32 bytes: offset to second bytes
            let firstOffset := calldataload(callBackData.offset)
            let secondOffset := calldataload(add(callBackData.offset, 0x20))

            // First bytes: length at offset, data starts after length
            let firstLen := calldataload(add(callBackData.offset, firstOffset))
            settleData.offset := add(add(callBackData.offset, firstOffset), 0x20)
            settleData.length := firstLen

            // Second bytes: length at offset, data starts after length
            let secondLen := calldataload(add(callBackData.offset, secondOffset))
            wrapperData.offset := add(add(callBackData.offset, secondOffset), 0x20)
            wrapperData.length := secondLen
        }

        _internalSettle(settleData, wrapperData);

        return true;
    }
}
