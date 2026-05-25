import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Deploy YieldVaultFactory behind a TransparentUpgradeableProxy and call initialize.
 *
 * Parameters:
 * - owner: factory owner/admin (default: deployer)
 */
export default buildModule("YieldVaultFactoryModule", (m) => {
  const deployer = m.getAccount(0);
  const owner = m.getParameter<string>("owner", deployer);

  const implementation = m.contract("YieldVaultFactory", [], {
    id: "YieldVaultFactoryImplementation",
  });

  const initData = m.encodeFunctionCall(implementation, "initialize", [owner]);

  const proxy = m.contract(
    "TransparentUpgradeableProxy",
    [implementation, owner, initData],
    {
      id: "YieldVaultFactoryProxy",
      after: [implementation],
    },
  );

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin",
  );

  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress, {
    id: "YieldVaultFactoryProxyAdmin",
    after: [proxy],
  });

  const factory = m.contractAt("YieldVaultFactory", proxy, {
    id: "YieldVaultFactory",
    after: [proxy],
  });

  return {
    YieldVaultFactory: factory,
    YieldVaultFactoryProxy: proxy,
    YieldVaultFactoryProxyAdmin: proxyAdmin,
    "yield-vault-factory-implementation-v1": implementation,
  };
});
