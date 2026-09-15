"""Fail-closed ABI/storage/size/NatSpec review guard. --update explicitly records reviewed snapshots."""
import json,re,sys,hashlib
from pathlib import Path
root=Path('docs/tbpros/verification')
read=lambda p:json.loads(p.read_text())

def normalize(value):
    # Compiler declaration IDs and provenance hashes are not storage locations or ABI semantics.
    if isinstance(value,dict):
        return {re.sub(r'\)\d+',')',k):normalize(v) for k,v in sorted(value.items()) if k not in ('astId','contract','profile')}
    if isinstance(value,list):return [normalize(v) for v in value]
    if isinstance(value,str):return re.sub(r'\)\d+',')',value)
    return value

abi=read(root/'core-abi.json')
layout=read(root/'core-storage-layout.json')
sizes=read(root/'core-bytecode.json')
wire={k:sorted(v,key=lambda x:json.dumps(x,sort_keys=True)) for k,v in abi['contracts'].items()}
current={'abi':normalize(wire),'storage':normalize({k:layout[k] for k in ['namespaces','types','ordinary_storage','transient','field_semantics','enum_definitions']})}
# Immutable baseline must keep its original byte-for-byte evidence.
for f in ['abi-v1.json','storage-layout-v1.json']:
    import subprocess
    old=subprocess.check_output(['git','show','6c9d407fa45c96e24c2928f0cf6fc5dd8e9fd2c6:docs/tbpros/verification/'+f])
    assert old==(root/f).read_bytes(),f+' historical baseline overwritten'
for kind,value in current.items():
    path=root/('storage-v20.json' if kind=='storage' else 'abi-v18.json')
    if '--update' not in sys.argv:assert read(path)==value,kind+' drift: review and explicitly regenerate snapshot; never auto-accept in CI'

# Document 19 approves only annotation changes; all physical schema and enums must still equal V18.
import copy
reviewed=copy.deepcopy(read(root/'storage-v18.json'))
for row in reviewed['field_semantics']:
    if row['field']=='Layout.openPositionCount':row['meaning']='all live unique Positions; only ordinary new-position admission requires count < 24; safe never uses an admission limit'
    if row['field'].startswith('Epoch.'):row['writer']='Vault shared request helper implemented; settle/claim helpers remain stub'
    if row['field'].startswith('Position.'):row['writer']='Vault shared request helper implemented; claim helper remains stub'
assert read(root/'storage-v19.json')==reviewed,'V19 may change only the explicitly approved request annotations'

# V20 changes only the implementation-status annotations for Mode and Source writers.
reviewed20=copy.deepcopy(reviewed)
for row in reviewed20['field_semantics']:
    if row['field'].startswith('Mode.'):row['writer']='Vault sync/restore implemented; objective incident metadata only'
    if row['field'].startswith('Source.'):row['writer']='Vault sync loss writer implemented; plan/checkpoint/close helpers remain stub'
assert read(root/'storage-v20.json')==reviewed20,'V20 may change only reviewed Mode/Source writer annotations'

# Physical placement comparison. This is deliberately NOT a semantic migration approval.
old=read(root/'storage-layout-v1.json')
def structs(j):return {v['label']:v for v in j['types'].values() if 'members' in v}
old_structs,new_structs=structs(old),structs(layout)
for name,o in old_structs.items():
    n=new_structs[name];new_fields={m['label']:m for m in n['members']}
    for field in o['members']:
        other=new_fields[field['label']]
        assert (field['slot'],field['offset'])==(other['slot'],other['offset']),(name,field['label'],'moved')
        ot=old['types'][field['type']];nt=layout['types'][other['type']]
        assert (ot['label'],ot['numberOfBytes'])==(nt['label'],nt['numberOfBytes']),(name,field['label'],'type or stride changed')
    if not name.endswith('.Layout'):assert o['numberOfBytes']==n['numberOfBytes'],name+' stride changed'
