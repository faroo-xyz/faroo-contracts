import type { Address } from "viem";

import { artifacts, deployScript } from "../rocketh/deploy.js";

/**
 * Deploy SlpDistributor behind the shared-admin transparent proxy.
 *
 * Optional env:
 *   SLP_DISTRIBUTOR_KEEPER=0x...            initial keeper (default: unset, set later via setKeeper)
 *   SLP_DISTRIBUTOR_SLPS=0xA...,0xB...      initial SLP whitelist (default: empty)
 *
 * pnpm deploy:testnet SlpDistributor
 * Then (owner/multisig): StPROS.setSlp(<SlpDistributor proxy>)
 */
function parseAddressList(value: string | undefined): Address[] {
  if (value === undefined || value.trim() === "") {
    return [];
  }
  return value.split(",").map((a) => a.trim() as Address);
}

export default deployScript(
  async ({ deployViaProxy, namedAccounts, viem }) => {
    const { deployer, owner } = namedAccounts;
    const keeper = (process.env.SLP_DISTRIBUTOR_KEEPER?.trim() || "0x0000000000000000000000000000000000000000") as Address;
    const slps = parseAddressList(process.env.SLP_DISTRIBUTOR_SLPS);

    const deployment = await deployViaProxy(
      "SlpDistributor",
      {
        account: deployer,
        artifact: artifacts.SlpDistributor as any,
      },
      {
        owner,
        proxyContract: "SharedAdminOpenZeppelinTransparentProxy",
        execute: {
          init: {
            methodName: "initialize",
            // Contract owner is the deployer account (TEST_PRIVATE_KEY on testnet)
            args: [deployer, keeper, slps],
          },
        },
      },
    );

    const distributor = viem.getContract(deployment);
    const [proxyOwner, currentKeeper, whitelisted] = await Promise.all([
      distributor.read.owner(),
      distributor.read.keeper(),
      distributor.read.getSlps(),
    ]);

    console.log(`[SlpDistributor] proxy=${deployment.address}`);
    console.log(`[SlpDistributor] owner=${proxyOwner}`);
    console.log(`[SlpDistributor] keeper=${currentKeeper}`);
    console.log(`[SlpDistributor] slps=${(whitelisted as readonly string[]).join(",")}`);
    console.log(`[SlpDistributor] next: StPROS.setSlp(${deployment.address}) from the StPROS owner`);
  },
  { tags: ["SlpDistributor", "SlpDistributor_deploy"] },
);
