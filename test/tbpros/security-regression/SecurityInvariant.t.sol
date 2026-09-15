// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MintModel, RegressionAsset, InventoryModel} from "./models/RegressionModels.sol";

contract SecurityHandler is Test {
    MintModel public mintModel;
    InventoryModel public inventory;
    uint256 public accepted;
    uint256 public rejected;
    uint256 public immutable start;

    constructor() {
        RegressionAsset t = new RegressionAsset();
        t.mint(address(this), type(uint128).max);
        mintModel = new MintModel(1003 ether, 1000 ether, true, t);
        t.approve(address(mintModel), type(uint256).max);
        inventory = new InventoryModel(true, false);
        start = block.timestamp;
        mintModel.subscribe(1 ether);
        accepted = 1;
    }

    function mintAndExit(uint64 seed) external {
        uint128 amount = uint128(seed) + 1;
        try mintModel.subscribe(amount) returns (uint256 q) {
            assertLe(mintModel.lastLossBpsCeil(), 1);
            // Independently measure the buyer's post-mint redeemable rational value.
            // This fixture's amounts keep both cross products within uint256.
            uint256 nominal = uint256(amount) * mintModel.S();
            uint256 valueNumerator = q * mintModel.R();
            assertLe((nominal - valueNumerator) * 10_000, nominal);
            accepted++;
            mintModel.fastBurn(q);
        } catch (bytes memory reason) {
            assertGe(reason.length, 4);
            bytes4 sig;
            assembly {
                sig := mload(add(reason, 32))
            }
            assertEq(sig, MintModel.UnfairMint.selector);
            rejected++;
        }
    }

    function buyExitAndAdvance(uint32 dt, uint64 a) external {
        vm.warp(block.timestamp + uint256(dt) % 3601);
        uint256 amount = uint256(a) % 100_000 ether + 1;
        uint256 available = inventory.tokens() + (block.timestamp - inventory.last()) * inventory.refillPerSecond();
        if (available > inventory.capacity()) available = inventory.capacity();
        if (amount > available || amount > inventory.reserve()) {
            rejected++;
            return;
        }
        inventory.subscribe(amount, 1 ether, 1 ether);
        inventory.exitAll();
        accepted++;
    }
}

contract SecurityInvariantTest is StdInvariant, Test {
    SecurityHandler h;

    function setUp() public {
        h = new SecurityHandler();
        targetContract(address(h));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = h.mintAndExit.selector;
        selectors[1] = h.buyExitAndAdvance.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: selectors}));
    }

    function invariant_E01AndE05BoundedModels() public view {
        assertLe(h.mintModel().lastLossBpsCeil(), 1);
        assertEq(h.mintModel().token().balanceOf(address(h.mintModel())), h.mintModel().R());
        InventoryModel m = h.inventory();
        assertLe(m.spent(), m.capacity() + (block.timestamp - h.start()) * m.refillPerSecond());
        assertEq(m.outstanding(), 0);
        assertGt(h.accepted(), 0);
    }
}
