// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

library BytesUtils {
    function sequentialByteArrayOfSize(uint256 length) internal pure returns (bytes memory data) {
        data = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            data[i] = bytes1(uint8(i));
        }
    }

    function pseudorandomByteArrayOfSize(uint256 length) internal pure returns (bytes memory data) {
        data = new bytes(length);
        // We use the memory location of the allocated array as a randomness
        // seed so that invoking pseudorandomByteArrayOfSize twice in the same
        // call returns two different arrays. They can still be the same in two
        // different call context.
        uint256 seed;
        assembly ("memory-safe") {
            seed := data
        }
        for (uint256 i = 0; i < length; i++) {
            data[i] = abi.encode(keccak256(abi.encodePacked(seed, length, i)))[0];
        }
    }
}
