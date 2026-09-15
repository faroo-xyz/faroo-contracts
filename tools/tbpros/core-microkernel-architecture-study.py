"""Reproducible operation-partition pressure probes; production contracts remain unchanged."""
import argparse,collections,hashlib,importlib.util,json,os,re,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True

def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
p=load('partition','tools/tbpros/multi-contract-architecture-study.py');t=load('microtemplates','tools/tbpros/core-microkernel-study-templates.py')
BASE='60f73de98c468c8f28027f8ea0994c070fd390c6';ROOT=Path.cwd();CACHE=ROOT/'cache/tbpros-core-microkernel-study';DEST=ROOT/'docs/tbpros/verification/core-microkernel-architecture-variants.json'
V=p.V;R='partition/Redemption.sol';Y='partition/Yield.sol';SUB='micro/Subscription.sol'
FLAGS=[('M0-previous-p9',None),('M0-context-control',{}),('M1-subscription',dict(sub=True)),('M2-yield',dict(yield_=True)),('M3-redemption-fast',dict(fast=True)),('M4-subscription-redemption',dict(sub=True,fast=True)),('M5-all-operations',dict(sub=True,fast=True,yield_=True)),('M6-context-fence',dict(sub=True,fast=True,yield_=True,fence=True)),('M6-core-consumer',dict(sub=True,fast=True,yield_=True,fence=True,core_consumer=True))]

