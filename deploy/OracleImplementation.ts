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
    console.log(
      "[Oracle_Implementation] first v2 upgrade: pnpm hardhat oracle:execute-upgrade-v2 --network <network> <implementation>",
    );
    console.log(
      "[Oracle_Implementation] subsequent impl swap: pnpm hardhat oracle:execute-upgrade --network <network> <implementation>",
    );
    console.log(
      "[Oracle_Implementation] multisig calldata (v2): pnpm hardhat oracle:upgrade-v2 --network <network> <oracleProxy> <implementation> <slp> <vToken> <maxUpdateAmount> <updateInterval>",
    );
    console.log(
      "[Oracle_Implementation] multisig calldata (impl only): pnpm hardhat oracle:upgrade --network <network> <oracleProxy> <implementation>",
    );
  },
  { tags: ["implementations", "Oracle_impl"] },
);
