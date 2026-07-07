import { task } from "hardhat/config";
import { encodeFunctionData, formatUnits, isAddress, type Address } from "viem";

import { Mainnet, TESTNET } from "../contants/index.js";

const ERC20_METADATA_ABI = [
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
] as const;

function getRequiredAddress(value: string | undefined, label: string): Address {
  if (value === undefined || value === "") {
    throw new Error(`Missing required ${label}`);
  }

  if (!isAddress(value)) {
    throw new Error(`Invalid ${label}: ${value}`);
  }

  return value;
}

function getRequiredBigInt(value: string | undefined, label: string): bigint {
  if (value === undefined || value.trim() === "") {
    throw new Error(`Missing required ${label}`);
  }

  return BigInt(value);
}

function getOptionalAddress(value: string | undefined, label: string): Address | undefined {
  if (value === undefined || value === "") {
    return undefined;
  }

  if (!isAddress(value)) {
    throw new Error(`Invalid ${label}: ${value}`);
  }

  return value;
}

function getNetworkStPros(networkName: string): Address | undefined {
  if (networkName === "mainnet") {
    return Mainnet.STPROS;
  }

  if (networkName === "testnet") {
    return TESTNET.STPROS;
  }

  return undefined;
}

function getNetworkSlp(networkName: string): Address | undefined {
  if (networkName === "testnet") {
    return TESTNET.SLP as Address;
  }

  return undefined;
}

function getNetworkBridgeVault(networkName: string): Address | undefined {
  if (networkName === "testnet") {
    return TESTNET.BRIDGE_VAULT as Address;
  }

  return undefined;
}

function getNetworkProxyAdmin(networkName: string): Address | undefined {
  if (networkName === "mainnet") {
    return "0x4238ea4adfa2bd6a5fc9b5e245dc1900cf0258aa";
  }

  if (networkName === "testnet") {
    return "0x79d6028229f2d819a1a4bb52a05bc97f5f37d667";
  }

  return undefined;
}

export const stProsSetOracleTask = task(
  "stpros:set-oracle",
  "Set oracle address for a StPROS proxy",
)
  /**
 * Current testnet deployment:
 * - stPROS: 0x5Dc91D0b17f1c5c60cAF2eAA7D93840Ce488dbB4
 * - asset:  0x838800b758277CC111B2d48Ab01e5E164f8E9471
 */

/**
   * Usage:
   * pnpm hardhat stpros:set-oracle --network testnet <stProsAddress> <oracleAddress>
   *
   * Example:
   * pnpm hardhat stpros:set-oracle --network testnet \
 *   0x5Dc91D0b17f1c5c60cAF2eAA7D93840Ce488dbB4 \
 *   <oracleAddress>
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
    const connection = await hre.network.getOrCreate();

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

export const stProsPreviewDepositTask = task(
  "stpros:preview-deposit",
  "Preview StPROS shares minted for a deposit amount",
)
  /**
   * Usage:
   * pnpm hardhat stpros:preview-deposit --network testnet <stProsAddress> <assets>
   *
   * Example:
   * pnpm hardhat stpros:preview-deposit --network testnet \
 *   0x5Dc91D0b17f1c5c60cAF2eAA7D93840Ce488dbB4 \
   *   1000000000000000000
   *
   * Notes:
 * - Current asset on testnet: 0x838800b758277CC111B2d48Ab01e5E164f8E9471
   * - assets must be passed in raw asset units.
   * - 1000000000000000000 means 1 token when decimals = 18.
   */
  .addPositionalArgument({
    name: "stPros",
    description: "StPROS proxy address",
  })
  .addPositionalArgument({
    name: "assets",
    description: "Asset amount in raw units",
  })
  .setInlineAction(async ({ stPros, assets }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const stProsAddress = getRequiredAddress(stPros, "stPros address");
      const assetsAmount = getRequiredBigInt(assets, "assets amount");
      const stProsContract = await connection.viem.getContractAt("StPROS", stProsAddress);
      const assetAddress = await stProsContract.read.asset();
      const shareDecimals = await stProsContract.read.decimals();
      const assetDecimals = await publicClient.readContract({
        address: assetAddress,
        abi: ERC20_METADATA_ABI,
        functionName: "decimals",
      });
      const shares = await stProsContract.read.previewDeposit([assetsAmount]);

      console.log(`[stpros:preview-deposit] stPROS=${stProsAddress}`);
      console.log(`[stpros:preview-deposit] asset=${assetAddress}`);
      console.log(`[stpros:preview-deposit] assetsRaw=${assetsAmount}`);
      console.log(
        `[stpros:preview-deposit] assetsFormatted=${formatUnits(assetsAmount, assetDecimals)}`,
      );
      console.log(`[stpros:preview-deposit] sharesRaw=${shares}`);
      console.log(
        `[stpros:preview-deposit] sharesFormatted=${formatUnits(shares, shareDecimals)}`,
      );
    } finally {
      await connection.close();
    }
  })
  .build();

