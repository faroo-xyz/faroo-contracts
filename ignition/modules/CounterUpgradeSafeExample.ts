import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Multisig upgrade path: deploy Counter implementation v2 only — **does not** call `upgradeAndCall` on-chain.
 * Then use `scripts/propose-counter-upgrade-safe-example.ts` to propose a Safe transaction that calls
 * `ProxyAdmin.upgradeAndCall` from the multisig.
 *
 * `deployed_addresses.json` only stores `implementation-v2` (module id `CounterUpgradeSafeExampleModule`).
 */
export default buildModule("CounterUpgradeSafeExampleModule", (m) => {
  const implementationV2 = m.contract("Counter", [], {
    id: "ImplementationV2SafeExample",
  });

  return { "implementation-v2": implementationV2 };
});
