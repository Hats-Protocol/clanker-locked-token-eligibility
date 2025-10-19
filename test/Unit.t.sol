// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { BaseTest, WithInstanceTest } from "./Base.t.sol";
import { ClankerPresaleLockedBalanceEligibilityModule } from "../src/ClankerPresaleLockedBalanceEligibilityModule.sol";
import { ClankerPresaleEthToCreatorLike } from "../src/lib/ClankerPresaleEthToCreatorLike.sol";

contract Deployment is WithInstanceTest {
  ClankerPresaleLockedBalanceEligibilityModule public instance2;

  function test_initialization() public {
    // implementation
    vm.expectRevert("Initializable: contract is already initialized");
    implementation.setUp("setUp attempt");
    // instance
    vm.expectRevert("Initializable: contract is already initialized");
    instance.setUp("setUp attempt");
  }

  function test_version() public {
    assertEq(instance.version(), MODULE_VERSION);
  }

  function test_implementation() public {
    assertEq(address(instance.IMPLEMENTATION()), address(implementation));
  }

  function test_hats() public {
    assertEq(address(instance.HATS()), address(HATS));
  }

  function test_hatId() public {
    assertEq(instance.hatId(), targetHatId);
  }

  function testFuzz_hatId(uint256 _hatId) public {
    instance = _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, presaleId, _hatId);
    assertEq(instance.hatId(), _hatId);
  }

  function test_immutable_clanker_presale_address() public {
    assertEq(instance.CLANKER_PRESALE_ADDRESS(), CLANKER_PRESALE);
  }

  function test_immutable_erc20_token_address() public {
    assertEq(instance.ERC20_TOKEN_ADDRESS(), address(mockToken));
  }

  function test_immutable_min_balance() public {
    assertEq(instance.MIN_BALANCE(), minBalance);
  }

  function testFuzz_min_balance(uint256 _minBalance) public {
    instance2 = _deployInstance(CLANKER_PRESALE, address(mockToken), _minBalance, presaleId, targetHatId);
    assertEq(instance2.MIN_BALANCE(), _minBalance);
  }

  function test_immutable_presale_id() public {
    assertEq(instance.CLANKER_PRESALE_ID(), presaleId);
  }

  function testFuzz_presale_id(uint256 _presaleId) public {
    instance2 = _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, _presaleId, targetHatId);
    assertEq(instance2.CLANKER_PRESALE_ID(), _presaleId);
  }

  function test_deployment_with_zero_erc20_address() public {
    instance2 = _deployInstance(address(0x5678), address(0), 500 ether, 2, targetHatId);
    assertEq(instance2.ERC20_TOKEN_ADDRESS(), address(0));
  }

  function test_deployment_with_zero_presale_address() public {
    instance2 = _deployInstance(address(0), address(mockToken), 500 ether, 2, targetHatId);
    assertEq(instance2.CLANKER_PRESALE_ADDRESS(), address(0));
  }

  function test_deployment_with_zero_min_balance() public {
    instance2 = _deployInstance(address(0x5678), address(mockToken), 0, 2, targetHatId);
    assertEq(instance2.MIN_BALANCE(), 0);
  }
}

