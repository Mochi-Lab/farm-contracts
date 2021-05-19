// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMomaVault {
    function moma() external view returns (address);

    function safeMomaTransfer(address _to, uint256 _amount) external;
}
