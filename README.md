# Clanker Presale Locked Balance Eligibility Module

A [Hats Protocol](https://github.com/Hats-Protocol/hats-protocol) eligibility module that gates hat eligibility based on combined ERC20 and locked Clanker presale token balances.

## Overview

This module determines eligibility by checking if an address holds a minimum balance across two sources:

1. **ERC20 tokens** - Standard token balance (typically the presale token or derivative)
2. **Locked presale tokens** - Unclaimed tokens in a [Clanker presale](https://github.com/Clanker-Protocol/v4-contracts) (only counted after presale closes)

**Use case:** Allow governance participation or role assignment for users who committed to a token presale, even if they haven't claimed their tokens yet.

## Technical Details

### Immutable Parameters

Configured at deployment via clones-with-immutable-args:

| Parameter | Type | Description |
|-----------|------|-------------|
| `CLANKER_PRESALE_ADDRESS` | `address` | Clanker presale contract (set to `address(0)` to ignore presale balance) |
| `ERC20_TOKEN_ADDRESS` | `address` | ERC20 token to check (set to `address(0)` to ignore ERC20 balance) |
| `MIN_BALANCE` | `uint256` | Minimum combined balance required for eligibility |
| `CLANKER_PRESALE_ID` | `uint256` | ID of the specific presale |

### Eligibility Logic

```solidity
totalBalance = erc20Balance + lockedPresaleBalance
eligible = totalBalance >= MIN_BALANCE
```

**Locked presale balance calculation:**
- Only counted if presale status is `Claimable` (successfully ended)
- `lockedTokens = (presale.tokenSupply * lockedEth) / presale.ethRaised`
- Where `lockedEth = presaleBuys - presaleClaimed`

### Key Behaviors

- **Zero addresses**: Setting either token address to `address(0)` ignores that balance source
- **Standing**: Always returns `true` (module only gates eligibility)
- **Presale status**: Returns 0 for locked balance if presale hasn't ended successfully
- **No state mutations**: Pure eligibility check, no claiming or state updates

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.19

### Setup

```bash
forge install
forge build
```

### Testing

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test contract
forge test --match-contract EligibilityTests

# Run with coverage
forge coverage
```

## Architecture

- **Base**: Extends `HatsEligibilityModule` from [hats-module](https://github.com/Hats-Protocol/hats-module)
- **Clone pattern**: Uses clones-with-immutable-args for gas-efficient deployments
- **Dependencies**: OpenZeppelin ERC20, Hats Protocol v1, Clanker presale interface

## License

MIT
