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
contract AaveBorrower is CowWrapper, IAaveFlashLoanReceiver {
    using SafeERC20 for IERC20;

    IAavePool public immutable LENDER;

    /// @param _lender The aave lending pool supported by this contract.
    /// @param _authentication The CoW Protocol authentication contract.
    constructor(IAavePool _lender, ICowAuthentication _authentication)
        CowWrapper(GPv2Authentication(address(_authentication)))
    {
        LENDER = _lender;
    }

    /// @inheritdoc CowWrapper
    function _wrap(bytes calldata settleData, bytes calldata wrapperData) internal override {
        uint256 len = uint256(bytes32(wrapperData[0:32]));
        (address[] memory assets, uint256[] memory amounts) = abi.decode(wrapperData[32:32+len], (address[], uint256[]));
        
        wrapperData = wrapperData[32+len:];

        IAaveFlashLoanReceiver receiverAddress = this;
        
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = abi.encode(settleData, wrapperData);

        uint16 referralCode = 0;

        IAavePool(LENDER).flashLoan(
            address(receiverAddress), assets, amounts, interestRateModes, onBehalfOf, params, referralCode
        );
    }

    function parseWrapperData(bytes calldata wrapperData) external override pure returns (bytes calldata) {
        (,, wrapperData) = _parseWrapperData(wrapperData);

        return wrapperData;
    }

    function _parseWrapperData(bytes calldata wrapperData) internal pure returns (address[] memory assets, uint256[] memory amounts, bytes calldata) {
        uint256 len = uint256(bytes32(wrapperData[0:32]));
        (assets, amounts) = abi.decode(wrapperData[32:32+len], (address[], uint256[]));

        wrapperData = wrapperData[32+len:];

        return (assets, amounts, wrapperData);
    }

    /// @inheritdoc IAaveFlashLoanReceiver
    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address initiator,
        bytes calldata callBackData
    ) external returns (bool) {

        if (initiator != address(this)) {
            return false;
        }

        bytes calldata settleData;
        bytes calldata wrapperData;

        // We cant use `abi.decode` because it wants to output `memory` types, so assembly it is!
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

        // get the settlement contract we will ultimately be calling
        address settlementContract;
        assembly {
            // Load the last 20 bytes as an address
            // wrapperData is calldata, so we use calldataload
            settlementContract := calldataload(add(wrapperData.offset, sub(wrapperData.length, 32)))
        }

        // Grant the settlement contract the approvals it will need to access the flashed funds
        for (uint256 i = 0;i < assets.length;i++) {
            IERC20(assets[i]).approve(settlementContract, amounts[i]);
        }

        _internalSettle(settleData, wrapperData);

        // There is technically a possibility that the settlement contract didnt actually pull the needed tokens
        // For max security, just make sure we reset the approvals (maybe not ultimately necessary)
        // And then, we approve the lender to take all the tokens it needs as repayment
        for (uint256 i = 0;i < assets.length;i++) {
            IERC20(assets[i]).approve(settlementContract, 0);
            IERC20(assets[i]).approve(address(LENDER), amounts[i] + premiums[i]);
        }

        return true;
    }
}