def variant(sub=False,yield_=False,fast=False,fence=False,core_consumer=False):
 src=p.build_variant(p.p.source_at(BASE),token=True,red=True,risk=True,yield_=True,orchestrator='manager')
 src={k:re.sub(r'(?m)^ *function ', '    function ',val) for k,val in src.items()};src['micro/Interfaces.sol']=t.INTERFACES;v=p.imports(src[V],t.IMPORTS)
 v=p.add(v,'address private _subscription;\n'+t.CONTEXT)
 init=p.fn(v,'initialize').replace('address[4] calldata components','address[5] calldata components')
 if sub:init=init.replace('T.Dependencies calldata d = config.dependencies;','T.Dependencies calldata d = config.dependencies;_requireCode(components[4]);require(IPhase(components[4]).core()==address(this),"SUB_BIND");_subscription=components[4];')
 v=p.put(v,'initialize',init)
 # Context is an entry fence, not an economic mirror. Raw getters remain unfenced for protocol snapshots.
 for name in re.findall(r'function (\w+)\(',v):
  f=p.fn(v,name)
  if 'nonReentrant' in f.split('{')[0]:
   v=p.put(v,name,f.replace('nonReentrant','nonReentrant contextIdle',1))
 v=p.add(v,'modifier contextIdle(){require(_get(CTX)==0,"ACTIVE_OPERATION");_;}\n')
 # Keep legacy local economic frames protected, but do not call all unrelated managers.
 v=p.put(v,'_beginTransition','function _beginTransition() internal {require(!PARTITION_PHASE.asBoolean().tload(),"PHASE");PARTITION_PHASE.asBoolean().tstore(true);}')
 v=p.put(v,'_endTransition','function _endTransition() internal {PARTITION_PHASE.asBoolean().tstore(false);}')
 # Managers read fresh Core bindings/config rather than retain an independently settable second copy.
 src[R]=p.imports(src[R],t.IMPORTS);src[Y]=p.imports(src[Y],t.IMPORTS)
 checkpoint='IMYield(IMCore(core).yieldManager()).checkpointFor();' if yield_ else 'IMCore(core).checkpointYield();'
 if sub:
  v=p.put(v,'subscribe','');v=p.add(v,t.SUB_CORE)
  src[SUB]=p.manager_header('PartitionSubscription','address public immutable risk;\n').replace('import {IPToken,IPCore,IPRedemption}','import {IPToken,IPCore,IPRedemption,IPRisk}')
  src[SUB]=p.imports(src[SUB],t.IMPORTS)+'constructor(address c,address tl,address rk){core=c;timelock=tl;risk=rk;}\n'+t.RECEIVE+t.SUB_FLOW+'function _checkpointBefore() internal {'+checkpoint+'}\n}\n'
  src['partition/Risk.sol']=p.imports(src['partition/Risk.sol'],t.IMPORTS)
  src['partition/Risk.sol']=p.put(src['partition/Risk.sol'],'consume','function consume(uint256 q) external {require(msg.sender==IMCore(core).subscription(),"SUBSCRIPTION");_consumeRisk(q);}')
 if yield_:
  for n in ['checkpointYield','fundPlan','activatePlan','closePlan','schedulePenaltyPlan']:v=p.put(v,n,'')
  v=p.add(v,t.YIELD_CORE);src[Y]=p.add(src[Y],t.RECEIVE+t.YIELD_FLOW)
  # Remove unused Core write selectors from YM, retaining read/loss/carry needed by Core.
  for n in ['recordFunding','activate','close','release']:src[Y]=p.put(src[Y],n,'')
  v=p.put(v,'_checkpoint','function _checkpoint() internal returns(uint256){return IMYield(_yieldManager).checkpointFor();}')
  v=p.add(v,'modifier preYield(){_checkpoint();_;}\n')
  for n,on in [('subscribe',not sub),('fastRedeem',not fast)]:
   if on:
    f=p.fn(v,n).replace('external nonReentrant','external preYield nonReentrant').replace('_checkpoint();','');v=p.put(v,n,f)
 if fast:
  v=p.put(v,'fastRedeem','');v=p.add(v,t.FAST_CORE);src[R]=p.add(src[R],t.FAST_FLOW+'function _checkpointBefore() internal {'+checkpoint+'}\n')
 # M6 covers the complete rights transition, not only its nested Core call.
 if fence:
  v=p.add(v,'''function beginSettlement() external nonReentrant onlyRedemption {_start(6);}
 function endSettlement() external nonReentrant onlyRedemption {_finish(6);}
 function beginClaim() external nonReentrant onlyRedemption {_start(7);}
 function endClaim() external nonReentrant onlyRedemption {_finish(7);}
''')
  v=p.put(v,'executeSettlement','function executeSettlement(uint256 q) external nonReentrant onlyRedemption returns(uint128 n,uint128 d,uint128 a){_match(6);(n,d,a)=_burnAccounting(q,address(this),true);S.layout().accounting.P+=a;}')
  v=p.put(v,'executeClaim','function executeClaim(address receiver,uint256 paid,uint256 dust) external nonReentrant onlyRedemption {_match(7);require(paid+dust<=S.layout().accounting.P,"P");_claimPayment(receiver,paid,dust);}')
  f=p.fn(src[R],'settleMaturedEpochs').replace('returns(uint256 count){','returns(uint256 count){IMCore(core).beginSettlement();');f=f[:-1]+'IMCore(core).endSettlement();}';src[R]=p.put(src[R],'settleMaturedEpochs',f)
  f=p.fn(src[R],'claimRedeem').replace('IPCore(core).assertClaimAllowed();','IMCore(core).beginClaim();');f=f[:-1]+'IMCore(core).endClaim();}';src[R]=p.put(src[R],'claimRedeem',f)
 # Keep unneeded legacy helpers unreachable; solc dead-code-eliminates them. No business capability is deleted.
 # Fixed purpose consumer and fixed intermediate receiver; final stPROS always Core.
 rp='contracts/tbpros/reserves/ProsReserve.sol';reserve=src[rp]
 reserve=p.imports(reserve,t.IMPORTS)
 reserve=reserve.replace('msg.sender != boundVault','msg.sender != _consumer()')
 consumer=('IMCore(boundVault).subscription()' if sub else 'boundVault')
 yc='IMCore(boundVault).yieldManager()' if yield_ else 'boundVault'
 reserve=p.add(reserve,'function _consumer() internal view returns(address){return purpose==Purpose.Subscription?'+consumer+':'+yc+';}\n')
 reserve=p.put(reserve,'consume',p.fn(reserve,'consume').replace('balanceOf(boundVault)','balanceOf(_consumer())').replace('safeTransfer(boundVault,a)','safeTransfer(_consumer(),a)'))
 if core_consumer:
  # Closed relay diagnostic; Core never exposes arbitrary recipient/spender/call data.
  reserve=p.put(reserve,'_consumer','function _consumer() internal view returns(address){return purpose==Purpose.Subscription?boundVault:'+yc+';}')
  v=p.add(v,'function consumeSubscriptionReserve(uint256 a) external nonReentrant onlySubscription {_match(1);require(a==_get(PROS),"PROS");IProsReserve(S.layout().dependencies.subscriptionReserve).consume(a);IERC20(S.layout().dependencies.wpros).safeTransfer(_subscription,a);}')
  src[SUB]=src[SUB].replace('IProsReserve(reserve).consume(pros);','IMCore(core).consumeSubscriptionReserve(pros);')
 src[rp]=reserve;src[V]=v
 return src

