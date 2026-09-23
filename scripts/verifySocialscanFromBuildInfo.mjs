// Verify a deployed contract on SocialScan using the exact solc input from a Hardhat build-info file.
// Usage:
//   node scripts/verifySocialscanFromBuildInfo.mjs <address> <buildInfoId> [contractFQN] [chainId]
// Example:
//   node scripts/verifySocialscanFromBuildInfo.mjs 0xf4caf6898a9316994b736cd03b3bfbe964e95384 \
//     solc-0_8_28-27d92adffcef10a905ddd72ad8e6757be2bf835f contracts/Oracle.sol:Oracle 688689
import fs from "node:fs";

const API = {
  688689: "https://api.socialscan.io/pharos-atlantic-testnet/v1/explorer/command_api/contract",
  1672: "https://api.socialscan.io/pharos-mainnet/v1/explorer/command_api/contract",
};
const BROWSER = { 688689: "https://pharos-testnet.socialscan.io", 1672: "https://pharos.socialscan.io" };

const [address, buildInfoId, fqn = "contracts/Oracle.sol:Oracle", chainIdArg = "688689"] = process.argv.slice(2);
if (!address || !buildInfoId) {
  console.error("Usage: node scripts/verifySocialscanFromBuildInfo.mjs <address> <buildInfoId> [contractFQN] [chainId]");
  process.exit(1);
}
const chainId = Number(chainIdArg);
const apiUrl = API[chainId];
if (!apiUrl) throw new Error(`No SocialScan API for chainId ${chainId}`);

const [srcPath, contractName] = fqn.split(":");
const sourceKey = `project/${srcPath}`;
const bi = JSON.parse(fs.readFileSync(`artifacts/build-info/${buildInfoId}.json`, "utf8"));
const out = JSON.parse(fs.readFileSync(`artifacts/build-info/${buildInfoId}.output.json`, "utf8"));
const compiled = out.output.contracts[sourceKey]?.[contractName];
if (!compiled) throw new Error(`${sourceKey}:${contractName} not found in ${buildInfoId}`);

// Keep only the sources recorded in the contract's metadata; keep settings exactly as compiled.
const meta = JSON.parse(compiled.metadata);
const input = {
  language: bi.input.language,
  sources: Object.fromEntries(Object.keys(meta.sources).map((k) => [k, bi.input.sources[k]])),
  settings: bi.input.settings,
};
const optimizer = meta.settings.optimizer ?? { enabled: false, runs: 200 };

// Sanity check against the local deployment record, if present.
const depFile = "deployments/testnet/Oracle_Implementation.json";
if (chainId === 688689 && fs.existsSync(depFile)) {
  const dep = JSON.parse(fs.readFileSync(depFile, "utf8"));
  if (dep.address?.toLowerCase() === address.toLowerCase()) {
    const same = dep.deployedBytecode.toLowerCase() === ("0x" + compiled.evm.deployedBytecode.object).toLowerCase();
    console.log(`[verify] deployment record bytecode match: ${same}`);
    if (!same) throw new Error("Build-info bytecode does not match deployment record");
  }
}

async function post(fields) {
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`SocialScan ${res.status}: ${text.slice(0, 500)}`);
  return JSON.parse(text);
}

console.log(`[verify] address=${address} contract=${fqn} compiler=v${bi.solcLongVersion} optimizer=${JSON.stringify(optimizer)}`);
const submit = await post({
  module: "contract",
  action: "verifysourcecode",
  contractaddress: address,
  sourceCode: JSON.stringify(input),
  codeformat: "solidity-standard-json-input",
  contractname: fqn,
  compilerversion: `v${bi.solcLongVersion}`,
  constructorArguments: "",
  optimizationUsed: optimizer.enabled ? "1" : "0",
  runs: String(optimizer.runs ?? 200),
});
console.log(`[verify] submit: ${JSON.stringify(submit)}`);
const done = (m) => /Pass - Verified|already verified|Already Verified|successfully verified/i.test(m);
if (submit.status === "1" && done(submit.message)) {
  console.log(`✅ ${BROWSER[chainId]}/address/${address}#code`);
  process.exit(0);
}
if (submit.status !== "1" || !submit.result) throw new Error(`Submit failed: ${submit.message}`);

for (let i = 0; i < 40; i++) {
  await new Promise((r) => setTimeout(r, 3000));
  const s = await post({ module: "contract", action: "checkverifystatus", guid: submit.result });
  console.log(`[verify] status: ${s.message}`);
  if (s.status === "1" && done(s.message)) {
    console.log(`✅ ${BROWSER[chainId]}/address/${address}#code`);
    process.exit(0);
  }
  if (String(s.message).startsWith("Fail")) throw new Error(s.message);
}
throw new Error("Timed out waiting for verification");
