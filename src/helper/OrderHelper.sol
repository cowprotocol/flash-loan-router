// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IAavePool} from "../vendored/IAavePool.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";

import {GPv2Order} from "./GPv2Order.sol";
import {ISettlement} from "./ISettlement.sol";
import {Initializable} from "./Initializable.sol";
import {SafeTransfer} from "./SafeTransfer.sol";
import {SignatureChecker} from "./SignatureChecker.sol";

interface IOrderFactory {
    function transferFromOwner(address _token, uint256 _amount) external;
    function isPresigned() external view returns (bool);
    function AAVE_LENDING_POOL() external view returns (address);
}

interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

interface IAaveBorrower {
    function payBack(IERC20 _token) external;
}

library OrderHelperError {
    error BadParameters();
    error PreHookNotCalled();
    error OrderNotSignedByOwner();
    error OrderDoesNotMatchMessageHash();
    error BadSellToken();
    error BadBuyToken();
    error WrongValidTo();
    error NotSellOrder();
    error BadReceiver();
    error BadSellAmount();
    error FeeIsNotZero();
    error NotEnoughOldCollateral();
    error NotEnoughBuyAmount();
    error NoPartiallyFillable();
    error OnlyBalanceERC20();
    error NotEnoughSupplyAmount();
    error NotLongerValid();
    error NotOwner();
    error InvalidWithdrawArguments();
    error PreHookAlreadyCalled();
}

/// @title OrderHelper
/// @author CoW DAO developers
/// @notice A contract per order to handle collateral for collateral swap
contract OrderHelper is Initializable {
    using SafeERC20 for IERC20;
    using GPv2Order for GPv2Order.Data;

    address public constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public AAVE_LENDING_POOL;

    address public owner;
    IAaveBorrower public borrower;
    IERC20 public oldCollateral;
    IERC20 public oldCollateralAToken;
    uint256 public oldCollateralAmount;
    IERC20 public newCollateral;
    IERC20 public newCollateralAToken;
    uint256 public minSupplyAmount;
    uint32 public validTo;
    uint256 public flashloanFee;
    address public factory;
    uint256 transient preHookCalled;

    function initialize(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _factory
    ) external initializer {
        // TODO: check the other params?
        if (_owner == address(0)) {
            revert OrderHelperError.BadParameters();
        }

        if (_validTo < block.timestamp) {
            revert OrderHelperError.BadParameters();
        }

        owner = _owner;
        borrower = IAaveBorrower(_borrower);
        oldCollateral = IERC20(_oldCollateral);
        newCollateral = IERC20(_newCollateral);
        oldCollateralAmount = _oldCollateralAmount;
        minSupplyAmount = _minSupplyAmount;
        validTo = _validTo;
        flashloanFee = _flashloanFee;
        factory = _factory;

        AAVE_LENDING_POOL = IOrderFactory(factory).AAVE_LENDING_POOL();
        oldCollateralAToken = IERC20(IAavePool(AAVE_LENDING_POOL).getReserveAToken(address(_oldCollateral)));
        newCollateralAToken = IERC20(IAavePool(AAVE_LENDING_POOL).getReserveAToken(address(_newCollateral)));

        // Approve the _oldCollateral AToken for the swap
        IERC20(oldCollateralAToken).forceApprove(ISettlement(SETTLEMENT).vaultRelayer(), type(uint256).max);

        // Approve the old collateral to deposit into aave in the prehook
        IERC20(_oldCollateral).forceApprove(AAVE_LENDING_POOL, type(uint256).max);

        // The system will pull the old collateral to payback the flash loan
        IERC20(_oldCollateral).forceApprove(_borrower, type(uint256).max);
    }

    // Prehook will take care of depositing the flash loan amount into aave
    function preHook() external {
        if (preHookCalled != 0) {
            revert OrderHelperError.PreHookAlreadyCalled();
        }
        preHookCalled = 1;

        // It should be the same amount, but someone can dust
        if (oldCollateral.balanceOf(address(this)) < oldCollateralAmount) {
            revert OrderHelperError.NotEnoughOldCollateral();
        }

        IAavePool(AAVE_LENDING_POOL).supply(address(oldCollateral), oldCollateralAmount, address(this), 0);
    }

    function isValidSignature(bytes32 _orderHash, bytes calldata _signature) external view returns (bytes4) {
        if (preHookCalled != 1) {
            revert OrderHelperError.PreHookNotCalled();
        }

        (GPv2Order.Data memory _order, bytes memory _userSignature) = abi.decode(_signature, (GPv2Order.Data, bytes));
        if (!SignatureChecker.isValidSignatureNow(owner, _orderHash, _userSignature)) {
            revert OrderHelperError.OrderNotSignedByOwner();
        }

        bytes32 _rebuiltOrderHash = _order.hash(ISettlement(SETTLEMENT).domainSeparator());
        if (_orderHash != _rebuiltOrderHash) {
            revert OrderHelperError.OrderDoesNotMatchMessageHash();
        }

        if (address(_order.sellToken) != address(oldCollateralAToken)) {
            revert OrderHelperError.BadSellToken();
        }

        if (address(_order.buyToken) != address(newCollateralAToken)) {
            revert OrderHelperError.BadBuyToken();
        }

        if (_order.validTo != validTo) {
            revert OrderHelperError.WrongValidTo();
        }

        if (_order.kind != GPv2Order.KIND_SELL) {
            revert OrderHelperError.NotSellOrder();
        }

        if (_order.receiver != owner) {
            revert OrderHelperError.BadReceiver();
        }

        if (_order.sellAmount != oldCollateralAmount - flashloanFee) {
            revert OrderHelperError.BadSellAmount();
        }

        if (_order.feeAmount != 0) {
            revert OrderHelperError.FeeIsNotZero();
        }

        if (_order.buyAmount < minSupplyAmount) {
            revert OrderHelperError.NotEnoughBuyAmount();
        }

        if (_order.partiallyFillable) {
            revert OrderHelperError.NoPartiallyFillable();
        }

        if (_order.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert OrderHelperError.OnlyBalanceERC20();
        }

        if (_order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert OrderHelperError.OnlyBalanceERC20();
        }

        return this.isValidSignature.selector;
    }

    function postHook() external {
        if (preHookCalled != 1) {
            revert OrderHelperError.PreHookNotCalled();
        }

        // After the swap the owner's oldCollateral is unlocked, move here to unwrap and pay the flashloan
        IOrderFactory(factory).transferFromOwner(address(oldCollateralAToken), oldCollateralAmount);
        IAavePool(AAVE_LENDING_POOL).withdraw(address(oldCollateral), type(uint256).max, address(this));

        borrower.payBack(oldCollateral);

        // For now we will pay the flashloan fee from the order itself, but this should be taken care by solvers
        IERC20(oldCollateral).transfer(address(borrower), flashloanFee);
    }

    function sweep(address[] calldata _tokens, uint256[] calldata _amounts) external {
        address _owner = owner;
        if (_owner != msg.sender) {
            revert OrderHelperError.NotOwner();
        }

        if (_tokens.length != _amounts.length) {
            revert OrderHelperError.InvalidWithdrawArguments();
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == address(0)) {
                SafeTransfer._safeTransferETH(_owner, _amounts[i]);
            } else {
                SafeTransfer._safeTransfer(_tokens[i], _owner, _amounts[i]);
            }
        }
    }
}
