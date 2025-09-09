// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Minimal interfaces to avoid importing full Uniswap packages that require older Solidity.
interface INonfungiblePositionManagerMinimal {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IUniswapV3PoolMinimal {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

/**
 * @title SimpleLiquidityVault
 * @dev A simple vault that holds two tokens and allows users to deposit/withdraw
 * This is a foundation that can be extended to interact with Uniswap V3
 */
contract LiquidityVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Vault tokens
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    
    // Uniswap V3 integration
    INonfungiblePositionManagerMinimal public immutable positionManager;
    address public immutable pool;
    uint24 public immutable fee; // pool fee
    int24 public immutable tickLower;
    int24 public immutable tickUpper;
    uint256 public tokenId; // Uniswap V3 position token id managed by this vault
    
    // Fee parameters
    uint256 public managementFee = 200; // 2% in basis points
    uint256 public performanceFee = 1000; // 10% in basis points
    uint256 public constant MAX_FEE = 2000; // 20% max fee
    
    // Events
    event Deposit(address indexed user, uint256 amount0, uint256 amount1, uint256 shares);
    event Withdraw(address indexed user, uint256 shares, uint256 amount0, uint256 amount1);
    event FeesUpdated(uint256 managementFee, uint256 performanceFee);
    event EmergencyWithdraw(address indexed user, uint256 amount0, uint256 amount1);

    constructor(
        address _token0,
        address _token1,
        address _positionManager,
        address _pool,
        uint24 _fee,
        int24 _tickLower,
        int24 _tickUpper,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        require(_positionManager != address(0), "Invalid position manager");
        require(_pool != address(0), "Invalid pool");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        positionManager = INonfungiblePositionManagerMinimal(_positionManager);
        pool = _pool;
        fee = _fee;
        tickLower = _tickLower;
        tickUpper = _tickUpper;

        // Pre-approve position manager for efficiency
        token0.safeApprove(_positionManager, 0);
        token0.safeApprove(_positionManager, type(uint256).max);
        token1.safeApprove(_positionManager, 0);
        token1.safeApprove(_positionManager, type(uint256).max);
    }

    /**
     * @dev Deposit tokens into the vault and receive shares
     * @param amount0 Amount of token0 to deposit
     * @param amount1 Amount of token1 to deposit
     * @return shares Amount of vault shares minted
     */
    function deposit(uint256 amount0, uint256 amount1) external nonReentrant returns (uint256 shares) {
        require(amount0 > 0 || amount1 > 0, "Must deposit at least one token");
        
        // Transfer tokens from user
        if (amount0 > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            token1.safeTransferFrom(msg.sender, address(this), amount1);
        }

        // Add liquidity to the Uniswap V3 position
        // Track liquidity before to compute shares
        uint256 liquidityBefore;
        if (tokenId != 0) {
            (, , , , , , , uint128 l, , , , ) = positionManager.positions(tokenId);
            liquidityBefore = uint256(l);
        }

        uint256 amount0Used;
        uint256 amount1Used;
        uint128 liquidityAdded;
        if (tokenId == 0) {
            INonfungiblePositionManagerMinimal.MintParams memory params = INonfungiblePositionManagerMinimal.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });
            (uint256 _tokenId, uint128 _liquidityAdded, uint256 _amount0, uint256 _amount1) = positionManager.mint(params);
            tokenId = _tokenId;
            liquidityAdded = _liquidityAdded;
            amount0Used = _amount0;
            amount1Used = _amount1;
            require(liquidityAdded > 0, "No liquidity added");
        } else {
            INonfungiblePositionManagerMinimal.IncreaseLiquidityParams memory paramsInc = INonfungiblePositionManagerMinimal.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
            (uint128 _liquidityAdded, uint256 _amount0, uint256 _amount1) = positionManager.increaseLiquidity(paramsInc);
            liquidityAdded = _liquidityAdded;
            amount0Used = _amount0;
            amount1Used = _amount1;
            require(liquidityAdded > 0, "No liquidity added");
        }

        // Calculate shares to mint based on liquidity added
        uint256 totalSupplyBefore = totalSupply();
        if (totalSupplyBefore == 0 || liquidityBefore == 0) {
            shares = uint256(liquidityAdded);
            require(shares > 0, "Initial deposit too small");
        } else {
            shares = (uint256(liquidityAdded) * totalSupplyBefore) / liquidityBefore;
        }

