import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const deployment = await deploy(
      "YieldVault_Implementation",
      {
        account: deployer,
        artifact: artifacts.YieldVault as any,
        args: [],
      },
      { alwaysOverride: true },
    );

    console.log(`[YieldVault_Implementation] address=${deployment.address}`);
    console.log(
      "[YieldVault_Implementation] multisig upgrade: YieldVaultFactory.upgradeBeaconTo(implementation)",
    );
  },
  { tags: ["implementations", "YieldVault_impl"] },
);
