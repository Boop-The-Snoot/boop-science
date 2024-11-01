// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BoopTheSnoot.sol";
import "./mocks/MockERC20.sol";
import "@openzeppelin/access/IAccessControl.sol";

contract BoopTheSnootAdvancedTest is Test {
    // Events
    event UnclaimedRewardsWithdrawn(uint256 indexed campaignId, uint256 amount, address indexed recipient);
    event RewardsClaimed(address indexed user, uint256 indexed campaignId, uint256 amount);
    event ReferralMade(address indexed referrer, address indexed referee, uint256 lpTokenAmount);

    BoopTheSnoot public boopTheSnoot;
    MockERC20 public rewardToken;
    MockERC20 public lpToken;

    address public owner;
    address public admin;
    address public updater;
    address public user1;
    address public user2;
    address public user3;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    uint256 constant ADMIN_COOLDOWN_PERIOD = 90 days;
    uint256 constant CREATOR_COOLDOWN_PERIOD = 30 days;

    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        admin = makeAddr("admin");
        updater = makeAddr("updater");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy tokens
        vm.startPrank(owner);
        rewardToken = new MockERC20("Reward Token", "RWD");
        lpToken = new MockERC20("LP Token", "LP");

        // Deploy main contract
        boopTheSnoot = new BoopTheSnoot();

        // Setup roles
        boopTheSnoot.grantRole(ADMIN_ROLE, admin);
        boopTheSnoot.grantRole(UPDATER_ROLE, updater);

        // Mint tokens
        rewardToken.mint(owner, 1_000_000 ether);
        rewardToken.mint(admin, 1_000_000 ether);
        rewardToken.mint(updater, 1_000_000 ether);
        rewardToken.mint(user1, 1_000 ether);
        rewardToken.mint(user2, 1_000 ether);
        rewardToken.mint(user3, 1_000 ether);

        // Approve tokens
        rewardToken.approve(address(boopTheSnoot), 1_000_000 ether);
        vm.stopPrank();

        vm.prank(admin);
        rewardToken.approve(address(boopTheSnoot), 1_000_000 ether);

        vm.prank(updater);
        rewardToken.approve(address(boopTheSnoot), 1_000_000 ether);

        vm.prank(user1);
        rewardToken.approve(address(boopTheSnoot), 1_000 ether);

        vm.prank(user2);
        rewardToken.approve(address(boopTheSnoot), 1_000 ether);

        vm.prank(user3);
        rewardToken.approve(address(boopTheSnoot), 1_000 ether);

        // Whitelist tokens
        vm.prank(admin);
        boopTheSnoot.whitelistToken(address(rewardToken));

        vm.prank(admin);
        boopTheSnoot.whitelistToken(address(lpToken));

        // Create initial campaign for referral tests
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);

        // Mint LP tokens for referral tests
        lpToken.mint(user1, 100 ether);
        vm.stopPrank();

        vm.prank(user1);
        lpToken.approve(address(boopTheSnoot), 100 ether);
    }

    function test_MerkleRootUpdate() public {
        bytes32 newRoot = keccak256(abi.encodePacked("new merkle root"));

        vm.prank(updater);
        boopTheSnoot.updateGlobalRoot(newRoot);

        assertEq(boopTheSnoot.globalMerkleRoot(), newRoot);
    }

    function test_NonUpdaterCannotUpdateRoot() public {
        bytes32 newRoot = keccak256(abi.encodePacked("new merkle root"));

        vm.prank(user1);
        // Just check that it reverts, without checking the specific message
        vm.expectRevert();
        boopTheSnoot.updateGlobalRoot(newRoot);
    }

    function test_CannotCreateCampaignWithInvalidTiming() public {
        uint256 startTimestamp = block.timestamp + 3600;
        uint256 endTimestamp = startTimestamp - 60;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidCampaignDuration()"));
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 2000 ether
        );
    }

    function test_CannotCreateCampaignWithNonWhitelistedToken() public {
        MockERC20 fakeToken = new MockERC20("Fake Token", "FAKE");

        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidRewardToken()"));
        boopTheSnoot.createCampaign(
            address(fakeToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
    }

    function test_PreventWithdrawalBeforeCooldown() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        uint256 campaignId = boopTheSnoot.campaignCount() - 1;

        // Fast forward to just after campaign end but before cooldown
        vm.warp(endTimestamp + ADMIN_COOLDOWN_PERIOD - 10);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("CooldownPeriodNotPassed()"));
        boopTheSnoot.adminWithdrawUnclaimedRewards(campaignId);
    }

    function test_ComplexRewardClaimingWithInvalidProof() public {
        uint256 campaignId = boopTheSnoot.campaignCount() - 1;
        vm.warp(block.timestamp + 61); // Move past campaign start time

        bytes32 leaf = keccak256(abi.encodePacked(campaignId, user1, uint256(100 ether), "game"));

        vm.prank(updater);
        boopTheSnoot.updateGlobalRoot(leaf);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(1));

        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](1);
        claims[0] = BoopTheSnoot.RewardClaim({
            campaignId: campaignId,
            user: user1,
            amount: 100 ether,
            rewardType: BoopTheSnoot.RewardType.Game
        });

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = invalidProof;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        boopTheSnoot.claimRewards(claims, proofs);
    }

    function test_ComplexRewardClaimingWithValidProof() public {
        uint256 campaignId = boopTheSnoot.campaignCount() - 1;
        vm.warp(block.timestamp + 61); // Move past campaign start time

        bytes32 leaf = keccak256(abi.encodePacked(campaignId, user1, uint256(100 ether), "game"));

        vm.prank(updater);
        boopTheSnoot.updateGlobalRoot(leaf);

        bytes32[] memory proof = new bytes32[](0);
        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](1);
        claims[0] = BoopTheSnoot.RewardClaim({
            campaignId: campaignId,
            user: user1,
            amount: 100 ether,
            rewardType: BoopTheSnoot.RewardType.Game
        });

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = proof;

        uint256 initialBalance = rewardToken.balanceOf(user1);

        vm.prank(user1);
        boopTheSnoot.claimRewards(claims, proofs);

        uint256 finalBalance = rewardToken.balanceOf(user1);
        assertEq(finalBalance, initialBalance + 100 ether);
    }

    function test_AdminWithdrawalAfterCooldown() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        uint256 campaignId = boopTheSnoot.campaignCount() - 1;

        // Fast forward to after cooldown period
        vm.warp(endTimestamp + ADMIN_COOLDOWN_PERIOD + 10);

        uint256 initialBalance = rewardToken.balanceOf(admin);

        vm.expectEmit(true, false, true, true);
        emit UnclaimedRewardsWithdrawn(campaignId, 1000 ether, admin);

        vm.prank(admin);
        boopTheSnoot.adminWithdrawUnclaimedRewards(campaignId);

        uint256 finalBalance = rewardToken.balanceOf(admin);
        assertEq(finalBalance, initialBalance + 1000 ether);
    }

    function test_PreventDoubleAdminWithdrawal() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken), address(lpToken), 1 ether, startTimestamp, endTimestamp, 1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        uint256 campaignId = boopTheSnoot.campaignCount() - 1;

        // Fast forward to after cooldown period
        vm.warp(endTimestamp + ADMIN_COOLDOWN_PERIOD + 10);

        vm.startPrank(admin);
        boopTheSnoot.adminWithdrawUnclaimedRewards(campaignId);

        vm.expectRevert(abi.encodeWithSignature("AdminWithdrawalAlreadyDone()"));
        boopTheSnoot.adminWithdrawUnclaimedRewards(campaignId);
        vm.stopPrank();
    }

    function test_ReferralSuccess() public {
        uint256 lpAmount = 10 ether;

        address[] memory referees = new address[](1);
        referees[0] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmount;

        vm.expectEmit(true, true, false, true);
        emit ReferralMade(user1, user2, lpAmount);

        vm.prank(user1);
        boopTheSnoot.makeReferral(referees, amounts);

        assertEq(boopTheSnoot.referrerOf(user2), user1, "Referrer should be user1");

        address[] memory actualReferees = boopTheSnoot.getReferees(user1);
        assertEq(actualReferees.length, 1, "Should have one referee");
        assertEq(actualReferees[0], user2, "Referee should be user2");
    }

    function test_PreventSelfReferral() public {
        uint256 lpAmount = 10 ether;

        address[] memory referees = new address[](1);
        referees[0] = user1; // Self-referral
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmount;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("SelfReferralNotAllowed()"));
        boopTheSnoot.makeReferral(referees, amounts);
    }

    function test_PreventDuplicateReferral() public {
        uint256 lpAmount = 10 ether;

        address[] memory referees = new address[](1);
        referees[0] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmount;

        vm.startPrank(user1);
        boopTheSnoot.makeReferral(referees, amounts);

        vm.expectRevert(abi.encodeWithSignature("UserAlreadyReferred()"));
        boopTheSnoot.makeReferral(referees, amounts);
        vm.stopPrank();
    }

    function test_ReferralRewardClaim() public {
        // Setup initial referral
        uint256 lpAmount = 10 ether;

        address[] memory referees = new address[](1);
        referees[0] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmount;

        vm.prank(user1);
        boopTheSnoot.makeReferral(referees, amounts);

        // Setup referral reward claim
        uint256 referralAmount = 50 ether;
        bytes32 leaf = keccak256(abi.encodePacked(user1, referralAmount, "referral"));

        vm.prank(updater);
        boopTheSnoot.updateGlobalRoot(leaf);

        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](1);
        claims[0] = BoopTheSnoot.RewardClaim({
            campaignId: 0,
            user: user1,
            amount: referralAmount,
            rewardType: BoopTheSnoot.RewardType.Referral
        });

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        uint256 initialBalance = rewardToken.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(user1, 0, referralAmount);

        vm.prank(user1);
        boopTheSnoot.claimRewards(claims, proofs);

        uint256 finalBalance = rewardToken.balanceOf(user1);
        assertEq(finalBalance, initialBalance + referralAmount);
    }

    function test_PreventDoubleReferralRewardClaim() public {
        // Setup initial referral
        uint256 lpAmount = 10 ether;

        address[] memory referees = new address[](1);
        referees[0] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmount;

        vm.prank(user1);
        boopTheSnoot.makeReferral(referees, amounts);

        // Setup referral reward claim
        uint256 referralAmount = 50 ether;
        bytes32 leaf = keccak256(abi.encodePacked(user1, referralAmount, "referral"));

        vm.prank(updater);
        boopTheSnoot.updateGlobalRoot(leaf);

        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](1);
        claims[0] = BoopTheSnoot.RewardClaim({
            campaignId: 0,
            user: user1,
            amount: referralAmount,
            rewardType: BoopTheSnoot.RewardType.Referral
        });

        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);

        vm.startPrank(user1);
        boopTheSnoot.claimRewards(claims, proofs);

        vm.expectRevert(abi.encodeWithSignature("ExceedsEntitlement()"));
        boopTheSnoot.claimRewards(claims, proofs);
        vm.stopPrank();
    }
}
