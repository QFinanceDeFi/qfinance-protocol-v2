// SPDX-License-Identifier: MIT
// QFinance contracts v2.0.1

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "./WrappedToken.sol";
import "../libraries/SafeMath.sol";

/**
 * @dev Implementation of the wrapped token registry.
 *
 * This contract serves to receive tokens, deposit them, and returned wrapped version,
 * and vice versa. It will also register the token in a registry to ensure that only one
 * lending pool is created for a token, and to provide the wrapped version address.
 */

contract WrapRegistry {
    using SafeMath for uint256;

    /**
     * @dev Calculates min and max repayment levels
     */ 
    uint private constant CLOSE_FACTOR_MIN = 5e16;
    uint private constant CLOSE_FACTOR_MAX = 9e17;

    /**
     * @dev Total markets
     */
    uint private _totalMarkets;

    /**
     * @dev Separate contract to calculate rates
     */
    IInterestRateModel private interestRateModel;

    /**
     * @dev List of user's entered markets.
     */
    mapping (address => address[]) private _assets;

    /**
     * @dev Maintains user market info across markets.
     * Initial mapping address is a token. The next lookup is a user account returning deposited and borrowed amounts.
     */
    mapping (address => mapping (address => UserMarketData)) private _marketUsers;

    /**
     * @dev Maintains totals for each market.
     */
    mapping (address => MarketData) private _marketData;

    /** 
     * @dev Maintains token address -> wrapped token address mapping
     */
    mapping (address => address) private _registry;

    /**
     * @dev Iterable mapping of all markets
     */
    mapping (uint => address) private _markets;

    /**
     * @dev Structs for storing user and market data efficiently
     */
    struct UserMarketData {
        uint128 deposited;
        uint128 borrowed;
    }

    struct MarketData {
        uint128 deposited;
        uint128 borrowed;
        uint128 minCollateral; // expressed as an integer where 1 = 1e18
        uint128 accrualBlock;
    }

    /**
     * @dev Returns assets an account has deposited/withdrawn
     */
    function getUserAssets(address account) external view returns (address[] memory) {
         address[] memory assets = _assets[account];
         return assets;
    }

    /**
     * @dev Returns token's wrapped address. If pool doesn't exist, returns 0 address.
     */
    function checkToken(address token) public view returns (address) {
        return _registry[token];
    }

    /**
     * @dev Returns user's balance for a certain asset.
     */
    function checkBalance(address token, address account) external view returns (uint, uint) {
        UserMarketData storage data = _marketUsers[token][account];
        return (data.deposited, data.borrowed);
    }

    /**
     * @dev Returns data for token market.
     */
    function getTokenData(address token) external view returns (uint, uint) {
        MarketData storage data = _marketData[token];
        return (data.deposited, data.borrowed);
    }

    /**
     * @dev Initiate a lending market for a token
     */
    function initialize(address token) public {
        require(_registry[token] != address(0), "Token doesn't exist");
        require(_marketData[token].accrualBlock == 0, "Token initialized");
        MarketData storage marketData = _marketData[token];
        marketData.accrualBlock = uint128(block.number);
    }

    /**
     * @dev Returns max borrowable amount.
     */
    function borrowable(address token) external view returns (uint) {
        MarketData storage data = _marketData[token];
        if (data.accrualBlock == 0) return 0;
        return uint256(data.deposited).div(data.minCollateral).mul(1e18).sub(data.borrowed);
    }

    /**
     * @dev Deposit funds
     */
    function depositFunds(address token, uint amount) external {
        require(_registry[token] != address(0), "Token not registered");
        IERC20 erc = IERC20(token);
        MarketData storage data = _marketData[token];
        UserMarketData storage userData = _marketUsers[token][msg.sender];
        erc.transferFrom(msg.sender, address(this), amount);
        data.deposited = uint128(uint256(data.deposited).add(amount));
        userData.deposited = uint128(uint256(userData.deposited).add(amount));
    }

    /**
     * @dev Withdraw funds
     */
    function withdrawFunds(address token, uint amount) external {
        require(_registry[token] != address(0), "Token not registered");
        IERC20 erc = IERC20(token);
        MarketData storage marketData = _marketData[token];
        UserMarketData storage userData = _marketUsers[token][msg.sender];
        require(
            getCollateralization(uint256(userData.borrowed).sub(amount), userData.borrowed) > marketData.minCollateral,
            "Not enough collateral"
        );
        marketData.deposited = uint128(uint256(marketData.deposited).sub(amount));
        userData.deposited = uint128(uint256(userData.deposited).sub(amount));
        erc.transfer(msg.sender, amount);
    }

    /**
     * @dev Creates a new loan for a user
     */
    function borrowFunds(address token, uint amount) external {
        require(_registry[token] != address(0), "Token not registered");
        require(_marketData[token].accrualBlock != 0, "No market for token");
        UserMarketData storage userData = _marketUsers[token][msg.sender];
        MarketData storage marketData = _marketData[token];
        IERC20 erc = IERC20(token);
        require(
            getCollateralization(userData.deposited, uint256(userData.borrowed).add(amount)) >= marketData.minCollateral,
            "Not enough collateral"
        );
        marketData.borrowed = uint128(uint256(marketData.borrowed).add(amount));
        userData.borrowed = uint128(uint256(userData.borrowed).add(amount));
        erc.transfer(msg.sender, amount);
    }

    /**
     * @dev Repays a loan for a user
     */
    function repayFunds(address token, uint amount) external {
        require(_registry[token] != address(0), "No market for token");
        UserMarketData storage userData = _marketUsers[token][msg.sender];
        MarketData storage marketData = _marketData[token];
        IERC20 erc = IERC20(token);
        erc.transferFrom(msg.sender, address(this), amount);
        marketData.borrowed = uint128(uint256(marketData.borrowed).sub(amount));
        userData.borrowed = uint128(uint256(userData.borrowed).sub(amount));
    }

    /** 
     * @dev Get user's collateralized ratio where 1e18 = 100%
     */
    function getCollateralization(uint deposited, uint borrowed) public pure returns (uint) {
        if (borrowed == 0) return 100e18;
        return deposited.div(borrowed).mul(1e18);
    }

    /**
     * @dev Deploy new wrapped token and add to registry
     */
    function createWrappedToken(address token) public returns (address) {
        require(_registry[token] == address(0), "Token already wrapped");
        IERC20 baseToken = IERC20(token);
        string memory name = baseToken.name();
        string memory symbol = baseToken.symbol();
        WrappedToken wToken = new WrappedToken(string(abi.encodePacked("QWrap ", name)), string(abi.encodePacked("q", symbol)), address(this));
        _registry[token] = address(wToken);
        _totalMarkets += 1;
        _markets[_totalMarkets] = token;
        _marketData[token] = MarketData({deposited: 0, borrowed: 0, minCollateral: 2e18, accrualBlock: 0});
        return address(wToken);
    }

    /**
     * @dev Pulls token from user and mints equivalent amount of wrapped version.
     */
    function mintWrapped(address token, uint amount) public {
        require(_registry[token] != address(0), "Token doesn't exist");
        IERC20 wToken = IERC20(_registry[token]);
        IERC20 baseToken = IERC20(token);
        baseToken.transferFrom(msg.sender, address(this), amount);
        wToken.mint(msg.sender, amount);
        uint totalMarket = _marketData[token].deposited;
        uint totalUser = _marketUsers[token][msg.sender].deposited;
        _marketData[token].deposited = uint128(totalMarket.add(amount));
        _marketUsers[token][msg.sender].deposited = uint128(totalUser.add(amount));
    }
    
    /**
     * @dev Pulls wrapped token from user, burns it and returns and equivalent amount of base token.
     */
    function burnWrapped(address token, uint amount) public {
        require(_registry[token] != address(0), "Token doesn't exist");
        IERC20 wToken = IERC20(_registry[token]);
        IERC20 baseToken = IERC20(token);
        uint totalMarket = _marketData[token].deposited;
        uint totalUser = _marketUsers[token][msg.sender].deposited;
        _marketData[token].deposited = uint128(totalMarket.sub(amount));
        _marketUsers[token][msg.sender].deposited = uint128(totalUser.add(amount));
        wToken.burn(msg.sender, amount);
        baseToken.transfer(msg.sender, amount);
    }

    /**
     * @dev Accrues interest to borrows and reserves
     */
     function accrueInterest(address token) public returns (uint) {
         require(_registry[token] != address(0), "Token doesn't exist");
         
         MarketData memory marketData = _marketData[token];
         uint currentBlock = block.number;
         
         if (marketData.accrualBlock == currentBlock) {
             return 0;
         }

         uint borrowRate = interestRateModel.getBorrowRate(marketData.deposited, marketData.borrowed, uint256(marketData.deposited).div(8));
         uint blockDelta = currentBlock.sub(marketData.accrualBlock);
         uint interest = borrowRate.mul(blockDelta);
         uint accumulated = interest.mul(marketData.borrowed);

         marketData.borrowed = uint128(uint256(marketData.borrowed).add(accumulated));
         marketData.accrualBlock = uint128(currentBlock);
         _marketData[token] = marketData;

         return accumulated;
     }
}