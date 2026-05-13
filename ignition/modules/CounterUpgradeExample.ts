import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Counter transparent proxy upgrade: deploy the new implementation and call `upgradeAndCall` on ProxyAdmin.
 *
 * Parameters (module id in JSON: `CounterUpgradeModule`):
 * - `proxy`, `proxyAdmin`: from the initial `CounterModule` deployment `deployed_addresses.json` (keys `CounterProxy`, `ProxyAdmin`)
 * - `upgradeCallData`: optional, default `0x` (no post-upgrade call)
 *
 * Deployment artifacts only record `implementation-v2`; the implementation contract name and proxy ABI must be the literal `Counter` (Ignition constraint).
 *
 * Multisig path: deploy `CounterUpgradeSafeExample.ts` first, then run `npm run propose:counter-upgrade-safe` to propose
 * `ProxyAdmin.upgradeAndCall` via Safe (see env vars in that script).
 */
export default buildModule("CounterUpgradeModule", (m) => {
  const owner = m.getAccount(0);

  const proxy = m.contractAt(
    "TransparentUpgradeableProxy",
    m.getParameter("proxy"),
  );
  const proxyAdmin = m.contractAt(
    "ProxyAdmin",
    m.getParameter("proxyAdmin"),
  );

  const upgradeCallData = m.getParameter("upgradeCallData", "0x");

  const implementationV2 = m.contract("Counter", [], {
    id: "ImplementationV2",
  });

  m.call(
    proxyAdmin,
    "upgradeAndCall",
    [proxy, implementationV2, upgradeCallData],
    {
      from: owner,
      after: [implementationV2, proxyAdmin],
    },
  );

  return { "implementation-v2": implementationV2 };
});
