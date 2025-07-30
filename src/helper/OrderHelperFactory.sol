// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";
import {Clones} from "./Clones.sol";

interface IOrderHelper {
    function initialize(
        address _owner,
        address _tracker,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _flashloanPayee,
        address _factory
    ) external;

    function owner() external view returns (address);
    function tracker() external view returns (address);
    function oldCollateral() external view returns (address);
    function oldCollateralAmount() external view returns (uint256);
    function newCollateral() external view returns (address);
    function minSupplyAmount() external view returns (uint256);
    function validTo() external view returns (uint32);
    function flashloanFee() external view returns (uint256);
}

library FactoryErrors {
    error InvalidImplementationContract();
    error ContractAlreadyDeployed();
    error OrderHelperDeploymentFailed();
    error BadHelper();
    error OwnerDidNotApproveTransfer();
}

contract OrderHelperFactory {
    using SafeERC20 for IERC20;

    event NewOrderHelper(address indexed helper);

    address internal immutable HELPER_IMPLEMENTATION;
    address public immutable AAVE_LENDING_POOL;

    constructor(address _helperImplementation, address _aaveLendingPool) {
        HELPER_IMPLEMENTATION = _helperImplementation;
        if (HELPER_IMPLEMENTATION.code.length == 0) {
            revert FactoryErrors.InvalidImplementationContract();
        }

        AAVE_LENDING_POOL = _aaveLendingPool;
    }

    function getOrderHelperAddress(
        address _owner,
        address _tracker,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _flashloanPayee
    ) public view returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner,
                _tracker,
                _oldCollateral,
                _oldCollateralAmount,
                _newCollateral,
                _minSupplyAmount,
                _validTo,
                _flashloanFee,
                _flashloanPayee
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));
    }

    function deployOrderHelper(
        address _owner,
        address _tracker,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _flashloanPayee
    ) external returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner,
                _tracker,
                _oldCollateral,
                _oldCollateralAmount,
                _newCollateral,
                _minSupplyAmount,
                _validTo,
                _flashloanFee,
                _flashloanPayee
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));

        if (orderHelperAddress.code.length > 0) {
            revert FactoryErrors.ContractAlreadyDeployed();
        }

        orderHelperAddress = Clones.cloneDeterministic(HELPER_IMPLEMENTATION, _salt);

        try IOrderHelper(orderHelperAddress).initialize(
            _owner,
            _tracker,
            _oldCollateral,
            _oldCollateralAmount,
            _newCollateral,
            _minSupplyAmount,
            _validTo,
            _flashloanFee,
            _flashloanPayee,
            address(this)
        ) {
            emit NewOrderHelper(orderHelperAddress);
        } catch {
            revert FactoryErrors.OrderHelperDeploymentFailed();
        }
    }
}
