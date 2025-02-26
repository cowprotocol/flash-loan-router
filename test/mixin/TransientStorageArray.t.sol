// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";

import {BusyStoreAndRead, BusyTransientStorage} from "./TransientStorageArray/BusyTransientStorage.sol";
import {
    BYTES_IN_WORD,
    ExposedTransientStorageArray,
    StoreAndRead
} from "./TransientStorageArray/ExposedTransientStorageArray.sol";
import {BytesUtils} from "test/test-lib/BytesUtils.sol";

contract TransientStorageArrayTest is Test {
    StoreAndRead executor;

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
        checkRoundTrip(BytesUtils.sequentialByteArrayOfSize(BYTES_IN_WORD));
    }

    function test_oneByteAndASingleWordArray() external {
        checkRoundTrip(BytesUtils.sequentialByteArrayOfSize(BYTES_IN_WORD + 1));
    }

    function test_largeArrayWordMultiple() external {
        checkRoundTrip(BytesUtils.sequentialByteArrayOfSize(BYTES_IN_WORD * 1337));
    }

    function test_largeArrayNotWordMultiple() external {
        checkRoundTrip(BytesUtils.sequentialByteArrayOfSize(BYTES_IN_WORD * 1337 + 1));
    }

    function test_veryLargeArrays() external {
        // The maximum size of the array is bounded by the gas block size.
        // If this test fails with `EvmError: MemoryOOG`, it likely means that
        // the transaction doesn't fit the block.
        checkRoundTrip(BytesUtils.sequentialByteArrayOfSize(80000 * BYTES_IN_WORD + 1));
    }

    function test_keepsTrackOfLength() external {
        executor.checkLength(vm, BytesUtils.sequentialByteArrayOfSize(BYTES_IN_WORD * 42));
    }

    function test_lengthChangesWhenOverriding() external {
        bytes memory short = BytesUtils.sequentialByteArrayOfSize(4242);
        bytes memory long = BytesUtils.sequentialByteArrayOfSize(31337);
        executor.checkOverriddenLength(vm, short, long);
        executor.checkOverriddenLength(vm, long, short);
    }

    function test_ignoresSpuriousCalldata() external {
        executor.checkRoundtripDirtyCalldata(vm);
    }

    function testFuzz_arbitraryArray(bytes calldata data) external {
        checkRoundTrip(data);
    }

    function testFuzz_canOverrideArray(bytes memory firstArray, bytes memory secondArray) external {
        assertEq(executor.storeTwiceAndRead(firstArray, secondArray), secondArray);
    }

    function testFuzz_clearingDoesNotAffectFutureStore(bytes memory data) external {
        assertEq(executor.storeClearAndRead(data), hex"");
    }

    function testFuzz_clearedArrayHasZeroLength(bytes memory data) external {
        assertEq(executor.storeClearReturnLength(data), 0);
    }

    function testFuzz_clearingDoesNotAffectFutureStore(bytes memory firstArray, bytes memory secondArray) external {
        assertEq(executor.storeClearStoreAndRead(firstArray, secondArray), secondArray);
    }

    function testFuzz_settingTransientVariablesDoesNotChangeArray(bytes memory data) external {
        BusyStoreAndRead busyExecutor = new BusyStoreAndRead(new BusyTransientStorage());
        assertEq(busyExecutor.storePopulateAndRead(data), data);
    }
}
