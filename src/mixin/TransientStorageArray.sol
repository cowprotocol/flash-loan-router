// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.28;

/// @title Transient Storage Array
/// @author CoW DAO developers
/// @notice Defines an interface to copy a (dynamic-size) bytes array from
/// calldata to transient storage as well as to read it at a later point in the
/// same transaction.
/// @dev The array length is defined as a Solidity transient variable. The
/// content of the array is stored word-by-word starting from the end of the
/// transient storage space (slot `type(uint256).max`); each next word is stored
/// in the transient storage slot immediately before. The endianness of
/// each word has not been changed.
/// The array is defined from the end to avoid conflicts with transient
/// variables that could be relied on by the importing contract. If the contract
/// that inherits this one only access transient storage through Solidity
/// variables that are only manipulated through basic Solidity operations (i.e.,
/// no assembly) then there should be no interferences with this contract.
/// Otherwise, it's important to have a full understanding of the transient
/// storage layout of the inheriting contract to avoid that the same transient
/// slot is overridden when working with two unrelated variables.
abstract contract TransientStorageArray {
    uint256 constant BYTES_IN_WORD = 32;

    /// @notice The number of bytes currently stored in the transient storage
    /// array.
    uint256 private transient length;

    /// @notice Read the length of the transient storage array.
    /// @return The length of the data stored in the transient storage array in
    /// bytes.
    /// @dev We don't want to give direct access to `length` as the code assumes
    /// that this value cannot be large enough to cause overflows.
    function transientStorageArrayLength() internal view returns (uint256) {
        return length;
    }

    /// @notice The input bytes array is copied to transient storage.
    /// @param data The bytes array to copy to the transient storage array.
    function storeToTransientStorageArray(bytes calldata data) internal {
        length = data.length;
        uint256 storedBytes = 0;
        while (storedBytes < data.length) {
            // Each (transient) storage slot stores a full word.
            bytes32 window;
            // Note: if windowEnd > data.length, then the extra bytes of
            // `window` are filled with arbitrary bytes (or zero bytes if after
            // the calldata range). The variable `length` encodes the array
            // boundaries, meaning that these extra bytes will be ignored when
            // recovering the stored content.
            assembly ("memory-safe") {
                // `add` is not expected to overflow as sending a transaction
                // with enough calldata to cause the offset to overflow would
                // not fit the block gas limit.
                window := calldataload(add(data.offset, storedBytes))
            }

            uint256 transientArraySlot;
            unchecked {
                // No overflow check: block gas limit avoids overflows.
                transientArraySlot = type(uint256).max - (storedBytes / BYTES_IN_WORD);
            }

            assembly ("memory-safe") {
                tstore(transientArraySlot, window)
            }
            unchecked {
                // No overflow check: block gas limit avoids overflows.
                storedBytes += BYTES_IN_WORD;
            }
        }
    }

    /// @notice A memory array is allocated with the current content of the
    /// transient storage array.
    /// @return data A memory array with the data contained in the transient
    /// storage array.
    function readTransientStorageArray() internal view returns (bytes memory data) {
        uint256 byteLength = length;
        uint256 wordsToRead;
        unchecked {
            // The number of words to read is `ceil(byteLength / BYTES_IN_WORD)`
            // and the only way to set `byteLength` is by storing data on the
            // storage array. Because of the block gas limit, this number cannot
            // be large enough to cause overflows.
            wordsToRead = (byteLength + BYTES_IN_WORD - 1) / BYTES_IN_WORD;
            data = new bytes(BYTES_IN_WORD * wordsToRead);
        }
        uint256 dataMemoryLocation;
        assembly ("memory-safe") {
            dataMemoryLocation := data
        }
        for (uint256 i = 0; i < wordsToRead;) {
            uint256 wordMemoryLocation;
            uint256 wordTransientLocation;
            unchecked {
                // Unchecked because it would take more iterations than gas
                // available in a block before `i` grows enough to cause
                // overflows or underflows.
                wordMemoryLocation = dataMemoryLocation + (i + 1) * BYTES_IN_WORD;
                wordTransientLocation = type(uint256).max - i;
                i = i + 1;
            }
            assembly {
                // Why this is not memory safe: this function writes to memory
                // that has been allocated by Solidity (`data`), however, the
                // last word may be outside of the range reserved to the bytes
                // array and thus overwrite other data if memory operations are
                // rearranged. This code relies on the assumption that `data` is
                // the last entry in memory and after that there's only free
                // memory. Note that leaving the free memory "dirty" is expected
                // by the compiler:
                // https://docs.soliditylang.org/en/v0.8.28/internals/layout_in_memory.html
                let word := tload(wordTransientLocation)
                mstore(wordMemoryLocation, word)
            }
        }

        // Truncate the size of the vector. Memory safe as we only decrease the
        // size of the array and so we never touch unallocated memory.
        assembly ("memory-safe") {
            mstore(dataMemoryLocation, byteLength)
        }
    }

    /// @notice Clear all the content of the transient storage array, leaving
    /// in its stead an empty array
    /// @dev The actual transient storage array content isn't actually reset to
    /// zero bytes, however this data cannot be accessed and can be overwritten
    /// at a later point
    function clearTransientStorageArray() internal {
        length = 0;
    }
}
