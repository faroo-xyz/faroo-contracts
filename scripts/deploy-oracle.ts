import { artifacts, network } from "hardhat";
import {
  encodeFunctionData,
  isAddress,
  parseEventLogs,
  type Address,
} from "viem";

/**
 * Usage:
 * [ORACLE_OWNER=<ownerAddress>] pnpm hardhat run scripts/deploy-oracle.ts --network testnet
 *
 * Example:
 * ORACLE_OWNER=0xB50C9E6DdEDbb1046a6134ad731d5B80481571f3 \
 * pnpm hardhat run scripts/deploy-oracle.ts --network testnet
 *
 * Notes:
 * - ORACLE_OWNER defaults to the deployer if omitted.
 * - The script deploys the implementation, proxy, and ProxyAdmin.
 * - The output includes the Oracle proxy, ProxyAdmin, and implementation addresses.
 */
function getOptionalAddress(value: string | undefined, label: string): Address | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!isAddress(value)) {
    throw new Error(`Invalid ${label}: ${value}`);
  }

  return value;
}

async function main(): Promise<void> {
  const connection = await network.connect();

  try {
    const [deployer] = await connection.viem.getWalletClients();

    if (deployer?.account?.address === undefined) {
      throw new Error("No deployer account available for the selected network");
    }

    const owner =
      getOptionalAddress(process.env.ORACLE_OWNER, "owner address") ??
      deployer.account.address;

    console.log(`[deploy-oracle] network=${connection.networkName}`);
    console.log(`[deploy-oracle] deployer=${deployer.account.address}`);
    console.log(`[deploy-oracle] owner=${owner}`);

    const oracleArtifact = await artifacts.readArtifact("Oracle");
    const proxyArtifact = await artifacts.readArtifact("TransparentUpgradeableProxy");
    const implementation = await connection.viem.deployContract("Oracle", [], {
      client: {
        wallet: deployer,
      },
    });

    console.log(`[deploy-oracle] implementation=${implementation.address}`);

    const initData = encodeFunctionData({
      abi: oracleArtifact.abi,
      functionName: "initialize",
      args: [owner],
    });

    const { contract: proxy, deploymentTransaction } =
      await connection.viem.sendDeploymentTransaction(
        "TransparentUpgradeableProxy",
        [implementation.address, owner, initData],
        {
          client: {
            wallet: deployer,
          },
        },
      );

    const publicClient = await connection.viem.getPublicClient();
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: deploymentTransaction.hash,
    });
    const [adminChangedLog] = parseEventLogs({
      abi: proxyArtifact.abi,
      logs: receipt.logs,
      eventName: "AdminChanged",
      strict: false,
    });
    const proxyAdminAddress = adminChangedLog?.args.newAdmin as Address | undefined;

    if (proxyAdminAddress === undefined) {
      throw new Error("Failed to resolve ProxyAdmin address from deployment receipt");
    }

    const proxyAdmin = await connection.viem.getContractAt(
      "ProxyAdmin",
      proxyAdminAddress,
      {
        client: {
          wallet: deployer,
        },
      },
    );
    const oracle = await connection.viem.getContractAt("Oracle", proxy.address, {
      client: {
        wallet: deployer,
      },
    });

    console.log("[deploy-oracle] deployment complete");
    console.log(`[deploy-oracle] oracle=${oracle.address}`);
    console.log(`[deploy-oracle] proxy=${proxy.address}`);
    console.log(`[deploy-oracle] proxyAdmin=${proxyAdmin.address}`);
    console.log(`[deploy-oracle] implementation=${implementation.address}`);
    console.log(`[deploy-oracle] txHash=${deploymentTransaction.hash}`);
  } finally {
    await connection.close();
  }
}

main().catch((error) => {
  console.error("[deploy-oracle] deployment failed");
  console.error(error);
  process.exitCode = 1;
});
