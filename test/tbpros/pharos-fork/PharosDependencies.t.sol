// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeDuringCallbackTest, GatewayProbe, FrameProbe} from "regression/UpgradeDuringCallback.t.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IWPROS {
    function deposit() external payable;
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IRealSt {
    function asset() external view returns (address);
    function deposit(uint256, address) external returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

contract RealPathProbe is FrameProbe {
    function depositReal(IRealSt st, uint256 amount) external returns (uint256 minted) {
        gateway.enter();
        require(gateway.busy());
        require(IWPROS(st.asset()).approve(address(st), amount));
        minted = st.deposit(amount, address(this));
        require(gateway.busy());
        gateway.leave();
    }
}

contract PharosDependenciesTest is UpgradeDuringCallbackTest {
    IRealSt constant ST = IRealSt(address(bytes20(hex"6b0a44c64190279f7034b77c13a566e914fe5ec4")));

    function setUp() public override {
        vm.createSelectFork("pharos", 17602269);
        assertEq(block.chainid, 1672);
        assertEq(block.number, 17602269);
        super.setUp();
    }

    function testFixedBlockRealStPROSDepositThroughProxyAndLatch() public {
        GatewayProbe gate = new GatewayProbe(address(tl));
        RealPathProbe v = RealPathProbe(
            address(
                new TransparentUpgradeableProxy(
                    address(new RealPathProbe()), address(gate), abi.encodeCall(FrameProbe.init, (gate))
                )
            )
        );
        bytes memory b = schedule(address(gate), abi.encodeCall(gate.bind, (address(v), adminOf(address(v)))));
        (bool ok,) = address(tl).call(b);
        assertTrue(ok);
        IWPROS w = IWPROS(ST.asset());
        vm.deal(address(this), 1 ether);
        w.deposit{value: 1 ether}();
        assertTrue(w.transfer(address(v), 1 ether));
        uint256 custodyBefore = w.balanceOf(address(ST));
        uint256 minted = v.depositReal(ST, 1 ether);
        assertGt(minted, 0);
        assertEq(ST.balanceOf(address(v)), minted);
        assertEq(w.balanceOf(address(v)), 0);
        assertFalse(gate.busy());
        // This fixed block runs the OLD custody implementation, not HEAD's SLP version.
        assertEq(w.balanceOf(address(ST)) - custodyBefore, 1 ether);
    }

    function testFixedBlockSlpGetterMissingIsRecordedDependencyGap() public view {
        (bool ok,) = address(ST).staticcall(abi.encodeWithSignature("slp()"));
        assertFalse(ok); // proves mismatch, NOT successful production SLP coverage
    }
}
