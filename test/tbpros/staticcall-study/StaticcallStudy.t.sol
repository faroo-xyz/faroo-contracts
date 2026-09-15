// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Vm} from "forge-std/Vm.sol";
import {CoreFixture} from "../core-skeleton/CoreSkeleton.t.sol";
import {ITbPROSVault} from "tbpros/interfaces/ITbPROSVault.sol";
import {TbPROSTypes as T} from "tbpros/TbPROSTypes.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

// TEST ONLY: DTOs mirror the generated standard ABI, not a production ABI addition.
library P {
    enum Kind { PrincipalCap, MintLossBound, FastFee, MaxPlanDuration, BucketConfig, Oracle, FoundationReceiver, YieldRefundReceiver }
    struct Update { Kind kind; uint256 value0; uint256 value1; address account; }
    struct Delta { uint256 mask; uint128 cap; uint16 mintLoss; uint16 fastFee; uint64 duration; uint8 slot; uint128 bucketCap; uint128 bucketRate; address oracle; address foundation; address refund; }
}
interface IProbe {
    function studySettlement(uint128 q) external returns(uint256,uint256,uint256);
    function studyClaim(uint64 due,uint128 delta) external returns(uint256,uint256);
    function studyMint(uint128 assets) external returns(uint256,uint256);
    function studyYield(uint64 elapsed,uint128 price,uint128 ratio) external returns(uint256,uint256,uint256);
    function studyRisk(uint8 slot,uint128 cap,uint128 rate,uint128 consume) external returns(uint256,uint256,uint256);
    function studyPlan(T.PlanTerms calldata terms,uint64 cursor,uint128 amount) external returns(uint256,uint256,uint256);
    function applyGovernance(P.Update calldata u) external;
    function applyGovernance(P.Delta calldata u) external;
}
interface IStudyInit {function initialize(T.InitConfig calldata config,address[1] calldata modules) external;}
interface IControllerProbe {
    function setPrincipalCap(uint128 x) external;
    function setFastFee(uint16 x) external;
    function setBucketConfig(uint8 slot,T.BucketConfig calldata config) external;
    function applyBatch(P.Delta calldata d) external;
}
contract StudyBalance {
    address public asset;
    uint256 public amount;
    function balanceOf(address) external view returns(uint256){return amount;}
}
contract StudyRegistry {
    address public governanceController;
    constructor(address c){governanceController=c;}
}
contract BadMath {
    bytes private response;
    uint8 private attack;
    address private vault;
    constructor(bytes memory r,uint8 a,address v){response=r;attack=a;vault=v;}
    fallback() external {
        if(attack==1)revert("MODULE_FAILURE");
        if(attack==2){
            (bool ok,bytes memory reason)=vault.call(abi.encodeWithSignature("transfer(address,uint256)",address(1),0));
            require(!ok && keccak256(reason)==keccak256(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)),"CALLBACK_NOT_BLOCKED");
            // A read callback is possible under static context; it cannot own/write an alternative ledger.
            (ok,)=vault.staticcall(abi.encodeWithSignature("mode()"));require(ok,"READ_CALLBACK");
        }
        bytes memory data=response;
        assembly ("memory-safe") { return(add(data,32),mload(data)) }
    }
}

