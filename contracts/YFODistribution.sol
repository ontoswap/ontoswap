pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./YFOToken.sol";

interface IMigrator {
    function migrate(IERC20 token) external returns (IERC20);
}

contract YFODistribution is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of YFOs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accYfoPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accYfoPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. YFOs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that YFOs distribution occurs.
        uint256 accYfoPerShare; // Accumulated YFOs per share, times 1e18. See below.
    }

    // The YFO TOKEN!
    YFOToken public yfo;
    // YFO tokens created per block.
    uint256 public yfoPerBlock;

    IMigrator public migrator;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when YFO mining starts.
    uint256 public startBlock;
    uint256 public endBlock;
    // about 1 week 
    uint256 public halvedBlock = 40320; 


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        YFOToken _yfo,
        uint256 _yfoPerBlock,
        uint256 _startBlock,
        IERC20[] memory _lpTokens,
        uint256[] memory _allocPoints
    ) public {
        yfo = _yfo;
        yfoPerBlock = _yfoPerBlock;
        startBlock = _startBlock;
        endBlock = _startBlock.add(halvedBlock.mul(10));
        require(_lpTokens.length == _allocPoints.length, "length error");
        for (uint i = 0; i < _lpTokens.length; i++) {
            _add(_lpTokens[i], _allocPoints[i]);
        }
    }
    
    
    function _add( IERC20 _lpToken, uint256 _allocPoint) internal {
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accYfoPerShare: 0
        }));
    }

    function add(IERC20 _lpToken) public onlyOwner {
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: 0,
            lastRewardBlock: uint256(-1),
            accYfoPerShare: 0
        }));
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigrator _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    } 

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return f(_to).sub(f(_from));
    }

    function f(uint256 _to) public view returns (uint256 _f) {
        if (_to < startBlock) {
            _f = 0;
        } else if(_to >= endBlock) {
            _f = 512 * halvedBlock;
        } else {
            uint256 halved = _to.sub(startBlock).div(halvedBlock);
            _f = (512 - 2 ** (9 - halved)) * halvedBlock;
            _f = halved < 9 ?  _f + 2 ** (8 - halved) * ((_to - startBlock) % halvedBlock) : _f + ((_to - startBlock) % halvedBlock);
        }
    }
    // View function to see pending YFOs on frontend.
    function pendingYfo(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accYfoPerShare = pool.accYfoPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 yfoReward = multiplier.mul(yfoPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accYfoPerShare = accYfoPerShare.add(yfoReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accYfoPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 yfoReward = multiplier.mul(yfoPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        if (yfoReward != 0) {
            yfo.mint(address(this), yfoReward);
            pool.accYfoPerShare = pool.accYfoPerShare.add(yfoReward.mul(1e18).div(lpSupply));
            pool.lastRewardBlock = block.number;
        }
    }

    // Deposit LP tokens to YFODistribution for YFO allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accYfoPerShare).div(1e18).sub(user.rewardDebt);
            if(pending > 0) {
                safeYfoTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        if (pool.accYfoPerShare != 0) {
            user.rewardDebt = user.amount.mul(pool.accYfoPerShare).div(1e18);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from YFODistribution.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accYfoPerShare).div(1e18).sub(user.rewardDebt);
        if(pending > 0) {
            safeYfoTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        if (pool.accYfoPerShare != 0) {
            user.rewardDebt = user.amount.mul(pool.accYfoPerShare).div(1e18);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe yfo transfer function, just in case if rounding error causes pool to not have enough YFOs.
    function safeYfoTransfer(address _to, uint256 _amount) internal {
        uint256 yfoBal = yfo.balanceOf(address(this));
        if (_amount > yfoBal) {
            yfo.transfer(_to, yfoBal);
        } else {
            yfo.transfer(_to, _amount);
        }
    }
}
