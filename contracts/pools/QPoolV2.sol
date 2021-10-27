// SPDX-License-Identifier: MIT
// QFinance Contracts V2.0.1

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IMultiswap.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/Context.sol";

contract QPoolV2 is Context {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    // Multiswap router to facilitate swaps
    IMultiswap private _swapRouter = IMultiswap(0x08b16410c53FA67b0CC2cA58bd0F6409f3349f7a);

    // Standard ERC20 information
    string public _name;
    string public _symbol;
    uint256 private _totalSupply;
    
    // Total tokens for mapping loop
    uint8 public _totalTokens;
    
    // Use 1 = false, 2 = true to prevent reentrancy
    uint8 private _swap = 1;

    mapping (address => uint256) private _balances; // Standard ERC20 balances
    mapping (address => mapping (address => uint256)) private _allowances; // Standard ERC20 allowances
    mapping (address => uint256) private _deposits; // Track user deposits
    mapping (address => uint256) private _withdrawals; // Track user withdrawals
    mapping (uint => PortfolioToken) private _breakdown; // Portfolio mapping an int to a struct for mapping loop
    mapping (address => uint) private _tokenIndex; // Look up a token by its mapping value in _breakdown
    
    // Pack token data into struct
    struct PortfolioToken {
        uint160 token;
        uint8 amount;
    }

    constructor(string memory name_, string memory symbol_, address[] memory tokens_, uint256[] memory amounts_) {
        require(tokens_.length == amounts_.length, "Input error"); // Ensure inputs match
        _name = name_;
        _symbol = symbol_;
        uint256 totalPercent;
        
        for (uint256 i = 0; i < amounts_.length && i <= 5; i++) {
            totalPercent += amounts_[i];
            uint256 index = i + 1;
            _breakdown[index] = PortfolioToken(uint160(tokens_[i]), uint8(amounts_[i]));
        }
        require(totalPercent == 100, "QPool: Percent not 100"); // Validate 100% allocated
        _totalTokens = uint8(amounts_.length); // Set amount of tokens in portfolio
    }

    // Ensure pool can receive ETH
    fallback() external payable {}
    receive() external payable {}
    
    // Check if swap is already in progress to prevent reentrancy
    modifier inSwap {
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
    function calcPoolValue() public view returns (uint256 total)
    {
        (address[] memory tokens, uint256[] memory amounts, ) = getPortfolio();
        uint256[] memory slippage = new uint256[](tokens.length);
        for (uint i; i < tokens.length; i++) slippage[i] = 1;
        total = _swapRouter.checkAllValue(tokens, amounts, slippage);
        return total;
    }
    
    /**
     * @dev Function to calculate the total value of the pool's holdings for an individual token.
     */
    function calcTokenValue(address token) public view returns (uint256 value)
    {
        uint index = _tokenIndex[token];
        require(index != 0, "Token not in pool");
        uint balance = getPoolTokenBalance(token);
        value = _swapRouter.checkTokenValueETH(address(_breakdown[index].token), balance, 0);
        return value;
    }
    
    /**
     * @dev Function to get expected swap outputs. Should be called prior to making a swap.
     */
    function calcSwap(uint256 amount, uint256[] calldata slippage) public view returns (uint256[] memory expected)
    {
        (address[] memory tokens, uint256[] memory amounts, ) = getPortfolio();
        require(slippage.length == tokens.length, "Input error");
        (, expected, ) = _swapRouter.checkOutputsETH(tokens, amounts, slippage, amount);
        return expected;
    }
    
    /**
     * @dev Calculate the depositor's share after swapping for assets
     */
    function calculateShare(uint256 preValue, uint256 postValue) internal view returns (uint256, uint256) {
        uint256 amount = postValue.sub(preValue);
        uint256 share = amount.mul(100).div(postValue).div(100);
        uint256 mintAmount = share.mul(9925).div(_totalSupply).div(10000);
        return (share, mintAmount);
    }
    
    /**
     * 
     * POOL FUNCTIONS
     * 
    **/
    
    /**
     * @dev Finds a token in the portfolio and returns its details as a tuple
     */
    function getToken(uint index) public view returns (uint160 token, uint8 amount)
    {
        return (_breakdown[index].token, _breakdown[index].amount); // Parse struct to tuple
    }

    /**
     * @dev Parses mappings and returns the portfolio details as a tuple
     */
    function getPortfolio() public view returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        address[] memory tokens = new address[](_totalTokens);
        uint256[] memory amounts = new uint256[](_totalTokens);
        uint256[] memory poolBalances = new uint256[](_totalTokens);
        
        // We start this loop at 1 since our mapping keys increment from 1
        for (uint i = 1; i <= _totalTokens; i++) {
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
    function getValueETH(uint256[] calldata expected) public pure returns (uint256) {
        uint256 total;
        for (uint i; i < expected.length; i++) {
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
    
    function makeSwap(uint256[] calldata expected) public payable inSwap
    {
        (address[] memory tokens, uint256[] memory amounts, uint256[] memory holdings) = getPortfolio();
        uint256 preValue = calcPoolValue(); // Take value before deposit
        _swapRouter.makeETHSwap{value: msg.value}(tokens, amounts, expected, address(_swapRouter)); // Make token swaps
        uint256 postValue = calcPoolValue(); // Take value after swaps
        
        // This loop allows us to validate the price on chain without the use of an oracle. We test to ensure that the amount
        // we acquired is at least 99% of what was passed from the client-side (i.e. accept up to 1% slippage). Front-end
        // systems should ensure the value passed from the client side is properly secure against sandwich attacks.
        for (uint i; i < tokens.length; i++) {
            require(getPoolTokenBalance(tokens[i]).sub(holdings[i]) > expected[i].mul(99).div(100), "Too much slippage");
        }
        
        (, uint256 mintAmount) = calculateShare(preValue, postValue); // Get mint amount
        _mint(msg.sender, mintAmount); // Mint new pool tokens for depositor
    }
    
    /**
     * 
     * ERC20 FUNCTIONS
     * 
    **/ 
    
    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    function decimals() external pure returns (uint256)
    {
        return 18;
    }


    function balanceOf(address owner) public view returns (uint256 balance)
    {
        return _balances[owner];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address _recipient, uint256 _amount) public virtual returns (bool) {
        _transfer(_msgSender(), _recipient, _amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from zero addr");
        require(recipient != address(0), "ERC20: transfer to zero addr");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from zero addr");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from zero addr");
        require(spender != address(0), "ERC20: approve to zero addr");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}