// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IUniswapV2Router {
    function WETH() external view returns (address);

    function factory() external view returns (address);
}
