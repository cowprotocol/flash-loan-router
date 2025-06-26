// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower, ICowSettlement, IERC20} from "src/interface/IBorrower.sol";

import {TokenBalanceAccumulator} from "./TokenBalanceAccumulator.sol";

interface ITracker {
    function takeOut(address user, IERC20 token, uint256 amount) external;
    function payBack(address user, IERC20 token) external;
}

interface IAaveHelper {
    function swap(address _oldCollateral, address _newCollateral, address _user, uint256 _pullAmount) external;
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

    function takeOut(address tracker, address user, IERC20 token, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(tracker),
            value: 0,
            callData: abi.encodeCall(ITracker.takeOut, (user, token, amount))
        });
    }

    function payBack(address tracker, address user, IERC20 token)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(tracker),
            value: 0,
            callData: abi.encodeCall(ITracker.payBack, (user, token))
        });
    }

    function helperSwap(
        address helper,
        address _oldCollateral,
        address _newCollateral,
        address _user,
        uint256 _pullAmount
    ) internal pure returns (ICowSettlement.Interaction memory) {
        return ICowSettlement.Interaction({
            target: address(helper),
            value: 0,
            callData: abi.encodeCall(IAaveHelper.swap, (_oldCollateral, _newCollateral, _user, _pullAmount))
        });
    }
}
