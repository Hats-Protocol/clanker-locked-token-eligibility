// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule } from "../lib/hats-module/src/HatsEligibilityModule.sol";
import { ClankerPresaleEthToCreatorLike, IClankerPresaleEthToCreator } from "./lib/ClankerPresaleEthToCreatorLike.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ClankerPresaleLockedBalanceEligibilityModule is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their location.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * ----------------------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                                         |
   * ----------------------------------------------------------------------------------|
   * Offset  | Constant                 | Type    | Length  | Source                   |
   * ----------------------------------------------------------------------------------|
   * 0       | IMPLEMENTATION           | address | 20      | HatsModule               |
   * 20      | HATS                     | address | 20      | HatsModule               |
   * 40      | hatId                    | uint256 | 32      | HatsModule               |
   * 72      | CLANKER_PRESALE_ADDRESS  | address | 20      | this                     |
   * 92      | ERC20_TOKEN_ADDRESS      | address | 20      | this                     |
   * 112     | MIN_BALANCE              | uint256 | 32      | this                     |
   * 144     | PRESALE_ID               | uint256 | 32      | this                     |
   * ----------------------------------------------------------------------------------+
   */

  /// @notice Get the address of the Clanker presale contract where tokens are locked
  function CLANKER_PRESALE_ADDRESS() public pure returns (address) {
    return _getArgAddress(72);
  }

  /// @notice Get the address of the ERC20 token. This is typically the token purchased in the presale,
  /// or a derivative thereof (e.g. a staked, locked, or wrapped version of the token).
  function ERC20_TOKEN_ADDRESS() public pure returns (address) {
    return _getArgAddress(92);
  }

  /// @notice Get the minimum balance for eligibility across ERC20 and Clanker presale locked tokens
  function MIN_BALANCE() public pure returns (uint256) {
    return _getArgUint256(112);
  }

  /// @notice Get the ID of the Clanker presale
  function CLANKER_PRESALE_ID() public pure returns (uint256) {
    return _getArgUint256(144);
  }

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // no init data required for this module
  }

  /*//////////////////////////////////////////////////////////////
                        HATS ELIGIBILITY FUNCTION
    //////////////////////////////////////////////////////////////*/
  /**
   * @inheritdoc HatsEligibilityModule
   */
  function getWearerStatus(
    address _wearer,
    uint256 /*_hatId */
  )
    public
    view
    override
    returns (
      bool eligible,
      bool /* standing */
    )
  {
    // get the total balance of the wearer across ERC20 and Clanker presale locked tokens
    uint256 totalBalance =
      _getERC20Balance(_wearer)
      + _getClankerPresaleLockedBalance(
        ClankerPresaleEthToCreatorLike(CLANKER_PRESALE_ADDRESS()), CLANKER_PRESALE_ID(), _wearer
      );

    // eligible if the total balance is gte the minimum balance
    eligible = totalBalance >= MIN_BALANCE();

    // this module is only used for eligibility, so standing is always true
    return (eligible, true);
  }

  /*//////////////////////////////////////////////////////////////
                        PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @dev Get the balance of the ERC20 token
  /// @param _account The address to get the balance of
  /// @return The balance of the ERC20 token
  function _getERC20Balance(address _account) internal view returns (uint256) {
    if (ERC20_TOKEN_ADDRESS() == address(0)) {
      return 0;
    }
    return IERC20(ERC20_TOKEN_ADDRESS()).balanceOf(_account);
  }

  /// @dev Get the balance of an account's locked Clanker presale tokens
  /// @param _presaleContract The Clanker presale contract
  /// @param _presaleId The ID of the presale
  /// @param _account The address to get the balance of
  /// @return The total locked token balance (unclaimed tokens after presale has closed)
  function _getClankerPresaleLockedBalance(
    ClankerPresaleEthToCreatorLike _presaleContract,
    uint256 _presaleId,
    address _account
  ) internal view returns (uint256) {
    if (address(_presaleContract) == address(0)) {
      return 0;
    }

    IClankerPresaleEthToCreator.Presale memory presale = _presaleContract.getPresale(_presaleId);

    // Only count locked tokens if presale has ended successfully
    if (presale.status != IClankerPresaleEthToCreator.PresaleStatus.Claimable) {
      return 0;
    }

    // Calculate locked ETH amount (what they bought minus what they've claimed)
    uint256 lockedEthAmount =
      _presaleContract.presaleBuys(_presaleId, _account) - _presaleContract.presaleClaimed(_presaleId, _account);

    uint256 lockedTokenAmount = (presale.tokenSupply * lockedEthAmount) / presale.ethRaised;
    return lockedTokenAmount;
  }
}
