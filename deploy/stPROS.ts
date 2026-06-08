import { artifacts, deployScript } from "../rocketh/deploy.js";
import { TESTNET } from "../contants/index.js";

const DEFAULT_STPROS_NAME = "Faroo Staked PROS";
const DEFAULT_STPROS_SYMBOL = "stPROS";

function getRequiredEnv(name: string): string {
  const value = process.env[name];

  if (value === undefined || value.trim() === "") {
    throw new Error(`${name} is required`);
  }

  return value;
}

export default deployScript(
  async ({ deployViaProxy, namedAccounts, viem }) => {
    const { deployer, owner } = namedAccounts;

    const asset = TESTNET.WPROS;
    const name = process.env.STPROS_NAME ?? DEFAULT_STPROS_NAME;
    const symbol = process.env.STPROS_SYMBOL ?? DEFAULT_STPROS_SYMBOL;

    const deployment = await deployViaProxy(
      "StPROS",
      {
        account: deployer,
        artifact: artifacts.StPROS as any,
      },
      {
        owner,
        proxyContract: "SharedAdminOpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [asset, owner, name, symbol],
          },
        },
      },
    );

    const stPros = viem.getContract(deployment);
    const deployedAsset = await stPros.read.asset();
    const deployedName = await stPros.read.name();
    const deployedSymbol = await stPros.read.symbol();

    console.log(
      `[StPROS] proxy=${deployment.address} asset=${deployedAsset} name=${deployedName} symbol=${deployedSymbol}`,
    );
  },
  { tags: ["StPROS", "StPROS_deploy"] },
);
