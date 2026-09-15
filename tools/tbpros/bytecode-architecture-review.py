"""Compile isolated architecture diagnostics. Never deploy or adopt generated sources.

Run from repository root with TBPROS_SOLC set to the exact native 0.8.28 binary.
Inputs/outputs remain in ignored cache. Evidence is regenerated, not a size gate.
No production source, ABI baseline, storage baseline or compiler profile is edited.
"""
import hashlib
import json
import os
import posixpath
import re
import subprocess
from pathlib import Path

BASE = '31a2648d535f70311320e9cbd324ef32bb4f9cc0'
V = 'contracts/tbpros/TbPROSVault.sol'
I = 'contracts/tbpros/interfaces/ITbPROSVault.sol'
S = 'contracts/tbpros/TbPROSStorage.sol'
ERC20 = '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol'
CACHE = Path('cache/tbpros-bytecode-review')
DEST = Path('docs/tbpros/verification/bytecode-architecture-variants.json')
PROFILE = {'optimizer': {'enabled': True, 'runs': 200}, 'viaIR': False, 'evmVersion': 'cancun'}
STUBS = ['subscribe', 'fastRedeem', 'claimRedeem', 'checkpointYield', 'settleMaturedEpochs',
         'fundPlan', 'activatePlan', 'closePlan', 'schedulePenaltyPlan', 'syncSurplus',
         'setPrincipalCap', 'tightenMintLossBound', 'setFastFee', 'setMaxPlanDuration', 'setBucketConfig']
GETTERS = ['YEAR', 'backingAsset', 'governanceBinding', 'sourceRemaining', 'pauseState',
           'accounting', 'mode', 'epoch', 'position', 'queueState', 'openPositionCount', 'nextPlanId', 'isOperator']


def digest(x):
    return hashlib.sha256(x.encode()).hexdigest()


def encode(x):
    return json.dumps(x, sort_keys=True, separators=(',', ':'))


def source_at(rev):
    files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', rev, 'contracts/tbpros'], text=True).splitlines()
    return {p: subprocess.check_output(['git', 'show', rev + ':' + p], text=True) for p in files if p.endswith('.sol')}


def span(source, name):
    match = re.search(r'    function ' + name + r'\(', source)
    if match is None:
        raise ValueError('Missing function: ' + name)
    start = match.start()
    op, semi = source.find('{', start), source.find(';', start)
    if semi < op or op < 0:
        return start, semi + 1
    depth, end = 1, op + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return start, end


def replace_function(source, name, replacement=''):
    a, b = span(source, name)
    return source[:a] + replacement + source[b:]


def remove(src, names):
    src = dict(src)
    for name in names:
        src[V] = replace_function(src[V], name)
        src[I] = replace_function(src[I], name)
    return src


def insert(src, code):
    src = dict(src)
    marker = '    /// @notice OZ role for emergency pause tightening only; Timelock appoints/revokes.'
    assert marker in src[V]
    src[V] = src[V].replace(marker, code + '\n' + marker, 1)
    return src


def closure(src, roots):
    result, queue = {}, list(roots)
    while queue:
        path = queue.pop()
        if path in result:
            continue
        content = src.get(path)
        if content is None:
            content = (Path('node_modules') / path if path.startswith('@') else Path(path)).read_text()
        result[path] = content
        for imp in re.findall(r'import[^;]*?["\']([^"\']+)["\'];', content):
            queue.append(posixpath.normpath(posixpath.join(posixpath.dirname(path), imp)) if imp.startswith('.') else imp)
    return result


def typ(p):
    return '(' + ','.join(typ(x) for x in p['components']) + ')' + p['type'][5:] if p['type'].startswith('tuple') else p['type']


def abi_entries(abi):
    return {a['type'] + ':' + a.get('name', '') + '(' + ','.join(typ(p) for p in a.get('inputs', [])) + ')': a for a in abi}


