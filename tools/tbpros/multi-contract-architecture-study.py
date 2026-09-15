"""Current-source state partition pressure probes; no production migration or deployment.

Run from repository root with exact TBPROS_SOLC. Mutated Solidity and logs stay in
ignored cache. Each domain has its own storage; shared declarations are types only.
"""
import argparse,collections,hashlib,importlib.util,json,os,re,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True

def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=load('previous','tools/tbpros/bytecode-architecture-review.py')
t=load('templates','tools/tbpros/multi-contract-study-templates.py')
g=load('governance','tools/tbpros/staticcall-study-templates.py')
BASE='35bea52ec5fe509ead650288ffff9431c2dc4c32';V,I,S=p.V,p.I,p.S
ROOT=Path.cwd();CACHE=ROOT/'cache/tbpros-multi-contract-study';DEST=ROOT/'docs/tbpros/verification/multi-contract-architecture-variants.json'
PROFILE=p.PROFILE

def strip(s):return re.sub(r'//[^\n]*','',s)
def fn(s,name):
 a,b=p.span(s,name);return s[a:b]
def put(s,name,code):return p.replace_function(s,name,'    '+code.strip())
def add(s,code):return s[:s.rfind('}')]+re.sub(r'(?m)^ *function ', '    function ',code)+'\n}\n'
def imports(s,code):return s.replace('pragma solidity 0.8.28;','pragma solidity 0.8.28;\n'+code,1)

def events(base):
 x=strip(base[I]);x=x[:x.index('    function initialize')];x=x.replace('interface ITbPROSVault','interface StudyEvents').replace('../TbPROSTypes.sol','contracts/tbpros/TbPROSTypes.sol')
 return x+'event DomainFunded(uint128 indexed id,uint8 source,uint256 amount,uint128 cap,uint64 start,uint64 end);\n}\n'

def manager_header(name,extra=''):
 return t.COMMON+'''import {StudyEvents} from "partition/Events.sol";
import {Domains} from "partition/Domains.sol";
import {MonthMath} from "contracts/tbpros/libraries/MonthMath.sol";
import {IPToken,IPCore,IPRedemption} from "partition/Interfaces.sol";
'''+f'contract {name} is ReentrancyGuardTransient, StudyEvents {{\n'+'''using TransientSlot for *;
 address public immutable core;address public immutable timelock;
 bytes32 constant PHASE=keccak256("partition.manager.phase");
 modifier onlyCore(){require(msg.sender==core,"CORE");_;}
 modifier onlyTimelock(){require(msg.sender==timelock,"TIMELOCK");_;}
 modifier idle(){require(!PHASE.asBoolean().tload(),"PHASE");_;}
 function beginPhase() external onlyCore {require(!PHASE.asBoolean().tload(),"PHASE");PHASE.asBoolean().tstore(true);}
 function endPhase() external onlyCore {require(PHASE.asBoolean().tload(),"PHASE");PHASE.asBoolean().tstore(false);}
'''+extra

INTERFACES='''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {TbPROSTypes as T} from "contracts/tbpros/TbPROSTypes.sol";
import {TbPROSStorage as S} from "contracts/tbpros/TbPROSStorage.sol";
interface IBinding {function timelock() external view returns(address);}
interface IPhase {function core() external view returns(address);function beginPhase() external;function endPhase() external;}
interface IPToken is IPhase {
 function redemption() external view returns(address);function totalSupply() external view returns(uint256);function balanceOf(address) external view returns(uint256);
 function protocolMint(address,uint256) external;function protocolBurnOwner(address,uint256) external;function protocolBurnEscrow(uint256) external;
 function spendRequestAllowance(address,address,uint256) external;function protocolEscrow(address,uint256) external;
}
interface IPCore {
 function assertRequestAllowed() external view;function assertClaimAllowed() external view;
 function executeSettlement(uint256) external returns(uint128,uint128,uint128);
 function executeClaim(address,uint256,uint256) external;
 function settleMaturedEpochs(uint256) external returns(uint256);
 function claimFor(address,uint64,uint256,address,address) external returns(uint256);
}
interface IPRedemption is IPhase {
 function token() external view returns(address);
 function safeFor(address,uint256) external returns(uint64);function requestFor(address,uint256,address,address) external returns(uint64);
 function nextSettlement() external view returns(uint64,uint128);
 function commitSettlement(uint64,uint128,uint128,uint128) external;
 function consumeClaim(address,uint64,uint256,address,address) external returns(uint256,uint256);
 function queueState() external view returns(uint64,uint64,uint64);
 function settleMaturedEpochs(uint256) external returns(uint256);
 function claimRedeem(uint64,uint256,address,address) external returns(uint256);
}
interface IPRisk is IPhase {
 function consume(uint256) external;
 function setBucketConfig(uint8,T.BucketConfig calldata) external;
}
interface IPYield is IPhase {
 function totalH() external view returns(uint256);function sourceRemaining(uint8,uint8) external view returns(uint128);
 function recordFunding(uint8,uint256,T.PlanTerms calldata,uint64) external returns(uint128);
 function activate(uint128,uint128) external;function close(uint128,address) external returns(uint256,uint256);
 function eligible(uint128,uint64) external view returns(uint256,uint64,uint256);
 function release(uint256,uint64,uint256,bytes32) external;function burnCarry(uint256,uint256) external;
 function absorbLoss(uint256,uint256) external returns(uint256[4] memory);
 function checkCap(uint128) external view;function nextPlanId() external view returns(uint128);
}
'''

