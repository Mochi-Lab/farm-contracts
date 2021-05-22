// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IMomaVault.sol";

contract MomaFarmMoma is Ownable, Initializable {
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
        uint256 _startBlock
    ) external initializer {
        require(_momaVault != address(0), "Farm: Invalid moma token");
        require(_momaPerBlock > 1000, "Farm: Invalid block reward"); // minimum 1000 divisibility per block reward
        require(_startBlock >= block.number, "Farm: Invalid start block"); // ideally at least 24 hours more to give farmers time

        momaVault = _momaVault;
        moma = IMomaVault(_momaVault).moma();
        momaPerBlock = _momaPerBlock;
        startBlock = _startBlock;
        isActive = true;

        lastRewardBlock = _startBlock;
        accMomaPerShare = 0;
    }

    /**
     * @notice Gets the reward multiplier over the given _fromBlock until _to block
     * @param _fromBlock the start of the period to measure rewards for
     * @param _toBlock the end of the period to measure rewards for
     * @return The weighted multiplier for the given period
     */
    function getMultiplier(uint256 _fromBlock, uint256 _toBlock) public view returns (uint256) {
        if (_fromBlock < startBlock) {
            return _toBlock - startBlock;
        }
        return _toBlock - _fromBlock;
    }

    function pendingMoma(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _accMomaPerShare = accMomaPerShare;
        uint256 _momaSupply = IERC20(moma).balanceOf(address(this));
        if (block.number > lastRewardBlock && _momaSupply != 0 && isActive == true) {
            uint256 _multiplier = getMultiplier(lastRewardBlock, block.number);
            uint256 _momaReward = (_multiplier * momaPerBlock);
            _accMomaPerShare = _accMomaPerShare + ((_momaReward * 1e12) / _momaSupply);
        }
        return user.amount + ((user.amount * _accMomaPerShare) / 1e12) - user.rewardDebt;
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
        uint256 _momaReward = _multiplier * momaPerBlock;

        if (_momaReward > 0) {
            _safeMomaTransfer(address(this), _momaReward);
        }

        accMomaPerShare = accMomaPerShare + ((_momaReward * 1e12) / _momaSupply);
        lastRewardBlock = block.number;
    }

    function deposit(uint256 _amount) public mustActive {
        require(_amount > 0, "MOMA Farm: Invalid amount");
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        uint256 profit = 0;
        if (user.amount > 0) {
            profit = ((user.amount * accMomaPerShare) / 1e12) - user.rewardDebt;
        }
        IERC20(moma).safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount + profit + _amount;
        user.rewardDebt = (user.amount * accMomaPerShare) / 1e12;
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        require(_amount > 0, "MOMA Farm: Invalid amount");
        UserInfo storage user = userInfo[msg.sender];

        if (isActive == true) {
            updatePool();
        }

        uint256 profit = 0;
        if (user.amount > 0) {
            profit = ((user.amount * accMomaPerShare) / 1e12) - user.rewardDebt;
        }

        require(user.amount + profit >= _amount, "withdraw: not good");
        IERC20(moma).safeTransfer(address(msg.sender), _amount);

        user.amount = user.amount + profit - _amount;
        user.rewardDebt = (user.amount * accMomaPerShare) / 1e12;
        emit Withdraw(msg.sender, _amount);
    }

    function withdrawAll() public {
        UserInfo storage user = userInfo[msg.sender];

        if (isActive == true) {
            updatePool();
        }

        uint256 profit = 0;
        if (user.amount > 0) {
            profit = ((user.amount * accMomaPerShare) / 1e12) - user.rewardDebt;
        }

        uint256 totalAmount = user.amount + profit;

        require(totalAmount > 0, "withdraw: not good");
        IERC20(moma).safeTransfer(address(msg.sender), totalAmount);

        user.amount = 0;
        user.rewardDebt = 0;
        emit Withdraw(msg.sender, totalAmount);
    }

    function _safeMomaTransfer(address _to, uint256 _amount) internal {
        IMomaVault(momaVault).safeMomaTransfer(_to, _amount);
    }

    function forceEnd() external onlyOwner mustActive {
        updatePool();
        isActive = false;
    }
}
