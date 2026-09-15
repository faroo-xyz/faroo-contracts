// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITbPROSVault} from "../interfaces/ITbPROSVault.sol";
import {IStPROS} from "../interfaces/IStPROS.sol";
import {TbPROSTypes as S} from "../TbPROSTypes.sol";

/// @notice Stateless aggregation; raw rights getters remain on Vault when this optional view fails.
contract TbPROSLens {
    /// @notice Aggregates raw Vault obligations and the actual stPROS custody balance.
    /// @dev Stateless optional view; no Oracle/Reserve. Q is uint256 and at most 7*(2^128-1); a failed balance call may fail Lens but cannot disable raw Vault rights getters.
    /// @param vault Vault whose fixed bindings or raw state are checked.
    /// @return insolvent Committed insolvency flag.
    /// @return obligations Q in stPROS raw18, derived in uint256.
    /// @return balance Actual L in stPROS raw18.
    /// @return deficit max(Q-L,0) in stPROS raw18.
    /// @return surplus max(L-Q,0) in stPROS raw18.
    function solvency(ITbPROSVault vault)
        external
        view
        returns (bool insolvent, uint256 obligations, uint256 balance, uint256 deficit, uint256 surplus)
    {
        S.Accounting memory a = vault.accounting();
        obligations = uint256(a.R) + a.P + a.F;
        for (uint8 i; i < 2; ++i) {
            obligations += uint256(vault.sourceRemaining(i, 0)) + vault.sourceRemaining(i, 1);
        }
        insolvent = vault.mode().insolvent;
        balance = IStPROS(vault.backingAsset()).balanceOf(address(vault));
        if (balance < obligations) deficit = obligations - balance;
        else surplus = balance - obligations;
    }
}
