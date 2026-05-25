import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Deploy StPROS behind a TransparentUpgradeableProxy and call initialize.
 *
 * Parameters:
 * - asset: underlying wrapped PROS token address (required) 0x838800b758277cc111b2d48ab01e5e164f8e9471
 * - owner: owner/admin for proxy admin + StPROS initialize owner (default: deployer)
 * - name: ERC20 name (default: "Staked PROS")
 * - symbol: ERC20 symbol (default: "stPROS")
 */
export default buildModule("StPROSModule", (m) => {
  const deployer = m.getAccount(0);

  const asset = m.getParameter<string>("asset");
  const owner = m.getParameter<string>("owner");
  const name = m.getParameter<string>("name", "Faroo Staked PROS");
  const symbol = m.getParameter<string>("symbol", "stPROS");

  const implementation = m.contract("StPROS", [], {
    id: "StPROSImplementation",
  });

  const initData = m.encodeFunctionCall(implementation, "initialize", [
    asset,
    owner,
    name,
    symbol,
  ]);

  const proxy = m.contract(
    "TransparentUpgradeableProxy",
    [implementation, owner, initData],
    {
      id: "StPROSProxy",
      after: [implementation],
    },
  );

  const proxyAdminAddress = m.readEventArgument(
    proxy,
    "AdminChanged",
    "newAdmin",
  );

  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress, {
    id: "StPROSProxyAdmin",
    after: [proxy],
  });

  const stPros = m.contractAt("StPROS", proxy, {
    id: "StPROS",
    after: [proxy],
  });

  return {
    StPROS: stPros,
    StPROSProxy: proxy,
    StPROSProxyAdmin: proxyAdmin,
    "stpros-implementation-v1": implementation,
  };
});
