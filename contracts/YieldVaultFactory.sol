// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {Counter} from "./Counter.sol";

contract YieldVaultFactory is Initializable, OwnableUpgradeable {
    UpgradeableBeacon public beacon;

    address[] public allProxies;

    event BeaconCreated(address indexed beacon, address indexed implementation);
    event CounterCreated(address indexed proxy, address indexed creator, uint256 initialX);
    event BeaconUpgraded(address indexed oldImplementation, address indexed newImplementation);

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);

        Counter implementation = new Counter();

        beacon = new UpgradeableBeacon(
            address(implementation),
            address(this)
        );

        emit BeaconCreated(address(beacon), address(implementation));
    }

    function createYieldVault(uint256 _x) external returns (address proxyAddr) {
        bytes memory initData = abi.encodeWithSelector(
            Counter.initialize.selector,
            msg.sender,
            _x
        );

        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            initData
        );

        proxyAddr = address(proxy);

        allProxies.push(proxyAddr);

        emit CounterCreated(proxyAddr, msg.sender, _x);

        return proxyAddr;
    }

    function upgradeBeaconTo(address newImplementation) external onlyOwner {
        require(newImplementation.code.length > 0, "Invalid implementation");

        address oldImplementation = beacon.implementation();

        beacon.upgradeTo(newImplementation);

        emit BeaconUpgraded(oldImplementation, newImplementation);
    }

    function getAllProxies() external view returns (address[] memory) {
        return allProxies;
    }

    function totalProxies() external view returns (uint256) {
        return allProxies.length;
    }

    function currentImplementation() external view returns (address) {
        return beacon.implementation();
    }
}