p=new_structs['struct TbPROSStorage.Plan'];cap=next(m for m in p['members'] if m['label']=='fundingUCap')
assert (cap['slot'],cap['offset'],p['numberOfBytes'])==('1',9,'224')
year=next(m for m in new_structs['struct TbPROSStorage.Layout']['members'] if m['label']=='yearSeconds')
assert (year['slot'],year['offset'])==('39',0)
for row in sizes['sizes']:
    assert row['runtime_bytes']<=row['runtime_budget']
    assert row['initcode_with_constructor_bytes']<=row['initcode_budget']
    assert row['runtime_bytes']<=24576
assert not any(x['name'] in {'asset','dependencies','plan','policy','riskBucket','setRiskConfig'} for x in wire['TbPROSVault'] if x['type']=='function')
assert 'TbPROSStorage' not in Path('contracts/tbpros/interfaces/ITbPROSVault.sol').read_text()

# AST checks use compiler-attached documentation, avoiding nearby-comment false positives.
# Enforce the permanent documentation rule for every production file changed since the user's base.
modified=set()
for production in Path('contracts/tbpros').rglob('*.sol'):
    previous=subprocess.run(['git','show','6c9d407fa45c96e24c2928f0cf6fc5dd8e9fd2c6:'+str(production)],capture_output=True)
    if previous.returncode or previous.stdout!=production.read_bytes():modified.add(str(production))
count=0
for f in Path('cache/tbpros-core/out').rglob('*.json'):
    if '/build-info/' in str(f):continue
    a=read(f);ast=a.get('ast',{});path=ast.get('absolutePath','')
    if not path.startswith('contracts/tbpros/') or path not in modified:continue
    text=Path(path).read_text()
    assert not re.search(r'[\u3400-\u9fff]',text),path+' non-English production text'
    def walk(node):
        global count
        if isinstance(node,dict):
            typ=node.get('nodeType');doc=node.get('documentation',{});doc=doc.get('text','') if isinstance(doc,dict) else (doc or '')
            if typ=='FunctionDefinition':
                if node['visibility'] in ('external','public'):
                    assert '@notice' in doc and '@dev' in doc,(path,node['name'],'NatSpec')
                    for p in node['parameters']['parameters']:
                        assert '@param '+p['name']+' ' in doc,(path,node['name'],p['name'])
                    assert doc.count('@return')>=len(node['returnParameters']['parameters']),(path,node['name'],'returns')
                else:assert '@dev' in doc,(path,node['name'],'helper intent')
                count+=1
            if typ in ('StructDefinition','EnumDefinition','ModifierDefinition','ErrorDefinition'):
                assert '@dev' in doc,(path,node.get('name'),'missing meaning')
            if typ=='StructDefinition':
                for m in node['members']:
                    # solc omits struct-member documentation from AST; anchor to compiler byte offset.
                    start=int(m['src'].split(':')[0])
                    prefix=text.encode()[:start].decode().rstrip()
                    assert prefix.splitlines()[-1].lstrip().startswith('/// @dev '),(path,node['name'],m['name'],'field documentation')
            if typ=='EventDefinition':
                assert '@notice' in doc,(path,node['name'],'event semantics')
                for p in node['parameters']['parameters']:assert '@param '+p['name']+' ' in doc,(path,node['name'],p['name'])
            for k,v in node.items():
                if k!='documentation':walk(v)
        elif isinstance(node,list):
            for v in node:walk(v)
    walk(ast)
if '--update' in sys.argv:
    for kind,value in current.items():(root/('storage-v20.json' if kind=='storage' else 'abi-v18.json')).write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
print(json.dumps({'status':'PASS','documented_function_ast_occurrences':count,'old_field_placements':'preserved','plan_stride_bytes':224,'fundingUCap':'relative 1:9','YEAR':'relative 39:0','semantic_migration':'NOT VERIFIED: legacy Ucap and zero new fields require explicit migration if old proxies ever existed'}))
