// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {YieldVault} from "./YieldVault.sol";

interface IFactoryManagedYieldVault {
    function emergencyCancel() external;
}

contract YieldVaultFactory is Initializable, OwnableUpgradeable, PausableUpgradeable {
    /// @notice Thrown when counterparty address is invalid
    error InvalidCounterparty();

    /// @notice Thrown when vault address is not created by factory
    error InvalidVault(address vault);

    /// @notice Thrown when implementation address has no code
    error InvalidImplementation();
    /// @notice Thrown when init params factory is not current factory
    error InvalidFactoryInParams(address factoryInParams);

    UpgradeableBeacon public beacon;

    address[] public allProxies;
    mapping(address => bool) public isFactoryVault;
    mapping(address => bool) public counterpartyWhitelist;

    event BeaconCreated(address indexed beacon, address indexed implementation);
    event YieldVaultCreated(address indexed proxy, address indexed creator);
    event BeaconUpgraded(address indexed oldImplementation, address indexed newImplementation);
    event CounterpartyWhitelistUpdated(address indexed counterparty, bool allowed);
    event EmergencyCancelled(address indexed vault, address indexed operator);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __Pausable_init();

        YieldVault implementation = new YieldVault();

        beacon = new UpgradeableBeacon(
            address(implementation),
            address(this)
        );

        emit BeaconCreated(address(beacon), address(implementation));
    }

    /// @notice Add counterparty address into whitelist
    function addCounterpartyToWhitelist(address counterparty) external onlyOwner {
        if (counterparty == address(0)) {
            revert InvalidCounterparty();
        }

        counterpartyWhitelist[counterparty] = true;
        emit CounterpartyWhitelistUpdated(counterparty, true);
    }

    /// @notice Remove counterparty address from whitelist
    function removeCounterpartyFromWhitelist(address counterparty) external onlyOwner {
        if (counterparty == address(0)) {
            revert InvalidCounterparty();
        }

        counterpartyWhitelist[counterparty] = false;
        emit CounterpartyWhitelistUpdated(counterparty, false);
    }

    function createYieldVault(YieldVault.InitParams calldata params) external onlyOwner whenNotPaused returns (address proxyAddr) {
        if (params.factory != address(this)) {
            revert InvalidFactoryInParams(params.factory);
        }
        if (!counterpartyWhitelist[params.counterparty]) {
            revert InvalidCounterparty();
        }

        bytes memory initData = abi.encodeWithSelector(
            YieldVault.initialize.selector,
            params
        );

        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            initData
        );

        proxyAddr = address(proxy);

        allProxies.push(proxyAddr);
        isFactoryVault[proxyAddr] = true;

        emit YieldVaultCreated(proxyAddr, msg.sender);

        return proxyAddr;
    }

    /// @notice Emergency-cancel an epoch vault (only works while vault is SUBSCRIBING)
    function emergencyCancel(address vault) external onlyOwner {
        if (!isFactoryVault[vault]) {
            revert InvalidVault(vault);
        }

        IFactoryManagedYieldVault(vault).emergencyCancel();
        emit EmergencyCancelled(vault, msg.sender);
    }

    /// @notice Pause factory: block createYieldVault and downstream vault deposit/fundProfit checks
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause factory
    function unpause() external onlyOwner {
        _unpause();
    }

    function upgradeBeaconTo(address newImplementation) external onlyOwner {
        if (newImplementation.code.length == 0) {
            revert InvalidImplementation();
        }

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