LENS='''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {TbPROSTypes as T} from "contracts/tbpros/TbPROSTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface ILCore {
 function accounting() external view returns(T.Accounting memory);
 function mode() external view returns(T.Mode memory);
 function backingAsset() external view returns(address);
 function transitionActive() external view returns(bool);
 function sourceRemaining(uint8,uint8) external view returns(uint128);
}
interface ILRights {function position(address,uint64) external view returns(T.Position memory);}
interface ILYield {function totalH() external view returns(uint256);}
// Optional fixed-address aggregation, never an economic gate or second ledger.
contract TbPROSLens {
 address public immutable core;address public immutable token;address public immutable redemption;
 address public immutable yieldManager;address public immutable risk;
 constructor(address c,address tok,address rd,address ym,address rk){require(c.code.length>0&&tok.code.length>0&&rd.code.length>0&&ym.code.length>0&&rk.code.length>0,"CODE");core=c;token=tok;redemption=rd;yieldManager=ym;risk=rk;}
 function protocolComponents() external view returns(address,address,address,address,address){return(token,core,redemption,yieldManager,risk);}
 function solvency() external view returns(bool insolvent,uint256 obligations,uint256 balance,uint256 deficit,uint256 surplus){
  require(!ILCore(core).transitionActive(),"TRANSITION");T.Accounting memory a=ILCore(core).accounting();obligations=uint256(a.R)+a.P+a.F;
  if(yieldManager!=core)obligations+=ILYield(yieldManager).totalH();else for(uint8 i;i<4;++i)obligations+=ILCore(core).sourceRemaining(i/2,i%2);
  insolvent=ILCore(core).mode().insolvent;balance=IERC20(ILCore(core).backingAsset()).balanceOf(core);
  if(balance<obligations)deficit=obligations-balance;else surplus=balance-obligations;
 }
 function position(address controller,uint64 due) external view returns(T.Position memory){require(!ILCore(core).transitionActive(),"TRANSITION");return ILRights(redemption).position(controller,due);}
}
'''

RD_FUNCS=['_requestAccounting','_admitRequestEpoch','setOperator','isOperator','epoch','position','queueState','openPositionCount']
RD_FIELDS=['queueHead','queueTail','lastSettledDueAt','epochs','positions','openPositionCount','operators']