def compile_all(fresh=False):
 solc=os.environ['TBPROS_SOLC'];compiler=subprocess.check_output([solc,'--version'],text=True).strip();assert '0.8.28+commit.7893614a' in compiler
 for n in ['contracts','contracts-upgradeable']:assert json.loads(Path('node_modules/@openzeppelin',n,'package.json').read_text())['version']=='5.6.1'
 rows=[]
 for label,flags in FLAGS:
  src=p.build_variant(p.p.source_at(BASE),token=True,red=True,risk=True,yield_=True,orchestrator='manager') if flags is None else variant(**flags)
  roots=[V,R,Y,'partition/Token.sol','partition/Risk.sol','contracts/tbpros/reserves/ProsReserve.sol','contracts/tbpros/governance/UpgradeGateway.sol','contracts/tbpros/lens/TbPROSLens.sol']+([SUB] if flags and flags.get('sub') else [])
  sources=p.p.closure(src,roots);sources['micro/Schema.sol']='// SPDX-License-Identifier: MIT\npragma solidity 0.8.28;import {TbPROSStorage as S} from "'+p.S+'";contract Schema {S.Layout internal witness;}'
  inp={'language':'Solidity','sources':{k:{'content':v} for k,v in sorted(sources.items())},'settings':{**p.PROFILE,'outputSelection':{'*':{'*':['abi','storageLayout','evm.bytecode.object','evm.deployedBytecode.object','evm.legacyAssembly']}}}}
  d=CACHE/label;d.mkdir(parents=True,exist_ok=True);encoded=p.p.encode(inp)
  if not fresh and (d/'input.json').exists() and (d/'input.json').read_text()==encoded and (d/'output.json').exists():out=json.loads((d/'output.json').read_text())
  else:
   run=subprocess.run([solc,'--standard-json'],input=encoded,capture_output=True,text=True,check=True);(d/'input.json').write_text(encoded);(d/'output.json').write_text(run.stdout);out=json.loads(run.stdout)
  err=[e['formattedMessage'] for e in out.get('errors',[]) if e['severity']=='error']
  if err:raise RuntimeError(label+'\n'+'\n'.join(err))
  sizes={};abis={};layouts={};ops={}
  names={'Core':(V,'TbPROSVault'),'Token':('partition/Token.sol','PartitionToken'),'Subscription':(SUB,'PartitionSubscription'),'Redemption':(R,'PartitionRedemption'),'Yield':(Y,'PartitionYield'),'Risk':('partition/Risk.sol','PartitionRisk'),'Reserve':('contracts/tbpros/reserves/ProsReserve.sol','ProsReserve'),'Gateway':('contracts/tbpros/governance/UpgradeGateway.sol','UpgradeGateway'),'Lens':('contracts/tbpros/lens/TbPROSLens.sol','TbPROSLens')}
  for n,(path,contract) in names.items():
   a=out['contracts'].get(path,{}).get(contract)
   if not a:sizes[n]=0;continue
   sizes[n]=len(a['evm']['deployedBytecode']['object'])//2;abis[n]=a['abi'];layouts[n]=a['storageLayout'];ops[n]=dict(collections.Counter(z['name'] for z in a['evm']['legacyAssembly']['.data']['0']['.code'] if z['name'] in ['CALL','STATICCALL','DELEGATECALL','CALLCODE']))
   assert not ops[n].get('DELEGATECALL') and not ops[n].get('CALLCODE')
   (d/(n+'.json')).write_text(json.dumps({'abi':a['abi'],'bytecode':{'object':'0x'+a['evm']['bytecode']['object']},'deployedBytecode':{'object':'0x'+a['evm']['deployedBytecode']['object']}}))
  (d/'layouts.json').write_text(json.dumps(layouts));(d/'abis.json').write_text(json.dumps(abis));(d/'flags.json').write_text(json.dumps(flags))
  row={'variant':label,'flags':flags,'runtime':sizes,'headroom_20480':{n:20480-v for n,v in sizes.items() if v},'core_headroom_16000':16000-sizes['Core'],'core_saving_vs_M0':rows[0]['runtime']['Core']-sizes['Core'] if rows else 0,'runtime_surface_excluding_proxies_admins_adapter':sum(sizes.values())+sizes['Reserve'],'compiler_input_sha256':p.p.digest(encoded),'abi_routes':{n:sorted(a['name'] for a in abi if a['type']=='function') for n,abi in abis.items()},'opcodes':ops,'warnings':dict(collections.Counter(str(e.get('errorCode')) for e in out.get('errors',[]) if e['severity']=='warning')),'gas':{},'recommended':False,'reason':'Y-A still requires complex Yield for Q; Claim and normal sync liveness blocked if Yield fails. Not production verified.'}
  row['state_ownership']={'Core':'R/P/F/U/B/C/Mode/custody/config; transaction-local fixed operation facts','Token':'OZ S/balances/allowances','Redemption':'Epoch/Position/queue/count/operators','Yield':'Plan/Source/H/cursor/carry','Risk':'Bucket[2]','Subscription':'immutable bindings only; no persistent economic ledger'}
  row['dependencies']={'safeRequest':['Redemption','Token'],'Claim':['Redemption','Core','stPROS','Yield(totalH)','Gateway']+(['Token/Risk phase (previous P9 only)'] if flags is None else []),'Settlement':['Redemption','Core','Token','Yield(totalH/burnCarry)']+(['Gateway'] if flags and flags.get('fence') else []),'sync':['Core','stPROS','Yield(totalH/absorbLoss)'],'subscription':['Subscription or Core','Core','Token','Yield','Risk','Oracle','Subscription Reserve','USDC','WPROS','stPROS','Gateway'],'yield':['Yield or Core','Core','Redemption backlog read','Oracle','Gateway'],'plan funding':['Yield or Core','Core','Yield Reserve','WPROS','stPROS','Gateway']}
  row['trust_assumptions']=['Redemption is authoritative rights truth: compromised writer can drain P within bounds','Subscription price/risk workflow remains trusted despite Core actual receipt and E01 checks','Yield totalH is authoritative: malicious source reporting defeats Q and H-delta checks','Fixed bindings and Model A root; existing Gateway is not a multi-proxy upgrade implementation','Raw getters are not callback-atomic value quotes; M6 Core frame fences aggregate Lens']
  row['gateway_probe_status']='NOT BUILT: full Core runtime gate fails; current Gateway included only as skeleton baseline cost. Coupled topology is design-only.'
  row['core_hard_gate']='PASS' if sizes['Core']<=20480 else 'FAIL'
  row['paired_control']='M0-context-control' if flags else 'M0-previous-p9'
  row['saving_vs_context_control']=next((r['runtime']['Core']-sizes['Core'] for r in rows if r['variant']=='M0-context-control'),None)
  rows.append(row);print(label,sizes,flush=True)
 if rows[0]['runtime']['Core']!=24682:raise AssertionError('M0 baseline drift')
 DEST.write_text(json.dumps({'source_basis':BASE,'compiler':compiler,'profile':p.PROFILE,'tool_sha256':p.p.digest(Path(__file__).read_text()),'templates_sha256':p.p.digest(Path('tools/tbpros/core-microkernel-study-templates.py').read_text()),'variants':rows},indent=2)+'\n')

