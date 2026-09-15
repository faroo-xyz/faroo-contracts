// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {YieldModel} from "./models/RegressionModels.sol";

contract H03YieldSandwichTest is Test {
    function testOriginalOrderingProfitsFixedSameTimestampDoesNot() public {
        YieldModel oldM = new YieldModel(false, address(0xB));
        YieldModel fixedM = new YieldModel(true, address(0xB));
        vm.warp(block.timestamp + 1 days);
        oldM.subscribe(9_000_000 ether);
        oldM.nav();
        assertGt(oldM.fastAll(), 9_001_200 ether);
        fixedM.subscribe(9_000_000 ether);
        fixedM.nav();
        assertLe(fixedM.fastAll(), 9_000_000 ether);
    }

    function testLastSecondAndTransferCarryExistingNAV() public {
        YieldModel m = new YieldModel(true, address(this));
        vm.warp(block.timestamp + 1 days - 1);
        address a = address(0xA);
        vm.prank(a);
        m.subscribe(9_000_000 ether);
        uint256 r = m.R();
        uint256 s = m.S();
        uint256 q = m.shares(a);
        vm.warp(block.timestamp + 1);
        m.nav();
        uint256 paid;
        vm.prank(a);
        paid = m.fastAll();
        uint256 oneSecondUpper = uint256(9_000_000 ether) / (20 * 365 days) + 10;
        assertLe(paid, 9_000_000 ether + oneSecondUpper);
        assertGt(m.R(), 0);
        assertGt(r, 0);
        assertGt(s, q);
        uint256 remaining = m.shares(address(this));
        m.transfer(a, remaining);
        assertEq(m.shares(address(this)), 0);
        assertEq(m.shares(a), remaining);
        uint256 before = m.R();
        m.nav();
        assertEq(m.R(), before); // no duplicate catchup
    }
}
