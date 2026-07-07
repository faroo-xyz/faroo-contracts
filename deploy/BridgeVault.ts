import type { Address } from "viem";

import { artifacts, deployScript } from "../rocketh/deploy.js";
import { Mainnet, TESTNET } from "../contants/index.js";

function resolveVTokenProxy(): Address {
  const override = process.env.BRIDGE_VAULT_VTOKEN?.trim();

  if (override !== undefined && override !== "") {
    return override as Address;
  }

  const network = process.env.HARDHAT_NETWORK ?? "mainnet";

  if (network === "testnet") {
    return TESTNET.STPROS as Address;
  }

  if (network === "mainnet") {
    return Mainnet.STPROS as Address;
  }

  throw new Error(
    "Set BRIDGE_VAULT_VTOKEN or deploy on mainnet/testnet so the StPROS proxy can be resolved",
  );
}

function resolveIsWeth(): boolean {
  return process.env.BRIDGE_VAULT_IS_WETH !== "false";
}

export default deployScript(
  async ({ deployViaProxy, namedAccounts, viem }) => {
    const { deployer, owner } = namedAccounts;
    const vToken = resolveVTokenProxy();
    const isWeth = resolveIsWeth();

    const deployment = await deployViaProxy(
      "BridgeVault",
      {
        account: deployer,
        artifact: artifacts.BridgeVault as any,
      },
      {
        owner,
        proxyContract: "SharedAdminOpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "initialize",
            args: [owner, vToken, isWeth],
          },
        },
      },
    );

    const bridgeVault = viem.getContract(deployment);
    const [proxyOwner, weth, isRegistered] = await Promise.all([
      bridgeVault.read.owner(),
      bridgeVault.read.weth(),
      bridgeVault.read.vTokenAddresses([vToken]),
    ]);

    console.log(`[BridgeVault] proxy=${deployment.address}`);
    console.log(`[BridgeVault] owner=${proxyOwner}`);
    console.log(`[BridgeVault] vToken=${vToken}`);
    console.log(`[BridgeVault] isWeth=${isWeth}`);
    console.log(`[BridgeVault] weth=${weth}`);
    console.log(`[BridgeVault] vTokenRegistered=${isRegistered}`);
    console.log(
      "[BridgeVault] next: upgradeAndCall Oracle, then upgradeAndCall StPROS with initializeV2(slp, bridgeVault)",
    );
  },
  { tags: ["BridgeVault", "BridgeVault_deploy"] },
);
