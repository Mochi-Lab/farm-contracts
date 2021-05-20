// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IMomaFarm.sol";

contract CompoundFarm is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 shares; // number of shares for a user
        uint256 lastDepositedTime; // keeps track of deposited time for potential penalty
        uint256 momaAtLastUserAction; // keeps track of moma deposited at the last user action
        uint256 lastUserActionTime; // keeps track of the last user action time
    }

    IERC20 public moma; // Moma token

    IMomaFarm public momaFarm;

    mapping(address => UserInfo) public userInfo;

    uint256 public totalShares;
    uint256 public lastHarvestedTime;

    uint256 public constant MAX_CALL_FEE = 100; // 1%

    uint256 public callFee = 25; // 0.25%

    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 shares,
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);
    event Harvest(address indexed sender, uint256 callFee);
    event Pause();
    event Unpause();

    /**
     * @notice Constructor
     * @param _momaFarm: momaFarm contract
     */
    constructor(IMomaFarm _momaFarm) {
        momaFarm = _momaFarm;
        moma = IERC20(_momaFarm.moma());

        // Infinite approve
        moma.safeApprove(address(_momaFarm), type(uint256).max);
    }

    /**
     * @notice Checks if the msg.sender is a contract or a proxy
     */
    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    /**
     * @notice Deposits funds into the Moma Vault
     * @dev Only possible when contract not paused.
     * @param _amount: number of tokens to deposit (in MOMA)
     */
    function deposit(uint256 _amount) external whenNotPaused notContract {
        require(_amount > 0, "Nothing to deposit");

        uint256 pool = balanceOf();
        moma.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 currentShares = 0;
        if (totalShares != 0) {
            currentShares = (_amount * totalShares) / pool;
        } else {
            currentShares = _amount;
        }
        UserInfo storage user = userInfo[msg.sender];

        user.shares = user.shares + currentShares;
        user.lastDepositedTime = block.timestamp;

        totalShares = totalShares + currentShares;

        user.momaAtLastUserAction = (user.shares * balanceOf()) / totalShares;
        user.lastUserActionTime = block.timestamp;

        _earn();

        emit Deposit(msg.sender, _amount, currentShares, block.timestamp);
    }

    /**
     * @notice Withdraws all funds for a user
     */
    function withdrawAll() external notContract {
        withdraw(userInfo[msg.sender].shares);
    }

    /**
     * @notice Reinvests MOMA tokens into momaFarm
     * @dev Only possible when contract not paused.
     */
    function harvest() external notContract whenNotPaused {
        momaFarm.withdraw(0);

        uint256 bal = available();
        uint256 currentCallFee = (bal * callFee) / 10000;

        moma.safeTransfer(msg.sender, currentCallFee);

        _earn();

        lastHarvestedTime = block.timestamp;

        emit Harvest(msg.sender, currentCallFee);
    }

    /**
     * @notice Sets call fee
     * @dev Only callable by the contract admin.
     */
    function setCallFee(uint256 _callFee) external onlyOwner {
        require(_callFee <= MAX_CALL_FEE, "callFee cannot be more than MAX_CALL_FEE");
        callFee = _callFee;
    }

    /**
     * @notice Withdraws from momaFarm to Vault without caring about rewards.
     * @dev EMERGENCY ONLY. Only callable by the contract admin.
     */
    function emergencyWithdraw() external onlyOwner {
        momaFarm.emergencyWithdraw(0);
    }

    /**
     * @notice Withdraw unexpected tokens sent to the Moma Vault
     */
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(moma), "Token cannot be same as deposit token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Triggers stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
        emit Pause();
    }

    /**
     * @notice Returns to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
        emit Unpause();
    }

    /**
     * @notice Calculates the expected harvest reward from third party
     * @return Expected reward to collect in MOMA
     */
    function calculateHarvestMomaRewards() external view returns (uint256) {
        uint256 amount = momaFarm.pendingMoma(address(this));
        amount = amount + available();
        uint256 currentCallFee = (amount * callFee) / 10000;

        return currentCallFee;
    }

    /**
     * @notice Calculates the total pending rewards that can be restaked
     * @return Returns total pending moma rewards
     */
    function calculateTotalPendingMomaRewards() external view returns (uint256) {
        uint256 amount = momaFarm.pendingMoma(address(this));
        amount = amount + available();

        return amount;
    }

    /**
     * @notice Calculates the price per share
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalShares == 0 ? 1e18 : (balanceOf() * 1e18) / totalShares;
    }

    /**
     * @notice Withdraws from funds from the Moma Vault
     * @param _shares: Number of shares to withdraw
     */
    function withdraw(uint256 _shares) public notContract {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares > 0, "Nothing to withdraw");
        require(_shares <= user.shares, "Withdraw amount exceeds balance");

        uint256 currentAmount = (balanceOf() * _shares) / totalShares;
        user.shares = user.shares - _shares;
        totalShares = totalShares - _shares;

        uint256 bal = available();
        if (bal < currentAmount) {
            uint256 balWithdraw = currentAmount - bal;
            momaFarm.withdraw(balWithdraw);
            uint256 balAfter = available();
            uint256 diff = balAfter - bal;
            if (diff < balWithdraw) {
                currentAmount = bal + diff;
            }
        }

        if (user.shares > 0) {
            user.momaAtLastUserAction = (user.shares * balanceOf()) / totalShares;
        } else {
            user.momaAtLastUserAction = 0;
        }

        user.lastUserActionTime = block.timestamp;

        moma.safeTransfer(msg.sender, currentAmount);

        emit Withdraw(msg.sender, currentAmount, _shares);
    }

    /**
     * @notice Custom logic for how much the vault allows to be borrowed
     * @dev The contract puts 100% of the tokens to work.
     */
    function available() public view returns (uint256) {
        return moma.balanceOf(address(this));
    }

    /**
     * @notice Calculates the total underlying tokens
     * @dev It includes tokens held by the contract and held in momaFarm
     */
    function balanceOf() public view returns (uint256) {
        (uint256 amount, ) = momaFarm.userInfo(address(this));
        return moma.balanceOf(address(this)) + amount;
    }

    /**
     * @notice Deposits tokens into momaFarm to earn staking rewards
     */
    function _earn() internal {
        uint256 bal = available();
        if (bal > 0) {
            momaFarm.deposit(bal);
        }
    }

    /**
     * @notice Checks if address is a contract
     * @dev It prevents contract from being targetted
     */
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
