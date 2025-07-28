// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ICowSettlement} from "./interface/ICowSettlement.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {SafeERC20} from "./vendored/SafeERC20.sol";

library FlashLoanTrackerError {
    error AlreadyTakenOut();
    error NotTakenOut();
}

/// @title Flash Loan Tracker
/// @author CoW DAO developers
/// @notice A contract that tracks flash loan takeouts and paybacks for the AaveBorrower.
contract FlashLoanTracker {
    using SafeERC20 for IERC20;

    ICowSettlement public immutable settlementContract;
    address public immutable borrower;

    /// @notice Tracks open flash loan amounts per user and token
    mapping(address => mapping(IERC20 => uint256)) public open;

    /// @notice A function with this modifier can only be called in the context
    /// of a CoW Protocol settlement.
    modifier onlySettlementContract() {
        require(msg.sender == address(settlementContract), "Only callable in a settlement");
        _;
    }

    constructor(address _borrower, ICowSettlement _settlementContract) {
        borrower = _borrower;
        settlementContract = _settlementContract;
    }

    function takeOut(address _user, IERC20 _token, uint256 _amount) external onlySettlementContract {
        if (open[_user][_token] != 0) {
            revert FlashLoanTrackerError.AlreadyTakenOut();
        }

        open[_user][_token] = _amount;
        _token.safeTransferFrom(borrower, _user, _amount);
    }

    function payBack(address _user, IERC20 _token) external onlySettlementContract {
        uint256 _amount = open[_user][_token];
        if (_amount == 0) {
            revert FlashLoanTrackerError.NotTakenOut();
        }

        open[_user][_token] = 0;
        _token.safeTransferFrom(_user, borrower, _amount);
    }
}
