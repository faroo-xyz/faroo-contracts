import { artifacts, network } from "hardhat";
import {
  encodeFunctionData,
  isAddress,
  parseEventLogs,
  type Address,
} from "viem";

/**
 * Usage:
 * STPROS_ASSET=<assetAddress> [STPROS_OWNER=<ownerAddress>] [STPROS_NAME=<name>] [STPROS_SYMBOL=<symbol>] \
 *   pnpm hardhat run scripts/deploy-stpros.ts --network testnet
 *
 * Example:
 * STPROS_ASSET=0x838800b758277CC111B2d48Ab01e5E164f8E9471 \
 * STPROS_OWNER=0xB50C9E6DdEDbb1046a6134ad731d5B80481571f3 \
 * pnpm hardhat run scripts/deploy-stpros.ts --network testnet
 *
 * Notes:
 * - STPROS_ASSET is required.
 * - STPROS_OWNER defaults to the deployer if omitted.
 * - STPROS_NAME defaults to "Faroo Staked PROS".
 * - STPROS_SYMBOL defaults to "stPROS".
 */
const DEFAULT_NAME = "Faroo Staked PROS";
const DEFAULT_SYMBOL = "stPROS";

function getOptionalAddress(value: string | undefined, label: string): Address | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!isAddress(value)) {
    throw new Error(`Invalid ${label}: ${value}`);
  }

  return value;
}

function getRequiredAddress(value: string | undefined, label: string): Address {
  const address = getOptionalAddress(value, label);

  if (address === undefined) {
    throw new Error(`Missing required ${label}`);
  }

  return address;
}

function printUsage(): void {
  console.log(`Usage:
  STPROS_ASSET=<address> [STPROS_OWNER=<address>] [STPROS_NAME=<string>] [STPROS_SYMBOL=<string>] pnpm hardhat run scripts/deploy-stpros.ts --network <network>

Environment fallbacks:
  STPROS_ASSET   required
  STPROS_OWNER   optional, defaults to deployer
  STPROS_NAME    optional, defaults to "${DEFAULT_NAME}"
  STPROS_SYMBOL  optional, defaults to "${DEFAULT_SYMBOL}"`);
}

async function main(): Promise<void> {
  if (process.argv.includes("--help")) {
    printUsage();
    return;
  }

  const connection = await network.connect();

  try {
    const [deployer] = await connection.viem.getWalletClients();

    if (deployer?.account?.address === undefined) {
      throw new Error("No deployer account available for the selected network");
    }

    const asset = getRequiredAddress(process.env.STPROS_ASSET, "asset address");
    const owner =
      getOptionalAddress(process.env.STPROS_OWNER, "owner address") ??
      deployer.account.address;
    const name = process.env.STPROS_NAME ?? DEFAULT_NAME;
    const symbol = process.env.STPROS_SYMBOL ?? DEFAULT_SYMBOL;

    console.log(`[deploy-stpros] network=${connection.networkName}`);
    console.log(`[deploy-stpros] deployer=${deployer.account.address}`);
    console.log(`[deploy-stpros] asset=${asset}`);
    console.log(`[deploy-stpros] owner=${owner}`);
    console.log(`[deploy-stpros] name=${name}`);
    console.log(`[deploy-stpros] symbol=${symbol}`);

    const stProsArtifact = await artifacts.readArtifact("StPROS");
    const proxyArtifact = await artifacts.readArtifact("TransparentUpgradeableProxy");

    const implementation = await connection.viem.deployContract("StPROS", [], {
      client: {
        wallet: deployer,
      },
    });

    console.log(`[deploy-stpros] implementation=${implementation.address}`);

    const initData = encodeFunctionData({
      abi: stProsArtifact.abi,
      functionName: "initialize",
      args: [asset, owner, name, symbol],
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
    const stPros = await connection.viem.getContractAt("StPROS", proxy.address, {
      client: {
        wallet: deployer,
      },
    });

    console.log("[deploy-stpros] deployment complete");
    console.log(`[deploy-stpros] stPROS=${stPros.address}`);
    console.log(`[deploy-stpros] proxy=${proxy.address}`);
    console.log(`[deploy-stpros] proxyAdmin=${proxyAdmin.address}`);
    console.log(`[deploy-stpros] implementation=${implementation.address}`);
    console.log(`[deploy-stpros] txHash=${deploymentTransaction.hash}`);
  } finally {
    await connection.close();
  }
}

main().catch((error) => {
  console.error("[deploy-stpros] deployment failed");
  console.error(error);
  process.exitCode = 1;
});
