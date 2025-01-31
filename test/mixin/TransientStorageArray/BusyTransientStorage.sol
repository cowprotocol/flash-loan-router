// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {ExposedTransientStorageArray} from "./ExposedTransientStorageArray.sol";

/// @dev This contract defines many storage slots for internal use. The way that
/// in which `TransientStorageArray` works means that simple transient storage
/// variables defined by Solidity's storage layout would not overlap with the
/// transient storage array data.
contract BusyTransientStorage is ExposedTransientStorageArray {
    // Note: as of Solidity 0.8.28, transient data location is only supported
    // for value types. It would be good to replace the following variables with
    // something like `uint256[1337] transient busywork`.
    uint256 transient busywork1;
    uint256 transient busywork2;
    uint256 transient busywork3;
    uint256 transient busywork4;
    uint256 transient busywork5;
    uint256 transient busywork6;
    uint256 transient busywork7;
    uint256 transient busywork8;
    uint256 transient busywork9;

    function populateTransientStorage() external {
        busywork1 = 1;
        busywork2 = 2;
        busywork3 = 3;
        busywork4 = 4;
        busywork5 = 5;
        busywork6 = 6;
        busywork7 = 7;
        busywork8 = 8;
        busywork9 = 9;
    }
}

/// @dev Same purpose as the `StoreAndRead` contract, but for tests involving
/// `BusyTransientStorage`.
contract BusyStoreAndRead {
    BusyTransientStorage bts;

    constructor(BusyTransientStorage _bts) {
        bts = _bts;
    }

    function storePopulateAndRead(bytes memory data) external returns (bytes memory) {
        bts.store(data);
        bts.populateTransientStorage();
        return bts.read();
    }
}