export const stProsPreviewWithdrawTask = task(
  "stpros:preview-withdraw",
  "Preview StPROS shares burned for a withdraw amount",
)
  /**
   * Usage:
   * pnpm hardhat stpros:preview-withdraw --network testnet <stProsAddress> <assets>
   *
   * Example:
   * pnpm hardhat stpros:preview-withdraw --network testnet \
 *   0x5Dc91D0b17f1c5c60cAF2eAA7D93840Ce488dbB4 \
   *   1000000000000000000
   *
   * Notes:
 * - Current asset on testnet: 0x838800b758277CC111B2d48Ab01e5E164f8E9471
   * - assets must be passed in raw asset units.
   * - 1000000000000000000 means 1 token when decimals = 18.
   */
  .addPositionalArgument({
    name: "stPros",
    description: "StPROS proxy address",
  })
  .addPositionalArgument({
    name: "assets",
    description: "Asset amount in raw units",
  })
  .setInlineAction(async ({ stPros, assets }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const stProsAddress = getRequiredAddress(stPros, "stPros address");
      const assetsAmount = getRequiredBigInt(assets, "assets amount");
      const stProsContract = await connection.viem.getContractAt("StPROS", stProsAddress);
      const assetAddress = await stProsContract.read.asset();
      const shareDecimals = await stProsContract.read.decimals();
      const assetDecimals = await publicClient.readContract({
        address: assetAddress,
        abi: ERC20_METADATA_ABI,
        functionName: "decimals",
      });
      const shares = await stProsContract.read.previewWithdraw([assetsAmount]);

      console.log(`[stpros:preview-withdraw] stPROS=${stProsAddress}`);
      console.log(`[stpros:preview-withdraw] asset=${assetAddress}`);
      console.log(`[stpros:preview-withdraw] assetsRaw=${assetsAmount}`);
      console.log(
        `[stpros:preview-withdraw] assetsFormatted=${formatUnits(assetsAmount, assetDecimals)}`,
      );
      console.log(`[stpros:preview-withdraw] sharesRaw=${shares}`);
      console.log(
        `[stpros:preview-withdraw] sharesFormatted=${formatUnits(shares, shareDecimals)}`,
      );
    } finally {
      await connection.close();
    }
  })
  .build();

export const stProsDepositWithProsTask = task(
  "stpros:deposit-with-pros",
  "Deposit native PROS into StPROS through depositWithPROS",
)
  /**
   * Usage:
   * pnpm hardhat stpros:deposit-with-pros --network testnet <stProsAddress> <amount>
   *
   * Example:
   * pnpm hardhat stpros:deposit-with-pros --network testnet \
   *   0x5Dc91D0b17f1c5c60cAF2eAA7D93840Ce488dbB4 \
   *   1000000000000000000
   *
   * Notes:
   * - amount must be passed in raw native-token units.
   * - 1000000000000000000 means 1 PROS when decimals = 18.
   * - The caller pays native PROS as transaction value.
   */
  .addPositionalArgument({
    name: "stPros",
    description: "StPROS proxy address",
  })
  .addPositionalArgument({
    name: "amount",
    description: "Native PROS amount in raw units",
  })
  .setInlineAction(async ({ stPros, amount }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const stProsAddress = getRequiredAddress(stPros, "stPros address");
      const amountRaw = getRequiredBigInt(amount, "amount");
      const stProsContract = await connection.viem.getContractAt("StPROS", stProsAddress, {
        client: {
          wallet: signer,
        },
      });
      const [assetAddress, shareDecimals, expectedShares] = await Promise.all([
        stProsContract.read.asset(),
        stProsContract.read.decimals(),
        stProsContract.read.previewDeposit([amountRaw]),
      ]);
      const assetDecimals = await publicClient.readContract({
        address: assetAddress,
        abi: ERC20_METADATA_ABI,
        functionName: "decimals",
      });
      const hash = await stProsContract.write.depositWithPROS({
        value: amountRaw,
      });

      await publicClient.waitForTransactionReceipt({ hash });

      console.log(`[stpros:deposit-with-pros] stPROS=${stProsAddress}`);
      console.log(`[stpros:deposit-with-pros] asset=${assetAddress}`);
      console.log(`[stpros:deposit-with-pros] caller=${signer.account.address}`);
      console.log(`[stpros:deposit-with-pros] amountRaw=${amountRaw}`);
      console.log(
        `[stpros:deposit-with-pros] amountFormatted=${formatUnits(amountRaw, assetDecimals)}`,
      );
      console.log(`[stpros:deposit-with-pros] expectedSharesRaw=${expectedShares}`);
      console.log(
        `[stpros:deposit-with-pros] expectedSharesFormatted=${formatUnits(expectedShares, shareDecimals)}`,
      );
      console.log(`[stpros:deposit-with-pros] txHash=${hash}`);
    } finally {
      await connection.close();
    }
  })
  .build();