def build_variant(base,token=False,red=False,risk=False,yield_=False,facade=False,orchestrator='core',full=True):
 src={k:strip(v) for k,v in base.items()};orig=src[V];v=orig
 src['partition/Events.sol']=events(base);src['partition/Domains.sol']=t.COMMON+t.DOMAINS;src['partition/Interfaces.sol']=INTERFACES
 v=v.replace('ReentrancyGuardTransient, ITbPROSVault','ReentrancyGuardTransient, StudyEvents')
 v=imports(v,'''import {StudyEvents} from "partition/Events.sol";
import {IPToken,IPCore,IPRedemption,IPRisk,IPYield,IPhase,IBinding} from "partition/Interfaces.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITbPROSOracleAdapter} from "contracts/tbpros/interfaces/ITbPROSOracleAdapter.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
''')
 binds=['token','redemption','risk','yieldManager'];active=[token,red,risk,yield_]
 v=add(v,'using SafeERC20 for IERC20;using TransientSlot for *;\n'+''.join('address private _'+a+';\n' for a,on in zip(binds,active) if on))
 init=fn(v,'initialize').replace('config) external','config,address[4] calldata components) external')
 checks=''
 for n,on in enumerate(active):
  if on:checks+=f'_requireCode(components[{n}]);require(IPhase(components[{n}]).core()==address(this),"BIND");_{binds[n]}=components[{n}];'
 for n in range(1,4):
  if active[n]:checks+=f'require(IBinding(components[{n}]).timelock()==d.timelock,"TIMELOCK_BIND");'
 checks+='require('+('IPToken(_token).redemption()=='+('_redemption' if red else 'address(this)') if token else 'components[0]==address(0)')+',"TOKEN_BIND");'
 if red:checks+='require(IPRedemption(_redemption).token()=='+('_token' if token else 'address(this)')+',"TOKEN_BIND");'
 init=init.replace('T.Dependencies calldata d = config.dependencies;','T.Dependencies calldata d = config.dependencies;'+checks)
 if token:init=init.replace('__ERC20_init("tbPROS", "tbPROS");','')
 if risk:
  init=re.sub(r'        for \(uint256 i; i < 2; \+\+i\) \{.*?\n        \}', '',init,flags=re.S)
 if yield_:init=init.replace('s.nextPlanId = 1;','')
 v=put(v,'initialize',init)
 if token:
  v=v.replace('is ERC20Upgradeable,','is')
  for name in ['transfer','transferFrom','approve','_update','_escrowShares']:v=put(v,name,'')
  v=add(v,'''function totalSupply() internal view returns(uint256){return IPToken(_token).totalSupply();}
 function _spendAllowance(address owner,address actor,uint256 q) internal {IPToken(_token).spendRequestAllowance(owner,actor,q);}
 function _escrowShares(address owner,uint256 q) internal {IPToken(_token).protocolEscrow(owner,q);}
 function _mintToken(address to,uint256 q) internal {IPToken(_token).protocolMint(to,q);}
 function _burnToken(address owner,uint256 q,bool escrow) internal {if(escrow)IPToken(_token).protocolBurnEscrow(q);else IPToken(_token).protocolBurnOwner(owner,q);}
''')
  src['partition/Token.sol']=t.TOKEN
 else:
  v=add(v,'function _mintToken(address to,uint256 q) internal {_mint(to,q);}\nfunction _burnToken(address owner,uint256 q,bool escrow) internal {_burn(escrow?'+('_redemption' if red else 'address(this)')+':owner,q);}\n')
 if red:
  r=manager_header('PartitionRedemption','address public immutable token; Domains.Redemption private _rights;\n')
  r+='constructor(address c,address tl,address tok){require(c!=address(0)&&tl.code.length>0&&tok!=address(0),"BIND");core=c;timelock=tl;token=tok;}\n'
  for name in RD_FUNCS:r+=fn(orig,name)+'\n';v=put(v,name,'')
  r=r.replace('S.Layout storage s','Domains.Redemption storage s').replace('S.layout()','_rights')
  r=r.replace('address owner, address controller, uint256 shares, bool safe','address owner, address controller, uint256 shares, bool safe, address actor')
  a,b=p.span(r,'_requestAccounting');part=r[a:b].replace('msg.sender','actor').replace('_spendAllowance(owner, actor, shares)','IPToken(token).spendRequestAllowance(owner, actor, shares)');r=r[:a]+part+r[b:]
  r=r.replace('owner == address(this) || controller == address(this)','owner == address(this) || controller == address(this) || owner==core || controller==core')
  r=r.replace('external nonReentrant {','external nonReentrant idle {')
  r+='function _escrowShares(address owner,uint256 q) internal {IPToken(token).protocolEscrow(owner,q);}\n'
  r+='''function safeRequestRedeem(uint256 q) external nonReentrant idle returns(uint64){return _safe(msg.sender,q);}
 function _safe(address actor,uint256 q) internal returns(uint64 due){due=_requestAccounting(actor,actor,q,true,actor);emit SafeRedeemRequested(actor,due,q);}
 function requestRedeem(uint256 q,address controller,address owner) external nonReentrant idle returns(uint64){return _ordinary(msg.sender,q,controller,owner);}
 function _ordinary(address actor,uint256 q,address controller,address owner) internal returns(uint64 due){IPCore(core).assertRequestAllowed();due=_requestAccounting(owner,controller,q,false,actor);emit RedeemRequested(owner,controller,due,q);}
 function safeFor(address actor,uint256 q) external onlyCore nonReentrant idle returns(uint64){return _safe(actor,q);}
 function requestFor(address actor,uint256 q,address controller,address owner) external onlyCore nonReentrant idle returns(uint64){return _ordinary(actor,q,controller,owner);}
'''
  r+=t.CLAIM_HELPER.replace('S.Layout storage s','Domains.Redemption storage s').replace('S.layout()','_rights')
  r+='function nextSettlement() external view returns(uint64,uint128){return _nextSettlement();}\n'
  if orchestrator=='core':
   r+='''function commitSettlement(uint64 due,uint128 num,uint128 den,uint128 a) external onlyCore {_commitSettlement(due,num,den,a);}
 function consumeClaim(address actor,uint64 due,uint256 q,address receiver,address controller) external onlyCore returns(uint256,uint256){return _consumeClaim(actor,due,q,receiver,controller);}
'''
  else:
   r+='''function settleMaturedEpochs(uint256 maxNodes) external nonReentrant idle returns(uint256 count){require(maxNodes>0&&maxNodes<=12,"NODES");for(;count<maxNodes;++count){(uint64 due,uint128 q)=_nextSettlement();if(due==0)break;(uint128 n,uint128 d,uint128 a)=IPCore(core).executeSettlement(q);_commitSettlement(due,n,d,a);}}
 function claimRedeem(uint64 due,uint256 q,address receiver,address controller) external nonReentrant idle returns(uint256 paid){IPCore(core).assertClaimAllowed();uint256 dust;(paid,dust)=_consumeClaim(msg.sender,due,q,receiver,controller);IPCore(core).executeClaim(receiver,paid,dust);}
'''
  src['partition/Redemption.sol']=r+'}\n'
  for name in ['_escrowShares','_spendAllowance']:
   if re.search(r'function '+name+r'\(',v):v=put(v,name,'')
  for name in ['safeRequestRedeem','requestRedeem']:v=put(v,name,'')
  if facade:
   v=add(v,'''function safeRequestRedeem(uint256 q) external returns(uint64){return IPRedemption(_redemption).safeFor(msg.sender,q);}
 function requestRedeem(uint256 q,address c,address o) external normalState requestsOpen returns(uint64){return IPRedemption(_redemption).requestFor(msg.sender,q,c,o);}
''')
  if not token:
   # Token domain stays Core in redemption-only control; fixed rights writer has only escrow/allowance powers.
   v=add(v,'''function spendRequestAllowance(address owner,address actor,uint256 q) external nonReentrant {require(msg.sender==_redemption,"REDEMPTION");_spendAllowance(owner,actor,q);}
 function protocolEscrow(address owner,uint256 q) external nonReentrant {require(msg.sender==_redemption&&owner!=address(0)&&owner!=address(this)&&owner!=_redemption&&q>0,"REDEMPTION");super._update(owner,_redemption,q);}
''')
   v=v.replace('if (to == address(this))','if (to == address(this) || to == _redemption)')
  v=add(v,'''function assertRequestAllowed() external view {_requireNormal();require(!S.layout().policy.requestsPaused,"REQUESTS");}
 function assertClaimAllowed() external view {_requireNormal();}
 function _queueHead() internal view returns(uint64 h){(h,,)=IPRedemption(_redemption).queueState();}
''')
 else:v=add(v,'function _queueHead() internal view returns(uint64){return S.layout().queueHead;}\n')
 if full:
  src['contracts/tbpros/lens/TbPROSLens.sol']=LENS
  v=add(v,t.CORE_HELPERS+'\nfunction _claimPayment(address receiver,uint256 paid,uint256 dust) internal {S.layout().accounting.P-=SafeCast.toUint128(paid+dust);S.layout().accounting.F+=SafeCast.toUint128(dust);_pay(receiver,paid);}\n')
  if not red:v=add(v,t.CLAIM_HELPER)
  elif orchestrator=='core':v=add(v,'''function _nextSettlement() internal view returns(uint64,uint128){return IPRedemption(_redemption).nextSettlement();}
 function _commitSettlement(uint64 due,uint128 num,uint128 den,uint128 a) internal {IPRedemption(_redemption).commitSettlement(due,num,den,a);}
 function _consumeClaim(address actor,uint64 due,uint256 q,address receiver,address controller) internal returns(uint256,uint256){return IPRedemption(_redemption).consumeClaim(actor,due,q,receiver,controller);}
''')
  for name,body in t.BODIES.items():v=put(v,name,body)
  if red and orchestrator=='manager':
   v=put(v,'settleMaturedEpochs','');v=put(v,'claimRedeem','')
   v=add(v,'''function executeSettlement(uint256 q) external nonReentrant normalState transition returns(uint128 n,uint128 d,uint128 a){require(msg.sender==_redemption,"REDEMPTION");(n,d,a)=_burnAccounting(q,address(this),true);S.layout().accounting.P+=a;}
 function executeClaim(address receiver,uint256 paid,uint256 dust) external nonReentrant normalState fundsLock transition {require(msg.sender==_redemption,"REDEMPTION");_claimPayment(receiver,paid,dust);}
''')
  # Complete core config final checks using the existing typed policy helper, never a Controller.
  helper=g.GOV_HELPER[:g.GOV_HELPER.index('  else if(u.kind==D.Kind.BucketConfig)')]+'\n }\n'
  v=imports(v,'import {D} from "partition/ConfigDTO.sol";');src['partition/ConfigDTO.sol']=g.DTO
  v=add(v,helper)
  for name,args,vals in g.SETTERS[:4]:v=put(v,name,f'function {name}({args}) external nonReentrant onlyTimelock {{_studyApply(D.Update({vals}));}}')
  riskhelpers=t.RISK_HELPERS.replace('__BUCKETS__','S.layout().riskBuckets')
  if risk:
   rm=manager_header('PartitionRisk','S.Bucket[2] private buckets;\n')
   rm+='constructor(address c,address tl,T.BucketConfig[2] memory cfg){require(c!=address(0)&&tl.code.length>0,"BIND");core=c;timelock=tl;for(uint256 i;i<2;++i){buckets[i].capacity=cfg[i].capacity;buckets[i].refillRateWad=cfg[i].refillRateWad;buckets[i].lastUpdate=SafeCast.toUint64(block.timestamp);}}\n'
   rm+=t.RISK_HELPERS.replace('__BUCKETS__','buckets')+'''function consume(uint256 q) external onlyCore {_consumeRisk(q);}
 function setBucketConfig(uint8 slot,T.BucketConfig calldata cfg) external onlyTimelock nonReentrant idle {_configureRisk(slot,cfg);}
 function bucket(uint8 slot) external view returns(S.Bucket memory){require(slot<2,"SLOT");return buckets[slot];}
}\n''';src['partition/Risk.sol']=rm
   v=put(v,'setBucketConfig','');v=add(v,'function _consumeRisk(uint256 q) internal {IPRisk(_risk).consume(q);}\n')
  else:
   v=add(v,riskhelpers);v=put(v,'setBucketConfig','function setBucketConfig(uint8 slot,T.BucketConfig calldata config) external nonReentrant onlyTimelock {_configureRisk(slot,config);}')
  if yield_:
   ym=manager_header('PartitionYield','Domains.Yield private _yield;\n')
   ym+='constructor(address c,address tl){require(c!=address(0)&&tl.code.length>0,"BIND");core=c;timelock=tl;_yield.nextPlanId=1;}\n'
   ym+=t.YIELD_HELPERS+fn(orig,'_absorbHLoss')
   ym=ym.replace('S.Layout storage s','Domains.Yield storage s').replace('S.layout()','_yield')
   ym+='''function totalH() external view returns(uint256){return _totalH();}
 function recordFunding(uint8 source,uint256 a,T.PlanTerms calldata terms,uint64 duration) external onlyCore returns(uint128){return _recordFunding(source,a,terms,duration);}
 function activate(uint128 id,uint128 u) external onlyCore {_activate(id,u);}
 function close(uint128 id,address receiver) external onlyCore returns(uint256,uint256){return _close(id,receiver);}
 function eligible(uint128 u,uint64 year_) external view returns(uint256,uint64,uint256){return _eligible(u,year_);}
 function release(uint256 a,uint64 cursor,uint256 carry,bytes32 obs) external onlyCore {_release(a,cursor,carry,obs);}
 function burnCarry(uint256 q,uint256 supply) external onlyCore {_burnCarry(q,supply);}
 function absorbLoss(uint256 target,uint256 total) external onlyCore returns(uint256[4] memory){require(total==_totalH()&&target<=total,"H");return _absorbHLoss(target,total);}
 function checkCap(uint128 u) external view {_checkCap(u);}
 function sourceRemaining(uint8 p,uint8 z) external view returns(uint128){require(p<2&&z<2,"SLOT");return _yield.plans[p].sources[z].remaining;}
 function nextPlanId() external view returns(uint128){return _yield.nextPlanId;}
}\n''';src['partition/Yield.sol']=ym
   # All plan/source fields actually leave Core; no H aggregate mirror.
   v=put(v,'_absorbHLoss','function _absorbHLoss(uint256 a,uint256 h) private returns(uint256[4] memory){return IPYield(_yieldManager).absorbLoss(a,h);}')
   v=put(v,'_accountedObligations','function _accountedObligations() internal view returns(uint256){S.Accounting storage a=S.layout().accounting;return uint256(a.R)+a.P+a.F+IPYield(_yieldManager).totalH();}')
   for name in ['sourceRemaining','nextPlanId']:v=put(v,name,'')
   wrappers={
    '_recordFunding':('uint8 z,uint256 a,T.PlanTerms memory terms,uint64 duration','returns(uint128)','recordFunding(z,a,terms,duration)'),
    '_activate':('uint128 id,uint128 u','','activate(id,u)'),
    '_close':('uint128 id,address receiver','returns(uint256,uint256)','close(id,receiver)'),
    '_eligible':('uint128 u,uint64 year_','view returns(uint256,uint64,uint256)','eligible(u,year_)'),
    '_release':('uint256 a,uint64 cursor,uint256 carry,bytes32 obs','','release(a,cursor,carry,obs)'),
    '_burnCarry':('uint256 q,uint256 supply','','burnCarry(q,supply)'),
    '_checkCap':('uint128 u','view','checkCap(u)')}
   for name,(args,ret,call) in wrappers.items():v=add(v,f'function {name}({args}) internal {ret} {{'+('return ' if 'returns' in ret else '')+f'IPYield(_yieldManager).{call};'+'}\n')
  else:v=add(v,t.YIELD_HELPERS)
 # One Core economic frame locks subordinate local writes without a global lock service.
 phase='bytes32 constant PARTITION_PHASE=keccak256("partition.core.phase");\nmodifier transition(){_beginTransition();_;_endTransition();}\n'
 phase+='function _beginTransition() internal {require(!PARTITION_PHASE.asBoolean().tload(),"PHASE");PARTITION_PHASE.asBoolean().tstore(true);'
 for name,on in zip(binds,active):
  if on:phase+=f'IPhase(_{name}).beginPhase();'
 phase+='}\nfunction _endTransition() internal {'
 for name,on in reversed(list(zip(binds,active))):
  if on:phase+=f'IPhase(_{name}).endPhase();'
 phase+='PARTITION_PHASE.asBoolean().tstore(false);}\nfunction transitionActive() external view returns(bool){return PARTITION_PHASE.asBoolean().tload();}\n'
 v=add(v,phase)
 # Already-mode sync/normal restore keep dependency-free returns; only active work enters phase.
 if yield_:
  v=v.replace('uint256 deficit = q - actual;','_beginTransition();\n        uint256 deficit = q - actual;',1)
  v=v.replace('if (deficit != 0) _enterInsolvency(actual, absorbedF, absorbedH, deficit);','if (deficit != 0) _enterInsolvency(actual, absorbedF, absorbedH, deficit);\n        _endTransition();')
 # No independent duplicates: remove transferred domains from the generated Core Layout.
 fields=(RD_FIELDS if red else [])+(['riskBuckets'] if risk else [])+(['plans','nextPlanId'] if yield_ else [])
 for field in fields:src[S]=re.sub(r'^\s*[^\n;]+\b'+field+r';[^\n]*\n','\n',src[S],flags=re.M)
 if not full:
  v=add(v,'function studyTokenRoundtrip(uint128 q) external nonReentrant normalState onlyTimelock transition returns(uint256 supply){supply=totalSupply();_mintToken(msg.sender,q);_burnToken(msg.sender,q,false);require(totalSupply()==supply,"SUPPLY");}\n')
 if full:
  rp='contracts/tbpros/reserves/ProsReserve.sol'
  src[rp]=imports(src[rp],'import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";')
  src[rp]=add(src[rp],'using SafeERC20 for IERC20;').replace('function available() external view','function available() public view')
  for name,body in t.RESERVE_BODIES.items():src[rp]=put(src[rp],name,body)
 src[V]=v
 return src

