// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IProsReserve {
    enum Purpose {
        Subscription,
        Yield
    }

    struct Period {
        uint128 id;
        uint64 start;
        uint64 expiry;
        uint128 limit;
        uint128 spent;
    }

    function purpose() external view returns (Purpose);
    function timelock() external view returns (address);
    function wpros() external view returns (address);
    function boundVault() external view returns (address);
    function fundingReceiver() external view returns (address);
    function period() external view returns (Period memory);
    function available() external view returns (uint256);
    function bindVault(address vault) external;
    function fund(uint256 amount) external;
    function authorizePeriod(uint128 id, uint64 start, uint64 expiry, uint128 limit) external;
    function consume(uint256 amount) external;
    function withdrawUncommitted(uint256 amount) external;
}
