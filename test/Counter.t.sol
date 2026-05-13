// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Counter} from "../contracts/Counter.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Test} from "forge-std/Test.sol";

contract CounterTest is Test {
  Counter internal counter;

  function setUp() public {
    Counter impl = new Counter();
    bytes memory data = abi.encodeCall(Counter.initialize, (address(this)));
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(impl),
      address(this),
      data
    );
    counter = Counter(address(proxy));
  }

  function test_InitialValue() public view {
    require(counter.x() == 0, "Initial value should be 0");
  }

  function testFuzz_Inc(uint8 n) public {
    for (uint8 i = 0; i < n; i++) {
      counter.inc();
    }
    require(counter.x() == n, "Value after calling inc n times should be n");
  }

  function test_IncByZero() public {
    vm.expectRevert();
    counter.incBy(0);
  }
}
