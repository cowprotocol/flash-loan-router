// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

library AddressUtils {
    function computeCreate2Address(address deployer, bytes32 salt, bytes memory bytecode)
        internal
        pure
        returns (address)
    {
        bytes32 bytecodeHash = keccak256(bytecode);
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash)))));
    }

    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
