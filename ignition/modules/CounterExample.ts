import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Initial deployment: Counter implementation v1 + OpenZeppelin transparent proxy (`initialize`).
 * Resolves the ProxyAdmin address from the `AdminChanged` event. `deployed_addresses.json`
 * only stores `CounterProxy`, `ProxyAdmin`, and `implementation-v1`.
 *
 * Upgrade: see `ignition/modules/CounterUpgradeExample.ts` (adds `implementation-v2` only in artifacts when using that flow).
 * @see https://hardhat.org/ignition/docs/guides/upgradeable-proxies
 */
export default buildModule("CounterModule", (m) => {
  const owner = m.getAccount(0);

  const implementation = m.contract("Counter", [], {
    id: "ImplementationV1",
  });

  const initData = m.encodeFunctionCall(implementation, "initialize", [owner]);

  const proxy = m.contract(
    "TransparentUpgradeableProxy",
    [implementation, owner, initData],
    {
      id: "CounterProxy",
      after: [implementation],
    },
  );

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin",
  );

  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress, {
    id: "ProxyAdmin",
    after: [proxy],
  });

  return {
    CounterProxy: proxy,
    ProxyAdmin: proxyAdmin,
    "implementation-v1": implementation,
  };
});
