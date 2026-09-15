"""Negative controls for the automated guard, with all mutations restored in finally blocks."""
import json,subprocess
from pathlib import Path
root=Path('docs/tbpros/verification')
results=[]
def reject(label,path,mutate,command,needle):
    before=path.read_bytes()
    try:
        value=json.loads(before);mutate(value);path.write_text(json.dumps(value))
        result=subprocess.run(command,capture_output=True,text=True)
        assert result.returncode!=0 and needle in result.stderr,(label,result.stdout,result.stderr)
        results.append({'negative_control':label,'rejected':True})
    finally:path.write_bytes(before)

g=['python3','tools/tbpros/hardening-guards.py']
reject('ABI drift',root/'core-abi.json',lambda j:j['contracts']['TbPROSVault'].append({'type':'function','name':'unexpectedView','inputs':[],'outputs':[],'stateMutability':'view'}),g,'abi drift')
reject('storage offset drift',root/'core-storage-layout.json',lambda j:j['namespaces'][0].update(slot='0x'+'00'*32),g,'storage drift')
reject('runtime exceeds 20480',root/'core-bytecode.json',lambda j:j['sizes'][0].update(runtime_bytes=20481),g,'AssertionError')
a=Path('cache/tbpros-core/out/TbPROSVault.sol/TbPROSVault.json')
def banned(j):
    j['abi'].append({'type':'function','name':'deposit','inputs':[],'outputs':[],'stateMutability':'view'})
    # keccak256('deposit()')[0:4]; computed by the same installed viem utility as the generator.
    selector=subprocess.check_output(['node','--input-type=module','-e',"import {toFunctionSelector} from 'viem'; console.log(toFunctionSelector('deposit()').slice(2))"],text=True).strip()
    j['methodIdentifiers']['deposit()']=selector
reject('forbidden selector',a,banned,['node','tools/tbpros/core-manifests.mjs'],'exposes deposit')
def missing_doc(j):
    for n in j['ast']['nodes']:
        if n.get('name')=='TbPROSVault':
            for f in n.get('nodes',[]):
                if f.get('name')=='initialize':f['documentation']['text']='';return
    raise AssertionError('initialize AST missing')
reject('missing NatSpec',a,missing_doc,g,'NatSpec')
subprocess.run(g,check=True,capture_output=True)
(root/'hardening-guard-negative-controls.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results))
