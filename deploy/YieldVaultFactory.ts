import type { Address } from "viem";

import { artifacts, deployScript } from "../rocketh/deploy.js";

export default deployScript(
  async ({ deployViaProxy, deploy, namedAccounts, viem }) => {
    const { deployer, owner } = namedAccounts;

    const deployment = await deployViaProxy(
      "YieldVaultFactory_test",
      {
        account: deployer,
        artifact: artifacts.YieldVaultFactory as any,
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
        strictBytecodeMatch: true,
      },
    );

    const yieldVaultImplementation = await deploy(
      "YieldVault_test",
      {
        account: deployer,
        artifact: artifacts.YieldVault as any,
        args: [],
      },
      { alwaysOverride: true },
    );

    const factoryRead = viem.getContract(deployment);
    const oldImplementation = (await factoryRead.read.currentImplementation()) as Address;

    if (oldImplementation.toLowerCase() !== yieldVaultImplementation.address.toLowerCase()) {
      const factoryWrite = viem.getWritableContract(deployment, { account: owner });
      const hash = await factoryWrite.write.upgradeBeaconTo([yieldVaultImplementation.address]);
      await viem.publicClient.waitForTransactionReceipt({ hash });

      console.log(
        `[YieldVaultFactory] beacon upgraded ${oldImplementation} -> ${yieldVaultImplementation.address} tx=${hash}`,
      );
    } else {
      console.log(
        `[YieldVaultFactory] beacon already points to ${yieldVaultImplementation.address}`,
      );
    }

    const beacon = await factoryRead.read.beacon();
    const currentImplementation = await factoryRead.read.currentImplementation();
    const [totalProxies, allProxies] = await Promise.all([
      factoryRead.read.totalProxies(),
      factoryRead.read.getAllProxies(),
    ]) as [bigint, Address[]];

    console.log(
      `[YieldVaultFactory] proxy=${deployment.address} beacon=${beacon} yieldVaultImplementation=${currentImplementation} totalProxies=${totalProxies}`,
    );
    allProxies.forEach((proxy, index) => {
      console.log(`[YieldVaultFactory] proxy[${index}]=${proxy}`);
    });
  },
  { tags: ["YieldVaultFactory_test", "YieldVaultFactory_test_deploy"] },
);
