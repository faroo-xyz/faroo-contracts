import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deployViaProxy, namedAccounts, viem }) => {
    const { deployer, owner } = namedAccounts;

    const deployment = await deployViaProxy(
      "Oracle",
      {
        account: deployer,
        artifact: artifacts.Oracle as any,
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

    const oracle = viem.getContract(deployment);
    const deployedOwner = await oracle.read.owner();
    const paused = await oracle.read.paused();

    console.log(
      `[Oracle] proxy=${deployment.address} owner=${deployedOwner} paused=${paused}`,
    );
  },
  { tags: ["Oracle", "Oracle_deploy"] },
);