def layout_shape(layout):
    # Resolve compiler type IDs recursively; AST numbering is not physical storage.
    types = layout.get('types') or {}
    def field(f):
        return {'label': f['label'], 'slot': f['slot'], 'offset': f['offset'], 'type': resolve(f['type'])}
    def resolve(key):
        t = types[key]
        out = {k: t[k] for k in ['encoding', 'label', 'numberOfBytes']}
        for k in ['key', 'value', 'base']:
            if k in t:
                out[k] = resolve(t[k])
        if 'members' in t:
            out['members'] = [field(f) for f in t['members']]
        return out
    return [field(f) for f in layout['storage']]


class Review:
    def __init__(self):
        self.solc = os.environ['TBPROS_SOLC']
        self.compiler = subprocess.check_output([self.solc, '--version'], text=True).strip()
        assert '0.8.28+commit.7893614a' in self.compiler
        for package in ['contracts', 'contracts-upgradeable']:
            assert json.loads(Path('node_modules/@openzeppelin', package, 'package.json').read_text())['version'] == '5.6.1'
        self.rows, self.baseline = [], None

    def run(self, label, src, reason, category='B', semantics='Unchanged', basis=BASE, all_contracts=False):
        probe = 'cache/tbpros-bytecode-review/LayoutProbe.sol'
        src = dict(src)
        src[probe] = '// SPDX-License-Identifier: MIT\npragma solidity 0.8.28;\nimport {TbPROSStorage as S} from "contracts/tbpros/TbPROSStorage.sol";\ncontract LayoutProbe { S.Layout internal layout; }\n'
        roots = [p for p in src if p.endswith('.sol') and p.startswith('contracts/')] if all_contracts else [V]
        sources = closure(src, roots + [probe])
        inp = {'language': 'Solidity', 'sources': {p: {'content': s} for p, s in sorted(sources.items())},
               'settings': {**PROFILE, 'outputSelection': {'*': {'*': ['abi', 'storageLayout', 'evm.bytecode.object', 'evm.deployedBytecode.object']}}}}
        directory = CACHE / label
        directory.mkdir(parents=True, exist_ok=True)
        encoded = encode(inp)
        (directory / 'input.json').write_text(encoded)
        process = subprocess.run([self.solc, '--standard-json'], input=encoded, text=True, capture_output=True, check=True)
        (directory / 'output.json').write_text(process.stdout)
        out = json.loads(process.stdout)
        errors = [e['formattedMessage'] for e in out.get('errors', []) if e['severity'] == 'error']
        if errors:
            raise RuntimeError(label + '\n' + '\n'.join(errors))
        vault = out['contracts'][V]['TbPROSVault']
        abi = abi_entries(vault['abi'])
        physical = {'ordinary': layout_shape(vault['storageLayout']),
                    'tbpros_namespace': layout_shape(out['contracts'][probe]['LayoutProbe']['storageLayout'])}
        if self.baseline is None:
            assert len(vault['evm']['deployedBytecode']['object']) // 2 == 18910, 'STOP: current baseline differs from 18910'
            self.baseline = (abi, physical)
        base_abi, base_physical = self.baseline
        abi_delta = {'removed': sorted(base_abi.keys() - abi.keys()), 'added': sorted(abi.keys() - base_abi.keys()),
                     'changed': sorted(k for k in abi.keys() & base_abi.keys() if abi[k] != base_abi[k])}
        row = {'variant': label, 'source_basis': basis, 'compiler_profile': PROFILE,
               'compiler_input_sha256': digest(encoded),
               'source_sha256': digest(encode({p: digest(s) for p, s in sorted(sources.items())})),
               'runtime_bytes': len(vault['evm']['deployedBytecode']['object']) // 2,
               'initcode_template_bytes': len(vault['evm']['bytecode']['object']) // 2,
               'ABI_change': any(abi_delta.values()), 'ABI_delta': abi_delta,
               'storage_physical_change': physical != base_physical,
               'storage_semantics': semantics, 'security_category': category,
               'adopted': False, 'reason': reason,
               'warning_counts': {code: sum(str(e.get('errorCode')) == code for e in out.get('errors', []) if e['severity'] == 'warning') for code in sorted({str(e.get('errorCode')) for e in out.get('errors', []) if e['severity'] == 'warning'})}}
        row['delta_vs_current_bytes'] = row['runtime_bytes'] - 18910
        row['headroom_bytes'] = 20480 - row['runtime_bytes']
        if all_contracts:
            names = {'TbPROSVault', 'ProsReserve', 'UpgradeGateway', 'TbPROSLens'}
            row['contracts'] = {n: {'runtime_bytes': len(a['evm']['deployedBytecode']['object']) // 2,
                                    'initcode_template_bytes': len(a['evm']['bytecode']['object']) // 2}
                                for contracts in out['contracts'].values() for n, a in contracts.items() if n in names}
        self.rows.append(row)
        print(label, row['runtime_bytes'], row['delta_vs_current_bytes'], flush=True)
        return row

    def save(self):
        DEST.write_text(json.dumps({'base_commit': BASE, 'compiler': self.compiler, 'dependencies': 'OpenZeppelin 5.6.1, installed pinned sources',
                                   'profile': PROFILE, 'tool_sha256': digest(Path(__file__).read_text()),
                                   'scope': 'Compiler diagnostics. Only Path-A-final-production is adopted, with behavioral verification recorded separately; Category B is never adopted. Initcode excludes constructor arguments. Physical comparison covers ordinary storage and recursively materialized tbPROS namespace; other inherited namespaces require manual semantic review.',
                                   'variants': self.rows}, indent=2) + '\n')


def guardian(src):
    src = dict(src)
    v = src[V].replace('AccessControlUpgradeable, ', '').replace('        __AccessControl_init();', '')
    v = v.replace('        _grantRole(DEFAULT_ADMIN_ROLE, d.timelock);', '').replace('        _grantRole(GUARDIAN_ROLE, config.guardian);', '        guardians[config.guardian] = true;\n        emit GuardianChanged(config.guardian, true);')
    v = v.replace('hasRole(GUARDIAN_ROLE, msg.sender)', 'guardians[msg.sender]')
    for name in ['grantRole', 'revokeRole', 'renounceRole']:
        v = replace_function(v, name)
    src[V] = v
    return insert(src, '''    mapping(address => bool) public guardians;
    event GuardianChanged(address indexed account, bool enabled);
    function setGuardian(address account, bool enabled) external nonReentrant onlyTimelock {
        if(account == address(0)) revert InvalidAddress();
        if(guardians[account] != enabled) { guardians[account] = enabled; emit GuardianChanged(account, enabled); }
    }
    function resignGuardian() external nonReentrant {
        if(guardians[msg.sender]) { guardians[msg.sender] = false; emit GuardianChanged(msg.sender, false); }
    }''')


def metadata(src, initialize=False):
    src = dict(src)
    if not initialize:
        src[V] = src[V].replace('        __ERC20_init("tbPROS", "tbPROS");', '')
    return insert(src, '''    function name() public pure override returns (string memory) { return "tbPROS"; }
    function symbol() public pure override returns (string memory) { return "tbPROS"; }''')


def immutables(src, getter):
    src = dict(src)
    fields = ['timelock', 'usdc', 'wpros', 'stpros', 'subscriptionReserve', 'yieldReserve', 'gateway']
    v = src[V].replace('constructor() {', 'constructor(T.Dependencies memory fixed_) {\n' + '\n'.join('        fixed_' + f + ' = fixed_.' + f + ';' for f in fields))
    v = v.replace('        T.Dependencies calldata d = config.dependencies;', '        T.Dependencies calldata d = config.dependencies;\n        if (' + ' || '.join('d.' + f + ' != fixed_' + f for f in fields) + ') revert InvalidAddress();')
    for f in fields:
        v = v.replace('S.layout().dependencies.' + f, 'fixed_' + f).replace('s.dependencies.' + f, 'fixed_' + f)
        # Leave dormant legacy fields in place; preserve all initializer identity validation.
        v = v.replace('            d.' + f + ',', '            address(0),')
    a, b = span(v, '_validateRefundReceiver')
    body = v[a:b].replace('d.subscriptionReserve', 'fixed_subscriptionReserve').replace('d.yieldReserve', 'fixed_yieldReserve')
    v = v[:a] + body + v[b:]
    src[V] = v
    code = '\n'.join('    address private immutable fixed_' + f + ';' for f in fields)
    if getter:
        code += '\n    function fixedBindings() external view returns(address[7] memory) { return [' + ','.join('fixed_' + f for f in fields) + ']; }'
    return insert(src, code)


CUSTOM_ERC20 = '''// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
// DIAGNOSTIC ONLY: unaudited replacement, ordinary storage incompatible with OZ namespace.
abstract contract ERC20Upgradeable is Initializable, IERC20Errors {
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private supply;
    string private tokenName;
    string private tokenSymbol;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function __ERC20_init(string memory n, string memory s) internal onlyInitializing { tokenName=n; tokenSymbol=s; }
    function name() public view virtual returns(string memory) { return tokenName; }
    function symbol() public view virtual returns(string memory) { return tokenSymbol; }
    function decimals() public pure returns(uint8) { return 18; }
    function totalSupply() public view returns(uint256) { return supply; }
    function balanceOf(address a) public view returns(uint256) { return balances[a]; }
    function allowance(address a,address b) public view returns(uint256) { return allowances[a][b]; }
    function approve(address b,uint256 n) public virtual returns(bool) {
        if(msg.sender==address(0)) revert ERC20InvalidApprover(msg.sender);
        if(b==address(0)) revert ERC20InvalidSpender(b);
        allowances[msg.sender][b]=n; emit Approval(msg.sender,b,n); return true;
    }
    function transfer(address b,uint256 n) public virtual returns(bool) { _transfer(msg.sender,b,n); return true; }
    function transferFrom(address a,address b,uint256 n) public virtual returns(bool) { _spendAllowance(a,msg.sender,n); _transfer(a,b,n); return true; }
    function _transfer(address a,address b,uint256 n) internal {
        if(a==address(0)) revert ERC20InvalidSender(a);
        if(b==address(0)) revert ERC20InvalidReceiver(b);
        _update(a,b,n);
    }
    function _spendAllowance(address a,address b,uint256 n) internal {
        uint256 old=allowances[a][b]; if(old==type(uint256).max) return;
        if(old<n) revert ERC20InsufficientAllowance(b,old,n);
        if(a==address(0)) revert ERC20InvalidApprover(a);
        if(b==address(0)) revert ERC20InvalidSpender(b);
        unchecked { allowances[a][b]=old-n; }
    }
    function _update(address a,address b,uint256 n) internal virtual {
        if(a==address(0)) supply+=n;
        else { uint256 old=balances[a]; if(old<n) revert ERC20InsufficientBalance(a,old,n); unchecked {balances[a]=old-n;} }
        if(b==address(0)) { unchecked {supply-=n;} } else { unchecked {balances[b]+=n;} }
        emit Transfer(a,b,n);
    }
}
'''


def timelock_dedup(src):
    k = dict(src)
    k[V] = k[V].replace('        if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();', '        _requireTimelock();', 1)
    k[V] = k[V].replace('        else if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();', '        else _requireTimelock();')
    k = insert(k, '''    /// @dev Require the fixed stored Timelock root; shared by delayed entries and request unpause.
    /// No external calls, role delegation, state writes or change to error precedence.
    function _requireTimelock() private view {
        if (msg.sender != S.layout().dependencies.timelock) revert Unauthorized();
    }''')
    return k


def main():
    r, base = Review(), source_at(BASE)
    r.run('A-current', base, 'Exact current committed production source; baseline must equal 18910 or stop.', 'BASELINE', all_contracts=True)
    for name, commit, expected in [('history-hardened', 'ebab5d794bade22353211899f6554ded6cafc11f', 14236),
                                   ('history-request', 'a12f2edaddeaa3c5b41b754fd4f10bfc08719749', 16737)]:
        row = r.run(name, source_at(commit), 'Actual historical production rebuild with identical compiler/dependencies/profile.', 'HISTORICAL', 'Historical schema; not an upgrade compatibility claim.', commit, True)
        assert row['runtime_bytes'] == expected
    r.run('B-without-remaining-stubs', remove(base, STUBS), 'DIAGNOSTIC ONLY / NOT FINAL-PRODUCT HEADROOM. Removes required V1 ABI, dispatch, modifiers and stub bodies.', 'ABI PRODUCT REDUCTION')
    r.run('C-selector-modifier-stub-reservation', base, 'Same selectors and mandatory modifiers with SkeletonOnly bodies already present in A. Paired against B; not additive per-function costs.', 'DIAGNOSTIC')
    for name in STUBS:
        r.run('C-without-' + name, remove(base, [name]), 'Individual current stub marginal: includes shared optimizer effects; does not estimate future business body.', 'ABI PRODUCT REDUCTION')
    r.run('D-minimal-guardian', guardian(base), 'Fixed TL, multiple Guardians, TL appoint/revoke, self-resign, pause tightening only. Different ABI/events/storage and unaudited custom authorization; approval required.', semantics='OZ role namespace abandoned; ordinary guardian mapping added; migration required.')
    r.run('E1-constant-metadata-keep-writes', metadata(base, True), 'Constant pure getters but retains initialization strings. Isolates getter strategy from write omission.', semantics='Metadata getters ignore legacy strings; uninitialized/implementation reads change.')
    r.run('E2-constant-metadata-omit-writes', metadata(base), 'Constant pure metadata, omit __ERC20_init only; all OZ token accounting retained. Requires metadata/storage semantic approval.', semantics='Legacy metadata slots stay declared but no longer initialized or read; token ledger unchanged.')
    for name in GETTERS:
        r.run('F-without-' + name, remove(base, [name]), 'Diagnostic marginal getter cost only; rights/governance/incident getters must not be removed. Only Vault import closure compiled; no claim that unchanged consumers remain compatible.')
    r.run('F2-monitoring-ui-candidate', remove(base, ['nextPlanId']), 'Only nextPlanId selected: optional future-plan UI convenience; keep incident monitoring and all exit/authority getters. ABI approval required.')
    grouped = remove(base, ['queueState', 'openPositionCount'])
    grouped[V] += ''
    grouped = insert(grouped, '''    function requestState(address controller) external view returns(uint64, uint64, uint64, uint128) {
        S.Layout storage s = S.layout();
        return (s.queueHead, s.queueTail, s.lastSettledDueAt, s.openPositionCount[controller]);
    }''')
    r.run('F3-group-request-state', grouped, 'Group only queue endpoints/watermark/count; keep Epoch/Position direct raw queries. Changes client ABI; no Lens dependence.')
    r.run('G2-duplicate-validation-control', base, 'No provably redundant validation with identical revert/call-order behavior found. EOA checks plus typed STATICCALL decoding are not identical safety controls. NO BENEFIT.', 'A-CONTROL')
    g = dict(base)
    a = g[V].index('        _requireCode(d.timelock);')
    b = g[V].index('        __ERC20_init(', a)
    g[V] = g[V][:a] + g[V][b:]
    g[V] = g[V].replace('        _validateRefundReceiver(d.yieldRefundReceiver);', '')
    r.run('G3-validation-outside-vault', g, 'DIAGNOSTIC ONLY: omit initialization validations, preserve initialization/writes. Validation relocation itself NOT IMPLEMENTED; deployment scripts are no substitute for on-chain safety.', semantics='Physical fields retained, but invalid/zero/mismatched initial states become admissible. Trust and deployment safety change.')
    r.run('H1-fixed-immutables', immutables(base, False), 'Seven fixed bindings in implementation; retain init identity checks and require config equality. No complete replacement verification API; not a deployable recommendation.', semantics='Seven legacy dependency fields dormant; constructor values now determine bindings; replacement migration required.')
    r.run('H2-fixed-immutables-verifiable', immutables(base, True), 'H1 plus complete seven-binding getter for future Gateway checks. Gateway comparison implementation not included; Model A still trusts replacement code.', semantics='Same as H1 plus new upgrade verification API; one implementation configuration per product.')
    custom = dict(base)
    custom[ERC20] = CUSTOM_ERC20
    r.run('I-custom-token-diagnostic', custom, 'DO NOT ADOPT. Diagnostic ERC20 balance/allowance/supply/transfer/events/direct-Vault restriction retained in source; no independent ERC20 compatibility or upgrade proof.', semantics='Replaces OZ token namespace with ordinary storage; new audit/migration and inheritance surface.')
    k = timelock_dedup(base)
    r.run('K1-timelock-check-dedup', k, 'Same stored root/error/call-order and complete ABI/layout. Applied only after Phase A measurement; production CI recorded separately.', 'A-CANDIDATE')
    k = dict(base)
    k[V] = k[V].replace('if (planSlot > 1 || sourceSlot > 1)', 'if ((planSlot | sourceSlot) > 1)')
    r.run('K2-source-index-predicate', k, 'uint8 bitwise OR bound equivalent for legal 0/1 slots; no guard removed. Compiler-only candidate; no production adoption.', 'A-CANDIDATE')
    k = dict(base)
    k[S] = re.sub(r'        uint128 uCap;\n', '', k[S], count=1)
    k[V] = k[V].replace('            0, // Reserved legacy global Ucap slot; never interpreted as current coverage.\n', '')
    r.run('K3-remove-retired-uCap', k, 'Diagnostic only: physical policy offsets change. Never reuse removed semantic storage; reject schema churn for negligible runtime.', semantics='Policy.uCap removed; packed policy members shift; policy still occupies one slot.')
    combo = remove(metadata(guardian(base)), ['nextPlanId'])
    r.run('Path-B-combined', combo, 'Actual combined Guardian + constant metadata without writes + nextPlanId removal. Not the sum of independent deltas; all Category B, not approved.', semantics='Combined guardian replacement and metadata semantic migration; tbPROS namespace retained.')
    r.run('Path-A-final-production', {str(p): p.read_text() for p in Path('contracts/tbpros').rglob('*.sol')},
          'Actual final working-tree production sources; only K1 Timelock check extraction adopted. Full local behavior/guard evidence is in latest-local-checks.md.',
          'A-ADOPTED', all_contracts=True)
    r.rows[-1]['adopted'] = True
    r.run('Option-1-A-plus-metadata', metadata(timelock_dedup(base)), 'Actual combined Category A + metadata proposal; metadata not approved.', semantics='Legacy metadata no longer read/written; OZ ledger preserved.')
    r.run('Option-2-A-plus-guardian-metadata', metadata(guardian(timelock_dedup(base))), 'Actual combined Category A + Guardian and metadata proposal; Category B not approved.', semantics='Guardian namespace migration and metadata semantic change.')
    r.run('Option-3-A-plus-Path-B', remove(metadata(guardian(timelock_dedup(base))), ['nextPlanId']), 'Actual combined Category A plus complete conservative Path B; Category B not approved.', semantics='Guardian namespace migration, metadata semantics and optional next-ID ABI removal.')
    r.save()


if __name__ == '__main__':
    main()
