// Read-only RPC + local fork. No private key, signing, sendTransaction or broadcast.
// Run from repository root; dotenv resolves the existing root .env.
import 'dotenv/config';
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';

const url = process.env.PHAROS_MAINNET_RPC_URL;
if (!url) throw new Error('PHAROS_MAINNET_RPC_URL is required');
const block = '0x10c96dd';
const expectedHash = '0x9ff5b9730b664be2066d0a7ae5a9481caf2f4efaa4c9e34644155c102266154d';
const st = '0x6b0a44c64190279f7034b77c13a566e914fe5ec4';
const probe = '0x000000000000000000000000000000000000f001';
const dir = 'docs/tbpros/verification/';
async function rpc(method, params) {
  const response = await fetch(url, {method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify({jsonrpc: '2.0', id: 1, method, params})});
  const j = await response.json();
  return j.error ? {error: j.error.code, message: String(j.error.message).replaceAll(url, '[REDACTED_RPC]')} : j.result;
}
try {
  const b = await rpc('eth_getBlockByNumber', [block, false]);
  const chainId = await rpc('eth_chainId', []);
  if (b.hash !== expectedHash || chainId !== '0x688') throw new Error('Fixed chain/block identity mismatch');
  const out = {block: {number: b.number, hash: b.hash, timestamp: b.timestamp}, chainId,
    stPROS: st, stateOverride: {}, getters: {}, production_slp_integration_verified: false};
  for (const [name, code] of Object.entries({control: '0x60425f5260205ff3', transient: '0x60425f5d5f5c5f5260205ff3', fresh: '0x5f5c5f5260205ff3'})) {
    out.stateOverride[name] = await rpc('eth_call', [{to: probe, data: '0x'}, block, {[probe]: {code}}]);
  }
  const expected42 = '0x' + '42'.padStart(64, '0');
  if (out.stateOverride.control !== expected42 || out.stateOverride.transient !== expected42 ||
      out.stateOverride.fresh !== '0x' + '0'.repeat(64)) throw new Error('Native EIP-1153 probe failed');
  out.creationControl = await rpc('eth_call', [{data: '0x60425f5260205ff3'}, block]);
  for (const [name, selector] of Object.entries({asset: '0x38d52e0f', slp: '0x02824acc', oracle: '0x7dc0d1d0', paused: '0x5c975abb'})) {
    const raw = await rpc('eth_call', [{to: st, data: selector}, block]);
    out.getters[name] = typeof raw === 'string' ? (name === 'paused' ? BigInt(raw) !== 0n : '0x' + raw.slice(-40)) : raw;
  }
  out.implementation = await rpc('eth_getStorageAt', [st,
    '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc', block]);
  for (const [name, address] of Object.entries({stPROS: st, ...out.getters})) {
    if (typeof address === 'string' && /^0x[0-9a-f]{40}$/i.test(address)) {
      const code = await rpc('eth_getCode', [address, block]);
      out[name + 'CodeBytes'] = typeof code === 'string' ? (code.length - 2) / 2 : code;
    }
  }
  fs.writeFileSync(dir + 'pharos-rpc.json', JSON.stringify(out, null, 2) + '\n');
  const compiler = process.env.TBPROS_SOLC_PATH || '/Users/wangningbo/Library/Caches/hardhat-nodejs/compilers-v3/macosx-amd64/solc-macosx-amd64-v0.8.28+commit.7893614a';
  const r = spawnSync('forge', ['test', '--root', 'test/tbpros/pharos-fork', '--match-contract',
    'PharosDependenciesTest', '--use', compiler, '--offline', '-vv'], {env: process.env, encoding: 'utf8', maxBuffer: 8*1024*1024});
  const output = ((r.stdout || '') + (r.stderr || '')).replaceAll(url, '[REDACTED_RPC]');
  fs.writeFileSync(dir + 'pharos-fork-output.txt', output);
  console.log(output);
  console.log('Native EIP-1153: PASS. Target production SLP integration: BLOCKED (old fixed-block implementation).');
  process.exitCode = r.status ?? 1;
} catch (e) {
  console.error('Read-only verification failed: ' + String(e.message).replaceAll(url, '[REDACTED_RPC]'));
  process.exitCode = 1;
}
