import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deployViaProxy, namedAccounts, viem }) => {
    const { deployer, owner } = namedAccounts;

    const deployment = await deployViaProxy(
      "YieldVaultFactory",
      {
        account: deployer,
        artifact: artifacts.YieldVaultFactory as any,
      },
      {
        owner,
        proxyContract: "SharedAdminOpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [owner],
          },
        },
      },
    );

    const factory = viem.getContract(deployment);
    const beacon = await factory.read.beacon();
    const yieldVaultImplementation = await factory.read.currentImplementation();
    const totalProxies = await factory.read.totalProxies();

    console.log(
      `[YieldVaultFactory] proxy=${deployment.address} beacon=${beacon} yieldVaultImplementation=${yieldVaultImplementation} totalProxies=${totalProxies}`,
    );
  },
  { tags: ["YieldVaultFactory", "YieldVaultFactory_deploy"] },
);
