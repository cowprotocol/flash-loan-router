// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";

import {GPv2Order} from "./GPv2Order.sol";
import {ISettlement} from "./ISettlement.sol";
import {Initializable} from "./Initializable.sol";

interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

interface IAavePool {
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

library OrderHelperError {
    error BadParameters();
    error OrderDoesNotMatchMessageHash();
    error BadSellToken();
    error BadBuyToken();
    error NotSellOrder();
    error BadReceiver();
    error BadSellAmount();
}

/// @title OrderHelper
/// @author CoW DAO developers
/// @notice A contract per order to handle collateral for collateral swap
contract OrderHelper is Initializable {
    using SafeERC20 for IERC20;
    using GPv2Order for GPv2Order.Data;

    address public constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant AAVE_LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    address public owner;
    address public borrower;
    IERC20 public oldCollateral;
    IERC20 public newCollateral;
    uint256 public oldCollateralAmount;
    uint256 public flashloanFee;

    function initialize(
        address _owner,
        address _borrower,
        address _oldCollateral,
        address _newCollateral,
        uint256 _oldCollateralAmount,
        uint256 _flashloanFee
    ) external initializer {
        if (_owner == address(0)) {
            revert OrderHelperError.BadParameters();
        }

        owner = _owner;
        borrower = _borrower;
        oldCollateral = IERC20(_oldCollateral);
        newCollateral = IERC20(_newCollateral);
        oldCollateralAmount = _oldCollateralAmount;
        flashloanFee = _flashloanFee;

        // Approve the underlying token for the swap
        address _sellingToken = IAaveToken(_oldCollateral).UNDERLYING_ASSET_ADDRESS();
        IERC20(_sellingToken).forceApprove(ISettlement(SETTLEMENT).vaultRelayer(), type(uint256).max);
    }

    function isValidSignature(bytes32 _orderHash, bytes calldata _signature) external view returns (bytes4) {
        // TODO: Grab order, user's signature from _signature
        // Validate the owner signed the order

        GPv2Order.Data memory _order = abi.decode(_signature, (GPv2Order.Data));

        bytes32 _rebuiltOrderHash = _order.hash(ISettlement(SETTLEMENT).domainSeparator());
        if (_orderHash != _rebuiltOrderHash) {
            revert OrderHelperError.OrderDoesNotMatchMessageHash();
        }

        if (address(_order.sellToken) != IAaveToken(address(oldCollateral)).UNDERLYING_ASSET_ADDRESS()) {
            revert OrderHelperError.BadSellToken();
        }

        if (_order.buyToken != newCollateral) {
            revert OrderHelperError.BadBuyToken();
        }

        if (_order.kind != GPv2Order.KIND_SELL) {
            revert OrderHelperError.NotSellOrder();
        }

        if (_order.receiver != address(this)) {
            revert OrderHelperError.BadReceiver();
        }

        if (_order.sellAmount != oldCollateralAmount) {
            revert OrderHelperError.BadSellAmount();
        }

        return this.isValidSignature.selector;
    }

    function swapCollateral() external {
        require(msg.sender == SETTLEMENT);

        // After a swap, the full output will be sent to the owner
        newCollateral.transfer(owner, newCollateral.balanceOf(address(this)));

        // Once the old collateral is unlocked, move to this contract and withdraw
        IERC20(oldCollateral).transferFrom(owner, address(this), oldCollateralAmount);

        address _underlying = IAaveToken(address(oldCollateral)).UNDERLYING_ASSET_ADDRESS();
        IAavePool(AAVE_LENDING_POOL).withdraw(_underlying, type(uint256).max, borrower);
    }
}
