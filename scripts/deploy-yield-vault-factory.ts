import { artifacts, network } from "hardhat";
import {
  encodeFunctionData,
  isAddress,
  parseEventLogs,
  type Address,
} from "viem";

/**
 * Usage:
 * [YVF_OWNER=<ownerAddress>] pnpm hardhat run scripts/deploy-yield-vault-factory.ts --network testnet
 *
 * Example:
 * YVF_OWNER=0xB50C9E6DdEDbb1046a6134ad731d5B80481571f3 \
 * pnpm hardhat run scripts/deploy-yield-vault-factory.ts --network testnet
 *
 * Notes:
 * - YVF_OWNER defaults to the deployer if omitted.
 * - The script deploys the implementation, proxy, ProxyAdmin, and initializes the beacon inside the factory.
 * - The output includes the factory proxy, ProxyAdmin, beacon, and current YieldVault implementation addresses.
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
      getOptionalAddress(process.env.YVF_OWNER, "owner address") ??
      deployer.account.address;

    console.log(`[deploy-yvf] network=${connection.networkName}`);
    console.log(`[deploy-yvf] deployer=${deployer.account.address}`);
    console.log(`[deploy-yvf] owner=${owner}`);

    const factoryArtifact = await artifacts.readArtifact("YieldVaultFactory");
    const proxyArtifact = await artifacts.readArtifact("TransparentUpgradeableProxy");
    const implementation = await connection.viem.deployContract("YieldVaultFactory", [], {
      client: {
        wallet: deployer,
      },
    });

    console.log(`[deploy-yvf] implementation=${implementation.address}`);

    const initData = encodeFunctionData({
      abi: factoryArtifact.abi,
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
    const factory = await connection.viem.getContractAt("YieldVaultFactory", proxy.address, {
      client: {
        wallet: deployer,
      },
    });
    const beacon = await factory.read.beacon();
    const currentImplementation = await factory.read.currentImplementation();

    console.log("[deploy-yvf] deployment complete");
    console.log(`[deploy-yvf] factory=${factory.address}`);
    console.log(`[deploy-yvf] proxy=${proxy.address}`);
    console.log(`[deploy-yvf] proxyAdmin=${proxyAdmin.address}`);
    console.log(`[deploy-yvf] beacon=${beacon}`);
    console.log(`[deploy-yvf] yieldVaultImplementation=${currentImplementation}`);
    console.log(`[deploy-yvf] txHash=${deploymentTransaction.hash}`);
  } finally {
    await connection.close();
  }
}

main().catch((error) => {
  console.error("[deploy-yvf] deployment failed");
  console.error(error);
  process.exitCode = 1;
});
