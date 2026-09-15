// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITbPROSVault} from "../interfaces/ITbPROSVault.sol";
import {IStPROS} from "../interfaces/IStPROS.sol";
import {TbPROSStorage as S} from "../TbPROSStorage.sol";

/// @notice Stateless aggregation; raw rights getters remain on Vault when this optional view fails.
contract TbPROSLens {
    function solvency(ITbPROSVault vault)
        external
        view
        returns (bool insolvent, uint256 obligations, uint256 balance, uint256 deficit, uint256 surplus)
    {
        S.Accounting memory a = vault.accounting();
        obligations = uint256(a.R) + a.P + a.F;
        for (uint8 i; i < 2; ++i) {
            S.Plan memory p = vault.plan(i);
            obligations += uint256(p.sources[0].remaining) + p.sources[1].remaining;
        }
        insolvent = vault.mode().insolvent;
        balance = IStPROS(vault.asset()).balanceOf(address(vault));
        if (balance < obligations) deficit = obligations - balance;
        else surplus = balance - obligations;
    }
}
