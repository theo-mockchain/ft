// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
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
        
        // Calculate shares to mint
        uint256 totalSupplyBefore = totalSupply();
        
        if (totalSupplyBefore == 0) {
            // First deposit - use sum of amounts as initial shares
            shares = amount0 + amount1;
            require(shares > 0, "Initial deposit too small");
        } else {
            // Calculate proportional shares based on current vault value
            uint256 totalValue = getTotalValue();
            uint256 depositValue = amount0 + amount1;
            shares = (depositValue * totalSupplyBefore) / totalValue;
        }
        
        require(shares > 0, "Shares calculation resulted in 0");
        
        // Mint shares to user
        _mint(msg.sender, shares);
        
        emit Deposit(msg.sender, amount0, amount1, shares);
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
        
        // Calculate proportional amounts
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        amount0 = (balance0 * shares) / totalShares;
        amount1 = (balance1 * shares) / totalShares;
        
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
        return token0.balanceOf(address(this)) + token1.balanceOf(address(this));
    }

    /**
     * @dev Get individual token balances
     * @return balance0 Balance of token0
     * @return balance1 Balance of token1
     */
    function getBalances() public view returns (uint256 balance0, uint256 balance1) {
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
        uint256 totalSupplyBefore = totalSupply();
        
        if (totalSupplyBefore == 0) {
            return amount0 + amount1;
        } else {
            uint256 totalValue = getTotalValue();
            uint256 depositValue = amount0 + amount1;
            return (depositValue * totalSupplyBefore) / totalValue;
        }
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
        
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        
        amount0 = (balance0 * shares) / totalShares;
        amount1 = (balance1 * shares) / totalShares;
    }
}
