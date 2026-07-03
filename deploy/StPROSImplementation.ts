import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const deployment = await deploy(
      "StPROS_Implementation",
      {
        account: deployer,
        artifact: artifacts.StPROS as any,
        args: [],
      },
      { alwaysOverride: true },
    );

    console.log(`[StPROS_Implementation] address=${deployment.address}`);
    console.log("[StPROS_Implementation] multisig upgrade: ProxyAdmin.upgrade(stProsProxy, implementation)");
  },
  { tags: ["implementations", "StPROS_impl"] },
);
