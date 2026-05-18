// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Counter is Initializable, OwnableUpgradeable {
  uint256 public x;

  event Increment(uint256 by);

  function initialize(address initialOwner, uint256 _x) public initializer {
    __Ownable_init(initialOwner);
    x = _x;
  }

  function inc() public {
    x = x + 1;
    emit Increment(1);
  }

  function incBy(uint256 by) public {
    require(by > 0, "incBy: increment should be positive");
    x += by;
    emit Increment(by);
  }
}
