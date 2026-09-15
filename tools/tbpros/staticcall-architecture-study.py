"""Reproducible STATICCALL/typed-governance feasibility probes. Never deploy these variants.

Uses the committed Vault, OZ and guards. Generated Solidity and compiler outputs stay
in ignored cache. Default runs compile + isolated Foundry tests; --compile-only builds
artifacts, --tests-only reruns tests. --fresh disables exact-input compiler cache reuse.
Production source/ABI/storage and all original financial stubs remain untouched.
"""
import argparse,collections,hashlib,importlib.util,json,os,re,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True

def load(name,file):
 s=importlib.util.spec_from_file_location(name,file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
prev=load('previous','tools/tbpros/bytecode-architecture-review.py')
t=load('templates','tools/tbpros/staticcall-study-templates.py')
BASE='f3187659eb19a464abfc5bc93e15a3d4e73c7e2b'
ROOT=Path.cwd();CACHE=ROOT/'cache/tbpros-staticcall-study';DEST=ROOT/'docs/tbpros/verification/staticcall-architecture-variants.json'
V,I,S=prev.V,prev.I,prev.S
GROUPS=['settlement','claim','mint','yield','risk','plan']
PROFILE=prev.PROFILE

def opcodes(evm):
 # Compiler runtime assembly instructions exclude both literal-data blobs and CBOR.
 # Linear byte disassembly can mistake embedded constant data for call opcodes.
 instructions=evm['legacyAssembly']['.data']['0']['.code']
 count=collections.Counter(x.get('name') for x in instructions)
 return {name:count[name] for name in ['CALL','STATICCALL','DELEGATECALL','SSTORE','TSTORE','SELFDESTRUCT']}


def support():
 calc='// SPDX-License-Identifier: MIT\npragma solidity 0.8.28;\nimport {D} from "study/DTO.sol";\nimport {Math} from "@openzeppelin/contracts/utils/math/Math.sol";\nlibrary Calc {\n'+'\n'.join(t.CALC_FUNCTIONS.values())+'\n}'
 interface='// SPDX-License-Identifier: MIT\npragma solidity 0.8.28;\nimport {D} from "study/DTO.sol";\ninterface IMath {\n function moduleVersion() external pure returns(bytes32);\n'
 for name,args,returns,call in t.SIGNATURES.values():interface+=f' function {name}({args}) external pure returns({returns});\n'
 interface+=' function claimScalars(uint128 oldClaimed,uint128 delta,uint128 requested,uint128 num,uint128 den,uint128 remaining) external pure returns(uint256,uint256);\n function claimPacked(bytes calldata data) external pure returns(uint256,uint256);\n}'
 interface+='\ninterface IRegistry {function governanceController() external view returns(address);}\ninterface IController {function timelock() external view returns(address);function vault() external view returns(address);}'
 return {'study/DTO.sol':t.DTO,'study/Calc.sol':calc,'study/IMath.sol':interface}

def module_source(groups,dto="struct"):
 s='// SPDX-License-Identifier: MIT\npragma solidity 0.8.28;\nimport {D} from "study/DTO.sol";\nimport {Calc} from "study/Calc.sol";\ncontract StudyModule {function moduleVersion() external pure returns(bytes32){return keccak256("tbpros.study.v1");}\n'
 for g in groups:
  if g=='claim' and dto!='struct':continue
  name,args,returns,call=t.SIGNATURES[g];s+=f'function {name}({args}) external pure returns({returns}){{return {call};}}\n'
 if 'claim' in groups and dto=='scalar':
  s+='function claimScalars(uint128 oldClaimed,uint128 delta,uint128 requested,uint128 num,uint128 den,uint128 remaining) external pure returns(uint256,uint256){return Calc.claim(D.Claim(oldClaimed,delta,requested,num,den,remaining));}\n'
 if 'claim' in groups and dto=='packed':
  s+='function claimPacked(bytes calldata data) external pure returns(uint256,uint256){(uint256 a,uint256 b,uint256 c)=abi.decode(data,(uint256,uint256,uint256));return Calc.claim(D.Claim(uint128(a),uint128(a>>128),uint128(b),uint128(b>>128),uint128(c),uint128(c>>128)));}\n'
 return s+'}\n'

def add_bindings(src,n,controller=False,derived=False,identity='decode',hashes=None):
 if not n and not controller:return src
 src=dict(src)
 fields=(f'address[{n}] modules;' if n else '')+('address controller;' if controller and not derived else '')
 if fields:
  src[S]=src[S].replace('    struct Layout {','    struct StudyBindings { '+fields+' }\n    struct Layout {',1)
  src[S]=src[S].replace('        uint64 yearSeconds;','        uint64 yearSeconds;\n        StudyBindings study;',1)
 extra=(f', address[{n}] calldata modules' if n else '')+(', address controller' if controller else '')
 for p in [V,I]:
  src[p]=re.sub(r'initialize\(([TS])\.InitConfig calldata config\)',lambda m:'initialize('+m[1]+'.InitConfig calldata config'+extra+')',src[p])
 code=''
 for j in range(n):
  code+=f'        _requireCode(modules[{j}]);\n        bytes32 version{j}=IMath(modules[{j}]).moduleVersion();\n        _studyReturnSize(32);\n'
  code+=f'        require(version{j}'+('==keccak256("tbpros.study.v1")' if identity in ['version','hash'] else '!=bytes32(0)')+',"MODULE_ID");\n'
  if identity=='hash':code+=f'        require(modules[{j}].codehash==hex"{hashes[j]}","MODULE_HASH");\n'
  code+=f'        S.layout().study.modules[{j}]=modules[{j}];\n'
 if controller:
  code+='        _requireCode(controller);\n        require(IController(controller).timelock()==d.timelock && IController(controller).vault()==address(this),"CONTROLLER_BINDING");\n'
  if not derived:code+='        S.layout().study.controller=controller;\n'
  else:code+='        require(IRegistry(d.gateway).governanceController()==controller,"REGISTRY_BINDING");\n'
 src[V]=src[V].replace('        _requireCode(d.timelock);',code+'        _requireCode(d.timelock);',1)
 return src

def governance(src,kind,count,derived=False):
 src=dict(src); helpers=t.GOV_HELPER
 # Both sides use the same complete final checks; entry ABI and authority are the experimental factor.
 if count==5:helpers=helpers[:helpers.index('  else if(u.kind==D.Kind.Oracle)')]+'\n }\n'
 src=prev.insert(src,helpers)
 for name,args,values in t.SETTERS[:count]:
  src[V]=prev.replace_function(src[V],name)
  if kind!='local':src[I]=prev.replace_function(src[I],name)
  else:src=prev.insert(src,f' function {name}({args}) external nonReentrant onlyTimelock {{_studyApply(D.Update({values}));}}\n')
 if kind=='local':return src
 target='IRegistry(S.layout().dependencies.gateway).governanceController()' if derived else 'S.layout().study.controller'
 check=f'require(msg.sender=={target},"CONTROLLER");'
 if kind=='enum':
  code=f' function applyGovernance(D.Update calldata u) external nonReentrant {{{check} require(uint8(u.kind)<{count},"KIND");_studyApply(u);}}'
 else:
  code=f' function applyGovernance(D.Delta calldata d) external nonReentrant {{{check}'+t.BATCH_BODY+'}'
 src=prev.insert(src,code)
 ctrl='''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {D} from "study/DTO.sol";
import {TbPROSTypes as T} from "contracts/tbpros/TbPROSTypes.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
interface IApply {function applyGovernance('''+('D.Update' if kind=='enum' else 'D.Delta')+''' calldata u) external;}
contract StudyController is ReentrancyGuardTransient {
 address public immutable timelock; address public immutable vault;
 constructor(address tl,address v){require(tl.code.length>0 && v!=address(0),"BINDING");timelock=tl;vault=v;}
 modifier onlyTimelock(){require(msg.sender==timelock,"TL");_;}
'''
 for idx,(name,args,values) in enumerate(t.SETTERS[:count]):
  validation=['','require(maxMintLossBps<=10000,"POLICY");','require(fastFeeBps<=10000,"POLICY");','require(maxPlanDuration>0,"POLICY");','require(slot<2,"POLICY");','require(oracle.code.length>0 && oracle!=vault,"POLICY");','require(receiver!=address(0) && receiver!=vault,"POLICY");','require(receiver!=address(0) && receiver!=vault,"POLICY");'][idx]
  if kind=='enum':body='IApply(vault).applyGovernance(D.Update('+values+'));'
  else:
   assignments=['d.cap=principalCap;','d.mintLoss=maxMintLossBps;','d.fastFee=fastFeeBps;','d.duration=maxPlanDuration;','d.slot=slot;d.bucketCap=config.capacity;d.bucketRate=config.refillRateWad;','d.oracle=oracle;','d.foundation=receiver;','d.refund=receiver;'][idx]
   body=f'D.Delta memory d;d.mask={1<<idx};'+assignments+'IApply(vault).applyGovernance(d);'
  ctrl+=f'function {name}({args}) external nonReentrant onlyTimelock {{{validation}{body}}}\n'
 if kind=='batch':ctrl+='function applyBatch(D.Delta calldata d) external nonReentrant onlyTimelock {require(d.mask>0 && d.mask<256,"MASK");IApply(vault).applyGovernance(d);}\n'
 src['study/Controller.sol']=ctrl+'}\n'
 if derived:
  g='contracts/tbpros/governance/UpgradeGateway.sol'
  src[g]=src[g].replace('    address public immutable timelock;', '    address public immutable timelock;\n    address public immutable governanceController;')
  src[g]=src[g].replace('    constructor(address tl, uint64 floor_) {','    constructor(address tl, uint64 floor_, address controller) {\n        governanceController=controller;')
 return src

def variant(base,groups=(),external=(),count=1,dto='struct',identity='decode',hashes=None,gov=None,gov_count=8,derived=False,h=False,extra_h_checks=True):
 src={**base,**support()}; assignments={g:0 for g in external}
 if count==2:assignments.update({g:1 for g in external if g in ['yield','risk','plan']})
 if count==3:assignments.update({g:1 if g=='yield' else 2 for g in external if g in ['yield','risk','plan']})
 if count==4:assignments.update({g:1 if g=='mint' else 2 if g=='yield' else 3 for g in external if g in ['mint','yield','risk','plan']})
 n=count if external or h else 0
 src[V]=src[V].replace('import {Math}',t.IMPORTS+'import {IRegistry,IController} from "study/IMath.sol";\nimport {Math}',1)
 if n:src=prev.insert(src,t.CHECK_RETURN)
 for j in range(n):src[f'study/Module{j}.sol']=module_source([g for g,i in assignments.items() if i==j]+(['hloss'] if h and j==0 else []),dto)
 src=add_bindings(src,n,gov not in [None,'local'],derived,identity,hashes)
 for g in groups:
  code=t.WRAPPERS[g]
  if g in external:
   name,args,returns,local=t.SIGNATURES[g];idx=assignments[g];call=f'IMath(S.layout().study.modules[{idx}]).{name}(a)'
   if g=='claim' and dto=='scalar':call=f'IMath(S.layout().study.modules[{idx}]).claimScalars(a.oldClaimed,a.delta,a.requested,a.num,a.den,a.remaining)'
   if g=='claim' and dto=='packed':call=f'IMath(S.layout().study.modules[{idx}]).claimPacked(abi.encode(uint256(a.oldClaimed)|(uint256(a.delta)<<128),uint256(a.requested)|(uint256(a.num)<<128),uint256(a.den)|(uint256(a.remaining)<<128)))'
   code=code.replace('__CALC__',call).replace('__RET__',f'_studyReturnSize({32*len(returns.split(","))});')
  else:code=code.replace('__CALC__',t.SIGNATURES[g][3]).replace('__RET__','')
  src=prev.insert(src,code)
 if h:
  text='''    function _absorbHLoss(uint256 target,uint256 total) private returns(uint256[4] memory cuts) {
    S.Layout storage s=S.layout();uint128[4] memory h;
    for(uint256 i;i<4;++i)h[i]=s.plans[i/2].sources[i%2].remaining;
    cuts=IMath(s.study.modules[0]).allocateHLoss(target,h);_studyReturnSize(128);
    __CHECKS__
    for(uint256 i;i<4;++i){S.Source storage z=s.plans[i/2].sources[i%2];uint128 cut=SafeCast.toUint128(cuts[i]);z.remaining-=cut;z.realizedLoss+=cut;}
    }'''
  text=text.replace('__CHECKS__','uint256 sum;for(uint256 i;i<4;++i){require(cuts[i]<=h[i],"CUT");sum+=cuts[i];}require(sum==target && target<=total,"SUM");' if extra_h_checks else '')
  src[V]=prev.replace_function(src[V],'_absorbHLoss',text)
  src[V]=src[V].replace('        s.accounting.F -= SafeCast.toUint128(absorbedF);','')
  src[V]=src[V].replace('        if (absorbedF != 0 || absorbedH != 0)', '        s.accounting.F -= SafeCast.toUint128(absorbedF);\n        if (absorbedF != 0 || absorbedH != 0)')
 if gov:src=governance(src,gov,gov_count,derived)
 return src,assignments,n

class Study:
 def __init__(self,fresh=False):
  self.solc=os.environ['TBPROS_SOLC'];self.compiler=subprocess.check_output([self.solc,'--version'],text=True).strip();assert '0.8.28+commit.7893614a' in self.compiler
  for pkg in ['contracts','contracts-upgradeable']:assert json.loads(Path('node_modules/@openzeppelin',pkg,'package.json').read_text())['version']=='5.6.1'
  self.rows=[];self.abi=None;self.layout=None;self.fresh=fresh
 def compile(self,label,src,paired=None,groups=(),assignments=None,n=0,gov=None,derived=False,h=False,category='SAFE_STATICCALC',reason=''):
  src=dict(src);src['study/Layout.sol']='// SPDX-License-Identifier: MIT\npragma solidity 0.8.28;import {TbPROSStorage as S} from "contracts/tbpros/TbPROSStorage.sol";contract Layout {S.Layout internal state;}'
  roots=[V,'study/Layout.sol']+[p for p in src if p.startswith('study/Module') or p=='study/Controller.sol']
  if derived:roots+=['contracts/tbpros/governance/UpgradeGateway.sol']
  sources=prev.closure(src,roots);inp={'language':'Solidity','sources':{k:{'content':v} for k,v in sorted(sources.items())},'settings':{**PROFILE,'outputSelection':{'*':{'*':['abi','storageLayout','evm.bytecode.object','evm.deployedBytecode.object','evm.legacyAssembly']}}}}
  directory=CACHE/label;directory.mkdir(parents=True,exist_ok=True);encoded=prev.encode(inp);fingerprint=prev.digest(encoded)
  reuse=not self.fresh and (directory/'input.json').exists() and (directory/'input.json').read_text()==encoded and (directory/'output.json').exists()
  (directory/'input.json').write_text(encoded)
  if reuse:out=json.loads((directory/'output.json').read_text())
  else:
   process=subprocess.run([self.solc,'--standard-json'],input=encoded,capture_output=True,text=True,check=True);(directory/'output.json').write_text(process.stdout);out=json.loads(process.stdout)
  errors=[e['formattedMessage'] for e in out.get('errors',[]) if e['severity']=='error']
  if errors:raise RuntimeError(label+'\n'+'\n'.join(errors))
  vault=out['contracts'][V]['TbPROSVault'];abi=prev.abi_entries(vault['abi']);layout=prev.layout_shape(out['contracts']['study/Layout.sol']['Layout']['storageLayout'])
  runtime=len(vault['evm']['deployedBytecode']['object'])//2
  if self.abi is None:assert runtime==18574;self.abi=abi;self.layout=layout
  modules={};artifacts={'Vault':vault}
  for i in range(n):
   a=out['contracts'][f'study/Module{i}.sol']['StudyModule'];modules[str(i)]=len(a['evm']['deployedBytecode']['object'])//2;artifacts[f'Module{i}']=a
   ops=opcodes(a['evm']);assert not any(ops.values()),ops
  ctrl=out['contracts'].get('study/Controller.sol',{}).get('StudyController');controller_runtime=0
  if ctrl:artifacts['Controller']=ctrl;controller_runtime=len(ctrl['evm']['deployedBytecode']['object'])//2
  if derived:artifacts['RegistryGateway']=out['contracts']['contracts/tbpros/governance/UpgradeGateway.sol']['UpgradeGateway']
  for name,a in artifacts.items():
   (directory/(name+'.json')).write_text(json.dumps({'abi':a['abi'],'bytecode':{'object':'0x'+a['evm']['bytecode']['object']},'deployedBytecode':{'object':'0x'+a['evm']['deployedBytecode']['object']}}))
  ops=opcodes(vault['evm']);assert ops['DELEGATECALL']==0
  row={'variant':label,'source_basis':BASE,'compiler_input_sha256':fingerprint,'compiler_profile':PROFILE,'source_hashes':{k:prev.digest(v) for k,v in sorted(sources.items()) if k.startswith('contracts/tbpros/')},'Vault_runtime':runtime,'Vault_initcode_template':len(vault['evm']['bytecode']['object'])//2,'Module_runtime':modules,'Controller_runtime':controller_runtime,'Vault_delta_vs_baseline':runtime-18574,'paired_local':paired,'Vault_saving_vs_paired':next((r['Vault_runtime']-runtime for r in self.rows if r['variant']==paired),None),'ABI_delta':{'removed':sorted(self.abi.keys()-abi.keys()),'added':sorted(abi.keys()-self.abi.keys()),'changed':sorted(k for k in abi.keys()&self.abi.keys() if abi[k]!=self.abi[k])},'storage_delta':{'changed':layout!=self.layout,'note':f'Append-only StudyBindings with {n} fixed module addresses; '+('controller derived via fixed Gateway getter' if derived else 'fixed controller stored' if ctrl else 'no controller')},'groups':list(groups),'assignments':assignments or {},'h_external':h,'external_calls_added':f'{n} fixed module identities at initialize; one STATICCALL per external calculator; '+('closed Controller CALL to applyGovernance' if ctrl else 'no Controller'),'Vault_opcodes':ops,'gas':{},'security_category':category,'recommended':False,'adopted':False,'reason':reason or 'Isolated calculator/configuration probe only, not completed financial implementation.','runtime_budget_status':'PASS' if runtime<=20480 else 'FAIL','module_budget_pass':all(x<=12288 for x in modules.values()),'controller_budget_pass':controller_runtime<=8192,'combined_measured_runtime':runtime+sum(modules.values())+controller_runtime,'warning_counts':dict(collections.Counter(str(e.get('errorCode')) for e in out.get('errors',[]) if e['severity']=='warning'))}
  (directory/'meta.json').write_text(json.dumps({'n':n,'controller':bool(ctrl),'gov':gov or '', 'derived':derived,'h':h,**{g:g in groups for g in GROUPS}}))
  if derived:row['Gateway_runtime']=len(artifacts['RegistryGateway']['evm']['deployedBytecode']['object'])//2
  self.rows.append(row);print(label,runtime,modules,controller_runtime,row['Vault_saving_vs_paired'],flush=True)
  return row
 def save(self):
  data={'base_commit':BASE,'compiler':self.compiler,'profile':PROFILE,'tool_sha256':prev.digest(Path(__file__).read_text()),'templates_sha256':prev.digest(Path('tools/tbpros/staticcall-study-templates.py').read_text()),'scope':'No production migration. Current Vault plus calculator-only pressure probes and closed config probes; original unimplemented financial bodies remain reverting. Runtime FAIL means this probe exceeds the unchanged 20480 gate, not a compiler failure. No final-product size claim. Gas uses local fixture/proxy calls, not Pharos receipts.','variants':self.rows}
  DEST.write_text(json.dumps(data,indent=2)+'\n')
  (CACHE/'labels.json').write_text(json.dumps({'labels':[r['variant'] for r in self.rows]}))

def build(fresh):
 study=Study(fresh);base=prev.source_at(BASE);study.compile('A-baseline',base,category='MUST_REMAIN_IN_VAULT')
 for count in [1,2,3,4]:
  src,a,n=variant(base,[],GROUPS,count=count);study.compile(f'binding-{count}-control',src,'A-baseline',[],a,n,reason='Initialization/binding marginal control only; no financial calculator caller.')
 for g in GROUPS:
  for ext in [False,True]:
   label=g+('-static' if ext else '-local');src,assign,n=variant(base,[g],[g] if ext else [])
   study.compile(label,src,g+'-local' if ext else None,[g],assign,n)
 for dto in ['scalar','packed']:
  src,a,n=variant(base,['claim'],['claim'],dto=dto);study.compile('claim-'+dto,src,'claim-local',['claim'],a,n)
 for id in ['version','hash']:
  # Hash pin is a real compiled module runtime hash, not caller supplied evidence.
  a=json.loads((CACHE/'claim-static/Module0.json').read_text())['deployedBytecode']['object']
  expected=subprocess.check_output(['cast','keccak',a],text=True).strip()[2:]
  src,assign,n=variant(base,['claim'],['claim'],identity=id,hashes=[expected]);study.compile('identity-'+id,src,'claim-local',['claim'],assign,n)
 src,a,n=variant(base,GROUPS,[]);study.compile('combined-local',src,groups=GROUPS)
 src,a,n=variant(base,GROUPS,['settlement','claim','mint']);study.compile('M1-one-core-math',src,'combined-local',GROUPS,a,n)
 for count in [1,2,3,4]:
  src,a,n=variant(base,GROUPS,GROUPS,count=count);study.compile('M3-unified' if count==1 else f'M2-{count}-modules',src,'combined-local',GROUPS,a,n)
 for checks in [True,False]:
  src,a,n=variant(base,h=True,extra_h_checks=checks);study.compile('H-static' if checks else 'H-without-output-checks',src,'A-baseline',[],a,n,h=True,category='DIAGNOSTIC_ONLY' if checks else 'SECURITY_REGRESSION_DO_NOT_ADOPT')
 for count in [5,8]:
  for kind in ['local','enum']+(['batch'] if count==8 else []):
   src,a,n=variant(base,gov=kind,gov_count=count);study.compile(f'G{count}-{kind}',src,f'G{count}-local' if kind!='local' else None,gov=kind,category='SAFE_CONTROLLER_ORCHESTRATION')
 src,a,n=variant(base,gov='enum',derived=True);study.compile('G8-derived',src,'G8-local',gov='enum',derived=True,category='SAFE_CONTROLLER_ORCHESTRATION')
 src,a,n=variant(base,GROUPS,[],gov='local');study.compile('C-local-control',src,groups=GROUPS,gov='local')
 src,a,n=variant(base,GROUPS,GROUPS,gov='enum');study.compile('C-module-controller',src,'C-local-control',GROUPS,a,n,gov='enum')
 study.save()

def tests():
 CACHE.mkdir(parents=True,exist_ok=True)
 cfg=f'''[profile.default]
src = "{ROOT}/contracts/tbpros"
test = "{ROOT}/test/tbpros/staticcall-study"
out = "{CACHE}/forge-out"
cache_path = "{CACHE}/forge-cache"
libs = ["{ROOT}/node_modules"]
remappings = ["tbpros/={ROOT}/contracts/tbpros/", "forge-std/={ROOT}/node_modules/forge-std/src/", "@openzeppelin/={ROOT}/node_modules/@openzeppelin/"]
optimizer = true
optimizer_runs = 200
via_ir = false
evm_version = "cancun"
fs_permissions = [{{access="read",path="{CACHE}"}},{{access="read",path="{DEST}"}}]
[profile.default.fuzz]
runs = 256
'''
 (CACHE/'foundry.toml').write_text(cfg)
 subprocess.run(['python3','reference/staticcall_study_model.py','--vectors',str(CACHE/'vectors.bin')],check=True)
 env=dict(os.environ);env.pop('FOUNDRY_PROFILE',None);env['TBPROS_STUDY_ROOT']=str(ROOT)
 result=subprocess.run(['forge','test','--root',str(ROOT),'--config-path',str(CACHE/'foundry.toml'),'--use',os.environ['TBPROS_SOLC'],'--offline','--match-contract','StaticcallStudyTest','-vvvv'],env=env,capture_output=True,text=True)
 (CACHE/'tests.log').write_text(result.stdout+'\n'+result.stderr)
 print('Study Foundry exit',result.returncode,flush=True)
 if result.returncode:raise RuntimeError('Study tests FAIL: '+str(CACHE/'tests.log'))
 data=json.loads(DEST.read_text())
 # Parse only log_named_uint summaries, not duplicate trace emit entries.
 gas=dict(re.findall(r'^  (STUDY/[^:]+): (\d+)\s*$',result.stdout,re.M))
 for row in data['variants']:
  row['gas']={k.removeprefix('STUDY/'+row['variant']+'/'):int(v) for k,v in gas.items() if k.startswith('STUDY/'+row['variant']+'/')}
 data['test_result']={'status':'PASS','summary':re.findall(r'Ran \d+ test suites?.*',result.stdout),'staticcall_trace_lines':sum('[staticcall]' in line and re.search(r'/Module[0-3]::',line) is not None for line in result.stdout.splitlines()),'gas_samples':len(gas),'test_source_sha256':prev.digest(Path('test/tbpros/staticcall-study/StaticcallStudy.t.sol').read_text())}
 data['test_result']['reference_sha256']=prev.digest(Path('reference/staticcall_study_model.py').read_text())
 data['test_result']['reference_cases']=len((CACHE/'vectors.bin').read_bytes())//512
 data['test_result']['vector_sha256']=hashlib.sha256((CACHE/'vectors.bin').read_bytes()).hexdigest()
 assert data['test_result']['staticcall_trace_lines']>0
 DEST.write_text(json.dumps(data,indent=2)+'\n')

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--compile-only',action='store_true');parser.add_argument('--tests-only',action='store_true');parser.add_argument('--fresh',action='store_true');args=parser.parse_args()
 if not args.tests_only:build(args.fresh)
 if not args.compile_only:tests()
