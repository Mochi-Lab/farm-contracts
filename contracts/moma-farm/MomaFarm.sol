// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IMomaVault.sol";

contract MomaFarm is Ownable, Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many Moma tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    address public moma;
    address public momaVault;
    uint256 public momaPerBlock;
    uint256 public startBlock;
    uint256 public lastRewardBlock;
    uint256 public accMomaPerShare;
    bool public isActive;

    uint256 public firstCycleRate;
    uint256 public initRate;
    uint256 public reducingRate; // 95 equivalent to 95%
    uint256 public reducingCycle; // 195000 equivalent 195000 block

    // Info of each user that stakes Moma tokens.
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    modifier mustActive() {
        require(isActive == true, "Farm: Not active");
        _;
    }

    constructor() {}

    function initialize(
        address _momaVault,
        uint256 _momaPerBlock,
        uint256 _startBlock,
        uint256[] memory _rateParameters // 0: firstCycleRate , 1: initRate, 2: reducingRate, 3: reducingCycle
    ) external initializer {
        require(_momaVault != address(0), "Farm: Invalid moma token");
        require(_momaPerBlock > 1000, "Farm: Invalid block reward"); // minimum 1000 divisibility per block reward
        require(_startBlock > block.number, "Farm: Invalid start block"); // ideally at least 24 hours more to give farmers time
        require(_rateParameters[0] > 0, "Farm: Invalid first cycle rate");
        require(_rateParameters[1] > 0, "Farm: Invalid initial rate");
        require(_rateParameters[2] > 0 && _rateParameters[1] < 100, "Farm: Invalid reducing rate");
        require(_rateParameters[3] > 0, "Farm: Invalid reducing cycle");

        momaVault = _momaVault;
        moma = IMomaVault(_momaVault).moma();
        momaPerBlock = _momaPerBlock;
        startBlock = _startBlock;

        firstCycleRate = _rateParameters[0];
        initRate = _rateParameters[1];
        reducingRate = _rateParameters[2];
        reducingCycle = _rateParameters[3];
        isActive = true;

        uint256 _lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        lastRewardBlock = _lastRewardBlock;
        accMomaPerShare = 0;
    }

    /**
     * @notice Gets the reward multiplier over the given _fromBlock until _to block
     * @param _fromBlock the start of the period to measure rewards for
     * @param _toBlock the end of the period to measure rewards for
     * @return The weighted multiplier for the given period
     */
    function getMultiplier(uint256 _fromBlock, uint256 _toBlock) public view returns (uint256) {
        return _getMultiplierFromStart(_toBlock) - _getMultiplierFromStart(_fromBlock);
    }

    function _getMultiplierFromStart(uint256 _block) internal view returns (uint256) {
        uint256 roundPassed = (_block - startBlock) / reducingCycle;

        if (roundPassed == 0) {
            return (_block - startBlock) * firstCycleRate * 1e12;
        } else {
            uint256 multiplier = reducingCycle * firstCycleRate * 1e12;
            uint256 i = 0;
            for (i = 0; i < roundPassed - 1; i++) {
                multiplier =
                    multiplier +
                    ((1e12 * initRate * reducingRate**i) / 100**i) *
                    reducingCycle;
            }

            if ((_block - startBlock) % reducingCycle > 0) {
                multiplier =
                    multiplier +
                    ((1e12 * initRate * reducingRate**i) / 100**i) *
                    ((_block - startBlock) % reducingCycle);
            }

            return multiplier;
        }
    }

    function pendingMoma(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accMomaPerShare = accMomaPerShare;
        uint256 _momaSupply = IERC20(moma).balanceOf(address(this));
        if (block.number > lastRewardBlock && _momaSupply != 0 && isActive == true) {
            uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
            uint256 _momaReward = (_multiplier * momaPerBlock) / 1e12;
            _accMomaPerShare = _accMomaPerShare + ((_momaReward * 1e12) / _momaSupply);
        }
        return ((user.amount * _accMomaPerShare) / 1e12) - user.rewardDebt;
    }

    function updatePool() public mustActive {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 _momaSupply = IERC20(moma).balanceOf(address(this));
        if (_momaSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 _momaReward = (_multiplier * momaPerBlock) / 1e12;

        accMomaPerShare = accMomaPerShare + ((_momaReward * 1e12) / _momaSupply);
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount) public mustActive {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = ((user.amount * accMomaPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                safeMomaTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            IERC20(moma).safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount + _amount;
        }
        user.rewardDebt = (user.amount * accMomaPerShare) / 1e12;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        if (isActive == true) {
            updatePool();
        }

        uint256 pending = ((user.amount * accMomaPerShare) / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safeMomaTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            IERC20(moma).safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = (user.amount * accMomaPerShare) / 1e12;
        emit Withdraw(msg.sender, _amount);
    }

    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        IERC20(moma).safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeMomaTransfer(address _to, uint256 _amount) internal {
        IMomaVault(momaVault).safeMomaTransfer(_to, _amount);
    }

    function updateReducingRate(uint256 _reducingRate) external onlyOwner mustActive {
        require(_reducingRate > 0 && _reducingRate <= 100, "Farm: Invalid reducing rate");
        reducingRate = _reducingRate;
    }

    function forceEnd() external onlyOwner mustActive {
        updatePool();
        isActive = false;
    }
}