def tests():
 CACHE.mkdir(parents=True,exist_ok=True)
 cfg=f'''[profile.default]
src = "{ROOT}/contracts/tbpros"
test = "{ROOT}/test/tbpros/core-microkernel-study"
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
 result=subprocess.run(['forge','test','--root',str(ROOT),'--config-path',str(CACHE/'foundry.toml'),'--use',os.environ['TBPROS_SOLC'],'--offline','--match-contract','Micro(Study|Invariant)Test','-vvv'],env=env,capture_output=True,text=True)
 (CACHE/'tests.log').write_text(result.stdout+'\n'+result.stderr);print('Study tests exit',result.returncode,flush=True)
 data=json.loads(DEST.read_text());gas=dict(re.findall(r'^  (MICRO/[^:]+): (\d+)\s*$',result.stdout,re.M))
 for row in data['variants']:row['gas']={k.removeprefix('MICRO/'+row['variant']+'/'):int(v) for k,v in gas.items() if k.startswith('MICRO/'+row['variant']+'/')}
 data['test_result']={'status':'PASS' if result.returncode==0 else 'FAIL','summary':re.findall(r'Ran \d+ test suites?.*',result.stdout),'gas_samples':len(gas),'source_sha256':{str(x):p.p.digest(x.read_text()) for x in sorted(Path('test/tbpros/core-microkernel-study').glob('*.sol'))},'reference_sha256':p.p.digest(Path('reference/core_microkernel_model.py').read_text())}
 DEST.write_text(json.dumps(data,indent=2)+'\n')
 if result.returncode:raise RuntimeError('Study tests FAIL: '+str(CACHE/'tests.log'))

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--fresh',action='store_true');parser.add_argument('--tests-only',action='store_true');parser.add_argument('--compile-only',action='store_true');args=parser.parse_args()
 if not args.tests_only:compile_all(args.fresh)
 if not args.compile_only:tests()
