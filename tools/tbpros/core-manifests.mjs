// Generate/assert compiler evidence only. No network, deployment or production parameter selection.
import {readFileSync, writeFileSync, readdirSync, existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import assert from 'node:assert/strict';
import {keccak256, stringToHex, encodeAbiParameters, toFunctionSelector, toEventSelector} from 'viem';

const dir = 'docs/tbpros/verification';
const read = p => JSON.parse(readFileSync(p, 'utf8'));
const save = (name, value) => writeFileSync(`${dir}/${name}`, JSON.stringify(value, null, 2) + '\n');
// V1 is a retained baseline, never silently replace it when regenerating current manifests.
const baseline = (name, value) => { if (!existsSync(`${dir}/${name}`)) save(name, value); };
const walk = d => readdirSync(d, {withFileTypes:true}).flatMap(e => e.isDirectory() ? walk(join(d,e.name)) : [join(d,e.name)]);
const sha = p => createHash('sha256').update(readFileSync(p)).digest('hex');
const find = (base, name) => {
  const found = walk(base).filter(p => p.endsWith(`/${name}.json`));
  assert.equal(found.length, 1, `ambiguous/missing artifact ${name}: ${found}`);
  return read(found[0]);
};
const forgeRoot = 'cache/tbpros-core/out';
const hhRoot = 'cache/tbpros-core/hardhat-artifacts';
const names = ['TbPROSVault','ProsReserve','UpgradeGateway','TbPROSLens'];
const artifacts = Object.fromEntries(names.map(n => [n, find(forgeRoot,n)]));
const type = p => p.type.startsWith('tuple') ? `(${p.components.map(type).join(',')})${p.type.slice(5)}` : p.type;
const signature = a => `${a.name}(${a.inputs.map(type).join(',')})`;
const bytes = code => (code.replace(/^0x/, '').length / 2);
const stripMetadata = code => {
  const s=code.replace(/^0x/,''); const len=parseInt(s.slice(-4),16);
  assert(len>0 && len*2+4<s.length); return s.slice(0,-len*2-4);
};
const economicStub = new Set(['subscribe','checkpointYield','settleMaturedEpochs','claimRedeem','fastRedeem','fundPlan','activatePlan','closePlan','schedulePenaltyPlan','syncSurplus','setPrincipalCap','tightenMintLossBound','setFastFee','setMaxPlanDuration','setBucketConfig']);
const funds = new Set(['subscribe','claimRedeem','fastRedeem','fundPlan','closePlan','fund','consume','withdrawUncommitted']);
const vaultReasons = {
  initialize:['constructor-time once','core/roles/dependencies','bind initial authority, immutable bindings and injected limits'],
  subscribe:['user','R/S/U/B/risk','only V1 USDC entry'],
  safeRequestRedeem:['owner only','queue/position/escrow','non-pausable minimum admission; sole shared request helper'],
  requestRedeem:['owner > owner operator > OZ allowance; delegates require controller=owner','queue/position/escrow/count; allowance only on spender path','same ledger as safe; only ordinary new unique positions limited to 24'],
  syncSolvency:['anyone','F/H/mode','commit objective buffer absorption/incident, no caller loss input'],
  restoreSolvency:['anyone','mode','clear only after actual full backing'],
  checkpointYield:['anyone','H/R/plan cursor','independent current-price realization'],
  settleMaturedEpochs:['anyone','R/P/S/U/B/epoch/queue','bounded Oracle-independent mature progress'],
  claimRedeem:['controller/operator','P/F/position/epoch budget','sole share-based Claim; healthy cumulative delta'],
  fastRedeem:['user','R/F/S/U/B','optional fixed capped fee exit'],
  fundPlan:['Timelock','plan/H','actual future base prefunding'],
  activatePlan:['Timelock','plans/cursor','activate funded terms without overwriting live sources'],
  closePlan:['Timelock','H/F/plans','source-aware final cleanup/refund'],
  schedulePenaltyPlan:['Timelock','F/H/plans','future penalty release; no immediate F->R'],
  syncSurplus:['Timelock','F','bounded classification after restore; never active NAV'],
  setPrincipalCap:['Timelock','C','future cap must stay >= B; no risk credit reset'],
  tightenMintLossBound:['Timelock','policy E01 bound','only decrease or retain bound; no ordinary widening'],
  setFastFee:['Timelock','policy fee','bounded by product hard max; monthly rights unchanged'],
  setMaxPlanDuration:['Timelock','future plan duration','existing active/next terms stay frozen'],
  setBucketConfig:['Timelock','one risk bucket config','materialize old refill; no free credit on increase'],
  setOracle:['Timelock; risk paused','oracle address','replace immutable provider adapter without changing accounting'],
  setYieldRefundReceiver:['Timelock','refund receiver','correct stPROS destination, never reserves'],
  setFoundationReceiver:['Timelock','USDC receiver','Foundation receipt configuration'],
  pause:['Guardian or Timelock','risk pause','explicit emergency exception: tighten risk only'],
  unpause:['Timelock','risk pause','delayed risk reopening'],
  setRequestsPaused:['tighten: Guardian/TL; loosen: TL','request pause','complex requests only; safe unaffected'],
  setOperator:['controller','operator mapping','authorize custom delegated rights'],
  transfer:['holder','OZ balances','bearer transfer, no checkpoint/solvency/backlog'],
  transferFrom:['spender allowance','OZ balances/allowance','ordinary ERC20 delegated bearer transfer'],
  approve:['holder','OZ allowance','ordinary ERC20 allowance'],
  grantRole:['Timelock; GUARDIAN_ROLE only','OZ roles','manage emergency actor; fixed TL root cannot be delegated'],
  revokeRole:['Timelock; GUARDIAN_ROLE only','OZ roles','revoke emergency actor; fixed TL root cannot be removed'],
  renounceRole:['self; GUARDIAN_ROLE only','OZ roles','emergency actor can resign; no root renunciation'],
};
const otherReasons = {
  bind:['Timelock once','binding','bind verified Vault and Gateway-owned dedicated admin; handoff association still requires slot proof'],
  bindVault:['Timelock once','binding','purpose reserve bound to sole Vault'],
  enter:['bound Vault','transient busy','prevent upgrade across external funds frame'],
  leave:['bound Vault','transient busy','release latch on completed funds frame'],
  queueUpgrade:['Timelock','proposal','commit implementation/dataHash/nonce and independent delay floor'],
  cancelUpgrade:['Timelock','proposal','cancel pending exact proposal'],
  executeUpgrade:['Timelock','proposal/upgrading/proxy','only bound ProxyAdmin exact upgrade; no arbitrary target'],
  fund:['anyone using own funds','reserve balance','add WPROS without reviving period'],
  authorizePeriod:['Timelock','period','new nonoverlapping explicit authorization'],
  consume:['bound Vault','spent/reserve balance','fixed recipient Vault and purpose'],
  withdrawUncommitted:['Timelock','reserve balance','only surplus over live allowance to fixed fundingReceiver'],
};
const rows=[];const errors=[];const events=[];const abi={};
for(const [name,a] of Object.entries(artifacts)) {
  abi[name]=a.abi; const seen=new Map();
  for(const item of a.abi.filter(x=>x.type==='function')) {
    const sig=signature(item), selector=toFunctionSelector(sig);
    assert.equal(a.methodIdentifiers[sig],selector.slice(2));
    assert(!seen.has(selector),`function collision ${name} ${sig}`);seen.set(selector,sig);
    const isView=['view','pure'].includes(item.stateMutability);
    const details=(name==='TbPROSVault'?vaultReasons:otherReasons)[item.name] ?? (isView?['anyone','read only','raw authoritative getter / actual inherited interface; Lens aggregates without another writable ledger']:null);
    assert(details,`selector needs manual rationale: ${name}.${sig}`);
    const stub=name==='TbPROSVault'?economicStub.has(item.name):['fund','authorizePeriod','consume','withdrawUncommitted','queueUpgrade','cancelUpgrade','executeUpgrade'].includes(item.name);
    rows.push({contract:name,selector,function:sig,auth:details[0],funds_in_completed_V1:funds.has(item.name),funds_in_skeleton:false,state_area:details[1],v1_reason:details[2],status:stub?'SKELETON_ONLY':(name==='TbPROSVault'&&['safeRequestRedeem','requestRedeem','syncSolvency','restoreSolvency'].includes(item.name)?'IMPLEMENTED':'STRUCTURAL_IMPLEMENTED'),move_to_lens:isView?(name==='TbPROSLens'?'already Lens':'aggregation only; keep raw authority / ERC20 / role queries'):'no: authority/writer boundary',deletable:isView?'review only; no removal in this freeze':'no: current V1 requirement'});
  }
  for(const kind of ['error','event']) {
    const local=new Map();
    for(const item of a.abi.filter(x=>x.type===kind)) {
      const sig=signature(item), id=kind==='event'?toEventSelector(sig):toFunctionSelector(sig);
      assert(!local.has(id)||local.get(id)===sig,`${kind} collision`);local.set(id,sig);
      (kind==='error'?errors:events).push({contract:name,signature:sig,[kind==='event'?'topic0':'selector']:id});
    }
  }
}
for(const collection of [errors,events]) {
 const seen=new Map();for(const e of collection){const id=e.selector??e.topic0;assert(!seen.has(id)||seen.get(id)===e.signature);seen.set(id,e.signature);}
}
// Compile-time interface implementation plus exact selector subset assertion.
for(const [contract,iface] of [['TbPROSVault','ITbPROSVault'],['ProsReserve','IProsReserve'],['UpgradeGateway','IUpgradeGateway']]) {
 for(const f of find(forgeRoot,iface).abi.filter(x=>x.type==='function')) assert(signature(f) in artifacts[contract].methodIdentifiers, `${contract} missing ${signature(f)}`);
}
const bannedNames=['deposit','mint','withdraw','claimWithdraw','claimAll','redeem','adminCatchUp','setInsolvent','clearInsolvent','setLossAmount','resetLossIndex','forceUnlock','sweep','execute','delegateExecute','emergencyWithdraw','claimUnits','recoveryShares','upgradeToAndCall','upgradeTo','proxiableUUID','transferOwnership','renounceOwnership','setRiskConfig'];
const forbiddenSignatures=['deposit(uint256,address)','mint(uint256,address)','withdraw(uint256,address,address)','claimWithdraw(uint256,address,address)','claimAll(address)','redeem(uint256,address,address)','adminCatchUp(uint256)','setInsolvent(bool)','clearInsolvent()','setLossAmount(uint256)','resetLossIndex(uint256)','forceUnlock()','sweep(address,address,uint256)','execute(address,bytes)','delegateExecute(address,bytes)','emergencyWithdraw(address,uint256)','claimUnits(uint256)','recoveryShares(address)','upgradeToAndCall(address,bytes)','upgradeTo(address)','proxiableUUID()','transferOwnership(address)','renounceOwnership()','fundPlan(uint128,uint256,(uint64,uint64))','queueUpgrade(address,bytes32)','setRiskConfig((uint128,uint128,uint16,uint16,uint16,uint64,(uint128,uint128)[2]))'];
for(const name of names) for(const item of abi[name].filter(x=>x.type==='function')) assert(!bannedNames.includes(item.name),`${name} exposes ${item.name}`);
const excluded={scope:names,dependency_exception:'IStPROS.deposit is an external required conversion dependency, never a user Vault entry. OZ Proxy/Admin implicit upgrade surface is separately controlled by Gateway; not inherited by Vault.',banned_names_all_overloads:bannedNames,signatures:forbiddenSignatures.map(s=>({signature:s,selector:toFunctionSelector(s),absent:names.every(n=>!Object.values(artifacts[n].methodIdentifiers).includes(toFunctionSelector(s).slice(2)))}))};
assert(excluded.signatures.every(s=>s.absent));

const budgets={TbPROSVault:[20480,40960,0],ProsReserve:[5120,10240,128],UpgradeGateway:[6144,12288,64],TbPROSLens:[8192,16384,0]};
const sizes=[];const parity=[];
for(const n of names) {
 const a=artifacts[n],h=find(hhRoot,n),[runtimeBudget,initBudget,argsBytes]=budgets[n];
 const runtime=bytes(a.deployedBytecode.object),template=bytes(a.bytecode.object);
 assert(runtime<=runtimeBudget && template+argsBytes<=initBudget,`SIZE BLOCKED ${n}`);
 const runtimeEqual=stripMetadata(a.deployedBytecode.object)===stripMetadata(h.deployedBytecode);
 // Both compilers can use different source names and hence metadata hashes, but no executable differences allowed.
 assert(runtimeEqual,`UNEXPLAINED runtime mismatch ${n}`);
 const ordered = abi => [...abi].sort((x,y)=>(x.type + (x.name??'') + JSON.stringify(x.inputs?.map(type))).localeCompare(y.type + (y.name??'') + JSON.stringify(y.inputs?.map(type))));
 assert.deepEqual(ordered(a.abi),ordered(h.abi),`ABI mismatch ${n}`);
 const creationEqual=stripMetadata(a.bytecode.object)===stripMetadata(h.bytecode);
 assert(creationEqual,`UNEXPLAINED initcode mismatch ${n}`);
 sizes.push({contract:n,runtime_bytes:runtime,runtime_budget:runtimeBudget,headroom:runtimeBudget-runtime,creation_template_bytes:template,constructor_encoding_bytes:argsBytes,initcode_with_constructor_bytes:template+argsBytes,initcode_budget:initBudget,status:'BASELINE_PASS_ONLY'});
 parity.push({contract:n,abi_equal:true,runtime_equal_without_metadata:runtimeEqual,initcode_equal_without_metadata:creationEqual,full_bytecode_equal:a.deployedBytecode.object===h.deployedBytecode,note:'Foundry source-unit names/remappings differ from Hardhat resolved .pnpm names; metadata hashes differ. Executable code must match after CBOR removal.'});
}

const layout=find(forgeRoot,'CoreLayoutIntrospection').storageLayout;
const namespace=(s)=>(BigInt(keccak256(encodeAbiParameters([{type:'uint256'}],[BigInt(keccak256(stringToHex(s)))-1n])))&~255n).toString(16).padStart(64,'0');
const roots=[['core','faroo.tbpros.storage.Core'],['erc20','openzeppelin.storage.ERC20'],['accessControl','openzeppelin.storage.AccessControl'],['initializable','openzeppelin.storage.Initializable']];
const namespaces=roots.map(([field,id])=>({namespace:id,slot:`0x${namespace(id)}`,type:layout.storage.find(s=>s.label===field).type}));
assert.equal(namespaces[0].slot,'0x7def806360c36a43f97881f41b9e336dc21f4bcdb6a0635f38229e4d0cd22100');
const mode=Object.values(layout.types).find(t=>t.label==='struct TbPROSStorage.Mode');
assert.equal(mode.numberOfBytes,'32');assert.deepEqual(mode.members.map(m=>[m.label,m.slot,m.offset]),[['insolvent','0',0],['incidentId','0',1],['enteredAt','0',17]]);
assert.equal(artifacts.TbPROSVault.storageLayout.storage.length,0,'namespaced Vault must not have ordinary persistent variables');
const storage={schema:'V1 candidate baseline, not an upgrade-compatibility proof',namespaces,types:layout.types,ordinary_storage:Object.fromEntries(names.map(n=>[n,artifacts[n].storageLayout])),materialization:'Compiler harness uses the actual imported production/OZ struct types. Its ordinary root slots are NOT production namespace locations; only compiler member offsets/types/array strides are used.',transient:{vault_local:'OZ ReentrancyGuardTransient namespace; no initializer or persistent status',gateway_busy:keccak256(stringToHex('faroo.tbpros.gateway.busy')),gateway_upgrading:keccak256(stringToHex('faroo.tbpros.gateway.upgrading'))},mode_packing_verified:true};

const nodeNames=new Map();const definitions=[];
for(const file of walk(forgeRoot).filter(p=>p.endsWith('.json')&&!p.includes('/build-info/'))) {
 const a=read(file);for(const node of a.ast?.nodes??[])if(node.nodeType==='ContractDefinition'){nodeNames.set(node.id,node.name);definitions.push(node);}
}
const inheritance=Object.fromEntries(names.map(n=>{const node=definitions.find(d=>d.name===n);assert(node);return [n,{direct:node.baseContracts.map(b=>b.baseName.name??nodeNames.get(b.baseName.referencedDeclaration)),linearized:node.linearizedBaseContracts.map(id=>nodeNames.get(id))}]}));
assert(inheritance.TbPROSVault.linearized.every(Boolean));
const sourceFiles=new Set(walk('contracts/tbpros').filter(p=>p.endsWith('.sol')));
for(const a of Object.values(artifacts)) for(const p of Object.keys(a.metadata.sources)) {assert(existsSync(p));sourceFiles.add(p);}
for(const p of ['foundry.toml','hardhat.tbpros.config.ts','pnpm-lock.yaml','test/tbpros/core-skeleton/CoreSkeleton.t.sol','reference/tbpros/calendar-fixtures.json'])sourceFiles.add(p);
for(const p of [...walk('test/tbpros/core-skeleton'),...walk('tools/tbpros')].filter(p=>!p.includes('__pycache__') && /\.(sol|py|mjs|sh)$/.test(p))) sourceFiles.add(p);
sourceFiles.add('reference/hardening_schema_model.py');sourceFiles.add('reference/request_accounting_model.py');sourceFiles.add('reference/solvency_production_model.py');sourceFiles.add('.github/workflows/tbpros-skeleton.yml');
const sources=Object.fromEntries([...sourceFiles].sort().map(p=>[p,sha(p)]));
const profile={compiler:artifacts.TbPROSVault.metadata.compiler.version,openzeppelin:read('node_modules/@openzeppelin/contracts/package.json').version,openzeppelin_upgradeable:read('node_modules/@openzeppelin/contracts-upgradeable/package.json').version,optimizer:{enabled:true,runs:200},viaIR:false,evmVersion:'cancun',source_sha256:sources};
assert.equal(profile.openzeppelin,'5.6.1');assert.equal(profile.openzeppelin_upgradeable,'5.6.1');assert(profile.compiler.startsWith('0.8.28+commit.7893614a'));
for(const a of Object.values(artifacts)) {assert.deepEqual(a.metadata.settings.optimizer,profile.optimizer);assert.equal(a.metadata.settings.evmVersion,'cancun');assert.equal(a.metadata.settings.viaIR??false,false);}
// Enum ordering changes storage meaning even when the underlying uint8 layout is unchanged.
const enums={};
for(const contract of ['TbPROSStorage','TbPROSTypes','IProsReserve']) {
 const a=find(forgeRoot,contract);
 for(const def of a.ast.nodes.filter(n=>n.nodeType==='ContractDefinition' && n.name===contract))
  for(const item of def.nodes.filter(n=>n.nodeType==='EnumDefinition')) enums[`${contract}.${item.name}`]=item.members.map(m=>m.name);
}
storage.enum_definitions=enums;
save('core-abi.json',{profile,contracts:abi,selectors:rows,errors,events,inheritance,collisions:[]});
baseline('abi-v1.json',{profile,contracts:abi});
save('core-storage-layout.json',{profile,...storage});baseline('storage-layout-v1.json',{profile,...storage});
save('excluded-selectors.json',excluded);save('core-bytecode.json',{profile,sizes,parity,oracle_adapter:'DEFERRED_INTERFACE_ONLY',vault_pressure:'HIGH: hardened skeleton still excludes all business implementation; remaining budget is not a full-size prediction'});
writeFileSync(`${dir}/core-selector-inventory.md`,'# Compiler selector inventory\n\nGenerated by tools/tbpros/core-manifests.mjs. Funds column is intended completed V1 behavior; skeleton has no funds transfer.\n\n| Selector | Function | Contract | Auth | Funds? | State Area | V1 Reason | Status |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n'+rows.map(r=>`| ${r.selector} | \`${r.function}\` | ${r.contract} | ${r.auth} | ${r.funds_in_completed_V1?'yes':'no'} | ${r.state_area} | ${r.v1_reason} | ${r.status} |`).join('\n')+'\n');
console.log(JSON.stringify({functions:rows.length,vaultFunctions:rows.filter(r=>r.contract==='TbPROSVault').length,errors:errors.length,events:events.length,sizes,parity,modeBytes:32},null,2));
