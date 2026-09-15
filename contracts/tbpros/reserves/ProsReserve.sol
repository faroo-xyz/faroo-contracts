// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IProsReserve} from "../interfaces/IProsReserve.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Immutable-code reserve SKELETON. Funding, period changes and all payouts revert.
contract ProsReserve is IProsReserve, ReentrancyGuardTransient {
    error SkeletonOnly();
    error Unauthorized();
    error InvalidBinding();

    event VaultBound(address indexed vault);
    event ReserveFunded(address indexed funder, uint256 amount);
    event ReservePeriodChanged(uint128 indexed periodId, uint64 start, uint64 expiry, uint128 limit);
    event ReserveConsumed(uint128 indexed periodId, uint256 amount, uint256 spent);
    event UncommittedWithdrawn(address indexed receiver, uint256 amount);

    address public immutable timelock;
    address public immutable wpros;
    address public immutable fundingReceiver;
    Purpose public immutable purpose;
    address public boundVault;
    Period private _period;

    constructor(address tl, address token, address receiver, Purpose purpose_) {
        if (tl.code.length == 0 || token.code.length == 0 || receiver == address(0) || receiver == address(this)) {
            revert InvalidBinding();
        }
        timelock = tl;
        wpros = token;
        fundingReceiver = receiver;
        purpose = purpose_;
    }

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert Unauthorized();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != boundVault || boundVault == address(0)) revert Unauthorized();
        _;
    }

    function bindVault(address v) external nonReentrant onlyTimelock {
        if (boundVault != address(0) || v.code.length == 0 || v == fundingReceiver || v == address(this)) {
            revert InvalidBinding();
        }
        boundVault = v;
        emit VaultBound(v);
    }

    function period() external view returns (Period memory) {
        return _period;
    }

    function available() external view returns (uint256) {
        Period memory p = _period;
        if (block.timestamp < p.start || block.timestamp >= p.expiry) return 0;
        return Math.min(IERC20(wpros).balanceOf(address(this)), uint256(p.limit) - p.spent);
    }

    function fund(uint256) external nonReentrant {
        revert SkeletonOnly();
    }

    function authorizePeriod(uint128, uint64, uint64, uint128) external nonReentrant onlyTimelock {
        revert SkeletonOnly();
    }

    function consume(uint256) external nonReentrant onlyVault {
        revert SkeletonOnly();
    }

    function withdrawUncommitted(uint256) external nonReentrant onlyTimelock {
        revert SkeletonOnly();
    }
}