contract EligibilityTests is BaseTest {
  // Use existing presale ID 1 on Base Sepolia (created at block 32445755)
  uint256 existingPresaleId = 1;

  function setUp() public virtual override {
    super.setUp();
    minBalance = 1000 ether;
  }

  /// @dev Test that a wearer is eligible if they have only exactly minBalance in ERC20 balance
  function test_eligible_with_only_erc20_balance() public {
    // Deploy instance with basic config (presale address doesn't matter for ERC20-only test)
    instance = _deployInstance(address(0), address(mockToken), minBalance, 0, targetHatId);

    // wearer1 has exactly min balance in ERC20
    deal(address(mockToken), wearer1, minBalance);

    (bool eligible, bool standing) = instance.getWearerStatus(wearer1, targetHatId);

    assertTrue(eligible);
    assertTrue(standing);
  }

  /// @dev Test that a wearer is eligible if they have only exactly minBalance in Clanker presale locked balance
  function test_eligible_with_only_clanker_presale_locked_balance() public {
    // Buy tokens and advance presale to claimable status
    _buyTokensFromPresale(existingPresaleId, wearer1, minBalance);

    // Verify wearer1 has NO ERC20 balance in mockToken (tokens are locked)
    assertEq(mockToken.balanceOf(wearer1), 0, "Should have no ERC20 balance");

    // Deploy instance configured for presale ID 1
    instance = _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, existingPresaleId, targetHatId);

    // Check eligibility - should be eligible with exactly minBalance locked tokens
    (bool eligible, bool standing) = instance.getWearerStatus(wearer1, targetHatId);

    assertTrue(eligible, "Should be eligible with exactly minBalance locked tokens");
    assertTrue(standing, "Standing should always be true");
  }

  /// @dev Test that a wearer is eligible if they have more than minBalance in ERC20 balance
  function test_eligible_with_erc20_above_threshold() public {
    // Deploy instance with basic config
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(address(0), address(mockToken), minBalance, 0, targetHatId);

    // wearer1 has more than min balance
    deal(address(mockToken), wearer1, minBalance + 1);

    (bool eligible, bool standing) = instance.getWearerStatus(wearer1, targetHatId);

    assertTrue(eligible, "Should be eligible with more than min balance in ERC20");
    assertTrue(standing, "Standing should always be true");
  }

  function test_ineligible_below_threshold() public {
    // Deploy instance with basic config
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(address(0), address(mockToken), minBalance, 0, targetHatId);

    // wearer1 has less than min balance
    deal(address(mockToken), wearer1, minBalance - 1);

    (bool eligible, bool standing) = instance.getWearerStatus(wearer1, targetHatId);

    assertFalse(eligible, "Should be ineligible with less than min balance in ERC20");
    assertTrue(standing, "Standing should always be true");
  }

  function test_standing_always_true() public {
    // Deploy instance with basic config
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(address(0), address(mockToken), minBalance, 0, targetHatId);

    // Test with no balance
    (, bool standing1) = instance.getWearerStatus(wearer1, targetHatId);
    assertTrue(standing1);

    // Test with balance
    deal(address(mockToken), wearer2, minBalance);
    (, bool standing2) = instance.getWearerStatus(wearer2, targetHatId);
    assertTrue(standing2);

    // Test with huge balance
    deal(address(mockToken), wearer3, minBalance * 1000);
    (, bool standing3) = instance.getWearerStatus(wearer3, targetHatId);
    assertTrue(standing3);
  }

  function test_multiple_wearers_independent() public {
    // Deploy instance with basic config
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(address(0), address(mockToken), minBalance, 0, targetHatId);

    // Set different balances for different wearers
    deal(address(mockToken), wearer1, minBalance - 1);
    deal(address(mockToken), wearer2, minBalance);
    deal(address(mockToken), wearer3, minBalance + 1);

    (bool eligible1,) = instance.getWearerStatus(wearer1, targetHatId);
    (bool eligible2,) = instance.getWearerStatus(wearer2, targetHatId);
    (bool eligible3,) = instance.getWearerStatus(wearer3, targetHatId);

    assertFalse(eligible1, "Should be ineligible with less than min balance in ERC20");
    assertTrue(eligible2, "Should be eligible with exactly min balance in ERC20");
    assertTrue(eligible3, "Should be eligible with more than min balance in ERC20");
  }

  /// @dev Test that a wearer is eligible if they have some ERC20 and some locked balance that together meet minimum,
  /// but each alone is insufficient
  function test_eligible_with_combined_erc20_and_locked_balance() public {
    // Calculate split: wearer1 will have 60% from ERC20, 40% from locked presale
    uint256 erc20Amount = (minBalance * 60) / 100;
    uint256 lockedAmount = minBalance - erc20Amount; // This ensures total equals minBalance

    // Verify each is insufficient alone
    assertLt(erc20Amount, minBalance, "ERC20 amount should be less than minBalance");
    assertLt(lockedAmount, minBalance, "Locked amount should be less than minBalance");
    assertEq(erc20Amount + lockedAmount, minBalance, "Combined should equal minBalance");

    // Buy locked tokens from presale for wearer1
    _buyTokensFromPresale(existingPresaleId, wearer1, lockedAmount);

    // Give wearer1 some ERC20 balance
    deal(address(mockToken), wearer1, erc20Amount);

    // Deploy instance configured for both ERC20 and presale
    instance = _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, existingPresaleId, targetHatId);

    // Check eligibility - should be eligible with combined balance
    (bool eligible, bool standing) = instance.getWearerStatus(wearer1, targetHatId);

    assertTrue(eligible, "Should be eligible with combined ERC20 and locked balance");
    assertTrue(standing, "Standing should always be true");
  }

  function test_presale_locked_balance_with_claimable_status() public {
    // Test that locked balance is counted when presale is Claimable
    _buyTokensFromPresale(existingPresaleId, wearer1, minBalance);

    // Deploy instance
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(CLANKER_PRESALE, address(0), minBalance, existingPresaleId, targetHatId);

    // Verify presale is claimable and wearer has locked tokens
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);
    assertEq(uint8(presale.status), uint8(PresaleStatus.Claimable), "Presale should be Claimable");

    (bool eligible,) = instance.getWearerStatus(wearer1, targetHatId);
    assertTrue(eligible, "Should be eligible with locked balance in claimable presale");
  }

  function test_presale_locked_balance_ignores_non_claimable() public {
    // Test that locked balance is NOT counted when presale is not Claimable (Active status)
    // Get presale details - it should be Active at fork block
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);

    // If already ended, skip this test
    // if (block.timestamp >= presale.endTime) {
    //   vm.skip(true);
    //   return;
    // }

    assertEq(uint8(presale.status), uint8(PresaleStatus.Active), "Presale should be Active");

    // Buy into presale but don't end it
    uint256 ethAmount = _calculateEthForTokens(presale, minBalance);
    _buyIntoPresale(existingPresaleId, wearer1, ethAmount);

    // Deploy instance
    ClankerPresaleLockedBalanceEligibilityModule instance =
      _deployInstance(CLANKER_PRESALE, address(0), minBalance, existingPresaleId, targetHatId);

    // Should be ineligible because presale is still Active (not Claimable)
    (bool eligible,) = instance.getWearerStatus(wearer1, targetHatId);
    assertFalse(eligible, "Should be ineligible when presale is Active (not Claimable)");
  }

  function test_locked_balance_calculation_math() public {
    // Buy a specific amount and verify the locked balance calculation
    uint256 desiredTokens = minBalance;
    _buyTokensFromPresale(existingPresaleId, wearer1, desiredTokens);

    // Get presale data
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(existingPresaleId);
    uint256 ethBought = presaleContract.presaleBuys(existingPresaleId, wearer1);
    uint256 ethClaimed = presaleContract.presaleClaimed(existingPresaleId, wearer1);
    uint256 lockedEth = ethBought - ethClaimed;

    // Calculate expected token amount using the presale's formula
    // tokensReceived = (ethBought * allocatedSupply) / totalEthRaised
    uint256 extensionBps =
      presale.deploymentConfig.extensionConfigs[presale.deploymentConfig.extensionConfigs.length - 1].extensionBps;
    uint256 allocatedSupply = (TOTAL_TOKEN_SUPPLY * extensionBps) / 10_000;
    uint256 expectedLockedTokens = (lockedEth * allocatedSupply) / presale.ethRaised;

    // The locked tokens should be >= desiredTokens (might be slightly more due to rounding)
    assertGe(expectedLockedTokens, desiredTokens, "Locked tokens should be >= desired amount");

    // Verify it's within 1% tolerance (accounting for approximation in ethRaised calculation)
    uint256 tolerance = desiredTokens / 100;
    assertLe(expectedLockedTokens - desiredTokens, tolerance, "Locked tokens should be close to desired amount");
  }
}

