//SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interface/IWETH.sol";

library SafeMath16 {
    function mul(uint16 a, uint16 b) internal pure returns (uint16) {
        if (a == 0) {
            return 0;
        }
        uint16 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint16 a, uint16 b) internal pure returns (uint16) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint16 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn’t hold
        return c;
    }

    function sub(uint16 a, uint16 b) internal pure returns (uint16) {
        assert(b <= a);
        return a - b;
    }

    function add(uint16 a, uint16 b) internal pure returns (uint16) {
        uint16 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract ZFarmPartnerChef is Ownable, ReentrancyGuard {
    using SafeMath16 for uint16;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward per share, times 1e12. See below.
        uint256 currentDepositAmount; // Current total deposit amount in this pool
        uint16 burnRateBP; // burn rate in basis points
        uint16 depositFeeBP; // Deposit fee in basis points
        bool enableForDeposit; // Enable for newcomer deposit and withdraw?
    }

    address public constant burnAddress =
        address(0x000000000000000000000000000000000000dEaD);

    address public depositFeeAddress; // Deposit Fee address

    address public constant wbnbAddress =
        address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    // The reward token
    IERC20 public rewardToken;
    // Reward tokens created per block.
    uint256 public rewardsPerBlock;

    // Info of each pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when mining starts.
    uint256 public startBlock;

    uint256 public remainingRewards = 0;

    event Harvest(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event UpdateEmissionRate(address indexed user, uint256 rewardsPerBlock);

    constructor(
        IERC20 _stakeToken,
        IERC20 _rewardToken,
        address _depositFeeAddress,
        uint256 _rewardsPerBlock,
        uint256 _startBlock
    ) public {
        rewardToken = _rewardToken;
        rewardsPerBlock = _rewardsPerBlock;
        depositFeeAddress = _depositFeeAddress;
        startBlock = _startBlock;

        poolInfo = PoolInfo({
            lpToken: _stakeToken,
            allocPoint: 100,
            lastRewardBlock: startBlock,
            accRewardPerShare: 0,
            currentDepositAmount: 0,
            burnRateBP: 0,
            depositFeeBP: 0,
            enableForDeposit: false
        });

        totalAllocPoint = 100;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        private
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // View function to see pending rewards on frontend.
    function pendingRewards(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.currentDepositAmount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            //calculate total rewards based on remaining funds
            if (remainingRewards > 0) {
                uint256 multiplier =
                    getMultiplier(pool.lastRewardBlock, block.number);
                uint256 totalRewards =
                    multiplier.mul(rewardsPerBlock).mul(pool.allocPoint).div(
                        totalAllocPoint
                    );
                totalRewards = Math.min(totalRewards, remainingRewards);
                accRewardPerShare = accRewardPerShare.add(
                    totalRewards.mul(1e12).div(lpSupply)
                );
            }
        }
        return
            user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        PoolInfo storage pool = poolInfo;
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.currentDepositAmount;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        if (remainingRewards == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        //calculate total rewards based on remaining funds
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 totalRewards =
            multiplier.mul(rewardsPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        totalRewards = Math.min(totalRewards, remainingRewards);
        remainingRewards = remainingRewards.sub(totalRewards);
        pool.accRewardPerShare = pool.accRewardPerShare.add(
            totalRewards.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Refill rewards into chef
    // V4 Added support for Tax-On-Transfer Tokens for example: Safe protocol
    function refill(uint256 _amount) external nonReentrant {
        updatePool();
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        uint256 balanceAfter = rewardToken.balanceOf(address(this));
        uint256 gained = balanceAfter.sub(balanceBefore);
        remainingRewards = remainingRewards.add(gained);
    }

    // Deposit LP tokens to Chef
    function deposit(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo;
        require(
            pool.enableForDeposit,
            "deposit to this pool has been suspended"
        );

        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                _safeRewardTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );

            uint256 amountAfterDepositFeeAndBurn = _amount;

            // deposit fee
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(depositFeeAddress, depositFee);
                amountAfterDepositFeeAndBurn = amountAfterDepositFeeAndBurn.sub(
                    depositFee
                );
            }

            // burn
            if (pool.burnRateBP > 0) {
                uint256 burnAmount = _amount.mul(pool.burnRateBP).div(10000);
                pool.lpToken.safeTransfer(burnAddress, burnAmount);
                amountAfterDepositFeeAndBurn = amountAfterDepositFeeAndBurn.sub(
                    burnAmount
                );
            }

            user.amount = user.amount.add(amountAfterDepositFeeAndBurn);
            pool.currentDepositAmount = pool.currentDepositAmount.add(
                amountAfterDepositFeeAndBurn
            );
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw LP tokens from Chef.
    function withdraw(uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending =
            user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            _safeRewardTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.currentDepositAmount = pool.currentDepositAmount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public nonReentrant {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.currentDepositAmount = pool.currentDepositAmount.sub(amount);
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // Safe rewards transfer function, just in case if rounding error causes pool to not have enough tokens.
    function _safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 balance = rewardToken.balanceOf(address(this));
        uint256 transferAmount = Math.min(balance, _amount);
        if (address(rewardToken) == wbnbAddress) {
            //If the reward token is a wrapped native token, we will unwrap it and send native
            IWETH(wbnbAddress).withdraw(transferAmount);
            _safeTransferETH(_to, transferAmount);
        } else {
            bool transferSuccess = rewardToken.transfer(_to, transferAmount);
            require(transferSuccess, "_safeRewardTransfer: transfer failed");
        }
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "_safeTransferETH: ETH_TRANSFER_FAILED");
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _rewardsPerBlock) public onlyOwner {
        updatePool();
        rewardsPerBlock = _rewardsPerBlock;
        emit UpdateEmissionRate(msg.sender, _rewardsPerBlock);
    }

    //Emergency function to rescue reward tokens in case of issue
    function rescueRemainingRewards(address to) external onlyOwner {
        updatePool();
        _safeRewardTransfer(to, remainingRewards);
        remainingRewards = 0;
    }

    //New function to trigger harvest for a specific user and pool
    //A specific user address is provided to facilitate aggregating harvests on multiple chefs
    //Also, it is harmless monetary-wise to help someone else harvests
    function harvestFor(address _user) public nonReentrant {
        //Limit to self or delegated harvest to avoid unnecessary confusion
        require(
            msg.sender == _user || tx.origin == _user,
            "harvestFor: FORBIDDEN"
        );
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        updatePool();
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accRewardPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                _safeRewardTransfer(_user, pending);
                user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(
                    1e12
                );
                emit Harvest(_user, pending);
            }
        }
    }

    function set(
        uint16 _burnRateBP,
        uint16 _depositFeeBP,
        bool _enableForDeposit
    ) public onlyOwner {
        require(
            _depositFeeBP.add(_burnRateBP) <= 10000,
            "add: invalid deposit fee and burn basis points"
        );

        updatePool();
        poolInfo.burnRateBP = _burnRateBP;
        poolInfo.depositFeeBP = _depositFeeBP;
        poolInfo.enableForDeposit = _enableForDeposit;
    }

    function setDepositFeeAddress(address _depositFeeAddress) public onlyOwner {
        depositFeeAddress = _depositFeeAddress;
    }
}
