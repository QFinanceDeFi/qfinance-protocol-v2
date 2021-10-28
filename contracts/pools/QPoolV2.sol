// SPDX-License-Identifier: MIT
// QFinance Contracts V2.0.1

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IMultiswap.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/Context.sol";
import "./QPoolDepositTokenV2.sol";

/**
 * @dev This contract is the base contract for static QPools (i.e. non AMM pools). This contract is mostly complete
 * but still requires in depth testing and audit. The rebalancing functionality will occur via a separate contract
 * acting as a proxy to communicate with Chainlink Keepers. This code will be added soon.
 */
contract QPoolV2 is Context, QPoolDepositTokenV2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Multiswap router to facilitate swaps
    IMultiswap private _swapRouter =
        IMultiswap(0x08b16410c53FA67b0CC2cA58bd0F6409f3349f7a);

    // Total tokens for mapping loop
    uint8 public _totalTokens;

    // Use 1 = false, 2 = true to prevent reentrancy
    uint8 private _swap = 1;

    mapping(address => uint256) private _deposits; // Track user deposits
    mapping(address => uint256) private _withdrawals; // Track user withdrawals
    mapping(uint256 => PortfolioToken) private _breakdown; // Portfolio mapping an int to a struct for mapping loop
    mapping(address => uint256) private _tokenIndex; // Look up a token by its mapping value in _breakdown

    // Pack token data into struct
    struct PortfolioToken {
        uint160 token;
        uint8 amount;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory tokens_,
        uint256[] memory amounts_
    ) {
        require(tokens_.length == amounts_.length, "Input error"); // Ensure inputs match
        _name = name_; // Pool Token Name
        _symbol = symbol_; // Pool Token Symbol

        uint256 totalPercent;

        for (uint256 i = 0; i < amounts_.length && i <= 5; i++) {
            totalPercent += amounts_[i];
            uint256 index = i + 1;
            _breakdown[index] = PortfolioToken(
                uint160(tokens_[i]),
                uint8(amounts_[i])
            );
        }
        require(totalPercent == 100, "QPool: Percent not 100"); // Validate 100% allocated
        _totalTokens = uint8(amounts_.length); // Set amount of tokens in portfolio
    }

    // Ensure pool can receive ETH
    fallback() external payable {}

    receive() external payable {}

    // Check if swap is already in progress to prevent reentrancy
    modifier inSwap() {
        require(_swap == 1, "Swap already in progress");
        _swap = 2;
        _;
        _swap = 1;
    }

    /**
     *
     * CALC FUNCTIONS
     *
     **/

    /**
     * @dev Function to calculate total pool value across all holdings.
     */
    function calcPoolValue() public view returns (uint256 total) {
        (address[] memory tokens, uint256[] memory amounts, ) = getPortfolio();
        uint256[] memory slippage = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) slippage[i] = 1;
        total = _swapRouter.checkAllValue(tokens, amounts, slippage);
        return total;
    }

    /**
     * @dev Function to calculate the total value of the pool's holdings for an individual token.
     */
    function calcTokenValue(address token) public view returns (uint256 value) {
        uint256 index = _tokenIndex[token];
        require(index != 0, "Token not in pool");
        uint256 balance = getPoolTokenBalance(token);
        value = _swapRouter.checkTokenValueETH(
            address(_breakdown[index].token),
            balance,
            0
        );
        return value;
    }

    /**
     * @dev Function to get expected swap outputs. Should be called prior to making a swap.
     */
    function calcSwap(uint256 amount, uint256[] calldata slippage)
        public
        view
        returns (uint256[] memory expected)
    {
        (address[] memory tokens, uint256[] memory amounts, ) = getPortfolio();
        require(slippage.length == tokens.length, "Input error");
        (, expected, ) = _swapRouter.checkOutputsETH(
            tokens,
            amounts,
            slippage,
            amount
        );
        return expected;
    }

    /**
     * @dev Calculate the depositor's share after swapping for assets
     */
    function calcPoolShare(address account) internal view returns (uint256) {
        uint256 balance = _balances[account];
        uint256 share = balance.mul(1e18).div(_totalSupply); // Return share as 1e18 = 1%
        return share;
    }

    /**
     *
     * POOL FUNCTIONS
     *
     **/

    /**
     * @dev Finds a token in the portfolio and returns its details as a tuple
     */
    function getToken(uint256 index)
        public
        view
        returns (uint160 token, uint8 amount)
    {
        return (_breakdown[index].token, _breakdown[index].amount); // Parse struct to tuple
    }

    /**
     * @dev Parses mappings and returns the portfolio details as a tuple
     */
    function getPortfolio()
        public
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        address[] memory tokens = new address[](_totalTokens);
        uint256[] memory amounts = new uint256[](_totalTokens);
        uint256[] memory poolBalances = new uint256[](_totalTokens);

        // We start this loop at 1 since our mapping keys increment from 1
        for (uint256 i = 1; i <= _totalTokens; i++) {
            PortfolioToken storage token = _breakdown[i]; // Find struct in storage
            // Fill arrays to return
            tokens[i] = address(token.token);
            amounts[i] = uint256(token.amount);
            poolBalances[i] = getPoolTokenBalance(address(token.token));
        }

        return (tokens, amounts, poolBalances);
    }

    /**
     * @dev Looks up pool's balance for a token
     */
    function getPoolTokenBalance(address token) public view returns (uint256) {
        IERC20 erc = IERC20(address(token));
        return erc.balanceOf(address(this));
    }

    /**
     * @dev Sums up all values in an array
     */
    function getValueETH(uint256[] calldata expected)
        public
        pure
        returns (uint256)
    {
        uint256 total;
        for (uint256 i; i < expected.length; i++) {
            total = total.add(expected[i]);
        }

        return total;
    }

    /**
     *
     * SWAP FUNCTIONS
     *
     **/

    /**
     * @dev Perform swap using multiswap router.
     **/

    function makeSwap(uint256[] calldata expected) public payable inSwap {
        (
            address[] memory tokens,
            uint256[] memory amounts,
            uint256[] memory holdings
        ) = getPortfolio();
        uint256 preValue = calcPoolValue(); // Take value before deposit
        _swapRouter.makeETHSwap{value: msg.value}(
            tokens,
            amounts,
            expected,
            address(_swapRouter)
        ); // Make token swaps
        uint256 postValue = calcPoolValue(); // Take value after swaps

        // This loop allows us to validate the price on chain without the use of an oracle. We test to ensure that the amount
        // we acquired is at least 99% of what was passed from the client-side (i.e. accept up to 1% slippage from expected amount).
        // Front-end systems should ensure the value passed from the client side is properly secure against sandwich attacks.
        for (uint256 i; i < tokens.length; i++) {
            require(
                getPoolTokenBalance(tokens[i]).sub(holdings[i]) >
                    expected[i].mul(99).div(100),
                "Too much slippage"
            );
        }

        uint256 mintAmount = (
            postValue.sub(preValue).mul(1e18).div(postValue).div(1e18)
        ).mul(1e18).div(_totalSupply).div(1e18); // Get mint amount
        _mint(msg.sender, mintAmount); // Mint new pool tokens for depositor
    }

    /**
     * @dev External function to sell portion of holdings
     */
    function sellPosition(uint256 percent, uint256[] calldata expected)
        external
        inSwap
    {
        require(percent > 0 && percent <= 100, "Not between 1-100");
        (address[] memory tokens, , ) = getPortfolio();
        uint256 poolShare = calcPoolShare(_msgSender());
        uint256 burnAmount = _balances[_msgSender()].mul(percent).div(100e18); // Pass percent as 1e18 where 1e18 = 1
        _burn(_msgSender(), burnAmount);
        uint256[] memory sendAmounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            IERC20 erc = IERC20(tokens[i]);
            sendAmounts[i] = erc
                .balanceOf(address(this))
                .mul(poolShare.mul(percent).div(100e18))
                .div(100e18); // Total contract balance * (pool share * percent to sell) / 100
        }
        _swapRouter.makeTokenSwapForETH(
            tokens,
            sendAmounts,
            expected,
            address(_swapRouter)
        );
    }
}
