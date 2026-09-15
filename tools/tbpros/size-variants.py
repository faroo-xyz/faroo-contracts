"""Reproducible isolated compiler variants; never deploy these diagnostic sources."""
import json, os, re, subprocess, hashlib, posixpath
from pathlib import Path
BASE='6c9d407fa45c96e24c2928f0cf6fc5dd8e9fd2c6'
SOLC=os.environ['TBPROS_SOLC']
V='contracts/tbpros/TbPROSVault.sol'
I='contracts/tbpros/interfaces/ITbPROSVault.sol'
S='contracts/tbpros/TbPROSStorage.sol'
def remove_function(s, name):
    m=re.search(r'    function '+name+r'\(',s)
    if not m:return s
    a=m.start(); op=s.find('{',a); semi=s.find(';',a)
    if semi<op or op<0:return s[:a]+s[semi+1:]
    depth=1;b=op+1
    while depth:
        depth+=(s[b]=='{')-(s[b]=='}');b+=1
    return s[:a]+s[b:]
def struct_fields(s,kind):
    body=re.search(r'    struct '+kind+r' \{(.*?)\n    \}',s,re.S)[1]
    return re.findall(r'^        ([\w\[\]]+) (\w+);',body,re.M)
def decouple(src):
    src=dict(src)
    src['contracts/tbpros/TbPROSTypes.sol']=src[S].replace('library TbPROSStorage','library TbPROSTypes').split('    /// @custom:storage-location')[0]+'}\n'
    src[I]=src[I].replace('TbPROSStorage as S','TbPROSTypes as S').replace('../TbPROSStorage.sol','../TbPROSTypes.sol')
    v=src[V].replace('import {TbPROSStorage as S}', 'import {TbPROSTypes as T} from "./TbPROSTypes.sol";\nimport {TbPROSStorage as S}')
    for k in ['InitConfig','RiskConfig','PlanTerms']:v=v.replace('S.'+k,'T.'+k)
    v=v.replace('S.Dependencies calldata','T.Dependencies calldata')
    fields=struct_fields(src[S],'Dependencies')
    v=v.replace('s.dependencies = d;', 's.dependencies = S.Dependencies('+','.join('d.'+f for _,f in fields)+');')
    for name,kind,expr in [('dependencies','Dependencies','S.layout().dependencies'),('accounting','Accounting','S.layout().accounting'),('mode','Mode','S.layout().mode'),('policy','Policy','S.layout().policy'),('epoch','Epoch','S.layout().epochs[dueAt]'),('position','Position','S.layout().positions[controller][dueAt]'),('riskBucket','Bucket','S.layout().riskBuckets[slot]'),('plan','Plan','S.layout().plans[slot]')]:
        v=v.replace('returns (S.'+kind+' memory)', 'returns (T.'+kind+' memory)')
        if name=='plan':
            body='S.Plan storage p = '+expr+'; T.Plan memory out;\n'
            for typ,f in struct_fields(src[S],kind):
                if f=='sources':
                    body+='for(uint256 i;i<2;++i){out.sources[i]=T.Source('+','.join('p.sources[i].'+x for _,x in struct_fields(src[S],'Source'))+');}\n'
                else:body+='out.'+f+' = '+('T.PlanStatus(uint8(p.status))' if f=='status' else 'p.'+f)+';\n'
            body+='return out;'
        else:
            body='S.'+kind+' storage p = '+expr+'; return T.'+kind+'('+','.join('T.EpochStatus(uint8(p.status))' if kind=='Epoch' and f=='status' else 'p.'+f for _,f in struct_fields(src[S],kind))+');'
        v=v.replace('return '+expr+';',body)
    src[V]=v
    for p in ['contracts/tbpros/lens/TbPROSLens.sol']:
        src[p]=src[p].replace('TbPROSStorage','TbPROSTypes')
    return src

