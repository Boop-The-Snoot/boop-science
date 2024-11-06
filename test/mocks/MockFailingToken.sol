// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.28;

import "./MockERC20.sol";

contract MockFailingToken is MockERC20 {
    constructor() MockERC20("Failing Token", "FAIL") {}

    function approve(address, uint256) public pure override returns (bool) {
        return false;
    }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }
} 