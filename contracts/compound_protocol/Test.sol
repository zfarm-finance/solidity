// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/**
 * @title Ballot
 * @dev Implements voting process along with vote delegation
 */
contract Test {
    // bytes: 0x0b540c440000000000000000000000000000000000000000000000000000000000000064
    bytes public _callData;
    // bytes: 0x0000000000000000000000000000000000000000000000000000000000000064
    bytes public i_bytes;
    // bytes4: 0x0b540c44
    bytes4 public _signature;

    constructor() {
        uint256 amount = 100;
        i_bytes = abi.encodePacked(amount);
        _signature = bytes4(keccak256(bytes("mintForTest(uint256)")));
        _callData = abi.encodePacked(_signature, i_bytes);
    }
}
