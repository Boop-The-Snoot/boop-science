# Boop The Snoot

A smart contract system for managing reward campaigns and referral programs on Ethereum.

## Overview

Boop The Snoot is a modular reward distribution system that enables:

- Creation and management of reward campaigns
- Merkle-tree based reward claiming
- Referral program management
- Token whitelisting and administration
- Secure withdrawal mechanisms with cooldown periods

## Key Features

- **Campaign Management**: Create and manage reward campaigns with customizable parameters
- **Reward Distribution**: Efficient reward distribution using Merkle proofs
- **Referral System**: Built-in referral tracking with LP token integration
- **Security Features**:
  - Role-based access control
  - Reentrancy protection
  - Pausable functionality
  - Timelock for parameter changes
  - Withdrawal cooldown periods

## Technical Stack

- Solidity ^0.8.28
- OpenZeppelin Contracts
- Foundry for development and testing

## Getting Started

### Prerequisites

1. Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:

```bash
forge soldeer install
```

Note: This project uses Soldeer through Forge for dependency management.

### Build

```bash
forge build
```

### Test

Run all tests:

```bash
forge test
```

Run tests with detailed output:

```bash
forge test -vv
```

### Format

```bash
forge fmt
```

### Deploy

1. Deploy to Berachain Testnet (bArtio):

```bash
forge create \
    --rpc-url https://bartio.rpc.berachain.com \
    --private-key $PRIVATE_KEY \
    src/BoopTheSnoot.sol:BoopTheSnoot \
    --legacy
```

2. Deploy to Berachain Mainnet (when available):

```bash
forge create \
    --rpc-url https://mainnet.rpc.berachain.com \
    --private-key $PRIVATE_KEY \
    src/BoopTheSnoot.sol:BoopTheSnoot \
    --legacy
```

### Verify Contract

1. Verify contract on Berachain Testnet (bArtio):

```bash
forge verify-contract [contract-address] src/BoopTheSnoot.sol:BoopTheSnoot \
--verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80084/etherscan' \
--etherscan-api-key "verifyContract" \
--num-of-optimizations 200 \
--compiler-version 0.8.28 \
--constructor-args $(cast abi-encode "constructor()")
```

Note: Make sure to:

- Replace environment variables with actual values
- Have sufficient BERA tokens for deployment on Berachain
- Verify contract parameters before mainnet deployment
- Test thoroughly on testnet first
- Check [Berachain documentation](https://www.berachain.com/) for the latest network configurations

## Contract Architecture

### Core Components

1. **Campaign System**

   - Campaign creation and management
   - Reward rate controls
   - Token deposit/withdrawal mechanisms

2. **Reward Distribution**

   - Merkle-tree based claiming
   - Support for both game and referral rewards
   - Batch claim processing

3. **Referral Program**

   - Referrer-referee tracking
   - LP token integration
   - Anti-gaming mechanisms

4. **Administration**
   - Role-based access control
   - Token whitelisting
   - Parameter management with timelock

## Security Features

- Reentrancy Guards
- Access Control
- Pausable Functionality
- Time-based Cooldowns
- Parameter Change Delays
- Whitelist Controls

## Testing

The project includes comprehensive test suites:

- Basic functionality tests
- Advanced integration tests
- Edge case handling
- Security scenario testing

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

Business Source License 1.1

## Documentation

For detailed documentation of the smart contracts and their functionality, please refer to the inline code comments and the test files.

## Support

For questions and support, please open an issue in the repository.
