// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IAaveFlashLoanReceiver} from "./vendored/IAaveFlashLoanReceiver.sol";
import {IAavePool} from "./vendored/IAavePool.sol";
import {ICowAuthentication} from "./vendored/ICowAuthentication.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {ISignatureTransfer} from "./vendored/ISignatureTransfer.sol";
import {SafeERC20} from "./vendored/SafeERC20.sol";
import {CowWrapper, CowAuthentication, CowSettlement} from "./vendored/CowWrapper.sol";

/// @title AaveCollateralSwapWrapper
/// @author CoW DAO developers
/// @notice A borrower contract for the flash-loan router that adds support for
/// Aave protocol.
contract AaveCollateralSwapWrapper is CowWrapper, IAaveFlashLoanReceiver {
    using SafeERC20 for IERC20;

    /**
     * @notice Definition for a swap operation
     * @dev This structure does not a signature. Examples of why if a solver were to mutate any of these fields:
     * * owner: if this is set to a address the solver controls, 
     * * swapTo: if its set to the wrong token, the user's order will not fill the flashloan and the process fails
     * * amountOut: if its set too high, the loan wont be repaid by the user's order. if its set too low, the money will just be leftover in the contract and the CoW DAO can retrieve it to return the money (and the solver gets slashed)
     * 
     */
    struct CollateralSwapOperation {
        address owner;
        uint256 deadline;
        uint256 nonce;
        address swapFrom;
        address swapTo;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    IAavePool public immutable LENDER;
    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    string public constant COLLATERAL_SWAP_WITNESS_TYPE = "CollateralSwapOperation(address owner,uint256 deadline,uint256 nonce,address swapFrom,address swapTo,uint256 amountIn,uint256 minAmountOut)";
    bytes32 public constant COLLATERAL_SWAP_WITNESS_TYPEHASH = keccak256(bytes(COLLATERAL_SWAP_WITNESS_TYPE));

    // Full witness type string for Permit2: "WitnessType witness)WitnessType(...)TokenPermissions(...)"
    string public constant COLLATERAL_SWAP_WITNESS_TYPESTRING = "CollateralSwapOperation witness)CollateralSwapOperation(address owner,uint256 deadline,uint256 nonce,address swapFrom,address swapTo,uint256 amountIn,uint256 minAmountOut)TokenPermissions(address token,uint256 amount)";

    /// @param _lender The aave lending pool supported by this contract.
    /// @param _authentication The CoW Protocol authentication contract.
    constructor(IAavePool _lender, ICowAuthentication _authentication)
        CowWrapper(CowAuthentication(address(_authentication)))
    {
        LENDER = _lender;
    }

    /// @inheritdoc CowWrapper
    function _wrap(bytes calldata settleData, bytes calldata wrapperData) internal override {
        CollateralSwapOperation memory op = abi.decode(wrapperData[:7*32], (CollateralSwapOperation));
        bytes memory signature = abi.decode(wrapperData[7*32:], (bytes));
        
        // Compute the EIP-712 witness hash
        bytes32 witnessHash = keccak256(
            abi.encode(
                COLLATERAL_SWAP_WITNESS_TYPEHASH,
                op.owner,
                op.deadline,
                op.nonce,
                op.swapFrom,
                op.swapTo,
                op.amountIn,
                op.minAmountOut
            )
        );

        PERMIT2.permitWitnessTransferFrom(
                ISignatureTransfer.PermitTransferFrom({
                    permitted: ISignatureTransfer.TokenPermissions({
                        token: op.swapFrom,
                        amount: op.amountIn
                    }),
                    nonce: op.nonce,
                    deadline: op.deadline
                }),
                ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: op.amountIn }),
                op.owner,
                witnessHash,
                COLLATERAL_SWAP_WITNESS_TYPESTRING,
                signature
        );

        CowSettlement settlement = CowSettlement(address(bytes20(wrapperData[wrapperData.length-20:])));

        IERC20(op.swapFrom).approve(address(settlement.vaultRelayer()), type(uint256).max);
        
        IAaveFlashLoanReceiver receiverAddress = this;
        
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = abi.encode(settleData, wrapperData);

        uint16 referralCode = 0;

        address[] memory assets = new address[](1);
        assets[0] = address(op.swapTo);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = op.minAmountOut;

        IAavePool(LENDER).flashLoan(
            address(receiverAddress), assets, amounts, interestRateModes, onBehalfOf, params, referralCode
        );
    }
    
    // EIP1271 signature check
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4 magic) {
        // blanket approve--this contract takes the role of verifying the user's wants
        return 0x1626ba7e;
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
        address[] memory,
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

        // deposit the proceeds of the swap into the user's desired aave token
        CollateralSwapOperation memory op = abi.decode(wrapperData[:7*32], (CollateralSwapOperation));
        bytes memory signature = abi.decode(wrapperData[7*32:], (bytes));
        
        wrapperData = wrapperData[9*32 + ((signature.length + 31) / 32) * 32:];
        
        IERC20(op.swapTo).approve(address(LENDER), op.minAmountOut);
        LENDER.supply(op.swapTo, op.minAmountOut, op.owner, 0);
        
        _internalSettle(settleData, wrapperData);

        // Allow the lender to pull whatever they need
        IERC20(op.swapTo).approve(address(LENDER), amounts[0] + premiums[0]);

        return true;
    }
}
