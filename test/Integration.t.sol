// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { BaseTest } from "./Base.t.sol";
import { ClankerPresaleLockedBalanceEligibilityModule } from "../src/ClankerPresaleLockedBalanceEligibilityModule.sol";
import { ClankerPresaleEthToCreatorLike } from "../src/lib/ClankerPresaleEthToCreatorLike.sol";

contract IntegrationTests is BaseTest {
  uint256 existingPresaleId = 1;

  function setUp() public virtual override {
    super.setUp();
    minBalance = 1000 ether;
  }

  /// @dev Integration test: buyer claims tokens and becomes ineligible
  function test_integration_claim_affects_eligibility_different_tokens() public {
    // Setup: buy tokens and make presale claimable
    _buyTokensFromPresale(existingPresaleId, wearer1, minBalance);

    // Deploy module instance
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, existingPresaleId, targetHatId);

    // Verify eligible before claim
    (bool eligibleBefore,) = instance.getWearerStatus(wearer1, targetHatId);
    assertTrue(eligibleBefore, "Should be eligible with locked balance");

    // Warp past lockup end time
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);
    vm.warp(presale.lockupEndTime + 1);

    // Claim tokens from presale
    vm.prank(wearer1);
    presaleContract.claimTokens(existingPresaleId);

    // Verify ineligible after claim (no ERC20 balance, no locked balance)
    (bool eligibleAfter,) = instance.getWearerStatus(wearer1, targetHatId);
    assertFalse(eligibleAfter, "Should be ineligible after claiming");

    // Note: The presale token is different from the ERC20 token on the module
    // Claiming from presale gives you the presale token, not the module's ERC20 token
  }

  /// @dev Integration test: claim does not affect eligibility when the ERC20 token is the same as the presale token
  function test_integration_claim_does_not_affect_eligibility_same_token() public {
    // Setup: buy tokens and make presale claimable
    _buyTokensFromPresale(existingPresaleId, wearer1, minBalance);

    // get the address of the presale token
    address deployedTokenAddress = presaleContract.getPresale(existingPresaleId).deployedToken;

    // Deploy module instance
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(CLANKER_PRESALE, deployedTokenAddress, minBalance, existingPresaleId, targetHatId);

    // Verify eligible before claim
    (bool eligibleBefore,) = instance.getWearerStatus(wearer1, targetHatId);
    assertTrue(eligibleBefore, "Should be eligible with locked balance");

    // Warp past lockup end time
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);
    vm.warp(presale.lockupEndTime + 1);

    // Claim tokens from presale
    vm.prank(wearer1);
    presaleContract.claimTokens(existingPresaleId);

    // Verify eligible after claim, since they now have sufficient ERC20 (presale token) balance
    (bool eligibleAfter,) = instance.getWearerStatus(wearer1, targetHatId);
    assertTrue(eligibleAfter, "Should be eligible after claiming");
  }

  /// @dev Integration test: claim + ERC20 balance combined
  function test_integration_claim_then_erc20_restores_eligibility() public {
    // Setup: buy tokens and make presale claimable
    _buyTokensFromPresale(existingPresaleId, wearer2, minBalance);

    // Deploy module instance
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, existingPresaleId, targetHatId);

    // Warp past lockup end time
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);
    vm.warp(presale.lockupEndTime + 1);

    // Claim all locked tokens
    vm.prank(wearer2);
    presaleContract.claimTokens(existingPresaleId);

    // Should be ineligible now
    (bool eligibleAfterClaim,) = instance.getWearerStatus(wearer2, targetHatId);
    assertFalse(eligibleAfterClaim, "Should be ineligible after claiming");

    // Give ERC20 balance (separate from presale token)
    deal(address(mockToken), wearer2, minBalance);

    // Should be eligible again with ERC20 balance
    (bool eligibleAfterERC20,) = instance.getWearerStatus(wearer2, targetHatId);
    assertTrue(eligibleAfterERC20, "Should be eligible with ERC20 balance");
  }

  /// @dev Integration test: multiple buyers with different claim states
  function test_integration_multiple_buyers_different_states() public {
    // Get presale details
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);

    // Check if presale is still active (not ended)
    if (block.timestamp >= presale.endTime) {
      vm.skip(true);
      return;
    }

    assertEq(uint8(presale.status), uint8(PresaleStatus.Active), "Presale should be Active");

    // To avoid dilution issues with multiple buyers and the min goal top-up,
    // we'll use a simpler strategy: each buyer buys enough ETH to comfortably
    // exceed minBalance even after all dilution factors (other buyers + min goal top-up)

    // Strategy: Have each buyer buy a significant amount of ETH (not tokens)
    // This ensures that regardless of dilution, they'll have enough tokens
    uint256 ethToBuy = 1 ether; // Each buyer puts in 1 ETH

    // Wearer1: buys into the presale
    _buyIntoPresale(existingPresaleId, wearer1, ethToBuy);

    // Wearer2: buys into the presale
    _buyIntoPresale(existingPresaleId, wearer2, ethToBuy);

    // Refresh presale data after both buys
    presale = presaleContract.getPresale(existingPresaleId);

    // Ensure minimum goal is met and end the presale (making it claimable)
    presale = _ensurePresaleMinGoalMet(existingPresaleId, presale);
    _endPresaleAndMakeClaimable(
      existingPresaleId, presale, keccak256(abi.encode("presale", existingPresaleId, "multi"))
    );

    // Refresh presale to get final state
    presale = presaleContract.getPresale(existingPresaleId);

    // Verify both wearers have enough locked balance
    uint256 wearer1EthBought = presaleContract.presaleBuys(existingPresaleId, wearer1);
    uint256 wearer2EthBought = presaleContract.presaleBuys(existingPresaleId, wearer2);

    // Calculate actual token amounts based on final ETH raised
    uint256 wearer1Tokens = (wearer1EthBought * presale.tokenSupply) / presale.ethRaised;
    uint256 wearer2Tokens = (wearer2EthBought * presale.tokenSupply) / presale.ethRaised;

    assertGe(wearer1Tokens, minBalance, "Wearer1 should have at least minBalance tokens");
    assertGe(wearer2Tokens, minBalance, "Wearer2 should have at least minBalance tokens");

    // Wearer3: has only ERC20 (eligible)
    deal(address(mockToken), wearer3, minBalance);

    // Deploy instance
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, existingPresaleId, targetHatId);

    // Warp past lockup end time
    vm.warp(presale.lockupEndTime + 1);

    // Wearer2 claims all their tokens
    vm.prank(wearer2);
    presaleContract.claimTokens(existingPresaleId);

    // Check all three wearers
    (bool eligible1,) = instance.getWearerStatus(wearer1, targetHatId);
    (bool eligible2,) = instance.getWearerStatus(wearer2, targetHatId);
    (bool eligible3,) = instance.getWearerStatus(wearer3, targetHatId);

    assertTrue(eligible1, "Wearer1 should be eligible (locked tokens, not claimed)");
    assertFalse(eligible2, "Wearer2 should be ineligible (claimed all, no ERC20)");
    assertTrue(eligible3, "Wearer3 should be eligible (ERC20 balance)");
  }
}

