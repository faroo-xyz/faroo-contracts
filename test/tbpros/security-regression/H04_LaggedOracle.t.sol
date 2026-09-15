// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {InventoryModel} from "./models/RegressionModels.sol";

contract H04LaggedOracleTest is Test {
    function testBurnRestoresPrincipalNotFlowBudget() public {
        InventoryModel oldM = new InventoryModel(false, false);
        InventoryModel newM = new InventoryModel(true, false);
        for (uint256 i; i < 3; i++) {
            oldM.subscribe(100_000 ether, 1 ether, 1 ether);
            oldM.exitAll();
        }
        assertEq(oldM.spent(), 300_000 ether);
        newM.subscribe(100_000 ether, 1 ether, 1 ether);
        newM.exitAll();
        vm.expectRevert(bytes("FLOW"));
        newM.subscribe(100_000 ether, 1 ether, 1 ether);
        assertEq(newM.spent(), 100_000 ether);
        assertEq(newM.outstanding(), 0);
        vm.warp(block.timestamp + 3600);
        newM.subscribe(3600 ether, 1 ether, 1 ether);
        assertLe(newM.spent(), newM.capacity() + 3600 * newM.refillPerSecond());
    }
}