def narrow(src):
    src=dict(src)
    for n in ['dependencies','plan','policy','riskBucket']:
        src[V]=remove_function(src[V],n);src[I]=remove_function(src[I],n)
    src[V]=src[V].replace('\n    function accounting()', '''
    function governanceBinding() external view returns(address timelock, address gateway) {
        return (S.layout().dependencies.timelock,S.layout().dependencies.gateway);
    }
    function sourceRemaining(uint8 planSlot, uint8 sourceSlot) external view returns(uint128) {
        if(planSlot>1 || sourceSlot>1) revert InvalidPlan();
        return S.layout().plans[planSlot].sources[sourceSlot].remaining;
    }
    function pauseState() external view returns(bool riskPaused, bool requestsPaused) {
        return (S.layout().policy.riskPaused,S.layout().policy.requestsPaused);
    }
    function accounting()''')
    src[I]=src[I].replace('    function accounting()', '    function governanceBinding() external view returns(address timelock, address gateway);\n    function sourceRemaining(uint8 planSlot,uint8 sourceSlot) external view returns(uint128);\n    function pauseState() external view returns(bool riskPaused,bool requestsPaused);\n    function accounting()')
    g='contracts/tbpros/governance/UpgradeGateway.sol'
    src[g]=re.sub(r'        if \(\n            ITbPROSVault\(v\).dependencies\(\).*?\) revert InvalidBinding\(\);', '        (address tl,address gateway)=ITbPROSVault(v).governanceBinding();\n        if(tl!=timelock || gateway!=address(this)) revert InvalidBinding();',src[g],flags=re.S)
    l='contracts/tbpros/lens/TbPROSLens.sol'
    src[l]=re.sub(r'            S.Plan memory p = vault.plan\(i\);\n            obligations \+= .*?;', '            obligations += uint256(vault.sourceRemaining(i,0)) + vault.sourceRemaining(i,1);',src[l])
    return src

