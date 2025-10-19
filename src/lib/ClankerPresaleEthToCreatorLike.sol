// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
  IClanker,
  IClankerPresaleEthToCreator
} from "../../lib/v4-contracts/src/extensions/interfaces/IClankerPresaleEthToCreator.sol";

interface ClankerPresaleEthToCreatorLike is IClankerPresaleEthToCreator {
  function presaleBuys(uint256 presaleId, address user) external view returns (uint256);
  function presaleClaimed(uint256 presaleId, address user) external view returns (uint256);
  function amountAvailableToClaim(uint256 presaleId, address user) external view returns (uint256);
  function claimTokens(uint256 presaleId) external;
  function buyIntoPresale(uint256 presaleId) external payable;
  function withdrawFromPresale(uint256 presaleId, uint256 amount, address recipient) external;
  function endPresale(uint256 presaleId, bytes32 salt) external returns (address token);
  function claimEth(uint256 presaleId, address recipient) external;
  function startPresale(
    IClanker.DeploymentConfig memory deploymentConfig,
    uint256 minEthGoal,
    uint256 maxEthGoal,
    uint256 presaleDuration,
    address recipient,
    uint256 lockupDuration,
    uint256 vestingDuration,
    address allowlist,
    bytes calldata allowlistInitializationData
  ) external returns (uint256 presaleId);
  function setWithdrawFeeRecipient(address recipient) external;
  function withdrawWithdrawFee() external;
  function getPresale(uint256 presaleId_) external view returns (Presale memory);
  function owner() external view returns (address);
  function setAdmin(address admin, bool enabled) external;
}
