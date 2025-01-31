// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";

import {BusyStoreAndRead, BusyTransientStorage} from "./TransientStorageArray/BusyTransientStorage.sol";
import {
    BYTES_IN_WORD,
    ExposedTransientStorageArray,
    StoreAndRead,
    sequentialByteArrayOfSize
} from "./TransientStorageArray/ExposedTransientStorageArray.sol";

contract TransientStorageArrayTest is Test {
    uint256 seed = 0;

    StoreAndRead executor;

    function pseudorandomByteArrayOfSize(uint256 length) internal returns (bytes memory data) {
        uint256 currentSeed = seed;
        data = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            data[i] = abi.encode(keccak256(abi.encodePacked(currentSeed, length, i)))[0];
        }
        seed = currentSeed + 1;
    }

    function setUp() public {
        executor = new StoreAndRead(new ExposedTransientStorageArray());
    }

    function checkRoundTrip(bytes memory data) private {
        assertEq(executor.storeAndRead(data), data);
    }

    function test_emptyArray() external {
        checkRoundTrip(hex"");
    }

    function test_shortArray() external {
        checkRoundTrip(hex"1337");
    }

    function test_singleWordArray() external {
        checkRoundTrip(sequentialByteArrayOfSize(BYTES_IN_WORD));
    }

    function test_oneByteAndASingleWordArray() external {
        checkRoundTrip(sequentialByteArrayOfSize(BYTES_IN_WORD + 1));
    }

    function test_largeArrayWordMultiple() external {
        checkRoundTrip(sequentialByteArrayOfSize(BYTES_IN_WORD * 1337));
    }

    function test_largeArrayNotWordMultiple() external {
        checkRoundTrip(sequentialByteArrayOfSize(BYTES_IN_WORD * 1337 + 1));
    }

    function test_veryLargeArrays() external {
        // The maximum size of the array is bounded by the gas block size.
        // If this test fails with `EvmError: MemoryOOG`, it likely means that
        // the transaction doesn't fit the block.
        checkRoundTrip(sequentialByteArrayOfSize(80000 * BYTES_IN_WORD + 1));
    }

    function test_keepsTrackOfLenght() external {
        executor.checkLength(vm, sequentialByteArrayOfSize(BYTES_IN_WORD * 42));
    }

    function test_lengthChangesWhenOverriding() external {
        bytes memory short = sequentialByteArrayOfSize(4242);
        bytes memory long = sequentialByteArrayOfSize(31337);
        executor.checkOverriddenLength(vm, short, long);
        executor.checkOverriddenLength(vm, long, short);
    }

    function test_ignoresSpuriousCalldata() external {
        executor.checkRoundtripDirtyCalldata(vm);
    }

    function testFuzz_arbitraryArray(bytes calldata data) external {
        checkRoundTrip(data);
    }

    function testFuzz_canOverrideArray(bytes memory firstArray, bytes memory secondArray) private {
        assertEq(executor.storeTwiceAndRead(firstArray, secondArray), secondArray);
    }

    function testFuzz_settingTransientVariablesDoesNotChangeArray(bytes memory data) external {
        BusyStoreAndRead busyExecutor = new BusyStoreAndRead(new BusyTransientStorage());
        assertEq(busyExecutor.storePopulateAndRead(data), data);
    }
}
