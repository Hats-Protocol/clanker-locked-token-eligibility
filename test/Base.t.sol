// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { ClankerPresaleLockedBalanceEligibilityModule } from "../src/ClankerPresaleLockedBalanceEligibilityModule.sol";
import { Deploy } from "../script/Deploy.s.sol";
import {
  HatsModuleFactory,
  IHats,
  deployModuleInstance,
  deployModuleFactory
} from "hats-module/utils/DeployFunctions.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { ClankerPresaleEthToCreatorLike } from "../src/lib/ClankerPresaleEthToCreatorLike.sol";
import {
  IClanker,
  IClankerPresaleEthToCreator
} from "../lib/v4-contracts/src/extensions/interfaces/IClankerPresaleEthToCreator.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BaseTest is Test {
  ClankerPresaleLockedBalanceEligibilityModule public implementation;
  bytes32 public SALT = bytes32(abi.encode(0x1234));

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 32_445_755; // tx block for presaleId 1

  // Existing Base Sepolia contracts
  IHats public HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137);
  HatsModuleFactory public factory = HatsModuleFactory(0x0a3f85fa597B6a967271286aA0724811acDF5CD9); // Base Sepolia
  address public CLANKER_PRESALE = 0x3bF4085A60Fe1DC2B3c82Bf404DC7F23340534d5;
  ClankerPresaleEthToCreatorLike public presaleContract = ClankerPresaleEthToCreatorLike(CLANKER_PRESALE);
  uint256 public constant TOTAL_TOKEN_SUPPLY = 100_000_000 ether;

  ClankerPresaleLockedBalanceEligibilityModule public instance;

  MockERC20 public mockToken;

  bytes public otherImmutableArgs;
  bytes public initArgs;
  uint256 public topHatId;
  uint256 public targetHatId;
  uint256 public saltNonce;
  uint256 public minBalance;
  uint256 public presaleId;

  address public org = makeAddr("org");
  address public wearer1 = makeAddr("wearer1");
  address public wearer2 = makeAddr("wearer2");
  address public wearer3 = makeAddr("wearer3");

  string public MODULE_VERSION = "test";

  enum PresaleStatus {
    NotCreated,
    Active,
    SuccessfulMinimumHit,
    SuccessfulMaximumHit,
    Failed,
    Claimable
  }

  function _deployImplementation(Deploy _deployScript) internal returns (ClankerPresaleLockedBalanceEligibilityModule) {
    _deployScript.prepare(false, MODULE_VERSION);
    _deployScript.run();
    return _deployScript.implementation();
  }

  function setUp() public virtual {
    // Fork Base Sepolia to use real contracts
    fork = vm.createSelectFork(vm.rpcUrl("base_sepolia"), BLOCK_NUMBER);

    // deploy implementation via the script
    Deploy deployScript = new Deploy();
    implementation = _deployImplementation(deployScript);

    // deploy mock ERC20 token for unit tests
    mockToken = new MockERC20("Mock Token", "MTK");

    // Set up test hats
    vm.startPrank(org);
    topHatId = HATS.mintTopHat(org, "tophat", "http://www.tophat.com/");
    targetHatId = HATS.createHat(topHatId, "targetHat", 10, address(1), address(1), false, "http://www.targethat.com/");
    HATS.mintHat(targetHatId, wearer1);
    HATS.mintHat(targetHatId, wearer2);
    vm.stopPrank();
  }

  function _deployInstance(
    address _presaleAddress,
    address _tokenAddress,
    uint256 _minBalance,
    uint256 _presaleId,
    uint256 _hatId
  ) internal returns (ClankerPresaleLockedBalanceEligibilityModule) {
    // set up the other immutable args
    // Addresses are padded to 32 bytes (uint256) as per the module's immutable args table
    otherImmutableArgs = abi.encodePacked(_presaleAddress, _tokenAddress, _minBalance, _presaleId);

    // set up the init args (empty for this module)
    initArgs = abi.encode();

    // set up the salt nonce
    saltNonce++;

    // deploy an instance of the module
    return ClankerPresaleLockedBalanceEligibilityModule(
      deployModuleInstance(factory, address(implementation), _hatId, otherImmutableArgs, initArgs, saltNonce)
    );
  }

  /// @dev Helper to start a new presale
  /// @param _minEthGoal The minimum ETH goal
  /// @param _maxEthGoal The maximum ETH goal
  /// @param _duration The presale duration
  /// @param _recipient The ETH recipient
  /// @param _lockupDuration The lockup duration (minimum 7 days)
  /// @param _vestingDuration The vesting duration (0 for no vesting)
  /// @return newPresaleId The newly created presale ID
  function _startPresale(
    uint256 _minEthGoal,
    uint256 _maxEthGoal,
    uint256 _duration,
    address _recipient,
    uint256 _lockupDuration,
    uint256 _vestingDuration
  ) internal returns (uint256 newPresaleId) {
    // Create deployment config for the token (copying values from presale ID 1)
    IClanker.DeploymentConfig memory deploymentConfig;

    // Set token config
    deploymentConfig.tokenConfig = IClanker.TokenConfig({
      tokenAdmin: _recipient,
      name: "Test Token",
      symbol: "TEST",
      salt: bytes32(0),
      image: "https://example.com/image.png",
      metadata: '{"description":"Test token"}',
      context: '{"test":"true"}',
      originatingChainId: block.chainid
    });

    // Set pool config (minimal for test)
    deploymentConfig.poolConfig = IClanker.PoolConfig({
      hook: address(0), pairedToken: address(0), tickIfToken0IsClanker: 0, tickSpacing: 200, poolData: ""
    });

    // Set locker config (minimal)
    deploymentConfig.lockerConfig = IClanker.LockerConfig({
      locker: address(0),
      rewardAdmins: new address[](0),
      rewardRecipients: new address[](0),
      rewardBps: new uint16[](0),
      tickLower: new int24[](0),
      tickUpper: new int24[](0),
      positionBps: new uint16[](0),
      lockerData: ""
    });

    // Set mev module config (minimal)
    deploymentConfig.mevModuleConfig = IClanker.MevModuleConfig({ mevModule: address(0), mevModuleData: "" });

    // Set extension config with presale
    deploymentConfig.extensionConfigs = new IClanker.ExtensionConfig[](1);
    deploymentConfig.extensionConfigs[0] = IClanker.ExtensionConfig({
      extension: CLANKER_PRESALE,
      msgValue: 0,
      extensionBps: 1000, // 10%
      extensionData: ""
    });

    // Start the presale
    address presaleOwner = makeAddr("presaleOwner");

    // Get the actual owner of the presale contract to set admin permissions
    address contractOwner = address(0x8F7EF51CF06f00aA796E8cdA498D712D4ecFE8E1);

    // Owner sets the presaleOwner as admin
    vm.prank(contractOwner);
    presaleContract.setAdmin(presaleOwner, true);

    // Now presaleOwner can start the presale
    vm.startPrank(presaleOwner);
    newPresaleId = presaleContract.startPresale(
      deploymentConfig,
      _minEthGoal,
      _maxEthGoal,
      _duration,
      _recipient,
      _lockupDuration,
      _vestingDuration,
      address(0), // allowlist
      "" // allowlistInitializationData
    );
    vm.stopPrank();
  }

  /// @dev Helper to calculate exact ETH needed to receive a specific amount of tokens
  /// @param _presale The presale details
  /// @param _desiredTokenAmount The exact amount of tokens desired
  /// @return ethNeeded The amount of ETH needed to buy to get exactly _desiredTokenAmount tokens
  function _calculateEthForTokens(ClankerPresaleEthToCreatorLike.Presale memory _presale, uint256 _desiredTokenAmount)
    internal
    pure
    returns (uint256 ethNeeded)
  {
    // Calculate the token supply allocated to presale from extension BPS
    // Total token supply is 100M * 10^18, presale gets extensionBps/10000 of that
    uint256 extensionBps =
      _presale.deploymentConfig.extensionConfigs[_presale.deploymentConfig.extensionConfigs.length - 1].extensionBps;
    uint256 allocatedSupply = (TOTAL_TOKEN_SUPPLY * extensionBps) / 10_000;

    // Calculate exact ETH needed to get _desiredTokenAmount tokens
    // Formula: tokensReceived = (ethBought * allocatedSupply) / (ethRaised + ethBought)
    // Solving for ethBought: ethBought = (_desiredTokenAmount * ethRaised) / (allocatedSupply - _desiredTokenAmount)
    uint256 ethRaised = _presale.ethRaised;

    require(allocatedSupply > _desiredTokenAmount, "Allocated supply must be greater than desired amount");

    // Special case: if no ETH has been raised yet, we can't calculate the exact amount
    // In this case, approximate by using a small initial purchase amount
    if (ethRaised == 0) {
      // Return a simple proportion: (desiredTokens / allocatedSupply) * minGoal
      // This is an approximation that works when starting from zero
      ethNeeded = (_desiredTokenAmount * _presale.minEthGoal) / allocatedSupply;
      if (ethNeeded == 0) ethNeeded = 1; // Ensure at least 1 wei
    } else {
      ethNeeded = (_desiredTokenAmount * ethRaised) / (allocatedSupply - _desiredTokenAmount);
    }
  }

  /// @dev Helper to buy into a presale
  /// @param _presaleId The presale ID to buy into
  /// @param _buyer The address buying tokens
  /// @param _amount The amount of ETH to spend
  function _buyIntoPresale(uint256 _presaleId, address _buyer, uint256 _amount) internal {
    // Give the buyer some ETH
    vm.deal(_buyer, _amount);

    // Buy into the presale
    vm.prank(_buyer);
    presaleContract.buyIntoPresale{ value: _amount }(_presaleId);
  }

  /// @dev Helper to ensure a presale meets its minimum goal
  /// @param _presaleId The prescale ID to check
  /// @param _presale The presale details (will be updated if a top-up buy occurs)
  /// @dev If the min goal isn't met, a backup account will contribute the remaining amount
  /// @return updated Updated presale details after ensuring min goal is met
  function _ensurePresaleMinGoalMet(uint256 _presaleId, ClankerPresaleEthToCreatorLike.Presale memory _presale)
    internal
    returns (ClankerPresaleEthToCreatorLike.Presale memory updated)
  {
    if (_presale.ethRaised < _presale.minEthGoal) {
      uint256 remainingNeeded = _presale.minEthGoal - _presale.ethRaised;
      _buyIntoPresale(_presaleId, address(0x9999), remainingNeeded);
      // Refresh after state change
      updated = presaleContract.getPresale(_presaleId);
    } else {
      updated = _presale;
    }

    require(updated.ethRaised >= updated.minEthGoal, "Min goal not met");
  }

  /// @dev Helper to move a presale to claimable status
  /// @param _presaleId The presale ID to end
  /// @param _presale The presale details
  /// @param _salt The salt for token deployment
  function _endPresaleAndMakeClaimable(
    uint256 _presaleId,
    ClankerPresaleEthToCreatorLike.Presale memory _presale,
    bytes32 _salt
  ) internal {
    // Fast forward past presale end time + SALT_SET_BUFFER (1 day)
    vm.warp(_presale.endTime + 1 days + 1); // +1 day for buffer, +1 second to be safe

    // End the presale (requires admin or specific caller)
    // This will deploy the token and make it claimable
    presaleContract.endPresale(_presaleId, _salt);
  }

  /// @dev Helper to verify a presale is in claimable status
  /// @param _presaleId The presale ID to check
  function _verifyPresaleClaimable(uint256 _presaleId) internal {
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(_presaleId);
    assertEq(uint256(presale.status), 5, "Presale should be Claimable");
  }

  /// @dev Helper to verify a presale is in claimable status (using existing presale struct)
  /// @param _presale The presale details (refreshed after endPresale call)
  function _verifyPresaleClaimable(ClankerPresaleEthToCreatorLike.Presale memory _presale) internal pure {
    require(uint256(_presale.status) == 5, "Presale should be Claimable");
  }

  /// @dev High-level helper to buy a specific amount of tokens from a presale and make it claimable
  /// @param _presaleId The presale ID to buy from
  /// @param _buyer The address that will buy the tokens
  /// @param _tokenAmount The exact amount of tokens the buyer should receive
  /// @return ethSpent The amount of ETH the buyer spent
  function _buyTokensFromPresale(uint256 _presaleId, address _buyer, uint256 _tokenAmount)
    internal
    returns (uint256 ethSpent)
  {
    // Get presale details (EXTERNAL CALL 1)
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(_presaleId);

    // Check if presale has already ended
    if (block.timestamp >= presale.endTime) {
      vm.skip(true);
      return 0;
    }

    assertEq(uint256(presale.status), 1, "Presale should be Active");

    // Calculate exact ETH needed for the desired token amount
    ethSpent = _calculateEthForTokens(presale, _tokenAmount);

    // Buy exactly enough tokens
    _buyIntoPresale(_presaleId, _buyer, ethSpent);

    // Verify the buy was recorded
    uint256 buyerBuys = presaleContract.presaleBuys(_presaleId, _buyer);
    assertEq(buyerBuys, ethSpent, "Buy should be recorded");

    // Refresh presale after state change (EXTERNAL CALL 2 - only if needed)
    presale = presaleContract.getPresale(_presaleId);

    // Ensure minimum goal is met (may refresh presale internally if top-up needed)
    presale = _ensurePresaleMinGoalMet(_presaleId, presale);

    // End the presale and make it claimable
    _endPresaleAndMakeClaimable(_presaleId, presale, keccak256(abi.encode("presale", _presaleId, _buyer)));

    // Refresh presale after endPresale state change
    presale = presaleContract.getPresale(_presaleId);

    // Verify presale is now claimable
    _verifyPresaleClaimable(presale);
  }

  /// @dev Complete helper to set up a full presale scenario with precise token amount
  /// @param _buyer The address that will buy tokens
  /// @param _desiredTokenAmount The exact amount of tokens the buyer should receive
  /// @return newPresaleId The ID of the created presale
  /// @return deployedToken The address of the deployed token
  /// @return buyerTokensBought The amount of tokens the buyer has locked (should equal _desiredTokenAmount)
  function _setupClaimablePresaleWithBuyer(address _buyer, uint256 _desiredTokenAmount)
    internal
    returns (uint256 newPresaleId, address deployedToken, uint256 buyerTokensBought)
  {
    // Start presale with no vesting
    newPresaleId = _startPresale(1 ether, 10 ether, 1 days, org, 7 days, 0);

    // Calculate how much ETH needs to be purchased to get exact token amount
    // Token supply for presale: 100 billion * 10% = 10 billion
    uint256 presaleTokenSupply = 10_000_000_000 ether;

    // Have buyer purchase with 1 ETH
    uint256 buyerEthAmount = 1 ether;
    _buyIntoPresale(newPresaleId, _buyer, buyerEthAmount);

    // Calculate how much another account needs to buy so buyer gets exactly desiredTokenAmount
    // Formula: otherEth = buyerEth * (tokenSupply - desiredTokens) / desiredTokens
    // This ensures: desiredTokens = (tokenSupply * buyerEth) / (buyerEth + otherEth)
    require(_desiredTokenAmount > 0 && _desiredTokenAmount < presaleTokenSupply, "Invalid desired token amount");
    uint256 otherEthAmount = (buyerEthAmount * (presaleTokenSupply - _desiredTokenAmount)) / _desiredTokenAmount;

    // Have another account buy to balance the ratio
    address otherBuyer = makeAddr("otherBuyer");
    _buyIntoPresale(newPresaleId, otherBuyer, otherEthAmount);

    // Get presale details before ending
    ClankerPresaleEthToCreatorLike.Presale memory presale = presaleContract.getPresale(newPresaleId);

    // End presale and make claimable
    _endPresaleAndMakeClaimable(newPresaleId, presale, keccak256("test-salt"));

    // Get the deployed token address (refresh after endPresale)
    presale = presaleContract.getPresale(newPresaleId);
    deployedToken = presale.deployedToken;
    buyerTokensBought = presaleContract.presaleBuys(newPresaleId, _buyer);
  }
}

contract WithInstanceTest is BaseTest {
  function setUp() public virtual override {
    super.setUp();

    // get the next presale id
    presaleId = 2; // as of BLOCK_NUMBER

    // set up default test values
    minBalance = 1000 ether;

    // deploy instance with mock token and real presale address (for tests that don't need presale)
    instance = _deployInstance(CLANKER_PRESALE, address(mockToken), minBalance, presaleId, targetHatId);
  }
}

