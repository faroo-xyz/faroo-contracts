// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {InventoryModel} from "./models/RegressionModels.sol";

contract H05USDCDepegTest is Test {
    function testFaceValueExtractionAndCircuitBreaker() public {
        InventoryModel a = new InventoryModel(false, false);
        InventoryModel b = new InventoryModel(true, true);
        uint256 out = a.subscribe(100_000 ether, 1 ether, 0.8 ether);
        assertEq(out - 80_000 ether, 20_000 ether);
        vm.expectRevert(bytes("DEPEG"));
        b.subscribe(100_000 ether, 1 ether, 0.8 ether);
        assertEq(b.spent(), 0);
    }
}
