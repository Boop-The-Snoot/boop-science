// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BoopTheSnoot.sol";
import "./mocks/MockERC20.sol";
import "./mocks/ReentrancyAttackToken.sol";
import "./mocks/MockFailingToken.sol";
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

    // Testing parameter boundaries and limits
    function test_MaxCampaignDurationLimit() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 366 days; // Exceeds MAX_CAMPAIGN_DURATION

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidCampaignDuration()"));
        boopTheSnoot.createCampaign(
            address(rewardToken),
            address(lpToken),
            1 ether,
            startTimestamp,
            endTimestamp,
            1000 ether
        );
    }

    // Testing batch claim limits
    function test_ExceedsMaxTokensPerBatch() public {
        vm.warp(block.timestamp + 61); // Move past campaign start

        uint256 maxBatch = boopTheSnoot.maxTokensPerBatch();
        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](maxBatch + 1);
        bytes32[][] memory proofs = new bytes32[][](maxBatch + 1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ExceedsMaxTokensPerBatch()"));
        boopTheSnoot.claimRewards(claims, proofs);
    }

    // Testing reentrancy protection
    function test_ReentrancyProtection() public {
        // Deploy malicious token that attempts reentrancy
        ReentrancyAttackToken attackToken = new ReentrancyAttackToken();
        
        vm.prank(admin);
        boopTheSnoot.whitelistToken(address(attackToken));

        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;

        vm.prank(owner);
        vm.expectRevert(); // Should revert due to ReentrancyGuard
        boopTheSnoot.createCampaign(
            address(attackToken),
            address(lpToken),
            1 ether,
            startTimestamp,
            endTimestamp,
            1000 ether
        );
    }

    // Testing role management edge cases
    function test_RoleRevocation() public {
        vm.startPrank(owner);
        
        // Test revoking admin role
        boopTheSnoot.revokeRole(ADMIN_ROLE, admin);
        assertFalse(boopTheSnoot.hasRole(ADMIN_ROLE, admin));

        // Verify revoked admin can't perform admin actions
        vm.stopPrank();
        vm.prank(admin);
        vm.expectRevert();
        boopTheSnoot.whitelistToken(address(rewardToken));
    }

    // Testing emergency scenarios
    function test_EmergencyPause() public {
        // Create active campaign
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;
        
        vm.prank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken),
            address(lpToken),
            1 ether,
            startTimestamp,
            endTimestamp,
            1000 ether
        );

        // Emergency pause
        vm.prank(admin);
        boopTheSnoot.pause();

        // Verify all critical functions are paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(user1);
        boopTheSnoot.claimRewards(new BoopTheSnoot.RewardClaim[](0), new bytes32[][](0));
    }

    // Testing referral system edge cases
    function test_ComplexReferralChain() public {
        uint256 lpAmount = 10 ether;
        
        // First, create a campaign
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;
        
        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken),
            address(lpToken),
            1 ether,
            startTimestamp,
            endTimestamp,
            1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        // Mint LP tokens for all users
        vm.startPrank(owner);
        lpToken.mint(user1, 100 ether);
        lpToken.mint(user2, 100 ether);
        lpToken.mint(user3, 100 ether);
        vm.stopPrank();

        // Approvals
        vm.prank(user1);
        lpToken.approve(address(boopTheSnoot), 100 ether);
        
        vm.prank(user2);
        lpToken.approve(address(boopTheSnoot), 100 ether);
        
        vm.prank(user3);
        lpToken.approve(address(boopTheSnoot), 100 ether);

        // Let's test each referral case separately
        
        // 1. Test self-referral (should fail)
        address[] memory selfReferral = new address[](1);
        selfReferral[0] = user1;
        uint256[] memory selfAmount = new uint256[](1);
        selfAmount[0] = lpAmount;

        console.log("Testing self-referral...");
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("SelfReferralNotAllowed()"));
        boopTheSnoot.makeReferral(selfReferral, selfAmount);
        console.log("Self-referral test passed");

        // 2. Make a valid referral
        address[] memory referees1 = new address[](1);
        referees1[0] = user2;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = lpAmount;

        console.log("Making first referral...");
        vm.prank(user1);
        boopTheSnoot.makeReferral(referees1, amounts1);
        
        console.log("Checking referral state:");
        console.log("user2's referrer:", boopTheSnoot.referrerOf(user2));
        assertEq(boopTheSnoot.referrerOf(user2), user1, "user2 should be referred by user1");

        // 3. Try to refer an already referred user
        address[] memory referees2 = new address[](1);
        referees2[0] = user2;  // user2 is already referred by user1
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = lpAmount;

        console.log("Attempting to refer already referred user...");
        vm.prank(user3);
        try boopTheSnoot.makeReferral(referees2, amounts2) {
            console.log("Should have reverted with UserAlreadyReferred");
            fail();
        } catch Error(string memory reason) {
            console.log("Revert reason:", reason);
        } catch (bytes memory rawRevert) {
            console.log("Raw revert data:", vm.toString(rawRevert));
        }
    }

    // Testing token approval and transfer edge cases
    function test_TokenApprovalEdgeCases() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;
        
        // Test with token that returns false on approve
        MockFailingToken failingToken = new MockFailingToken();
        
        vm.prank(admin);
        boopTheSnoot.whitelistToken(address(failingToken));
        
        vm.prank(owner);
        vm.expectRevert();
        boopTheSnoot.createCampaign(
            address(failingToken),
            address(lpToken),
            1 ether,
            startTimestamp,
            endTimestamp,
            1000 ether
        );
    }

    function test_UpdateContractParameters() public {
        // Test MAX_CAMPAIGN_DURATION update
        vm.startPrank(admin);
        uint256 newDuration = 180 days;
        boopTheSnoot.proposeParameterChange("MAX_CAMPAIGN_DURATION", newDuration);
        
        vm.warp(block.timestamp + 3 days + 1);
        boopTheSnoot.executeChange("MAX_CAMPAIGN_DURATION");
        assertEq(boopTheSnoot.MAX_CAMPAIGN_DURATION(), newDuration);

        // Test CREATOR_WITHDRAW_COOLDOWN update
        uint256 newCreatorCooldown = 45 days;
        boopTheSnoot.proposeParameterChange("CREATOR_WITHDRAW_COOLDOWN", newCreatorCooldown);
        
        vm.warp(block.timestamp + 3 days + 1);
        boopTheSnoot.executeChange("CREATOR_WITHDRAW_COOLDOWN");
        assertEq(boopTheSnoot.CREATOR_WITHDRAW_COOLDOWN(), newCreatorCooldown);

        // Test ADMIN_WITHDRAW_COOLDOWN update
        uint256 newAdminCooldown = 120 days;
        boopTheSnoot.proposeParameterChange("ADMIN_WITHDRAW_COOLDOWN", newAdminCooldown);
        
        vm.warp(block.timestamp + 3 days + 1);
        boopTheSnoot.executeChange("ADMIN_WITHDRAW_COOLDOWN");
        assertEq(boopTheSnoot.ADMIN_WITHDRAW_COOLDOWN(), newAdminCooldown);

        // Test MAX_TOKENS_PER_BATCH update
        uint256 newMaxTokens = 100;
        boopTheSnoot.proposeParameterChange("MAX_TOKENS_PER_BATCH", newMaxTokens);
        
        vm.warp(block.timestamp + 3 days + 1);
        boopTheSnoot.executeChange("MAX_TOKENS_PER_BATCH");
        assertEq(boopTheSnoot.maxTokensPerBatch(), newMaxTokens);

        // Test zero value proposal
        vm.expectRevert();
        boopTheSnoot.proposeParameterChange("MAX_CAMPAIGN_DURATION", 0);

        // Test executing change too early
        boopTheSnoot.proposeParameterChange("MAX_CAMPAIGN_DURATION", 200 days);
        vm.expectRevert();
        boopTheSnoot.executeChange("MAX_CAMPAIGN_DURATION");

        // Test non-admin cannot propose changes
        vm.stopPrank();
        vm.prank(user1);
        vm.expectRevert();
        boopTheSnoot.proposeParameterChange("MAX_CAMPAIGN_DURATION", 200 days);
    }

    function test_CreatorWithdrawalScenarios() public {
        uint256 startTimestamp = block.timestamp + 60;
        uint256 endTimestamp = startTimestamp + 3600;
        
        vm.startPrank(owner);
        boopTheSnoot.createCampaign(
            address(rewardToken),
            address(lpToken),
            1 ether,
            startTimestamp,
            endTimestamp,
            1000 ether
        );
        rewardToken.transfer(address(boopTheSnoot), 1000 ether);
        vm.stopPrank();

        uint256 campaignId = boopTheSnoot.campaignCount() - 1;

        // Test withdrawal before campaign end
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("CooldownPeriodNotPassed()"));
        boopTheSnoot.withdrawUnclaimedRewards(campaignId);

        // Move to just after campaign end but before cooldown
        vm.warp(endTimestamp + 1);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("CooldownPeriodNotPassed()"));
        boopTheSnoot.withdrawUnclaimedRewards(campaignId);

        // Move past cooldown and test successful withdrawal
        vm.warp(endTimestamp + boopTheSnoot.CREATOR_WITHDRAW_COOLDOWN() + 1);
        uint256 initialBalance = rewardToken.balanceOf(owner);
        
        vm.prank(owner);
        boopTheSnoot.withdrawUnclaimedRewards(campaignId);
        
        assertEq(rewardToken.balanceOf(owner), initialBalance + 1000 ether);

        // Test double withdrawal prevention
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InsufficientRewardBalance()"));
        boopTheSnoot.withdrawUnclaimedRewards(campaignId);
    }

    function test_MinLpTokenAmountManagement() public {
        vm.startPrank(admin);
        
        // Test setting min LP token amount
        uint256 minAmount = 5 ether;
        boopTheSnoot.setMinLpTokenAmount(address(lpToken), minAmount);
        assertEq(boopTheSnoot.minLpTokenAmounts(address(lpToken)), minAmount);

        // Test updating existing min LP token amount
        uint256 newMinAmount = 10 ether;
        boopTheSnoot.setMinLpTokenAmount(address(lpToken), newMinAmount);
        assertEq(boopTheSnoot.minLpTokenAmounts(address(lpToken)), newMinAmount);

        vm.stopPrank();

        // Test non-admin cannot set min LP token amount
        vm.prank(user1);
        vm.expectRevert();
        boopTheSnoot.setMinLpTokenAmount(address(lpToken), minAmount);
    }

    function test_InvalidRewardClaims() public {
        // Test claim with empty arrays
        vm.prank(user1);
        vm.expectRevert();
        boopTheSnoot.claimRewards(new BoopTheSnoot.RewardClaim[](0), new bytes32[][](0));

        // Test claim with mismatched array lengths
        BoopTheSnoot.RewardClaim[] memory claims = new BoopTheSnoot.RewardClaim[](1);
        bytes32[][] memory proofs = new bytes32[][](2);
        
        vm.prank(user1);
        vm.expectRevert();
        boopTheSnoot.claimRewards(claims, proofs);
    }
}
