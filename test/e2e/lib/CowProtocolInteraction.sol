// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower, ICowSettlement, IERC20} from "src/interface/IBorrower.sol";

import {TokenBalanceAccumulator} from "./TokenBalanceAccumulator.sol";

interface IOrderHelper {
    function preHook() external;
    function postHook() external;
}

interface IOrderHelperFactory {
    function deployOrderHelper(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _flashloanPayee
    ) external returns (address orderHelperAddress);
}

interface IFlashLoanTracer {
    function takeOut(address _borrower, address _user, IERC20 _token, uint256 _amount) external;
    function payBack(address _borrower, address _user, IERC20 _token) external;
}

library CowProtocolInteraction {
    function transferFrom(IERC20 token, address from, address to, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(token),
            value: 0,
            callData: abi.encodeCall(IERC20.transferFrom, (from, to, amount))
        });
    }

    function transfer(IERC20 token, address to, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(token),
            value: 0,
            callData: abi.encodeCall(IERC20.transfer, (to, amount))
        });
    }

    function takeOut(address _tracker, address _borrower, address _user, IERC20 _token, uint256 _amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(_tracker),
            value: 0,
            callData: abi.encodeCall(IFlashLoanTracer.takeOut, (_borrower, _user, _token, _amount))
        });
    }

    function payBack(address _tracker, address _borrower, address _user, IERC20 _token)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(_tracker),
            value: 0,
            callData: abi.encodeCall(IFlashLoanTracer.payBack, (_borrower, _user, _token))
        });
    }

    function borrowerApprove(IBorrower borrower, IERC20 token, address spender, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(borrower),
            value: 0,
            callData: abi.encodeCall(IBorrower.approve, (token, spender, amount))
        });
    }

    function pushBalanceToAccumulator(TokenBalanceAccumulator tokenBalanceAccumulator, IERC20 token, address owner)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(tokenBalanceAccumulator),
            value: 0,
            callData: abi.encodeCall(TokenBalanceAccumulator.push, (token, owner))
        });
    }

    function orderHelperPreHook(address helper) internal pure returns (ICowSettlement.Interaction memory) {
        return ICowSettlement.Interaction({
            target: address(helper),
            value: 0,
            callData: abi.encodeCall(IOrderHelper.preHook, ())
        });
    }

    function orderHelperPostHook(address helper) internal pure returns (ICowSettlement.Interaction memory) {
        return ICowSettlement.Interaction({
            target: address(helper),
            value: 0,
            callData: abi.encodeCall(IOrderHelper.postHook, ())
        });
    }

    function deployOrderHelper(
        address factory,
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _flashloanPayee
    ) internal pure returns (ICowSettlement.Interaction memory) {
        return ICowSettlement.Interaction({
            target: address(factory),
            value: 0,
            callData: abi.encodeCall(
                IOrderHelperFactory.deployOrderHelper,
                (
                    _owner,
                    _borrower,
                    _oldCollateral,
                    _oldCollateralAmount,
                    _newCollateral,
                    _minSupplyAmount,
                    _validTo,
                    _flashloanFee,
                    _flashloanPayee
                )
            )
        });
    }
}