const PROXY_ADMIN_UPGRADE_AND_CALL_ABI = [
  {
    type: "function",
    name: "upgradeAndCall",
    stateMutability: "payable",
    inputs: [
      { name: "proxy", type: "address" },
      { name: "implementation", type: "address" },
      { name: "data", type: "bytes" },
    ],
    outputs: [],
  },
] as const;

const STPROS_INITIALIZE_V2_ABI = [
  {
    type: "function",
    name: "initializeV2",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_slp", type: "address" },
      { name: "_bridgeVault", type: "address" },
    ],
    outputs: [],
  },
] as const;

export const stProsUpgradeV2Task = task(
  "stpros:upgrade-v2",
  "Print calldata for upgrading StPROS and calling initializeV2 atomically",
)
  /**
   * Usage:
   * pnpm hardhat stpros:upgrade-v2 --network mainnet \
   *   <stProsProxy> <newImplementation> <slp> <bridgeVault>
   *
   * Owner multisig one-shot:
   * 1) oracle.setVToken(stProsProxy, true)
   * 2) ProxyAdmin.upgradeAndCall(stProsProxy, implementation, initializeV2(slp, bridgeVault))
   *    initializeV2 seeds oracle pool info from totalSupply() and the current oracle rate
   */
  .addPositionalArgument({
    name: "stProsProxy",
    description: "StPROS transparent proxy address",
  })
  .addPositionalArgument({
    name: "implementation",
    description: "New StPROS implementation address",
  })
  .addPositionalArgument({
    name: "slp",
    description: "SLP address that receives unwrapped PROS",
  })
  .addPositionalArgument({
    name: "bridgeVault",
    description: "BridgeVault address that funds redemptions",
  })
  .addOption({
    name: "proxyAdmin",
    description: "ProxyAdmin contract address",
    defaultValue: "0x4238ea4adfa2bd6a5fc9b5e245dc1900cf0258aa",
  })
  .setAction(async (taskArgs, hre) => {
    const connection = await hre.network.connect();

    const stProsProxy = getRequiredAddress(taskArgs.stProsProxy, "stProsProxy");
    const implementation = getRequiredAddress(taskArgs.implementation, "implementation");
    const slp = getRequiredAddress(taskArgs.slp, "slp");
    const bridgeVault = getRequiredAddress(taskArgs.bridgeVault, "bridgeVault");
    const proxyAdmin = getRequiredAddress(taskArgs.proxyAdmin, "proxyAdmin");

    const initData = encodeFunctionData({
      abi: STPROS_INITIALIZE_V2_ABI,
      functionName: "initializeV2",
      args: [slp, bridgeVault],
    });

    const upgradeAndCallData = encodeFunctionData({
      abi: PROXY_ADMIN_UPGRADE_AND_CALL_ABI,
      functionName: "upgradeAndCall",
      args: [stProsProxy, implementation, initData],
    });

    console.log(`[stpros:upgrade-v2] stProsProxy=${stProsProxy}`);
    console.log(`[stpros:upgrade-v2] implementation=${implementation}`);
    console.log(`[stpros:upgrade-v2] slp=${slp}`);
    console.log(`[stpros:upgrade-v2] bridgeVault=${bridgeVault}`);
    console.log(`[stpros:upgrade-v2] proxyAdmin=${proxyAdmin}`);
    console.log(`[stpros:upgrade-v2] initializeV2Calldata=${initData}`);
    console.log(`[stpros:upgrade-v2] upgradeAndCallCalldata=${upgradeAndCallData}`);
    console.log(
      "[stpros:upgrade-v2] multisig tx.to=ProxyAdmin function=upgradeAndCall(proxy, implementation, initializeV2Data)",
    );

    await connection.close();
  })
  .build();