class Study:
 def __init__(self,fresh=False):
  self.solc=os.environ['TBPROS_SOLC'];self.compiler=subprocess.check_output([self.solc,'--version'],text=True).strip();assert '0.8.28+commit.7893614a' in self.compiler
  for n in ['contracts','contracts-upgradeable']:assert json.loads(Path('node_modules/@openzeppelin',n,'package.json').read_text())['version']=='5.6.1'
  self.rows=[];self.fresh=fresh
 def compile(self,label,src,paired=None,flags=None):
  flags=flags or {};roots=[V,'contracts/tbpros/reserves/ProsReserve.sol','contracts/tbpros/governance/UpgradeGateway.sol','contracts/tbpros/lens/TbPROSLens.sol']+[x for x in src if x.startswith('partition/') and x.split('/')[-1] in ['Token.sol','Risk.sol','Redemption.sol','Yield.sol']]
  sources=p.closure(src,roots)
  # Materialize the generated namespace as a type witness; never a deployed ledger.
  sources['partition/SchemaWitness.sol']='// SPDX-License-Identifier: MIT\npragma solidity 0.8.28; import {TbPROSStorage as S} from "'+S+'"; contract SchemaWitness {S.Layout internal witness;}'
  inp={'language':'Solidity','sources':{k:{'content':v} for k,v in sorted(sources.items())},'settings':{**PROFILE,'outputSelection':{'*':{'*':['abi','storageLayout','evm.bytecode.object','evm.deployedBytecode.object','evm.legacyAssembly']}}}}
  d=CACHE/label;d.mkdir(parents=True,exist_ok=True);encoded=p.encode(inp)
  reuse=not self.fresh and (d/'input.json').exists() and (d/'input.json').read_text()==encoded and (d/'output.json').exists()
  (d/'input.json').write_text(encoded)
  if reuse:out=json.loads((d/'output.json').read_text())
  else:
   proc=subprocess.run([self.solc,'--standard-json'],input=encoded,capture_output=True,text=True,check=True);(d/'output.json').write_text(proc.stdout);out=json.loads(proc.stdout)
  errors=[e['formattedMessage'] for e in out.get('errors',[]) if e['severity']=='error']
  if errors:raise RuntimeError(label+'\n'+'\n'.join(errors))
  sizes={};abis={};layouts={};ops={}
  names={'Reserve':('contracts/tbpros/reserves/ProsReserve.sol','ProsReserve'),'Gateway':('contracts/tbpros/governance/UpgradeGateway.sol','UpgradeGateway'),'Lens':('contracts/tbpros/lens/TbPROSLens.sol','TbPROSLens'),'Core':(V,'TbPROSVault'),'Token':('partition/Token.sol','PartitionToken'),'Redemption':('partition/Redemption.sol','PartitionRedemption'),'Yield':('partition/Yield.sol','PartitionYield'),'Risk':('partition/Risk.sol','PartitionRisk')}
  for n,(path,contract) in names.items():
   a=out['contracts'].get(path,{}).get(contract)
   if not a:sizes[n]=0;continue
   sizes[n]=len(a['evm']['deployedBytecode']['object'])//2;abis[n]=a['abi'];layouts[n]=a['storageLayout']
   ops[n]=dict(collections.Counter(x['name'] for x in a['evm']['legacyAssembly']['.data']['0']['.code'] if x['name'] in ['CALL','STATICCALL','DELEGATECALL','CALLCODE']))
   assert ops[n].get('DELEGATECALL',0)==0 and ops[n].get('CALLCODE',0)==0
   (d/(n+'.json')).write_text(json.dumps({'abi':a['abi'],'bytecode':{'object':'0x'+a['evm']['bytecode']['object']},'deployedBytecode':{'object':'0x'+a['evm']['deployedBytecode']['object']}}))
  (d/'abis.json').write_text(json.dumps(abis));(d/'layouts.json').write_text(json.dumps(layouts));(d/'flags.json').write_text(json.dumps(flags))
  schema=out['contracts']['partition/SchemaWitness.sol']['SchemaWitness']['storageLayout']
  (d/'core-schema.json').write_text(json.dumps(schema))
  row={'variant':label,'source_basis':BASE,'compiler_input_sha256':p.digest(encoded),'compiler_profile':PROFILE,'runtime':sizes,'headroom':{n:20480-s for n,s in sizes.items() if s},'combined_runtime':sum(sizes.values()),'paired':paired,'core_saving':next((r['runtime']['Core']-sizes['Core'] for r in self.rows if r['variant']==paired),None),'flags':flags,'ABI_migration':{n:sorted(x['name'] for x in a if x['type']=='function') for n,a in abis.items()},'state_ownership':{'S':'Token' if flags.get('token') else 'Core','R/P/F/U/B/C/Mode/custody':'Core','Epoch/Position/queue/count/operators':'Redemption' if flags.get('red') else 'Core','Plan/Source/H':'Yield' if flags.get('yield_') else 'Core','Bucket[2]':'Risk' if flags.get('risk') else 'Core'},'opcodes':ops,'gas':{},'recommended':False,'reason':'Isolated source-shaped pressure probe; no production migration or full integration verification.','runtime_gate':{n:'PASS' if s<20480 else 'FAIL' for n,s in sizes.items() if s},'warning_counts':dict(collections.Counter(str(x.get('errorCode')) for x in out.get('errors',[]) if x['severity']=='warning'))}
  self.rows.append(row);print(label,sizes,'saving',row['core_saving'],flush=True)
  row['core_namespace_members']=[m['label'] for m in schema['types'][schema['storage'][0]['type']]['members']]
  row['layout_sha256']=p.digest(json.dumps({'namespace':schema,'components':layouts},sort_keys=True))
  row['domain_runtime_sum']=sum(sizes[n] for n in ['Core','Token','Redemption','Yield','Risk'])
  row['deployment_runtime_sum_excluding_proxies_admins_adapter']=sum(sizes.values())+sizes['Reserve']
  row['core_16000_target']='PASS' if sizes['Core']<=16000 else 'FAIL'
  row['external_call_graph']={'safeRequest':['User -> '+('Core facade -> ' if flags.get('facade') else '')+('Redemption -> ' if flags.get('red') else 'Core -> ')+('Token' if flags.get('token') else 'Core local ERC20')], 'settlement':['User -> '+('Redemption -> Core -> Token; Core -> Redemption phase' if flags.get('orchestrator')=='manager' else 'Core -> rights / Token / Yield')], 'claim':['User -> '+('Redemption -> Core' if flags.get('orchestrator')=='manager' else 'Core -> rights')+'; Core -> Gateway / phase components / stPROS'], 'yield':['Core -> OracleAdapter / Yield' if flags.get('yield_') else 'Core -> OracleAdapter; local Plan'], 'solvency':['Core -> stPROS balanceOf'+(' / Yield totalH,absorbLoss' if flags.get('yield_') else '')], 'risk':['Timelock -> Risk; Core -> Risk' if flags.get('risk') else 'Core local Bucket'], 'interpretation':'Static source-derived topology, not a measured dynamic trace. Inactive domains are local. Already-mode sync returns before dependencies.'}
  if label.startswith('T'):
   for op in ['settlement','claim','yield','risk']:row['external_call_graph'][op]=['SkeletonOnly; no completed business call graph']
   row['reason']='Current skeleton/control only; token-only headroom does not prove complete V1 fit.'
  else:row['reason']=f"Core runtime {sizes['Core']} exceeds 20480 hard gate and 16000 comfort target; no architecture adoption."
 def save(self):
  DEST.write_text(json.dumps({'source_basis':BASE,'compiler':self.compiler,'tool_sha256':p.digest(Path(__file__).read_text()),'templates_sha256':p.digest(Path('tools/tbpros/multi-contract-study-templates.py').read_text()),'scope':'Pressure-only; committed production source unchanged. Generated domain contracts are not deployable product releases.','variants':self.rows},indent=2)+'\n')

