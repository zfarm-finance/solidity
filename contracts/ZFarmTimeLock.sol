//SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/TokenTimelock.sol";

contract ZFarmTimeLock is TokenTimelock {
    constructor(
        address token,
        address beneficiary,
        uint256 releaseTime
    )
        public
        TokenTimelock(
            IERC20(token), // token
            beneficiary, // beneficiary
            releaseTime
        )
    {}
}
