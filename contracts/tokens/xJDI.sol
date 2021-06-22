//SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "../BEP20.sol";

contract xJDI is BEP20("Fake mintable xJDI", "xJDI") {
    function mint(uint256 amount) public onlyOwner returns (bool) {
        _mint(_msgSender(), amount);
        return true;
    }

    function mintForTest(uint256 amount) public returns (bool) {
        _mint(_msgSender(), amount);
        return true;
    }
}
