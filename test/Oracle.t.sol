// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Oracle} from "../contracts/Oracle.sol";
import {VToken} from "../contracts/VToken.sol";
import {MockWPROS} from "./mocks/MockWPROS.sol";

contract OracleVTokenHarness is VToken {
    function initialize(IERC20 asset_, address owner_, address oracle_) external initializer {
        __VToken_init(asset_, owner_, "Staked PROS", "stPROS");
        oracle = Oracle(oracle_);
    }
}

contract OracleTest is Test {
    Oracle internal oracle;
    OracleVTokenHarness internal vtoken;
    MockWPROS internal wpros;

    address internal owner = makeAddr("owner");
    address internal slp = makeAddr("slp");
    address internal alice = makeAddr("alice");
    address internal commissionAccount = makeAddr("commissionAccount");

    uint256 internal constant MAX_UPDATE = 100 ether;
    uint256 internal constant UPDATE_INTERVAL = 1 hours;

    function setUp() external {
        wpros = new MockWPROS();

        Oracle oracleImplementation = new Oracle();
        bytes memory oracleInitData = abi.encodeWithSelector(Oracle.initialize.selector, owner);
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImplementation), oracleInitData);
        oracle = Oracle(address(oracleProxy));

        OracleVTokenHarness vtokenImplementation = new OracleVTokenHarness();
        bytes memory vtokenInitData =
            abi.encodeWithSelector(OracleVTokenHarness.initialize.selector, address(wpros), owner, address(oracle));
        ERC1967Proxy vtokenProxy = new ERC1967Proxy(address(vtokenImplementation), vtokenInitData);
        vtoken = OracleVTokenHarness(payable(address(vtokenProxy)));

        vm.prank(owner);
        oracle.setPoolInfo(address(wpros), 1_000 ether, 1_000 ether);
    }

    function _upgradeOracleToV2() internal {
        vm.prank(owner);
        oracle.initializeV2(slp, address(vtoken), MAX_UPDATE, UPDATE_INTERVAL);
    }

    function _commissionMappings() internal view returns (address[] memory tokens, address[] memory vTokens) {
        tokens = new address[](1);
        vTokens = new address[](1);
        tokens[0] = address(wpros);
        vTokens[0] = address(vtoken);
    }

    function _upgradeOracleToV3(uint256 ratePpm) internal {
        (address[] memory tokens, address[] memory vTokens) = _commissionMappings();
        vm.prank(owner);
        oracle.initializeV3(commissionAccount, ratePpm, tokens, vTokens);
    }

    function test_InitializeV2_ShouldConfigureSlpVTokenAndLimits() external {
        _upgradeOracleToV2();

        assertEq(oracle.slp(), slp, "slp");
        assertTrue(oracle.vTokenAddresses(address(vtoken)), "vToken registered");
        assertEq(oracle.maxUpdateAmount(), MAX_UPDATE, "max update");
        assertEq(oracle.updateInterval(), UPDATE_INTERVAL, "interval");
    }

    function test_InitializeV2_ShouldRevert_WhenCalledTwice() external {
        _upgradeOracleToV2();

        vm.prank(owner);
        vm.expectRevert();
        oracle.initializeV2(slp, address(vtoken), MAX_UPDATE, UPDATE_INTERVAL);
    }

    function test_InitializeV3_ShouldConfigureCommission() external {
        _upgradeOracleToV2();
        _upgradeOracleToV3(1_000);

        assertEq(oracle.commissionAccount(), commissionAccount, "commission account");
        assertEq(oracle.commissionRatePpm(), 1_000, "commission rate");
        assertEq(oracle.tokenToVToken(address(wpros)), address(vtoken), "commission vToken");
    }

    function test_InitializeV2AndV3_ShouldConfigureBothVersions() external {
        (address[] memory tokens, address[] memory vTokens) = _commissionMappings();

        vm.prank(owner);
        oracle.initializeV2AndV3(
            slp, address(vtoken), MAX_UPDATE, UPDATE_INTERVAL, commissionAccount, 10_000, tokens, vTokens
        );

        assertEq(oracle.slp(), slp, "slp");
        assertTrue(oracle.vTokenAddresses(address(vtoken)), "registered");
        assertEq(oracle.maxUpdateAmount(), MAX_UPDATE, "max update");
        assertEq(oracle.updateInterval(), UPDATE_INTERVAL, "interval");
        assertEq(oracle.commissionAccount(), commissionAccount, "commission account");
        assertEq(oracle.commissionRatePpm(), 10_000, "commission rate");
        assertEq(oracle.tokenToVToken(address(wpros)), address(vtoken), "commission vToken");
    }

    function test_Update_ShouldIncreaseTokenAmount_WhenCalledBySlp() external {
        _upgradeOracleToV2();
        vm.warp(UPDATE_INTERVAL + 1);

        assertTrue(oracle.canUpdate(address(wpros), 10 ether), "preview allows update");

        vm.prank(slp);
        oracle.update(address(wpros), 10 ether);

        (uint256 tokenAmount,) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 1_010 ether, "token amount increased");
        assertEq(oracle.lastUpdateAt(address(wpros)), block.timestamp, "timestamp updated");
    }

    function test_Update_ShouldMintCommissionUsingPreUpdateRate() external {
        _upgradeOracleToV2();
        _upgradeOracleToV3(10_000);
        vm.prank(owner);
        oracle.setPoolInfo(address(wpros), 2_000 ether, 1_000 ether);
        vm.warp(UPDATE_INTERVAL + 1);

        vm.prank(slp);
        oracle.update(address(wpros), 100 ether);

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 2_100 ether, "token side uses full update amount");
        assertEq(vTokenAmount, 1_000 ether + 0.5 ether, "vToken side adds commission shares");
        assertEq(vtoken.balanceOf(commissionAccount), 0.5 ether, "commission minted");
    }

    function test_Update_ShouldRevert_WhenCommissionMappingMissing() external {
        _upgradeOracleToV2();
        vm.prank(owner);
        oracle.initializeV3(commissionAccount, 10_000, new address[](0), new address[](0));
        vm.warp(UPDATE_INTERVAL + 1);

        assertFalse(oracle.canUpdate(address(wpros), 100 ether), "missing commission mapping");

        vm.prank(slp);
        vm.expectRevert(abi.encodeWithSelector(Oracle.MissingCommissionVToken.selector, address(wpros)));
        oracle.update(address(wpros), 100 ether);
    }

    function test_Update_ShouldNotMintCommission_WhenRoundedToZero() external {
        _upgradeOracleToV2();
        _upgradeOracleToV3(10);
        vm.warp(UPDATE_INTERVAL + 1);

        vm.prank(slp);
        oracle.update(address(wpros), 1);

        (, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(vTokenAmount, 1_000 ether, "vToken side unchanged");
        assertEq(vtoken.balanceOf(commissionAccount), 0, "no commission minted");
    }

    function test_SetCommissionConfig_ShouldRevert_WhenRateAboveMax() external {
        _upgradeOracleToV2();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Oracle.InvalidCommissionRate.selector, 1_000_001, 1_000_000));
        oracle.initializeV3(commissionAccount, 1_000_001, new address[](0), new address[](0));
    }

    function test_SetCommissionVToken_ShouldValidateAsset() external {
        _upgradeOracleToV2();
        address wrongToken = makeAddr("wrongToken");
        address expectedAsset = IERC4626(address(vtoken)).asset();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Oracle.InvalidVTokenAsset.selector, wrongToken, expectedAsset));
        oracle.setCommissionVToken(wrongToken, address(vtoken));
    }

    function test_Update_ShouldRevert_WhenNotSlp() external {
        _upgradeOracleToV2();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Oracle.NotSlp.selector, alice));
        oracle.update(address(wpros), 1 ether);
    }

    function test_Update_ShouldRevert_WhenExceedsMax() external {
        _upgradeOracleToV2();

        vm.prank(slp);
        vm.expectRevert(abi.encodeWithSelector(Oracle.UpdateAmountTooLarge.selector, MAX_UPDATE + 1, MAX_UPDATE));
        oracle.update(address(wpros), MAX_UPDATE + 1);
    }

    function test_Update_ShouldRevert_WhenTooFrequent() external {
        _upgradeOracleToV2();
        vm.warp(UPDATE_INTERVAL + 1);

        vm.prank(slp);
        oracle.update(address(wpros), 1 ether);

        assertFalse(oracle.canUpdate(address(wpros), 1 ether), "preview blocks frequent update");

        vm.prank(slp);
        vm.expectRevert();
        oracle.update(address(wpros), 1 ether);
    }

    function test_CanUpdate_ShouldReturnFalse_WhenPaused() external {
        _upgradeOracleToV2();
        vm.warp(UPDATE_INTERVAL + 1);

        vm.prank(owner);
        oracle.pause();

        assertFalse(oracle.canUpdate(address(wpros), 1 ether), "paused");
    }

    function test_CanUpdate_ShouldReturnFalse_WhenAmountExceedsMax() external {
        _upgradeOracleToV2();
        vm.warp(UPDATE_INTERVAL + 1);

        assertFalse(oracle.canUpdate(address(wpros), MAX_UPDATE + 1), "amount too large");
    }

    function test_CanUpdate_ShouldReturnFalse_WhenTokenIsZero() external {
        _upgradeOracleToV2();

        assertFalse(oracle.canUpdate(address(0), 1 ether), "zero token");
    }

    function test_CanUpdate_ShouldReturnFalse_WhenAmountIsZero() external {
        _upgradeOracleToV2();

        assertFalse(oracle.canUpdate(address(wpros), 0), "zero amount");
    }

    function test_CanUpdate_ShouldReturnFalse_WhenUpdateDisabled() external {
        vm.prank(owner);
        oracle.initializeV2(slp, address(vtoken), 0, 0);

        assertFalse(oracle.canUpdate(address(wpros), 1 ether), "maxUpdateAmount zero");
    }

    function test_OnMint_ShouldIncreasePool() external {
        _upgradeOracleToV2();

        vm.prank(address(vtoken));
        oracle.onMint(address(wpros), 20 ether, 20 ether);

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 1_020 ether, "token side");
        assertEq(vTokenAmount, 1_020 ether, "vToken side");
    }

    function test_OnRedeem_ShouldDecreasePool() external {
        _upgradeOracleToV2();

        vm.prank(address(vtoken));
        oracle.onRedeem(address(wpros), 30 ether, 30 ether);

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 970 ether, "token side");
        assertEq(vTokenAmount, 970 ether, "vToken side");
    }

    function test_OnRedeem_ShouldRevert_WhenInsufficientPool() external {
        _upgradeOracleToV2();

        vm.prank(address(vtoken));
        vm.expectRevert(Oracle.InsufficientPoolAmount.selector);
        oracle.onRedeem(address(wpros), 2_000 ether, 2_000 ether);
    }

    function test_SetPoolInfo_ByOwner_ShouldAllowAnyToken() external {
        address otherToken = makeAddr("otherToken");

        vm.prank(owner);
        oracle.setPoolInfo(otherToken, 3 ether, 4 ether);

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(otherToken);
        assertEq(tokenAmount, 3 ether, "token amount");
        assertEq(vTokenAmount, 4 ether, "vToken amount");
    }

    function test_SetPoolInfo_ByVToken_ShouldAllowOwnAsset() external {
        _upgradeOracleToV2();

        vm.prank(address(vtoken));
        oracle.setPoolInfo(address(wpros), 500 ether, 500 ether);

        (uint256 tokenAmount, uint256 vTokenAmount) = oracle.poolInfo(address(wpros));
        assertEq(tokenAmount, 500 ether, "token amount");
        assertEq(vTokenAmount, 500 ether, "vToken amount");
    }

    function test_SetPoolInfo_ByVToken_ShouldRevert_WrongAsset() external {
        _upgradeOracleToV2();
        address wrongToken = makeAddr("wrongToken");

        vm.startPrank(address(vtoken));
        vm.expectRevert(
            abi.encodeWithSelector(Oracle.InvalidVTokenAsset.selector, wrongToken, IERC4626(address(vtoken)).asset())
        );
        oracle.setPoolInfo(wrongToken, 1 ether, 1 ether);
        vm.stopPrank();
    }

    function test_SetPoolInfo_ByUnregisteredCaller_ShouldRevert() external {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Oracle.NotVToken.selector, alice));
        oracle.setPoolInfo(address(wpros), 1 ether, 1 ether);
    }
}
