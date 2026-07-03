import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const deployment = await deploy(
      "Oracle_Implementation",
      {
        account: deployer,
        artifact: artifacts.Oracle as any,
        args: [],
      },
      { alwaysOverride: true },
    );

    console.log(`[Oracle_Implementation] address=${deployment.address}`);
    console.log("[Oracle_Implementation] multisig upgrade: ProxyAdmin.upgrade(oracleProxy, implementation)");
  },
  { tags: ["implementations", "Oracle_impl"] },
);
