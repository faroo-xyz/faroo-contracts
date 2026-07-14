import { task } from "hardhat/config";
import { isAddress, type Address } from "viem";

import { Mainnet, TESTNET } from "../contants/index.js";

function getOptionalAddress(value: string | undefined, label: string): Address | undefined {
  if (value === undefined || value === "") {
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

function getRequiredBigInt(value: string | undefined, label: string): bigint {
  if (value === undefined || value.trim() === "") {
    throw new Error(`Missing required ${label}`);
  }

  return BigInt(value);
}

function getNetworkOracle(networkName: string): Address | undefined {
  if (networkName === "mainnet") {
    return Mainnet.ORACLE as Address;
  }

  if (networkName === "testnet") {
    return TESTNET.ORACLE as Address;
  }

  return undefined;
}

export const oracleSetPoolInfoTask = task(
  "oracle:set-pool-info",
  "Set Oracle pool conversion rate for a token (owner only)",
)
  /**
   * Usage:
   * pnpm hardhat oracle:set-pool-info --network mainnet <tokenAddress> <tokenAmount> <vTokenAmount>
   *
   * Example (1:1 rate for WPROS):
   * pnpm hardhat oracle:set-pool-info --network mainnet \
   *   0x52c48d4213107b20bc583832b0d951fb9ca8f0b0 \
   *   1000000000000000000 \
   *   1000000000000000000
   *
   * Example with explicit oracle proxy:
   * pnpm hardhat oracle:set-pool-info --network mainnet \
   *   0x52c48d4213107b20bc583832b0d951fb9ca8f0b0 \
   *   1000000000000000000 \
   *   1000000000000000000 \
   *   --oracle 0x051713fd66845a13bf23baca008c5c22c27ccb58
   *
   * Notes:
   * - Callable only by Oracle owner.
   * - tokenAmount and vTokenAmount are raw integer units.
   * - Setting either amount to 0 makes getVTokenAmountByToken / getTokenAmountByVToken fall back to 1:1.
   */
  .addPositionalArgument({
    name: "token",
    description: "Underlying token address used as the pool key",
  })
  .addPositionalArgument({
    name: "tokenAmount",
    description: "Token side of the conversion ratio, in raw units",
  })
  .addPositionalArgument({
    name: "vTokenAmount",
    description: "VToken side of the conversion ratio, in raw units",
  })
  .addOption({
    name: "oracle",
    description: "Oracle proxy address; defaults to contants/index.ts on mainnet/testnet",
    defaultValue: "",
  })
  .setInlineAction(async (taskArgs, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const token = getRequiredAddress(taskArgs.token, "token address");
      const tokenAmount = getRequiredBigInt(taskArgs.tokenAmount, "tokenAmount");
      const vTokenAmount = getRequiredBigInt(taskArgs.vTokenAmount, "vTokenAmount");
      const oracleAddress =
        getOptionalAddress(taskArgs.oracle, "oracle address")
        ?? getNetworkOracle(connection.networkName);

      if (oracleAddress === undefined) {
        throw new Error("Missing oracle address. Pass --oracle or use mainnet/testnet.");
      }

      const oracleContract = await connection.viem.getContractAt("Oracle", oracleAddress, {
        client: {
          wallet: signer,
        },
      });
      const [owner, previousPoolInfo] = await Promise.all([
        oracleContract.read.owner(),
        oracleContract.read.poolInfo([token]),
      ]);

      const hash = await oracleContract.write.setPoolInfo([token, tokenAmount, vTokenAmount]);
      const publicClient = await connection.viem.getPublicClient();
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const currentPoolInfo = await oracleContract.read.poolInfo([token]);

      console.log(`[oracle:set-pool-info] oracle=${oracleAddress}`);
      console.log(`[oracle:set-pool-info] caller=${signer.account.address}`);
      console.log(`[oracle:set-pool-info] owner=${owner}`);
      console.log(`[oracle:set-pool-info] token=${token}`);
      console.log(
        `[oracle:set-pool-info] previousPoolInfo tokenAmount=${previousPoolInfo[0]} vTokenAmount=${previousPoolInfo[1]}`,
      );
      console.log(`[oracle:set-pool-info] tokenAmount=${tokenAmount}`);
      console.log(`[oracle:set-pool-info] vTokenAmount=${vTokenAmount}`);
      console.log(
        `[oracle:set-pool-info] currentPoolInfo tokenAmount=${currentPoolInfo[0]} vTokenAmount=${currentPoolInfo[1]}`,
      );
      console.log(`[oracle:set-pool-info] txHash=${hash}`);
      console.log(`[oracle:set-pool-info] blockNumber=${receipt.blockNumber}`);
    } finally {
      await connection.close();
    }
  })
  .build();

export const oraclePoolInfoTask = task(
  "oracle:pool-info",
  "Read Oracle pool conversion rate for a token",
)
  /**
   * Usage:
   * pnpm hardhat oracle:pool-info --network mainnet <tokenAddress>
   */
  .addPositionalArgument({
    name: "token",
    description: "Underlying token address used as the pool key",
  })
  .addOption({
    name: "oracle",
    description: "Oracle proxy address; defaults to contants/index.ts on mainnet/testnet",
    defaultValue: "",
  })
  .setInlineAction(async (taskArgs, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const token = getRequiredAddress(taskArgs.token, "token address");
      const oracleAddress =
        getOptionalAddress(taskArgs.oracle, "oracle address")
        ?? getNetworkOracle(connection.networkName);

      if (oracleAddress === undefined) {
        throw new Error("Missing oracle address. Pass --oracle or use mainnet/testnet.");
      }

      const oracleContract = await connection.viem.getContractAt("Oracle", oracleAddress);
      const [owner, paused, poolInfo] = await Promise.all([
        oracleContract.read.owner(),
        oracleContract.read.paused(),
        oracleContract.read.poolInfo([token]),
      ]);

      console.log(`[oracle:pool-info] oracle=${oracleAddress}`);
      console.log(`[oracle:pool-info] owner=${owner}`);
      console.log(`[oracle:pool-info] paused=${paused}`);
      console.log(`[oracle:pool-info] token=${token}`);
      console.log(`[oracle:pool-info] tokenAmount=${poolInfo[0]}`);
      console.log(`[oracle:pool-info] vTokenAmount=${poolInfo[1]}`);
    } finally {
      await connection.close();
    }
  })
  .build();
