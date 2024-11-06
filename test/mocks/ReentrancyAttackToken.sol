// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.28;

import "./MockERC20.sol";
import "../../src/BoopTheSnoot.sol";

contract ReentrancyAttackToken is MockERC20 {
    constructor() MockERC20("Attack Token", "ATK") {}

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Attempt reentrancy attack
        BoopTheSnoot(msg.sender).createCampaign(
            address(this), address(this), 1 ether, block.timestamp + 60, block.timestamp + 3600, 1000 ether
        );
        return super.transferFrom(from, to, amount);
    }
}
