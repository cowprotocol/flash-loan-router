// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {TransientStorageArray} from "src/mixin/TransientStorageArray.sol";

/// @dev This contract exposes all internal methods of TransientStorageArray.
contract ExposedTransientStorageArray is TransientStorageArray {
    function store(bytes calldata data) external {
        storeToTransientStorageArray(data);
    }

    function read() external view returns (bytes memory) {
        return readTransientStorageArray();
    }

    function length() external view returns (uint256) {
        return transientStorageArrayLength();
    }

    function clear() external {
        clearTransientStorageArray();
    }
}

uint256 constant BYTES_IN_WORD = 32;

function sequentialByteArrayOfSize(uint256 length) pure returns (bytes memory data) {
    data = new bytes(length);
    for (uint256 i = 0; i < length; i++) {
        data[i] = bytes1(uint8(i));
    }
}

/// @dev We use this contract to store to transient storage and read from it in
/// the same transaction. A dedicated contract for this is only needed when
/// running `forge test` with the `isolate` flag.
contract StoreAndRead {
    ExposedTransientStorageArray tsa;

    constructor(ExposedTransientStorageArray _tsa) {
        tsa = _tsa;
    }

    function storeAndRead(bytes memory data) external returns (bytes memory) {
        tsa.store(data);
        return tsa.read();
    }

    function storeTwiceAndRead(bytes memory first, bytes memory second) external returns (bytes memory) {
        tsa.store(first);
        tsa.store(second);
        return tsa.read();
    }

    function storeClearReturnLength(bytes memory data) external returns (uint256) {
        tsa.store(data);
        tsa.clear();
        return tsa.length();
    }

    function storeClearAndRead(bytes memory data) external returns (bytes memory) {
        tsa.store(data);
        tsa.clear();
        return tsa.read();
    }

    function storeClearStoreAndRead(bytes memory data1, bytes memory data2) external returns (bytes memory) {
        tsa.store(data1);
        tsa.clear();
        tsa.store(data2);
        return tsa.read();
    }

    function checkLength(Vm vm, bytes memory data) external {
        vm.assertEq(tsa.length(), 0);
        tsa.store(data);
        vm.assertEq(tsa.length(), data.length);
        tsa.read();
        // Reading doesn't clear the array.
        vm.assertEq(tsa.length(), data.length);
    }

    function checkOverriddenLength(Vm vm, bytes memory data1, bytes memory data2) external {
        vm.assertEq(tsa.length(), 0);
        tsa.store(data1);
        vm.assertEq(tsa.length(), data1.length);
        tsa.store(data2);
        vm.assertEq(tsa.length(), data2.length);
    }

    function checkRoundtripDirtyCalldata(Vm vm) external {
        // The library reads raw data from calldata; this data is in general
        // under user control. In most cases, a bytes array will be encoded
        // in multiples of full words and extra bytes will be zero.
        // We want to check that the library behaves as expected when the input
        // data has nonzero data in fields that are usually zero. For example,
        // the byte array [0x42] is usually encoded as follows:
        //
        //   | -------------------------- length -------------------------- || ---------------------------- data -------------------------- |
        // 0x00000000000000000000000000000000000000000000000000000000000000014200000000000000000000000000000000000000000000000000000000000000
        //
        // The following is also a valid encoding of [0x42] though, all nonzero
        // bytes at the end are ignored on decoding:
        //
        //   | -------------------------- length -------------------------- || ---------------------------- data -------------------------- |
        // 0x00000000000000000000000000000000000000000000000000000000000000014231333333333333333333333333333333333333333333333333333333333337
        //
        // Because of how the library works, these extra bytes are also copied
        // to transient storage. This test is to make sure they don't impact the
        // store or reading process.

        uint256 calldataArrayOffset = 0x20;
        uint256 populatedBytesCount = 2 * BYTES_IN_WORD;
        uint256 calldataBytesLength = BYTES_IN_WORD + 1;
        // The following ia a manual implementation of:
        // abi.encodeCall(ExposedTransientStorageArray.store, sequentialByteArrayOfSize(calldataBytesLength));
        // except that the last (BYTES_IN_WORD - 1) bytes aren't filled with
        // zeroes but are filled with nonzero sequential bytes to the end of the
        // bytes array last word.
        bytes memory storeCalldata = abi.encodePacked(
            ExposedTransientStorageArray.store.selector,
            calldataArrayOffset,
            calldataBytesLength,
            sequentialByteArrayOfSize(populatedBytesCount)
        );

        bytes memory expectedStoredData = sequentialByteArrayOfSize(calldataBytesLength);

        // This is `tsa.store(sequentialByteArrayOfSize(expectedStoredData))`
        // with the byte array manipulation explained above.
        (bool success,) = address(tsa).call(storeCalldata);

        // The following block is here to double check that the manual encoding
        // has been done correctly. A failure here is most likely a problem in
        // the test and not in the library.
        bytes memory decodedStoredData;
        // Ideally. here we'd write:
        // (decodedStoredData) = abi.decodeCall(ExposedTransientStorageArray.store, storeCalldata)
        // but `decodeCall` doesn't exist in Solidity. So we do it by hand as
        // well.
        bytes memory storeCalldataWithoutSelector;
        assembly {
            // Trim the first four bytes of the selector
            storeCalldataWithoutSelector := add(storeCalldata, 4)
        }
        decodedStoredData = abi.decode(storeCalldataWithoutSelector, (bytes));
        vm.assertEq(decodedStoredData, expectedStoredData);
        vm.assertTrue(success, "Unexpected revert when storing data");

        // Actual check that the read output coincides with the stored data.
        vm.assertEq(tsa.read(), expectedStoredData);
    }

    function assertEq(bytes memory lhs, bytes memory) private {}
}
