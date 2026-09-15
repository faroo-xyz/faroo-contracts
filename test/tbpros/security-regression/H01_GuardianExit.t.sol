// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ExitModel} from "./models/RegressionModels.sol";

contract H01GuardianExitTest is Test {
    function testSafeAdmissionBeyondOrdinary24PositionLimit() public {
        ExitModel m = new ExitModel(address(this));
        m.seed(address(this), 26);
        m.pauseBoth();
        for (uint256 i; i < 25; i++) {
            vm.warp(block.timestamp + 32 days);
            m.safeRequest(1, block.timestamp + 31 days);
        }
        assertEq(m.escrow(), 25);
        assertEq(m.helpersCalled(), 25);
        assertEq(m.balances(address(this)), 1);
    }

    function testBothPausesAndNoTimelockResponse() public {
        address user = address(0xA);
        ExitModel m = new ExitModel(address(this));
        m.seed(user, 10 ether);
        m.pauseBoth();
        vm.prank(user);
        vm.expectRevert();
        m.ordinaryRequest(10 ether, block.timestamp + 31 days);
        vm.prank(user);
        m.safeRequest(10 ether, block.timestamp + 31 days);
        assertEq(m.escrow(), 10 ether);
        assertEq(m.helpersCalled(), 1);
        assertEq(m.positions(user, block.timestamp + 31 days), 10 ether);
        vm.expectRevert();
        m.safeRequest(1, block.timestamp + 31 days);
        assertTrue(m.riskPaused());
        assertTrue(m.requestsPaused());
    }
}
