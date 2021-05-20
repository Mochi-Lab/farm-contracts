// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMomaFarm {
    function momaPerBlock() external view returns (uint256);

    function userInfo(address _account) external view returns (uint256 amount, uint256 rewardDebt);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingMoma(address _user) external view returns (uint256);

    function moma() external view returns (address);
}
