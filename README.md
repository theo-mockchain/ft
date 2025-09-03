# Simple Liquidity Vault

A foundational smart contract for managing liquidity positions with two ERC20 tokens. This vault serves as a base that can be extended to interact with Uniswap V3 or other DeFi protocols.

## Features

- **Dual Token Management**: Manages two ERC20 tokens (token0 and token1)
- **Share-based System**: Users receive vault shares proportional to their deposits
- **Fee Management**: Configurable management and performance fees
- **Emergency Controls**: Owner can perform emergency withdrawals
- **Preview Functions**: Users can preview deposit/withdrawal amounts before execution
- **Comprehensive Testing**: Full test suite with 8 passing tests

## Core Functions

### User Functions

- `deposit(uint256 amount0, uint256 amount1)`: Deposit tokens and receive vault shares
- `withdraw(uint256 shares)`: Burn shares and withdraw proportional token amounts
- `previewDeposit(uint256 amount0, uint256 amount1)`: Preview shares for a deposit
- `previewWithdraw(uint256 shares)`: Preview token amounts for a withdrawal

### View Functions

- `getTotalValue()`: Get total vault value (sum of both token balances)
- `getBalances()`: Get individual token balances
- `getSharePrice()`: Get current share price
- `balanceOf(address)`: Get user's share balance (inherited from ERC20)

### Owner Functions

- `updateFees(uint256 managementFee, uint256 performanceFee)`: Update fee structure
- `emergencyWithdraw()`: Emergency withdrawal of all vault funds

## Architecture

The vault extends OpenZeppelin's battle-tested contracts:

- `ERC20`: For share token functionality
- `Ownable`: For access control
- `ReentrancyGuard`: For protection against reentrancy attacks

## Fee Structure

- **Management Fee**: Default 2% (200 basis points), max 20%
- **Performance Fee**: Default 10% (1000 basis points), max 20%
- Fees are configurable by the contract owner

## Security Features

- Reentrancy protection on all state-changing functions
- Input validation and proper error messages
- Safe token transfers using OpenZeppelin's SafeERC20
- Owner-only functions for administrative tasks

## Usage Example

```solidity
// Deploy vault with two tokens
SimpleLiquidityVault vault = new SimpleLiquidityVault(
    address(tokenA),
    address(tokenB),
    "My Vault Token",
    "MVT"
);

// User deposits tokens
token0.approve(address(vault), 100e18);
token1.approve(address(vault), 200e18);
uint256 shares = vault.deposit(100e18, 200e18);

// User withdraws
vault.withdraw(shares / 2); // Withdraw half
```

## Testing

The contract includes comprehensive tests covering:

- Initial and subsequent deposits
- Proportional withdrawals
- Preview function accuracy
- Owner administrative functions
- Error conditions and edge cases

Run tests with:

```bash
forge test
```

## Extension Possibilities

This vault serves as a foundation for more complex DeFi strategies:

1. **Uniswap V3 Integration**: Add position management with `INonfungiblePositionManager`
2. **Automated Rebalancing**: Implement strategies to maintain optimal price ranges
3. **Fee Collection**: Collect and compound trading fees
4. **Multi-Pool Support**: Manage positions across multiple pools
5. **Strategy Plugins**: Add modular strategy components

## Deployment

1. Install dependencies:

   ```bash
   forge install
   ```

2. Compile contracts:

   ```bash
   forge build
   ```

3. Run tests:

   ```bash
   forge test
   ```

4. Deploy (example for local network):
   ```bash
   forge create SimpleLiquidityVault \
     --constructor-args <token0> <token1> "Vault Name" "SYMBOL" \
     --private-key $PRIVATE_KEY
   ```

## Contract Addresses

The vault requires two ERC20 token addresses for deployment:

- `token0`: Address of the first token
- `token1`: Address of the second token

## License

MIT License - see LICENSE file for details.