def compile_variant(label, src, note):
    sources=dict(src);queue=list(src)
    while queue:
        p=queue.pop()
        for imp in re.findall(r'import[^;]*?["\']([^"\']+)["\'];',sources[p]):
            key=posixpath.normpath(posixpath.join(posixpath.dirname(p),imp)) if imp.startswith('.') else imp
            if key not in sources:
                path=Path('node_modules')/key if key.startswith('@') else Path(key)
                sources[key]=path.read_text();queue.append(key)
    inp={'language':'Solidity','sources':{k:{'content':v} for k,v in sources.items()},'settings':{'optimizer':{'enabled':True,'runs':200},'viaIR':False,'evmVersion':'cancun','outputSelection':{'*':{'*':['evm.deployedBytecode.object','evm.bytecode.object','abi','storageLayout']}}}}
    d=Path('cache/tbpros-hardening')/label;d.mkdir(parents=True,exist_ok=True)
    encoded=json.dumps(inp);(d/'input.json').write_text(encoded)
    result=subprocess.run([SOLC,'--standard-json'],input=encoded,text=True,capture_output=True,check=True)
    out=json.loads(result.stdout)
    errors=[x for x in out.get('errors',[]) if x['severity']=='error']
    if errors:raise RuntimeError(label+'\n'+'\n'.join(x['formattedMessage'] for x in errors))
    (d/'output.json').write_text(result.stdout)
    c=out['contracts'][V]['TbPROSVault']
    row={'variant':label,'runtime_bytes':len(c['evm']['deployedBytecode']['object'])//2,'creation_template_bytes':len(c['evm']['bytecode']['object'])//2,'input_sha256':hashlib.sha256(encoded.encode()).hexdigest(),'note':note}
    print(json.dumps(row),flush=True);return row

def main():
    files=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'contracts/tbpros'],text=True).splitlines()
    base={p:subprocess.check_output(['git','show',BASE+':'+p],text=True) for p in files if p.endswith('.sol')}
    rows=[compile_variant('A-baseline',base,'Exact committed production sources')]
    b=dict(base);v=b[V]
    v=v.replace('AccessControlUpgradeable, ','').replace('        __AccessControl_init();','').replace('        _grantRole(DEFAULT_ADMIN_ROLE, d.timelock);','').replace('        _grantRole(GUARDIAN_ROLE, config.guardian);','        guardians[config.guardian] = true;')
    v=v.replace('    uint256 public constant APR_BPS', '    mapping(address => bool) public guardians;\n    uint256 public constant APR_BPS')
    v=v.replace('hasRole(GUARDIAN_ROLE, msg.sender)','guardians[msg.sender]')
    for n in ['grantRole','revokeRole','renounceRole']:v=remove_function(v,n)
    v=v.replace('    function asset()', '''    function setGuardian(address account,bool enabled) external nonReentrant onlyTimelock {
        if(account==address(0)) revert InvalidAddress(); guardians[account]=enabled;
    }
    function resignGuardian() external nonReentrant { guardians[msg.sender]=false; }
    function asset()''')
    b[V]=v;rows.append(compile_variant('B-minimal-guardian',b,'Diagnostic only: removes OZ role/165 ABI and uses ordinary mapping; not storage-compatible or recommended'))
    rows.append(compile_variant('C-narrow-getters',narrow(base),'Remove four full getters; add narrow governanceBinding/sourceRemaining/pauseState; update consumers'))
    rows.append(compile_variant('D-types',decouple(base),'Identical wire shapes with explicit storage-to-DTO copies; no storage reinterpretation'))
    e=dict(base)
    for n in ['setRiskConfig']:e[V]=remove_function(e[V],n);e[I]=remove_function(e[I],n)
    rows.append(compile_variant('E1-without-risk-setter',e,'Marginal dispatcher plus tuple decoder plus stub; not decoder-only'))
    e=dict(base)
    e[V]=re.sub(r'    function initialize\(.*?\n    function _validateReserve', '    function initialize(bytes calldata) external initializer nonReentrant { revert SkeletonOnly(); }\n\n    function _validateReserve',e[V],flags=re.S)
    e[I]=e[I].replace('initialize(S.InitConfig calldata config)','initialize(bytes calldata config)')
    rows.append(compile_variant('E2-initializer-stub-control',e,'NON-EQUIVALENT diagnostic: removes initialization validation/writes as well as tuple decode; never an optimization candidate'))
    # Paired isolated decoder: same revert body and dispatcher, differing only input schema.
    e=dict(base)
    e[V]=re.sub(r'    function initialize\(.*?\n    function _validateReserve', '    function initialize(S.InitConfig calldata) external initializer nonReentrant { revert SkeletonOnly(); }\n\n    function _validateReserve',e[V],flags=re.S)
    rows.append(compile_variant('E3-tuple-initializer-stub-control',e,'Paired with E2: identical reverting initializer, measures validated tuple input marginal cost, not full initialization cost'))
    # Actual initializing control: preserve validation/writes but move decoding to an opaque bytes payload.
    e=dict(base)
    e[V]=e[V].replace('function initialize(S.InitConfig calldata config)', 'function initialize(bytes calldata encoded)')
    e[V]=e[V].replace('        S.Dependencies calldata d = config.dependencies;', '        S.InitConfig memory config = abi.decode(encoded,(S.InitConfig));\n        S.Dependencies memory d = config.dependencies;')
    e[V]=e[V].replace('S.Dependencies calldata d)', 'S.Dependencies memory d)').replace('S.RiskConfig calldata r)', 'S.RiskConfig memory r)')
    e[I]=e[I].replace('initialize(S.InitConfig calldata config)', 'initialize(bytes calldata encoded)')
    rows.append(compile_variant('E4-opaque-initializer-real-validation',e,'Real initialization preserved, but bytes+abi.decode to memory changes ABI/decoding strategy; diagnostic only, not adopted'))
    final={str(p):p.read_text() for p in Path('contracts/tbpros').rglob('*.sol')}
    rows.append(compile_variant('F-combined-safe',final,'Adopted final skeleton: narrow getters + DTO + initial-only YEAR + frozen plan terms + narrow config setters + proposal expiry; guards/OZ retained'))
    for r in rows:r['delta_vs_baseline']=r['runtime_bytes']-rows[0]['runtime_bytes']
    assert rows[0]['runtime_bytes']==15462
    Path('docs/tbpros/verification/hardening-size-variants.json').write_text(json.dumps({'base_commit':BASE,'compiler':subprocess.check_output([SOLC,'--version'],text=True).strip(),'settings':{'optimizer':200,'viaIR':False,'evmVersion':'cancun'},'variants':rows},indent=2)+'\n')
if __name__=='__main__':main()
