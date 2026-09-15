// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MintModel, RegressionAsset} from "./models/RegressionModels.sol";

contract H02LowSupplyMintTest is Test {
    RegressionAsset token;

    function setUp() public {
        token = new RegressionAsset();
        token.mint(address(this), type(uint128).max);
    }

    function testLegacyExtractionAndFixedPreTransferGate() public {
        uint256 d = 1 ether;
        MintModel oldM = new MintModel(d + 1, 1, false, token);
        token.approve(address(oldM), type(uint256).max);
        assertEq(oldM.subscribe(uint128(2 * d)), 1);
        assertEq(oldM.R() / oldM.S() - (d + 1), d / 2 - 1);
        MintModel newM = new MintModel(d + 1, 1, true, token);
        token.approve(address(newM), type(uint256).max);
        vm.expectCall(
            address(token),
            abi.encodeWithSelector(token.transferFrom.selector, address(this), address(newM), 2 * d),
            uint64(0)
        );
        vm.expectRevert(MintModel.UnfairMint.selector);
        newM.subscribe(uint128(2 * d));
        assertEq(newM.R(), d + 1);
        assertEq(newM.S(), 1);
    }

    function testLegacy119RoundAmplificationVictimBlocked() public {
        MintModel oldM = new MintModel(1e11 + 1, 1, false, token);
        token.approve(address(oldM), type(uint256).max);
        uint256 rounds;
        while (oldM.R() < 1e24) {
            uint256 r = oldM.R();
            uint256 m = (2 * r - 1) * 3 / 1e12;
            if (m == 0) m = 1;
            uint256[7] memory ks = [uint256(1), 2, 3, m, m > 1 ? m - 1 : 1, m + 1, m + 2];
            uint256 bestR;
            uint256 bestA;
            for (uint256 j; j < 7; j++) {
                uint256 a = ks[j] * 1e12 / 3;
                uint256 q = a / r;
                if (q == 0) continue;
                uint256 nr = r + a - q * (r + a) / (q + 1);
                if (nr > bestR || (nr == bestR && a > bestA)) {
                    bestR = nr;
                    bestA = a;
                }
            }
            uint256 minted = oldM.subscribe(uint128(bestA));
            oldM.fastBurn(minted);
            assertEq(oldM.S(), 1);
            assertGt(oldM.R(), r);
            rounds++;
            require(rounds < 200);
        }
        assertEq(rounds, 119);
        assertEq(oldM.R(), 1289860291852071152694510);
        uint128 victim = 2579720583704000000000000;
        MintModel fixedM = new MintModel(oldM.R(), 1, true, token);
        token.approve(address(fixedM), type(uint256).max);
        vm.expectRevert(MintModel.UnfairMint.selector);
        fixedM.subscribe(victim);
        uint256 attackerCapital = oldM.R();
        address victimActor = address(0xBEEF);
        token.mint(victimActor, victim);
        vm.startPrank(victimActor);
        token.approve(address(oldM), victim);
        oldM.subscribe(victim);
        vm.stopPrank();
        assertEq(oldM.R() / 2 - attackerCapital, 644930145925964423652745);
        uint256 beforePayout = token.balanceOf(address(this));
        uint256 attackerPayout = oldM.fastBurn(1);
        assertEq(token.balanceOf(address(this)) - beforePayout, attackerPayout);
        assertEq(attackerPayout - attackerCapital, 644930145925964423652745);
        vm.prank(victimActor);
        uint256 victimPayout = oldM.fastBurn(1);
        assertEq(victim - victimPayout, attackerPayout - attackerCapital);
        assertEq(token.balanceOf(address(oldM)), 0);
        assertEq(oldM.R(), 0);
        assertEq(oldM.S(), 0);
    }

    function testFuzzE01(uint64 a0, uint64 r0, uint64 s0) public {
        uint128 a = uint128(a0) + 1;
        uint256 s = uint256(s0) + 1;
        uint256 r = s + uint256(r0);
        MintModel m = new MintModel(r, s, true, token);
        token.approve(address(m), type(uint256).max);
        uint256 rem = mulmod(a, s, r);
        if (uint256(a) * s / r == 0 || rem * 10000 > uint256(a) * s) {
            vm.expectRevert(MintModel.UnfairMint.selector);
            m.subscribe(a);
        } else {
            m.subscribe(a);
            assertLe(m.lastLossBpsCeil(), 1);
        }
    }
}