def build(fresh=False,token_only=False):
 study=Study(fresh);base=p.source_at(BASE);study.compile('T0-current',base)
 study.compile('T0-token-glue-local',build_variant(base,full=False),'T0-current',{'full':False})
 study.compile('T1-token-current',build_variant(base,token=True,full=False),'T0-token-glue-local',{'token':True,'full':False})
 if not token_only:
  variants=[('P0-full-local',{}),('P1-token',{'token':True}),('P2-risk',{'risk':True}),('P3-red-direct',{'red':True}),('P4-red-facade',{'red':True,'facade':True}),('P5-token-red',{'token':True,'red':True}),('P6-token-red-risk',{'token':True,'red':True,'risk':True}),('P7-yield',{'yield_':True}),('P8-full-partition',{'token':True,'red':True,'risk':True,'yield_':True}),('P10-full-facade',{'token':True,'red':True,'risk':True,'yield_':True,'facade':True}),('P9-full-manager-orchestrated',{'token':True,'red':True,'risk':True,'yield_':True,'orchestrator':'manager'})]
  for name,flags in variants:study.compile(name,build_variant(base,**flags),None if name=='P0-full-local' else 'P0-full-local',flags)
 study.save()

def tests():
 CACHE.mkdir(parents=True,exist_ok=True)
 cfg=f'''[profile.default]
src = "{ROOT}/contracts/tbpros"
test = "{ROOT}/test/tbpros/multi-contract-study"
out = "{CACHE}/forge-out"
cache_path = "{CACHE}/forge-cache"
libs = ["{ROOT}/node_modules"]
remappings = ["tbpros/={ROOT}/contracts/tbpros/", "forge-std/={ROOT}/node_modules/forge-std/src/", "@openzeppelin/={ROOT}/node_modules/@openzeppelin/"]
optimizer = true
optimizer_runs = 200
via_ir = false
evm_version = "cancun"
fs_permissions = [{{access="read",path="{CACHE}"}}]
[profile.default.fuzz]
runs = 256
[profile.default.invariant]
runs = 128
depth = 64
fail_on_revert = true
'''
 (CACHE/'foundry.toml').write_text(cfg)
 env=dict(os.environ);env.pop('FOUNDRY_PROFILE',None);env['TBPROS_STUDY_ROOT']=str(ROOT)
 result=subprocess.run(['forge','test','--root',str(ROOT),'--config-path',str(CACHE/'foundry.toml'),'--use',os.environ['TBPROS_SOLC'],'--offline','--match-contract','MultiContract(Study|Invariant)Test','-vvv'],env=env,capture_output=True,text=True)
 (CACHE/'tests.log').write_text(result.stdout+'\n'+result.stderr);print('Study tests exit',result.returncode,flush=True)
 data=json.loads(DEST.read_text());gas=dict(re.findall(r'^  (PARTITION/[^:]+): (\d+)\s*$',result.stdout,re.M))
 for row in data['variants']:row['gas']={k.removeprefix('PARTITION/'+row['variant']+'/'):int(v) for k,v in gas.items() if k.startswith('PARTITION/'+row['variant']+'/')}
 data['test_result']={'status':'PASS' if result.returncode==0 else 'FAIL','summary':re.findall(r'Ran \d+ test suites?.*',result.stdout),'gas_samples':len(gas),'source_sha256':{str(x):p.digest(x.read_text()) for x in sorted(Path('test/tbpros/multi-contract-study').glob('*.sol'))},'reference_sha256':p.digest(Path('reference/multi_contract_partition_model.py').read_text())}
 DEST.write_text(json.dumps(data,indent=2)+'\n')
 if result.returncode:raise RuntimeError('Study tests FAIL: '+str(CACHE/'tests.log'))

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--fresh',action='store_true');parser.add_argument('--token-only',action='store_true');parser.add_argument('--tests-only',action='store_true');parser.add_argument('--compile-only',action='store_true');args=parser.parse_args()
 if not args.tests_only:build(args.fresh,args.token_only)
 if not args.token_only and not args.compile_only:tests()
