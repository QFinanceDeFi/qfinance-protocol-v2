// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./PoolToken.sol";
import "./PoolMath.sol";

contract Pool is PoolToken, PoolMath {

    struct Record {
        uint256 denorm; // denormalized weight
        uint256 balance;
        uint8 index;
        uint8 bound;
    }

    struct PoolData {
        uint160 factory;
        uint64 swapFee;
        uint8 mutex;
        uint8 totalTokens;
        uint8 finalized;
    }

    PoolData private poolData;

    mapping(uint256 => address) private _tokens;

    mapping(address => Record) private _records;
    uint256 private _totalWeight;

    constructor() {
        poolData.factory = uint160(msg.sender);
        poolData.swapFee = uint64(MIN_FEE);
        poolData.mutex = 1;
        poolData.totalTokens = 0;
        poolData.finalized = 1;
    }

    function isFinalized() external view returns (bool) {
        return poolData.finalized == 2 ? true : false;
    }

    function isBound(address t) external view returns (bool) {
        return _records[t].bound == 2 ? true : false;
    }

    function getNumTokens() external view returns (uint256) {
        return poolData.totalTokens;
    }

    function getToken(uint256 index) internal view returns (address) {
        return _tokens[index];
    }

    function getCurrentTokens()
        external
        view
        _viewlock_
        returns (address[] memory)
    {
        address[] memory tokens = new address[](poolData.totalTokens);

        for (uint256 i; i < poolData.totalTokens; i++) {
            tokens[i] = getToken(i + 1);
        }

        return tokens;
    }

    function getFinalTokens()
        external
        view
        _viewlock_
        returns (address[] memory)
    {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");

        address[] memory tokens = new address[](poolData.totalTokens);

        for (uint256 i; i < poolData.totalTokens; i++) {
            tokens[i] = getToken(i + 1);
        }

        return tokens;
    }

    function getDenormalizedWeight(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound == 2, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
        external
        view
        _viewlock_
        returns (uint256)
    {
        return _totalWeight;
    }

    function getNormalizedWeight(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound == 2, "ERR_NOT_BOUND");
        uint256 denorm = _records[token].denorm;
        return div(denorm, _totalWeight);
    }

    function getBalance(address token)
        external
        view
        _viewlock_
        returns (uint256)
    {
        require(_records[token].bound == 2, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getSwapFee() external view _viewlock_ returns (uint256) {
        return poolData.swapFee;
    }

    function setSwapFee(uint256 swapFee) external _logs_ _lock_ {
        require(poolData.finalized == 1, "ERR_IS_FINALIZED");
        require(swapFee >= MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= MAX_FEE, "ERR_MAX_FEE");
        poolData.swapFee = uint64(swapFee);
    }

    function finalize() external _logs_ _lock_ {
        require(poolData.finalized == 1, "ERR_IS_FINALIZED");
        require(poolData.totalTokens >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");

        poolData.finalized = 2;

        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);
    }

    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    )
        external
        _logs_
    {
        require(_records[token].bound == 1, "ERR_IS_BOUND");
        require(poolData.finalized == 1, "ERR_IS_FINALIZED");
        require(poolData.totalTokens < MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");

        // Increment prior to setting record index so mapping starts at 1
        poolData.totalTokens += 1;

        _records[token] = Record({
            bound: 2,
            index: poolData.totalTokens,
            denorm: 0, // balance and denorm will be validated
            balance: 0 // and set by `rebind`
        });

        _tokens[poolData.totalTokens] = token;
        rebind(token, balance, denorm);
    }

    function rebind(
        address token,
        uint256 balance,
        uint256 denorm
    ) public _logs_ _lock_ {
        require(_records[token].bound == 2, "ERR_NOT_BOUND");
        require(poolData.finalized == 1, "ERR_IS_FINALIZED");
        require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(balance >= MIN_BALANCE, "ERR_MIN_BALANCE");

        // Adjust the denorm and totalWeight
        uint256 oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight = add(_totalWeight, sub(denorm, oldWeight));
            require(_totalWeight <= MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
        } else if (denorm < oldWeight) {
            _totalWeight = sub(_totalWeight, sub(oldWeight, denorm));
        }
        _records[token].denorm = denorm;

        // Adjust the balance record and actual token balance
        uint256 oldBalance = _records[token].balance;
        _records[token].balance = balance;
        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, sub(balance, oldBalance));
        } else if (balance < oldBalance) {
            // In this case liquidity is being withdrawn, so charge EXIT_FEE
            uint256 tokenBalanceWithdrawn = sub(oldBalance, balance);
            uint256 tokenExitFee = mul(tokenBalanceWithdrawn, EXIT_FEE);
            _pushUnderlying(
                token,
                msg.sender,
                sub(tokenBalanceWithdrawn, tokenExitFee)
            );
            _pushUnderlying(token, address(poolData.factory), tokenExitFee);
        }
    }

    function unbind(address token) external _logs_ _lock_ {
        require(_records[token].bound == 2, "ERR_NOT_BOUND");
        require(poolData.finalized == 1, "ERR_IS_FINALIZED");

        uint256 tokenBalance = _records[token].balance;
        uint256 tokenExitFee = mul(tokenBalance, EXIT_FEE);

        _totalWeight = sub(_totalWeight, _records[token].denorm);

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint256 index = _records[token].index;
        _tokens[index] = _tokens[poolData.totalTokens];
        _records[_tokens[index]].index = uint8(index);
        poolData.totalTokens -= 1;
        delete _records[token];

        _pushUnderlying(token, msg.sender, sub(tokenBalance, tokenExitFee));
        _pushUnderlying(token, address(poolData.factory), tokenExitFee);
    }

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token) external _logs_ _lock_ {
        require(_records[token].bound == 2, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    function getSpotPrice(address tokenIn, address tokenOut)
        external
        view
        _viewlock_
        returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound == 2, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound == 2, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return
            calcSpotPrice(
                inRecord.balance,
                inRecord.denorm,
                outRecord.balance,
                outRecord.denorm,
                poolData.swapFee
            );
    }

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external
        view
        _viewlock_
        returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound == 2, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound == 2, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return
            calcSpotPrice(
                inRecord.balance,
                inRecord.denorm,
                outRecord.balance,
                outRecord.denorm,
                0
            );
    }

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn)
        external
        _logs_
        _lock_
    {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 ratio = div(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint256 i; i < poolData.totalTokens; i++) {
            address t = getToken(i + 1);
            uint256 balance = _records[t].balance;
            uint256 tokenAmountIn = mul(ratio, balance);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _records[t].balance = add(_records[t].balance, tokenAmountIn);
            emit Join(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut)
        external
        _logs_
        _lock_
    {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");

        uint256 poolTotal = totalSupply();
        uint256 exitFee = mul(poolAmountIn, EXIT_FEE);
        uint256 pAiAfterExitFee = sub(poolAmountIn, exitFee);
        uint256 ratio = div(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(address(poolData.factory), exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i; i < poolData.totalTokens; i++) {
            address t = getToken(i + 1);
            uint256 balance = _records[t].balance;
            uint256 tokenAmountOut = mul(ratio, balance);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            _records[t].balance = sub(_records[t].balance, tokenAmountOut);
            emit Exit(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }
    }

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
        external
        _logs_
        _lock_
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(_records[tokenIn].bound == 2, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound == 2, "ERR_NOT_BOUND");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountIn <= mul(inRecord.balance, MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        uint256 spotPriceBefore = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            poolData.swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountOut = calcOutGivenIn(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountIn,
            poolData.swapFee
        );
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = add(inRecord.balance, tokenAmountIn);
        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            poolData.swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(
            spotPriceBefore <= div(tokenAmountIn, tokenAmountOut),
            "ERR_MATH_APPROX"
        );

        emit Swap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return (tokenAmountOut, spotPriceAfter);
    }

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
        external
        _logs_
        _lock_
        returns (uint256 tokenAmountIn, uint256 spotPriceAfter)
    {
        require(_records[tokenIn].bound == 2, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound == 2, "ERR_NOT_BOUND");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountOut <= mul(outRecord.balance, MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        uint256 spotPriceBefore = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            poolData.swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountIn = calcInGivenOut(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountOut,
            poolData.swapFee
        );
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        inRecord.balance = add(inRecord.balance, tokenAmountIn);
        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            poolData.swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(
            spotPriceBefore <= div(tokenAmountIn, tokenAmountOut),
            "ERR_MATH_APPROX"
        );

        emit Swap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return (tokenAmountIn, spotPriceAfter);
    }

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external _logs_ _lock_ returns (uint256 poolAmountOut) {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound == 2, "ERR_NOT_BOUND");
        require(
            tokenAmountIn <= mul(_records[tokenIn].balance, MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        Record storage inRecord = _records[tokenIn];

        poolAmountOut = calcPoolOutGivenSingleIn(
            inRecord.balance,
            inRecord.denorm,
            _totalSupply,
            _totalWeight,
            tokenAmountIn,
            poolData.swapFee
        );

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = add(inRecord.balance, tokenAmountIn);

        emit Join(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return poolAmountOut;
    }

    function joinswapPoolAmountOut(
        address tokenIn,
        uint256 poolAmountOut,
        uint256 maxAmountIn
    ) external _logs_ _lock_ returns (uint256 tokenAmountIn) {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound == 2, "ERR_NOT_BOUND");

        Record storage inRecord = _records[tokenIn];

        tokenAmountIn = calcSingleInGivenPoolOut(
            inRecord.balance,
            inRecord.denorm,
            _totalSupply,
            _totalWeight,
            poolAmountOut,
            poolData.swapFee
        );

        require(tokenAmountIn != 0, "ERR_MATH_APPROX");
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        require(
            tokenAmountIn <= mul(_records[tokenIn].balance, MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        inRecord.balance = add(inRecord.balance, tokenAmountIn);

        emit Join(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        return tokenAmountIn;
    }

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external _logs_ _lock_ returns (uint256 tokenAmountOut) {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound == 2, "ERR_NOT_BOUND");

        Record storage outRecord = _records[tokenOut];

        tokenAmountOut = calcSingleOutGivenPoolIn(
            outRecord.balance,
            outRecord.denorm,
            _totalSupply,
            _totalWeight,
            poolAmountIn,
            poolData.swapFee
        );

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        require(
            tokenAmountOut <= mul(_records[tokenOut].balance, MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        uint256 exitFee = mul(poolAmountIn, EXIT_FEE);

        emit Exit(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(sub(poolAmountIn, exitFee));
        _pushPoolShare(address(poolData.factory), exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return tokenAmountOut;
    }

    function exitswapExternAmountOut(
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPoolAmountIn
    ) external _logs_ _lock_ returns (uint256 poolAmountIn) {
        require(poolData.finalized == 2, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound == 2, "ERR_NOT_BOUND");
        require(
            tokenAmountOut <= mul(_records[tokenOut].balance, MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        Record storage outRecord = _records[tokenOut];

        poolAmountIn = calcPoolInGivenSingleOut(
            outRecord.balance,
            outRecord.denorm,
            _totalSupply,
            _totalWeight,
            tokenAmountOut,
            poolData.swapFee
        );

        require(poolAmountIn != 0, "ERR_MATH_APPROX");
        require(poolAmountIn <= maxPoolAmountIn, "ERR_LIMIT_IN");

        outRecord.balance = sub(outRecord.balance, tokenAmountOut);

        uint256 exitFee = mul(poolAmountIn, EXIT_FEE);

        emit Exit(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(sub(poolAmountIn, exitFee));
        _pushPoolShare(address(poolData.factory), exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return poolAmountIn;
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety on functions that use these.

    function _pullUnderlying(
        address erc20,
        address from,
        uint256 amount
    ) internal {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(
        address erc20,
        address to,
        uint256 amount
    ) internal {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pullPoolShare(address from, uint256 amount) internal {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint256 amount) internal {
        _push(to, amount);
    }

    function _mintPoolShare(uint256 amount) internal {
        _mint(amount);
    }

    function _burnPoolShare(uint256 amount) internal {
        _burn(amount);
    }

        event Swap(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    event Join(
        address indexed caller,
        address indexed tokenIn,
        uint256 tokenAmountIn
    );

    event Exit(
        address indexed caller,
        address indexed tokenOut,
        uint256 tokenAmountOut
    );

    event Call(
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    modifier _logs_() {
        emit Call(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        require(poolData.mutex == 1, "ERR_REENTRY");
        poolData.mutex = 2;
        _;
        poolData.mutex = 1;
    }

    modifier _viewlock_() {
        require(poolData.mutex == 1, "ERR_REENTRY");
        _;
    }
}
