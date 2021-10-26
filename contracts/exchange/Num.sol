// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Const.sol";

contract Num is Const {

    /**
    * @dev Takes value `a` and normalizes from 18 decimal places.
    */
    function toi(uint256 a) internal pure returns (uint256) {
        return a / ONE;
    }

    /**
    * @dev Converts value `a` and normalizes to 18 decimal places.
    */
    function floor(uint256 a) internal pure returns (uint256) {
        return toi(a) * ONE;
    }

    /**
    * @dev Check addition overflow
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    /**
    * @dev Check subtraction overflow
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        (uint256 c, bool flag) = subSign(a, b);
        require(!flag, "ERR_SUB_UNDERFLOW");
        return c;
    }

    /**
    * @dev Check if negative value and if so, return true along with value
    */
    function subSign(uint256 a, uint256 b)
        internal
        pure
        returns (uint256, bool)
    {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    /**
    * @dev Check multiplication errors
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, "ERR_MUL_OVERFLOW");
        uint256 c1 = c0 + (ONE / 2);
        require(c1 >= c0, "ERR_MUL_OVERFLOW");
        uint256 c2 = c1 / ONE;
        return c2;
    }

    /**
    * @dev Check division errors
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "ERR_DIV_ZERO");
        uint256 c0 = a * ONE;
        require(a == 0 || c0 / a == ONE, "ERR_DIV_INTERNAL"); // bmul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, "ERR_DIV_INTERNAL"); //  badd require
        uint256 c2 = c1 / b;
        return c2;
    }

    // DSMath.wpow
    function powi(uint256 a, uint256 n) internal pure returns (uint256) {
        uint256 z = n % 2 != 0 ? a : ONE;

        for (n /= 2; n != 0; n /= 2) {
            a = mul(a, a);

            if (n % 2 != 0) {
                z = mul(z, a);
            }
        }
        return z;
    }

    // Compute b^(e.w) by splitting it into (b^e)*(b^0.w).
    // Use `powi` for `b^e` and `powK` for k iterations
    // of approximation of b^0.w
    function pow(uint256 base, uint256 exp) internal pure returns (uint256) {
        require(base >= MIN_POW_BASE, "ERR_POW_BASE_TOO_LOW");
        require(base <= MAX_POW_BASE, "ERR_POW_BASE_TOO_HIGH");

        uint256 whole = floor(exp);
        uint256 remain = sub(exp, whole);

        uint256 wholePow = powi(base, toi(whole));

        if (remain == 0) {
            return wholePow;
        }

        uint256 partialResult = powApprox(base, remain, POW_PRECISION);
        return mul(wholePow, partialResult);
    }

    function powApprox(
        uint256 base,
        uint256 exp,
        uint256 precision
    ) internal pure returns (uint256) {
        // term 0:
        uint256 a = exp;
        (uint256 x, bool xneg) = subSign(base, ONE);
        uint256 term = ONE;
        uint256 sum = term;
        bool negative = false;

        // term(k) = numer / denom
        //         = (product(a - i - 1, i=1-->k) * x^k) / (k!)
        // each iteration, multiply previous term by (a-(k-1)) * x / k
        // continue until term is less than precision
        for (uint256 i = 1; term >= precision; i++) {
            uint256 bigK = i * ONE;
            (uint256 c, bool cneg) = subSign(a, sub(bigK, ONE));
            term = mul(term, mul(c, x));
            term = div(term, bigK);
            if (term == 0) break;

            if (xneg) negative = !negative;
            if (cneg) negative = !negative;
            if (negative) {
                sum = sub(sum, term);
            } else {
                sum = add(sum, term);
            }
        }

        return sum;
    }
}
