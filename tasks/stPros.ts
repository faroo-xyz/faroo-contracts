import { task } from "hardhat/config";
import { isAddress, type Address } from "viem";

function getRequiredAddress(value: string | undefined, label: string): Address {
  if (value === undefined || value === "") {
    throw new Error(`Missing required ${label}`);
  }

  if (!isAddress(value)) {
    throw new Error(`Invalid ${label}: ${value}`);
  }

  return value;
}

export const stProsSetOracleTask = task(
  "stpros:set-oracle",
  "Set oracle address for a StPROS proxy",
)
  /**
   * Usage:
   * pnpm hardhat stpros:set-oracle --network testnet <stProsAddress> <oracleAddress>
   *
   * Example:
   * pnpm hardhat stpros:set-oracle --network testnet \
   *   0xStPROSProxyAddress \
   *   0xOracleProxyAddress
   *
   * Notes:
   * - stProsAddress should be the StPROS proxy address.
   * - oracleAddress should be the Oracle proxy address.
   * - The caller must be the owner of StPROS.
   */
  .addPositionalArgument({
    name: "stPros",
    description: "StPROS proxy address",
  })
  .addPositionalArgument({
    name: "oracle",
    description: "Oracle proxy address",
  })
  .setInlineAction(async ({ stPros, oracle }, hre) => {
    const connection = await hre.network.connect();

    try {
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const stProsAddress = getRequiredAddress(stPros, "stPros address");
      const oracleAddress = getRequiredAddress(oracle, "oracle address");
      const stProsContract = await connection.viem.getContractAt(
        "StPROS",
        stProsAddress,
        {
          client: {
            wallet: signer,
          },
        },
      );
      const hash = await stProsContract.write.setOracle([oracleAddress]);
      const publicClient = await connection.viem.getPublicClient();

      await publicClient.waitForTransactionReceipt({ hash });

      console.log(`[stpros:set-oracle] stPROS=${stProsAddress}`);
      console.log(`[stpros:set-oracle] oracle=${oracleAddress}`);
      console.log(`[stpros:set-oracle] txHash=${hash}`);
    } finally {
      await connection.close();
    }
  })
  .build();
