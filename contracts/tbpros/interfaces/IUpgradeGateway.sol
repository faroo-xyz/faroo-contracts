// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IUpgradeGateway {
    struct Proposal {
        uint128 nonce;
        uint64 eta;
        bool canceled;
        address implementation;
        bytes32 dataHash;
    }

    function timelock() external view returns (address);
    function delayFloor() external view returns (uint64);
    function boundVault() external view returns (address);
    function proxyAdmin() external view returns (address);
    function proposal() external view returns (Proposal memory);
    function bind(address vault, address admin) external;
    function queueUpgrade(address implementation, bytes32 dataHash) external returns (uint128 nonce);
    function cancelUpgrade(uint128 nonce) external;
    function executeUpgrade(uint128 nonce, address implementation, bytes calldata data) external;
    function enter() external;
    function leave() external;
    function busy() external view returns (bool);
    function upgrading() external view returns (bool);
}
