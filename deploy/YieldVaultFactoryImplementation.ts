import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const deployment = await deploy(
      "YieldVaultFactory_Implementation",
      {
        account: deployer,
        artifact: artifacts.YieldVaultFactory as any,
        args: [],
      },
      { alwaysOverride: true },
    );

    console.log(`[YieldVaultFactory_Implementation] address=${deployment.address}`);
    console.log(
      "[YieldVaultFactory_Implementation] multisig upgrade: ProxyAdmin.upgrade(factoryProxy, implementation)",
    );
  },
  { tags: ["implementations", "YieldVaultFactory_impl"] },
);