        require(shares > 0, "Shares calculation resulted in 0");

        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount0Used, amount1Used, shares);
    }

    /**
     * @dev Withdraw tokens from the vault by burning shares
     * @param shares Amount of shares to burn
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(shares > 0, "Must withdraw positive amount");
        require(balanceOf(msg.sender) >= shares, "Insufficient balance");
        
        uint256 totalShares = totalSupply();

        // Proportion of position liquidity to remove
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
            if (liquidity > 0) {
                uint128 liquidityToRemove = uint128((uint256(liquidity) * shares) / totalShares);
                if (liquidityToRemove > 0) {
                    INonfungiblePositionManagerMinimal.DecreaseLiquidityParams memory paramsDec = INonfungiblePositionManagerMinimal.DecreaseLiquidityParams({
                        tokenId: tokenId,
                        liquidity: liquidityToRemove,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    });
                    positionManager.decreaseLiquidity(paramsDec);
                    // Collect the withdrawn tokens
                    INonfungiblePositionManagerMinimal.CollectParams memory paramsCol = INonfungiblePositionManagerMinimal.CollectParams({
                        tokenId: tokenId,
                        recipient: address(this),
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    });
                    (uint256 amount0Collected, uint256 amount1Collected) = positionManager.collect(paramsCol);
                    // amount0Collected/amount1Collected should be >= amount0Out/amount1Out
                    amount0 += amount0Collected;
                    amount1 += amount1Collected;
                }
            }
        }

        // Include share of any idle balances
        uint256 idle0 = token0.balanceOf(address(this));
        uint256 idle1 = token1.balanceOf(address(this));
        if (idle0 > 0) {
            amount0 += (idle0 * shares) / totalShares;
        }
        if (idle1 > 0) {
            amount1 += (idle1 * shares) / totalShares;
        }

        // Burn shares first
        _burn(msg.sender, shares);

        // Transfer tokens to user
        if (amount0 > 0) {
            token0.safeTransfer(msg.sender, amount0);
        }
        if (amount1 > 0) {
            token1.safeTransfer(msg.sender, amount1);
        }

        emit Withdraw(msg.sender, shares, amount0, amount1);
    }

    /**
     * @dev Emergency withdraw all tokens (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        if (balance0 > 0) {
            token0.safeTransfer(owner(), balance0);
        }
        if (balance1 > 0) {
            token1.safeTransfer(owner(), balance1);
        }
        
        emit EmergencyWithdraw(owner(), balance0, balance1);
    }

    /**
     * @dev Update management and performance fees (owner only)
     * @param _managementFee New management fee in basis points
     * @param _performanceFee New performance fee in basis points
     */
    function updateFees(uint256 _managementFee, uint256 _performanceFee) external onlyOwner {
        require(_managementFee <= MAX_FEE, "Management fee too high");
        require(_performanceFee <= MAX_FEE, "Performance fee too high");
        
        managementFee = _managementFee;
        performanceFee = _performanceFee;
        
        emit FeesUpdated(_managementFee, _performanceFee);
    }

    /**
     * @dev Get the total value held by the vault
     * @return Total value as sum of both token balances
     */
    function getTotalValue() public view returns (uint256) {
        // For simplicity, treat liquidity units plus idle token balances as total value proxy.
        // Note: Units differ; this is only a rough proxy for accounting purposes.
        uint256 l;
        if (tokenId != 0) {
            (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
            l = uint256(liquidity);
        }
        uint256 idle0 = token0.balanceOf(address(this));
        uint256 idle1 = token1.balanceOf(address(this));
        return l + idle0 + idle1;
    }

    /**
     * @dev Get individual token balances
     * @return balance0 Balance of token0
     * @return balance1 Balance of token1
     */
    function getBalances() public view returns (uint256 balance0, uint256 balance1) {
        // Only idle balances are exact; position amounts are unknown without price math.
        balance0 = token0.balanceOf(address(this));
        balance1 = token1.balanceOf(address(this));
    }

    /**
     * @dev Get the share price based on current vault value
     * @return Share price (vault value per share)
     */
    function getSharePrice() public view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 1e18; // Default price for first deposit
        
        return (getTotalValue() * 1e18) / totalShares;
    }

    /**
     * @dev Preview how many shares would be received for a deposit
     * @param amount0 Amount of token0 to deposit
     * @param amount1 Amount of token1 to deposit
     * @return shares Amount of shares that would be minted
     */
    function previewDeposit(uint256 amount0, uint256 amount1) public view returns (uint256 shares) {
        // Approximate preview: if position exists, assume proportional to existing liquidity vs idle contributions
        uint256 totalSupplyBefore = totalSupply();
        uint256 liquidityBefore;
        if (tokenId != 0) {
            (, , , , , , , uint128 l, , , , ) = positionManager.positions(tokenId);
            liquidityBefore = uint256(l);
        }
        if (totalSupplyBefore == 0 || liquidityBefore == 0) {
            return amount0 + amount1; // rough approximation
        }
        // Assume similar ratio as previous deposits: 1 share ~= liquidity unit
        // We cannot derive expected liquidity without price math; return proportional estimate.
        return (amount0 + amount1) * totalSupplyBefore / (liquidityBefore + 1);
    }

    /**
     * @dev Preview how many tokens would be received for a withdrawal
     * @param shares Amount of shares to withdraw
     * @return amount0 Amount of token0 that would be received
     * @return amount1 Amount of token1 that would be received
     */
    function previewWithdraw(uint256 shares) public view returns (uint256 amount0, uint256 amount1) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return (0, 0);

        // Share of idle balances; position amounts unknown without price math
        uint256 idle0 = token0.balanceOf(address(this));
        uint256 idle1 = token1.balanceOf(address(this));
        amount0 = (idle0 * shares) / totalShares;
        amount1 = (idle1 * shares) / totalShares;
    }

    /**
     * @dev Collect all fees from the position into the vault.
     */
    function collectFees() external nonReentrant onlyOwner {
        if (tokenId == 0) return;
        INonfungiblePositionManagerMinimal.CollectParams memory paramsCol = INonfungiblePositionManagerMinimal.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        positionManager.collect(paramsCol);
    }

    /**
     * @dev Returns current pool tick.
     */
    function getCurrentTick() external view returns (int24 tick) {
        (, tick, , , , , ) = IUniswapV3PoolMinimal(pool).slot0();
    }

    /**
     * @dev Returns current position liquidity managed by the vault.
     */
    function getPositionLiquidity() external view returns (uint128 liquidity) {
        if (tokenId == 0) return 0;
        (, , , , , , , liquidity, , , , ) = positionManager.positions(tokenId);
    }
}
