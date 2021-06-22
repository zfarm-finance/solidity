//SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "../BEP20.sol";

contract xBUSD is BEP20("Fake mintable BUSD", "xBUSD") {
    /**
     * @dev Creates `amount` tokens and assigns them to `msg.sender`, increasing
     * the total supply.
     *
     * Requirements
     *
     * - `msg.sender` allow to mint for testing
     */
    function mintForTest(uint256 amount) public returns (bool) {
        _mint(_msgSender(), amount);
        return true;
    }
}
