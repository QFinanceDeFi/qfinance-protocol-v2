// SPDX-License-Identifier: MIT
// QFinance Contracts V2.0.1

pragma solidity ^0.8.0;

interface IMultiswap {

    /**
     * @dev Checks and returns expected output fom ETH swap.
     */
    function checkOutputsETH(
        address[] memory _tokens,
        uint256[] memory _percent,
        uint256[] memory _slippage,
        uint256 _total
    ) external view returns (address[] memory, uint256[] memory, uint256);

    /**
     * @dev Checks and returns expected output from token swap.
     */
    function checkOutputsToken(
        address[] memory _tokens,
        uint256[] memory _percent,
        uint256[] memory _slippage,
        address _base,
        uint256 _total
    ) external view returns (address[] memory, uint256[] memory);
    
    /**
     * @dev Checks and returns ETH value of token amount.
    */
    function checkTokenValueETH(
        address _token,
        uint256 _amount,
        uint256 _slippage
    ) external view returns (uint256);

    /**
     * @dev Checks and returns ETH value of portfolio.
    */
    function checkAllValue(address[] memory _tokens, uint256[] memory _amounts, uint256[] memory _slippage)
        external
        view
        returns (uint256);

    /**
     * @dev Execute ETH swap for each token in portfolio.
     */
    function makeETHSwap(address[] memory _tokens, uint256[] memory _percent, uint256[] memory _expected, address _referrer)
        external
        payable;

    /**
     * @dev Execute token swap for each token in portfolio.
     */
    function makeTokenSwap(
        address[] memory _tokens,
        uint256[] memory _percent,
        uint256[] memory _expected,
        address _referrer,
        address _base,
        uint256 _total
    ) external;

    /**
     * @dev Execute token swap with ETH as output asset
    */
    function makeTokenSwapForETH(
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory _expected,
        address referrer
    ) external;

}