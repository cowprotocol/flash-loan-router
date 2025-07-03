// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Clones} from "./Clones.sol";

interface IOrderHelper {
    function initialize(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        bytes32 _appData
    ) external;
}

library FactoryErrors {
    error InvalidImplementationContract();
    error ContractAlreadyDeployed();
    error OrderHelperDeploymentFailed();
}

contract OrderHelperFactory {
    event NewOrderHelper(address indexed helper);

    address internal immutable HELPER_IMPLEMENTATION;

    /// @dev appData is the keccak256 hash of bytes.concat(preAppDataBytes, orderAddressBytes, postAppDataBytes)
    /// `orderAddressBytes` corresponds to the address of the new order converted to bytes
    bytes internal preAppDataBytes;
    bytes internal postAppDataBytes;

    constructor(address _helperImplementation) {
        HELPER_IMPLEMENTATION = _helperImplementation;
        if (HELPER_IMPLEMENTATION.code.length == 0) {
            revert FactoryErrors.InvalidImplementationContract();
        }

        /* TODO: add partner fee with the proper recipient + bps
            "partnerFee": {"recipient": "0xC542C2F197c4939154017c802B0583C596438380", "volumeBps": 25},
        */
        string memory _preAppDataStr = '{"version":"1.4.0",' '"appCode":"aave-v3-flashloan",' '"metadata":'
            '{"hooks":' '{"version":"0.1.0",' '"pre":[{"target":"';
        preAppDataBytes = bytes(_preAppDataStr);

        /// @dev `0x156c6390` is the selector for `swapCollateral()`
        string memory _postAppDataStr = '","callData":"0x156c6390",' '"gasLimit":"100000"}]}}}';
        postAppDataBytes = bytes(_postAppDataStr);
    }

    function getOrderHelperAddress(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo
    ) external view returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner, _borrower, _oldCollateral, _oldCollateralAmount, _newCollateral, _minSupplyAmount, _validTo
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));
    }

    function deployOrderHelper(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo
    ) external returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner, _borrower, _oldCollateral, _oldCollateralAmount, _newCollateral, _minSupplyAmount, _validTo
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));

        if (orderHelperAddress.code.length > 0) {
            revert FactoryErrors.ContractAlreadyDeployed();
        }

        orderHelperAddress = Clones.cloneDeterministic(HELPER_IMPLEMENTATION, _salt);
        bytes32 _appData = _getAppDataHash(orderHelperAddress);

        try IOrderHelper(orderHelperAddress).initialize(
            _owner,
            _borrower,
            _oldCollateral,
            _oldCollateralAmount,
            _newCollateral,
            _minSupplyAmount,
            _validTo,
            _appData
        ) {
            emit NewOrderHelper(orderHelperAddress);
        } catch {
            revert FactoryErrors.OrderHelperDeploymentFailed();
        }
    }

    function _addressToBytes(address _newOrder) internal pure returns (bytes memory addressBytes) {
        bytes32 value = bytes32(uint256(uint160(_newOrder)));
        bytes memory alphabet = "0123456789abcdef";

        addressBytes = new bytes(42);
        addressBytes[0] = "0";
        addressBytes[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            addressBytes[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            addressBytes[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
    }

    function _getAppDataHash(address _newOrder) internal view returns (bytes32) {
        bytes memory _appDataStr = bytes.concat(preAppDataBytes, _addressToBytes(_newOrder), postAppDataBytes);
        return keccak256(bytes(_appDataStr));
    }
}
