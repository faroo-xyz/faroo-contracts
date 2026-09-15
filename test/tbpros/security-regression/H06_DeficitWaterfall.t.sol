// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LossSnapshotModel} from "./models/RegressionModels.sol";

contract H06DeficitWaterfallTest is Test {
    function testOneUnitDeficitAbsorbedByF() public {
        LossSnapshotModel m = new LossSnapshotModel(900, 100, 10, 1009, address(this), address(0xB));
        vm.expectRevert(bytes("GLOBAL_DEFICIT"));
        m.legacyClaim();
        assertEq(m.claim(), 50);
        assertEq(m.F(), 9);
        assertEq(m.R(), 900);
        vm.expectRevert();
        m.claim();
    }

    function testFuzzSnapshotOrderIndependent(uint8 lossSeed) public {
        address b = address(0xB);
        uint256 l = uint256(lossSeed) % 201;
        LossSnapshotModel x = new LossSnapshotModel(90, 100, 10, l, address(this), b);
        LossSnapshotModel y = new LossSnapshotModel(90, 100, 10, l, address(this), b);
        uint256 xa = x.claim();
        vm.prank(b);
        uint256 xb = x.claim();
        vm.prank(b);
        uint256 yb = y.claim();
        uint256 ya = y.claim();
        assertEq(xa, ya);
        assertEq(xb, yb);
        assertLe(xa + xb, l);
        assertEq(x.L(), x.R() + x.P() + x.F());
    }
}