export const stProsExecuteUpgradeV2Task = task(
  "stpros:execute-upgrade-v2",
  "Upgrade StPROS via ProxyAdmin.upgradeAndCall and initializeV2",
)
  /**
   * Usage (testnet defaults from contants/index.ts):
   * pnpm hardhat stpros:execute-upgrade-v2 --network testnet <implementation>
   *
   * Full override:
   * pnpm hardhat stpros:execute-upgrade-v2 --network testnet \
   *   <implementation> \
   *   --st-pros 0xb1437aeea18189eb6d02dc46cd4d28613d582e9a \
   *   --slp 0x464017CDC3c2af2b5B525FDe03Ac93F15172Db43 \
   *   --bridge-vault 0xb79db65038a11fa8f5a361e5ff265842b3619ddc \
   *   --proxy-admin 0x79d6028229f2d819a1a4bb52a05bc97f5f37d667
   *
   * Requires ProxyAdmin owner signer. Run after oracle:execute-upgrade-v2.
   */
  .addPositionalArgument({
    name: "implementation",
    description: "New StPROS implementation address",
  })
  .addOption({
    name: "stPros",
    description: "StPROS proxy address; defaults to contants/index.ts on mainnet/testnet",
    defaultValue: "",
  })
  .addOption({
    name: "slp",
    description: "SLP address; defaults to TESTNET.SLP on testnet",
    defaultValue: "",
  })
  .addOption({
    name: "bridgeVault",
    description: "BridgeVault address; defaults to TESTNET.BRIDGE_VAULT on testnet",
    defaultValue: "",
  })
  .addOption({
    name: "proxyAdmin",
    description: "ProxyAdmin contract address",
    defaultValue: "",
  })
  .setInlineAction(async (taskArgs, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const networkName = connection.networkName;
      const implementation = getRequiredAddress(taskArgs.implementation, "implementation");
      const stProsProxy =
        getOptionalAddress(taskArgs.stPros, "stPros address")
        ?? getNetworkStPros(networkName);
      const slp =
        getOptionalAddress(taskArgs.slp, "slp address")
        ?? getNetworkSlp(networkName);
      const bridgeVault =
        getOptionalAddress(taskArgs.bridgeVault, "bridgeVault address")
        ?? getNetworkBridgeVault(networkName);
      const proxyAdmin =
        getOptionalAddress(taskArgs.proxyAdmin, "proxyAdmin address")
        ?? getNetworkProxyAdmin(networkName);

      if (stProsProxy === undefined) {
        throw new Error("Missing stPros proxy. Pass --st-pros or use mainnet/testnet.");
      }

      if (slp === undefined) {
        throw new Error("Missing slp address. Pass --slp or use testnet defaults.");
      }

      if (bridgeVault === undefined) {
        throw new Error("Missing bridgeVault address. Pass --bridge-vault or use testnet defaults.");
      }

      if (proxyAdmin === undefined) {
        throw new Error("Missing proxyAdmin address. Pass --proxy-admin or use mainnet/testnet.");
      }

      const initData = encodeFunctionData({
        abi: STPROS_INITIALIZE_V2_ABI,
        functionName: "initializeV2",
        args: [slp, bridgeVault],
      });

      const proxyAdminContract = await connection.viem.getContractAt(
        "ProxyAdmin",
        proxyAdmin,
        {
          client: {
            wallet: signer,
          },
        },
      );
      const publicClient = await connection.viem.getPublicClient();
      const proxyAdminOwner = await proxyAdminContract.read.owner();

      if (proxyAdminOwner.toLowerCase() !== signer.account.address.toLowerCase()) {
        throw new Error(
          `Signer ${signer.account.address} is not ProxyAdmin owner ${proxyAdminOwner}`,
        );
      }

      const hash = await proxyAdminContract.write.upgradeAndCall([
        stProsProxy,
        implementation,
        initData,
      ]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const stProsContract = await connection.viem.getContractAt("StPROS", stProsProxy);
      const [slpOnChain, bridgeVaultOnChain, totalCanWithdrawAmount] = await Promise.all([
        stProsContract.read.slp(),
        stProsContract.read.bridgeVault(),
        stProsContract.read.totalCanWithdrawAmount(),
      ]);

      console.log(`[stpros:execute-upgrade-v2] stProsProxy=${stProsProxy}`);
      console.log(`[stpros:execute-upgrade-v2] implementation=${implementation}`);
      console.log(`[stpros:execute-upgrade-v2] proxyAdmin=${proxyAdmin}`);
      console.log(`[stpros:execute-upgrade-v2] caller=${signer.account.address}`);
      console.log(`[stpros:execute-upgrade-v2] slp=${slpOnChain}`);
      console.log(`[stpros:execute-upgrade-v2] bridgeVault=${bridgeVaultOnChain}`);
      console.log(`[stpros:execute-upgrade-v2] totalCanWithdrawAmount=${totalCanWithdrawAmount}`);
      console.log(`[stpros:execute-upgrade-v2] initializeV2Calldata=${initData}`);
      console.log(`[stpros:execute-upgrade-v2] txHash=${hash}`);
      console.log(`[stpros:execute-upgrade-v2] blockNumber=${receipt.blockNumber}`);
    } finally {
      await connection.close();
    }
  })
  .build();
