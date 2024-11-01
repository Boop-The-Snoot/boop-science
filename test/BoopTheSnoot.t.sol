// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BoopTheSnoot.sol";
import "./mocks/MockERC20.sol";

contract BoopTheSnootTest is Test {
    // Add event definitions
    event UnclaimedRewardsWithdrawn(uint256 indexed campaignId, uint256 amount, address indexed recipient);
    event RewardsClaimed(address indexed user, uint256 indexed campaignId, uint256 amount);

    BoopTheSnoot public boopTheSnoot;
    MockERC20 public rewardToken;
    MockERC20 public lpToken;

    address public owner;
    address public admin;
    address public updater;
    address public user1Wallet;
    address public user2Wallet;
    address public user3Wallet;

    uint256 constant ADMIN_COOLDOWN_PERIOD = 90 days;
    uint256 constant CREATOR_COOLDOWN_PERIOD = 30 days;

    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        updater = makeAddr("updater");
        user1Wallet = makeAddr("user1");
        user2Wallet = makeAddr("user2");
        user3Wallet = makeAddr("user3");

        console.log("Owner address:", owner);

        // Deploy tokens first
        vm.startPrank(owner);
        rewardToken = new MockERC20("Reward Token", "RWD");
        lpToken = new MockERC20("LP Token", "LP");

        // Deploy main contract with owner as deployer
        boopTheSnoot = new BoopTheSnoot();

        // Verify roles
        bytes32 defaultAdminRole = 0x00;
        console.log("Has default admin role:", boopTheSnoot.hasRole(defaultAdminRole, owner));
        console.log("Contract address:", address(boopTheSnoot));

        // Setup roles
        try boopTheSnoot.grantRole(boopTheSnoot.ADMIN_ROLE(), admin) {
            console.log("Admin role granted successfully");
        } catch Error(string memory reason) {
            console.log("Failed to grant admin role:", reason);
        }

        try boopTheSnoot.grantRole(boopTheSnoot.UPDATER_ROLE(), updater) {
            console.log("Updater role granted successfully");
        } catch Error(string memory reason) {
            console.log("Failed to grant updater role:", reason);
        }

        // Fund accounts
        vm.deal(user1Wallet, 1 ether);
        vm.deal(user2Wallet, 1 ether);
        vm.deal(user3Wallet, 1 ether);

        // Mint and approve tokens
        uint256 mintAmount = 1_000_000 ether;
        rewardToken.mint(owner, mintAmount);
        lpToken.mint(owner, mintAmount);
        rewardToken.approve(address(boopTheSnoot), mintAmount);
        lpToken.approve(address(boopTheSnoot), mintAmount);
        vm.stopPrank();

        // Whitelist tokens using admin
        vm.startPrank(admin);
        try boopTheSnoot.whitelistToken(address(rewardToken)) {
            console.log("Reward token whitelisted successfully");
        } catch Error(string memory reason) {
            console.log("Failed to whitelist reward token:", reason);
        }

        try boopTheSnoot.whitelistToken(address(lpToken)) {
            console.log("LP token whitelisted successfully");
        } catch Error(string memory reason) {
            console.log("Failed to whitelist LP token:", reason);
        }
        vm.stopPrank();
    }

    function test_CreateCampaign() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;
        uint256 maxRate = 1 ether;
        uint256 totalRewards = 1000 ether;

        vm.prank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), maxRate, startTimestamp, endTimestamp, totalRewards
        );

        (
            address creator,
            address _rewardToken,
            address _lpToken,
            uint256 maxRewardRate,
            uint256 _startTimestamp,
            uint256 _endTimestamp,
            uint256 totalRewards_,
            uint256 claimedRewards,
            bool adminWithdrawn
        ) = boopTheSnoot.campaigns(0);

        // Assert all campaign parameters
        assertEq(creator, owner, "Creator should be owner");
        assertEq(_rewardToken, address(rewardToken), "Incorrect reward token");
        assertEq(_lpToken, address(lpToken), "Incorrect LP token");
        assertEq(maxRewardRate, maxRate, "Incorrect max reward rate");
        assertEq(_startTimestamp, startTimestamp, "Incorrect start timestamp");
        assertEq(_endTimestamp, endTimestamp, "Incorrect end timestamp");
        assertEq(totalRewards_, totalRewards, "Incorrect total rewards");
        assertEq(claimedRewards, 0, "Claimed rewards should start at 0");
        assertFalse(adminWithdrawn, "Admin withdrawn should start as false");

        // Additional checks
        uint256 contractBalance = IERC20(rewardToken).balanceOf(address(boopTheSnoot));
        assertEq(contractBalance, totalRewards, "Contract should have received reward tokens");
    }

    function test_AdminWithdrawal() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        // Move time past end + cooldown
        vm.warp(endTimestamp + ADMIN_COOLDOWN_PERIOD + 1);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit UnclaimedRewardsWithdrawn(0, 1000 ether, admin);
        boopTheSnoot.adminWithdrawUnclaimedRewards(0);
    }

    function test_CreatorWithdrawal() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);

        // Move time past end + cooldown
        vm.warp(endTimestamp + CREATOR_COOLDOWN_PERIOD + 1);

        vm.expectEmit(true, true, false, true);
        emit UnclaimedRewardsWithdrawn(0, 1000 ether, owner);
        boopTheSnoot.withdrawUnclaimedRewards(0);
        vm.stopPrank();
    }

    function test_Pausability() public {
        // Test pause
        vm.prank(admin);
        boopTheSnoot.pause();
        assertTrue(boopTheSnoot.paused());

        // Test unpause
        vm.prank(admin);
        boopTheSnoot.unpause();
        assertFalse(boopTheSnoot.paused());

        // Test non-admin cannot pause
        vm.prank(user1Wallet);
        vm.expectRevert();
        boopTheSnoot.pause();

        // Test paused state prevents actions
        vm.prank(admin);
        boopTheSnoot.pause();

        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
    }

    function test_RewardClaiming() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        // Move to campaign start
        vm.warp(startTimestamp);

        // Create merkle tree data - UPDATED to match contract's format
        bytes32 leaf = keccak256(
            abi.encodePacked(
                uint256(0), // campaignId
                user1Wallet, // user
                uint256(100 ether), // amount
                "game" // literal string "game"
            )
        );

        // For testing purposes, we'll use a simple one-node merkle tree
        bytes32[] memory proof = new bytes32[](0);
        bytes32 root = leaf; // For a single-node tree, the leaf is the root

        vm.prank(updater);
        boopTheSnoot.updateGlobalRoot(root);

        vm.startPrank(user1Wallet);
        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](1);
        claims[0] = BoopTheSnoot.RewardClaim({
            campaignId: 0,
            user: user1Wallet,
            amount: 100 ether,
            rewardType: BoopTheSnoot.RewardType.Game
        });

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        boopTheSnoot.claimRewards(claims, proofs);
        vm.stopPrank();

        // Verify the claim was successful
        assertEq(boopTheSnoot.userClaims(0, user1Wallet), 100 ether, "Claim amount should be recorded");
    }
}
