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
    console.log(
      "[StPROS_Implementation] prereq: oracle.setVToken(stProsProxy, true)",
    );
    console.log(
      "[StPROS_Implementation] owner multisig: ProxyAdmin.upgradeAndCall(stProsProxy, implementation, initializeV2(slp, bridgeVault))",
    );
    console.log(
      "[StPROS_Implementation] helper: pnpm hardhat stpros:upgrade-v2 --network <network> <stProsProxy> <implementation> <slp> <bridgeVault>",
    );
  },
  { tags: ["implementations", "StPROS_impl"] },
);