contract StaticcallStudyTest is CoreFixture {
    bytes32 constant CORE=0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100;
    string root;
    address[] modules;
    address controller;
    string meta;
    function setUp() public override {
        super.setUp();root=string.concat(vm.envString("TBPROS_STUDY_ROOT"),"/cache/tbpros-staticcall-study/");
        v.seedShares(address(this),1000e18);v.seedShares(alice,100e18);
        // Total S is 1100e18. All math inputs below are checked against that snapshot.
        StudyBalance balanceCode=new StudyBalance();vm.etch(address(token),address(balanceCode).code);
        seed();
    }
    function slot(uint256 n) internal pure returns(bytes32){return bytes32(uint256(CORE)+n);}
    function seed() internal {
        vm.warp(1000);
        vm.store(address(v),slot(0),bytes32(uint256(1000e18)|(uint256(100e18)<<128)));
        vm.store(address(v),slot(1),bytes32(uint256(10e18)|(uint256(1000e6)<<128)));
        vm.store(address(v),slot(2),bytes32(uint256(1000e18)|(uint256(1e24)<<128)));
        vm.store(address(v),slot(3),bytes32(0));
        // Policy: reserved Ucap, mint loss, fee, hard fee, duration, risk/request flags.
        vm.store(address(v),slot(14),bytes32((uint256(1)<<128)|(uint256(1)<<144)|(uint256(100)<<160)|(uint256(365 days)<<176)));
        vm.store(address(v),slot(17),bytes32(uint256(17)));
        for(uint256 i;i<4;++i){uint256 s=18+(i/2)*7+(i%2)*2;vm.store(address(v),slot(s),bytes32(uint256(100e18)));vm.store(address(v),slot(s+1),bytes32(uint256(100e18)<<128));}
        vm.store(address(v),slot(29),bytes32(uint256(100)|(uint256(20)<<128)));
        vm.store(address(v),slot(30),bytes32(uint256(1e18)|(uint256(900)<<128)));
        vm.store(address(v),slot(33),bytes32(uint256(1)));vm.store(address(v),slot(34),bytes32(0));
        vm.store(address(v),slot(39),bytes32(uint256(365 days)));
        bytes32 e=keccak256(abi.encode(uint64(1),slot(35)));
        vm.store(address(v),e,bytes32(uint256(100e18)|(uint256(3e18)<<128)));
        vm.store(address(v),bytes32(uint256(e)+1),bytes32(uint256(1000e18)|(uint256(1100e18)<<128)));
        vm.store(address(v),bytes32(uint256(e)+2),bytes32(uint256(100e18)|(uint256(2)<<192)));
        bytes32 pos=keccak256(abi.encode(uint64(1),keccak256(abi.encode(address(this),slot(36)))));
        vm.store(address(v),pos,bytes32(uint256(100e18)|(uint256(3e18)<<128)));
        vm.store(address(token),bytes32(uint256(1)),bytes32(uint256(10000e18)));
    }
    function deployArtifact(string memory label,string memory name,bytes memory args) internal returns(address deployed){
        string memory data=vm.readFile(string.concat(root,label,"/",name,".json"));
        bytes memory code=abi.encodePacked(vm.parseJsonBytes(data,".bytecode.object"),args);
        assembly ("memory-safe") { deployed:=create(0,add(code,32),mload(code)) }
        require(deployed!=address(0),"ARTIFACT_DEPLOY");
    }
    function install(string memory label) internal {
        seed();delete modules;controller=address(0);
        string memory code=vm.readFile(string.concat(root,label,"/Vault.json"));
        // Test-only code replacement permits measurement of oversized probes without raising any size gate.
        // It is NOT a deployment/migration test. The existing real OZ proxy still executes the measured runtime.
        vm.etch(address(implementation),vm.parseJsonBytes(code,".deployedBytecode.object"));
        meta=vm.readFile(string.concat(root,label,"/meta.json"));uint256 n=vm.parseJsonUint(meta,".n");
        for(uint256 i;i<n;++i){address m=deployArtifact(label,string.concat("Module",vm.toString(i)),"");modules.push(m);vm.label(m,string.concat(label,"/Module",vm.toString(i)));vm.store(address(v),slot(40+i),bytes32(uint256(uint160(m))));}
        if(vm.parseJsonBool(meta,".controller")){
            controller=deployArtifact(label,"Controller",abi.encode(address(this),address(v)));vm.label(controller,string.concat(label,"/Controller"));
            if(vm.parseJsonBool(meta,".derived")){
                // Fixed-dependency lookup gas is represented by an immutable-code getter fixture.
                address registry=deployArtifact(label,"RegistryGateway",abi.encode(address(this),uint64(72 hours),controller));
                vm.etch(address(gate),registry.code);
            }else vm.store(address(v),slot(40+n),bytes32(uint256(uint160(controller))));
        }
    }
    function measured(string memory label,string memory operation,address target,bytes memory data) internal {
        uint256 beforeGas=gasleft();(bool ok,)=target.call(data);uint256 used=beforeGas-gasleft();require(ok,"PROBE_FAILURE");
        emit log_named_uint(string.concat("STUDY/",label,"/",operation,"/fixture-first"),used);
        beforeGas=gasleft();(ok,)=target.call(data);used=beforeGas-gasleft();require(ok,"PROBE_REPEAT_FAILURE");
        emit log_named_uint(string.concat("STUDY/",label,"/",operation,"/repeat"),used);
    }
    function testGasAcrossActualVaultVariants() public {
        string[] memory labels=vm.parseJsonStringArray(vm.readFile(string.concat(root,"labels.json")),".labels");
        for(uint256 i;i<labels.length;++i){string memory label=labels[i];install(label);
            if(vm.parseJsonBool(meta,".settlement"))measured(label,"settlement",address(v),abi.encodeCall(IProbe.studySettlement,(uint128(100e18))));
            if(vm.parseJsonBool(meta,".claim"))measured(label,"claim",address(v),abi.encodeCall(IProbe.studyClaim,(uint64(1),uint128(7e18))));
            if(vm.parseJsonBool(meta,".mint"))measured(label,"mint",address(v),abi.encodeCall(IProbe.studyMint,(uint128(10e18))));
            if(vm.parseJsonBool(meta,".yield"))measured(label,"yield",address(v),abi.encodeCall(IProbe.studyYield,(uint64(100),uint128(1e18),uint128(1e18))));
            if(vm.parseJsonBool(meta,".risk"))measured(label,"risk",address(v),abi.encodeCall(IProbe.studyRisk,(uint8(0),uint128(80),uint128(1e18),uint128(5))));
            if(vm.parseJsonBool(meta,".plan"))measured(label,"plan",address(v),abi.encodeCall(IProbe.studyPlan,(T.PlanTerms(1000,1,2000),uint64(900),uint128(5))));
            if(bytes(vm.parseJsonString(meta,".gov")).length>0){
                measured(label,"governance-cap",controller==address(0)?address(v):controller,abi.encodeWithSignature("setPrincipalCap(uint128)",uint128(1000e18)));
            }
        }
    }
    function testHLossGasAndValidation() public {
        string[2] memory labels=[string("A-baseline"),string("H-static")];
        for(uint256 i;i<2;++i){install(labels[i]);vm.store(address(token),bytes32(uint256(1)),bytes32(uint256(1500e18-3)));
            uint256 g=gasleft();v.syncSolvency();emit log_named_uint(string.concat("STUDY/",labels[i],"/hloss/fixture-first"),g-gasleft());
            assertEq(v.accounting().F,0);assertEq(v.sourceRemaining(0,0),100e18-1);assertEq(v.sourceRemaining(0,1),100e18-1);assertEq(v.sourceRemaining(1,0),100e18-1);assertEq(v.sourceRemaining(1,1),100e18);
        }
    }
    function replaceModule(bytes memory response,uint8 attack) internal {
        BadMath bad=new BadMath(response,attack,address(v));vm.store(address(v),slot(40),bytes32(uint256(uint160(address(bad)))));
    }
    function assertClaimReject(bytes memory response,uint8 attack) internal {
        install("claim-static");bytes32 beforeHash=keccak256(abi.encode(v.accounting(),v.position(address(this),1),v.epoch(1),v.totalSupply()));
        replaceModule(response,attack);(bool ok,)=address(v).call(abi.encodeCall(IProbe.studyClaim,(uint64(1),uint128(7e18))));assertFalse(ok);
        assertEq(keccak256(abi.encode(v.accounting(),v.position(address(this),1),v.epoch(1),v.totalSupply())),beforeHash);
    }
    function testMalformedRevertMaxOversizedAndWrongProgressReject() public {
        assertClaimReject(hex"01",0);assertClaimReject("",1);
        assertClaimReject(abi.encode(type(uint256).max,type(uint256).max),0);
        assertClaimReject(abi.encode(uint256(10e18),uint256(101e18)),0);
        assertClaimReject(abi.encode(uint256(11e18),uint256(1)),0);
        assertClaimReject(abi.encode(uint256(10e18),uint256(1),uint256(0)),0);
    }
    function testBoundedWrongRoundingRequiresPinnedTrustedCode() public {
        install("claim-static");replaceModule(abi.encode(uint256(10e18),uint256(1)),0);
        (,uint256 payout)=IProbe(address(v)).studyClaim(1,7e18);assertEq(payout,1);
        // Expected limitation: budget/domain checks cannot prove the exact cumulative floor result.
        assertTrue(payout!=uint256(10e18)*1000/1100-uint256(3e18)*1000/1100);
    }
    function testStaticCallbackCannotWriteButCanRead() public {
        install("claim-static");uint256 shares=v.balanceOf(address(this));replaceModule(abi.encode(uint256(10e18),uint256(1)),2);
        IProbe(address(v)).studyClaim(1,7e18);assertEq(v.balanceOf(address(this)),shares);
    }
    function testSafeTransferAndAlreadyModeIgnoreFailedModule() public {
        install("H-static");replaceModule("",1);
        vm.store(address(v),slot(3),bytes32(uint256(1)));
        v.approve(bob,1);v.transfer(bob,1);vm.prank(bob);v.transferFrom(address(this),bob,1);
        v.safeRequestRedeem(1);v.syncSolvency();assertTrue(v.mode().insolvent);
    }
    function testHLossWrongSumRejectsAndRollsBackF() public {
        install("H-static");vm.store(address(token),bytes32(uint256(1)),bytes32(uint256(1500e18-3)));
        replaceModule(abi.encode([uint256(1),0,0,0]),0);vm.expectRevert();v.syncSolvency();assertEq(v.accounting().F,10e18);assertEq(v.sourceRemaining(0,0),100e18);
        replaceModule(abi.encode([uint256(100e18+1),0,0,0]),0);vm.expectRevert();v.syncSolvency();assertEq(v.accounting().F,10e18);
    }
    function testMintIndependentFairnessRejectsPlausibleBadResult() public {
        install("mint-static");replaceModule(abi.encode(uint256(11e18-1),uint256(0)),0);
        vm.expectRevert();IProbe(address(v)).studyMint(10e18);
    }
    function testRiskCreditGiftRejected() public {
        install("risk-static");replaceModule(abi.encode(uint256(76),uint256(0),uint256(1000)),0);
        vm.expectRevert();IProbe(address(v)).studyRisk(0,80,1e18,5);
    }
    function testGovernanceModeAuthorityAndCoreChecks() public {
        install("G8-enum");vm.store(address(v),slot(3),bytes32(uint256(1)));
        vm.recordLogs();IControllerProbe(controller).setFastFee(2);
        Vm.Log[] memory entries=vm.getRecordedLogs();assertEq(entries.length,1);assertEq(entries[0].emitter,address(v));
        IControllerProbe(controller).setPrincipalCap(1000e18);
        vm.prank(bob);vm.expectRevert();IControllerProbe(controller).setFastFee(2);
        vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.FastFee,2,0,address(0)));
        // Even an impersonated malicious Controller cannot bypass final Vault checks.
        vm.prank(controller);vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.PrincipalCap,1,0,address(0)));
        vm.prank(controller);vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.FastFee,101,0,address(0)));
        vm.prank(controller);vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.MintLossBound,2,0,address(0)));
        vm.prank(controller);vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.MaxPlanDuration,0,0,address(0)));
        vm.prank(controller);vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.Oracle,0,0,address(v)));
        vm.prank(controller);vm.expectRevert();IProbe(address(v)).applyGovernance(P.Update(P.Kind.YieldRefundReceiver,0,0,address(sub)));
        vm.prank(controller);vm.expectRevert(ITbPROSVault.INSOLVENT.selector);v.syncSurplus(1);
        vm.prank(controller);
        (bool accepted,)=address(v).call(abi.encodeWithSignature("applyGovernance((uint8,uint256,uint256,address))",uint8(8),uint256(0),uint256(0),address(0)));
        assertFalse(accepted);
        assertTrue(v.mode().insolvent);assertEq(v.accounting().R,1000e18);
    }
    function testBatchAtomicityUnknownMaskAndNoCreditGift() public {
        install("G8-batch");P.Delta memory d;d.mask=5;d.cap=1001e18;d.fastFee=101;
        vm.expectRevert();IControllerProbe(controller).applyBatch(d);assertEq(v.accounting().C,1e24);
        d.mask=256;vm.expectRevert();IControllerProbe(controller).applyBatch(d);
        vm.store(address(v),slot(3),bytes32(uint256(1)));
        vm.warp(900);IControllerProbe(controller).setBucketConfig(0,T.BucketConfig(1000,2e18));
        assertEq(uint128(uint256(vm.load(address(v),slot(29)))),1000);
        assertEq(uint128(uint256(vm.load(address(v),slot(29))>>128)),20);
    }
    function initWith(string memory label,address module) internal returns(address) {
        address code=deployArtifact(label,"Vault","");address[1] memory refs=[module];
        // Isolated initialization checks only; not a complete Gateway ownership handoff.
        vm.store(address(sub),bytes32(0),bytes32(0));vm.store(address(yieldReserve),bytes32(0),bytes32(0));
        return address(new TransparentUpgradeableProxy(code,address(gate),abi.encodeCall(IStudyInit.initialize,(config,refs))));
    }
    function testInitializationIdentityAndSpoofing() public {
        address valid=deployArtifact("claim-static","Module0","");
        address initialized=initWith("identity-hash",valid);assertEq(ITbPROSVault(initialized).backingAsset(),address(token));
        // Hash pin rejects a spoofed version even when its return ABI and version match.
        BadMath spoof=new BadMath(abi.encode(keccak256("tbpros.study.v1")),0,address(v));
        try this.externalInit("identity-hash",address(spoof)) returns(address){fail();}catch{}
        address versionOnly=initWith("identity-version",address(spoof));assertTrue(versionOnly!=address(0));
        try this.externalInit("claim-static",address(0x12345)) returns(address){fail();}catch{}
        BadMath shortData=new BadMath(hex"01",0,address(v));
        try this.externalInit("claim-static",address(shortData)) returns(address){fail();}catch{}
    }
    function externalInit(string calldata label,address module) external returns(address){return initWith(label,module);}
    function word(bytes memory data,uint256 offset) internal pure returns(uint256 value){
        require(offset+32<=data.length,"VECTOR_BOUNDS");
        assembly ("memory-safe") {value:=mload(add(add(data,32),offset))}
    }
    function differential(uint256 kind) internal {
        string memory label=kind==6?"H-static":"M3-unified";install(label);
        bytes memory data=vm.readFileBinary(string.concat(root,"vectors.bin"));
        string[7] memory sigs=[string("computeSettlement((uint128,uint128,uint128,uint128,uint128))"),"computeClaim((uint128,uint128,uint128,uint128,uint128,uint128))","computeMint((uint128,uint128,uint128,uint16))","computeYield((uint128,uint64,uint64,uint256,uint128,uint128))","materializeBucket((uint128,uint128,uint128,uint64,uint64,uint64,uint128,uint128,uint128))","validatePlanTerms((uint128,uint64,uint64,uint64,uint64,uint64,uint128,uint128,uint128))","allocateHLoss(uint256,uint128[4])"];
        uint256[7] memory inputCount=[uint256(5),6,4,6,9,9,5];uint256[7] memory outputCount=[uint256(3),2,2,3,3,3,4];uint256 checked;
        for(uint256 off;off<data.length;off+=512){if(word(data,off)!=kind)continue;
            bytes memory args=abi.encodePacked(bytes4(keccak256(bytes(sigs[kind]))));
            for(uint256 j;j<inputCount[kind];++j)args=bytes.concat(args,abi.encode(word(data,off+32*(j+1))));
            (bool ok,bytes memory ret)=modules[0].staticcall(args);assertTrue(ok);
            for(uint256 j;j<outputCount[kind];++j)assertEq(word(ret,j*32),word(data,off+(10+j)*32));++checked;
        }
        assertGt(checked,0);emit log_named_uint("Differential cases",checked);
    }
    function testDifferentialSettlement() public {differential(0);}
    function testDifferentialClaim() public {differential(1);}
    function testDifferentialMint() public {differential(2);}
    function testDifferentialYield() public {differential(3);}
    function testDifferentialRisk() public {differential(4);}
    function testDifferentialPlan() public {differential(5);}
    function testDifferentialHLoss() public {differential(6);}
}
