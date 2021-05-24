// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Test {
    constructor() {}

    function test(uint256 number) external pure returns (uint256) {
        uint256 result;
        for (uint256 i = 1; i <= number; i++) {
            result = result + 1;
        }

        return result;
    }
}
