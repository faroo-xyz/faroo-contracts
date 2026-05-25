import { task } from "hardhat/config";
import { isAddress, parseEventLogs, type Address } from "viem";

type YieldVaultInitParams = {
  asset: Address;
  factory: Address;
  admin: Address;
  counterparty: Address;
  feeRecipient: Address;
  name: string;
  symbol: string;
  lockDuration: bigint;
  subscriptionStartAt: bigint;
  subscriptionWindow: bigint;
  epochCap: bigint;
  perAddressCap: bigint;
  minSubscription: bigint;
  performanceFeeBps: bigint;
  settleTimelockWindow: bigint;
};

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

function getOptionalBigInt(
  cliValue: string | undefined,
  label: string,
): bigint | undefined {
  const rawValue = cliValue;

  if (rawValue === undefined || rawValue === "") {
    return undefined;
  }

  if (typeof rawValue === "bigint") {
    return rawValue;
  }

  if (typeof rawValue === "number") {
    if (!Number.isInteger(rawValue) || rawValue < 0) {
      throw new Error(`Invalid ${label}: ${rawValue}`);
    }

    return BigInt(rawValue);
  }

  if (typeof rawValue === "string") {
    if (rawValue.trim() === "") {
      throw new Error(`Invalid ${label}: empty string`);
    }

    return BigInt(rawValue);
  }

  throw new Error(`Invalid ${label}: ${String(rawValue)}`);
}

function getRequiredBigInt(
  cliValue: string | undefined,
  label: string,
): bigint {
  const value = getOptionalBigInt(cliValue, label);

  if (value === undefined) {
    throw new Error(`Missing required ${label}`);
  }

  return value;
}

function resolveCreateYieldVaultParams(
  taskArgs: {
    factory: string;
    asset: string | undefined;
    admin: string | undefined;
    counterparty: string | undefined;
    feeRecipient: string | undefined;
    name: string | undefined;
    symbol: string | undefined;
    lockDuration: string | undefined;
    subscriptionStartAt: string | undefined;
    subscriptionWindow: string | undefined;
    epochCap: string | undefined;
    perAddressCap: string | undefined;
    minSubscription: string | undefined;
    performanceFeeBps: string | undefined;
    settleTimelockWindow: string | undefined;
  },
  signerAddress: Address,
): YieldVaultInitParams {
  const factory = getRequiredAddress(taskArgs.factory, "factory address");

  return {
    asset: getRequiredAddress(taskArgs.asset, "asset address"),
    factory,
    admin: getOptionalAddress(taskArgs.admin, "admin address") ?? signerAddress,
    counterparty: getRequiredAddress(taskArgs.counterparty, "counterparty address"),
    feeRecipient: getRequiredAddress(taskArgs.feeRecipient, "feeRecipient address"),
    name: (() => {
      const value = taskArgs.name;

      if (value === undefined || value === "") {
        throw new Error("Missing required name");
      }

      return value;
    })(),
    symbol: (() => {
      const value = taskArgs.symbol;

      if (value === undefined || value === "") {
        throw new Error("Missing required symbol");
      }

      return value;
    })(),
    lockDuration: getRequiredBigInt(taskArgs.lockDuration, "lockDuration"),
    subscriptionStartAt: getRequiredBigInt(
      taskArgs.subscriptionStartAt,
      "subscriptionStartAt",
    ),
    subscriptionWindow: getRequiredBigInt(
      taskArgs.subscriptionWindow,
      "subscriptionWindow",
    ),
    epochCap: getRequiredBigInt(taskArgs.epochCap, "epochCap"),
    perAddressCap: getRequiredBigInt(taskArgs.perAddressCap, "perAddressCap"),
    minSubscription: getRequiredBigInt(taskArgs.minSubscription, "minSubscription"),
    performanceFeeBps: getRequiredBigInt(
      taskArgs.performanceFeeBps,
      "performanceFeeBps",
    ),
    settleTimelockWindow: getRequiredBigInt(
      taskArgs.settleTimelockWindow,
      "settleTimelockWindow",
    ),
  };
}

export const yvfAddCounterpartyTask = task(
  "yvf:add-counterparty",
  "Add a counterparty to YieldVaultFactory whitelist",
)
  /**
   * Usage:
   * pnpm hardhat yvf:add-counterparty --network testnet 0xc096F8e4B1cc222899752a5504fDE557A147c57b <counterpartyAddress>
   *
   * Example:
   * pnpm hardhat yvf:add-counterparty --network testnet \
   *   0xFactoryProxyAddress \
   *   0xCounterpartyAddress
   */
  .addPositionalArgument({
    name: "factory",
    description: "YieldVaultFactory proxy address",
  })
  .addPositionalArgument({
    name: "counterparty",
    description: "Counterparty address to whitelist",
  })
  .setInlineAction(async ({ factory, counterparty }, hre) => {
    const connection = await hre.network.connect();

    try {
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const factoryAddress = getRequiredAddress(factory, "factory address");
      const counterpartyAddress = getRequiredAddress(
        counterparty,
        "counterparty address",
      );

      const factoryContract = await connection.viem.getContractAt(
        "YieldVaultFactory",
        factoryAddress,
        {
          client: {
            wallet: signer,
          },
        },
      );

      const hash = await factoryContract.write.addCounterpartyToWhitelist([
        counterpartyAddress,
      ]);
      const publicClient = await connection.viem.getPublicClient();

      await publicClient.waitForTransactionReceipt({ hash });

      console.log(`[yvf:add-counterparty] factory=${factoryAddress}`);
      console.log(`[yvf:add-counterparty] counterparty=${counterpartyAddress}`);
      console.log(`[yvf:add-counterparty] txHash=${hash}`);
    } finally {
      await connection.close();
    }
  })
  .build();

export const yvfRemoveCounterpartyTask = task(
  "yvf:remove-counterparty",
  "Remove a counterparty from YieldVaultFactory whitelist",
)
  /**
   * Usage:
   * pnpm hardhat yvf:remove-counterparty --network testnet 0xc096F8e4B1cc222899752a5504fDE557A147c57b <counterpartyAddress>
   *
   * Example:
   * pnpm hardhat yvf:remove-counterparty --network testnet \
   *   0xFactoryProxyAddress \
   *   0xCounterpartyAddress
   */
  .addPositionalArgument({
    name: "factory",
    description: "YieldVaultFactory proxy address",
  })
  .addPositionalArgument({
    name: "counterparty",
    description: "Counterparty address to remove",
  })
  .setInlineAction(async ({ factory, counterparty }, hre) => {
    const connection = await hre.network.connect();

    try {
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const factoryAddress = getRequiredAddress(factory, "factory address");
      const counterpartyAddress = getRequiredAddress(
        counterparty,
        "counterparty address",
      );

      const factoryContract = await connection.viem.getContractAt(
        "YieldVaultFactory",
        factoryAddress,
        {
          client: {
            wallet: signer,
          },
        },
      );

      const hash = await factoryContract.write.removeCounterpartyFromWhitelist([
        counterpartyAddress,
      ]);
      const publicClient = await connection.viem.getPublicClient();

      await publicClient.waitForTransactionReceipt({ hash });

      console.log(`[yvf:remove-counterparty] factory=${factoryAddress}`);
      console.log(`[yvf:remove-counterparty] counterparty=${counterpartyAddress}`);
      console.log(`[yvf:remove-counterparty] txHash=${hash}`);
    } finally {
      await connection.close();
    }
  })
  .build();

export const yvfCreateTask = task(
  "yvf:create",
  "Create a YieldVault from a factory proxy",
)
  /**
   * Usage:
   * pnpm hardhat yvf:create --network testnet 0xc096F8e4B1cc222899752a5504fDE557A147c57b \
   *   --asset 0x5Dc91D0b17f1c5c60cAF2eAA7D93840Ce488dbB4 \
   *   --admin <adminAddress> \
   *   --counterparty <counterpartyAddress> \
   *   --feeRecipient <feeRecipientAddress> \
   *   --name "Faroo Yield Vault 001" \
   *   --symbol "FYV001" \
   *   --lockDuration 2592000 \
   *   --subscriptionStartAt 1748188800 \
   *   --subscriptionWindow 604800 \
   *   --epochCap 1000000000000000000000 \
   *   --perAddressCap 100000000000000000000 \
   *   --minSubscription 1000000000000000000 \
   *   --performanceFeeBps 1000 \
   *   --settleTimelockWindow 86400
   *
   * Notes:
   * - factory is the YieldVaultFactory proxy address.
   * - asset is usually the deployed stPROS proxy address.
   * - admin defaults to the current signer if omitted.
   * - numeric values should be passed in raw integer form.
   */
  .addPositionalArgument({
    name: "factory",
    description: "YieldVaultFactory proxy address",
  })
  .addOption({
    name: "asset",
    description: "stPROS asset address",
    defaultValue: "",
  })
  .addOption({
    name: "admin",
    description: "Vault admin address, defaults to signer",
    defaultValue: "",
  })
  .addOption({
    name: "counterparty",
    description: "Counterparty address",
    defaultValue: "",
  })
  .addOption({
    name: "feeRecipient",
    description: "Performance fee recipient address",
    defaultValue: "",
  })
  .addOption({
    name: "name",
    description: "Vault token name",
    defaultValue: "",
  })
  .addOption({
    name: "symbol",
    description: "Vault token symbol",
    defaultValue: "",
  })
  .addOption({
    name: "lockDuration",
    description: "Lock duration in seconds",
    defaultValue: "",
  })
  .addOption({
    name: "subscriptionStartAt",
    description: "Subscription start timestamp",
    defaultValue: "",
  })
  .addOption({
    name: "subscriptionWindow",
    description: "Subscription window in seconds",
    defaultValue: "",
  })
  .addOption({
    name: "epochCap",
    description: "Epoch cap in asset units",
    defaultValue: "",
  })
  .addOption({
    name: "perAddressCap",
    description: "Per-address cap in asset units",
    defaultValue: "",
  })
  .addOption({
    name: "minSubscription",
    description: "Minimum subscription amount",
    defaultValue: "",
  })
  .addOption({
    name: "performanceFeeBps",
    description: "Performance fee in basis points",
    defaultValue: "",
  })
  .addOption({
    name: "settleTimelockWindow",
    description: "Settlement timelock window in seconds",
    defaultValue: "",
  })
  .setInlineAction(async (taskArgs, hre) => {
    const connection = await hre.network.connect();

    try {
      const [signer] = await connection.viem.getWalletClients();

      if (signer?.account?.address === undefined) {
        throw new Error("No signer account available for the selected network");
      }

      const params = resolveCreateYieldVaultParams(
        taskArgs as Parameters<typeof resolveCreateYieldVaultParams>[0],
        signer.account.address,
      );
      const factoryArtifact = await hre.artifacts.readArtifact("YieldVaultFactory");
      const factoryContract = await connection.viem.getContractAt(
        "YieldVaultFactory",
        params.factory,
        {
          client: {
            wallet: signer,
          },
        },
      );
      const hash = await factoryContract.write.createYieldVault([params]);
      const publicClient = await connection.viem.getPublicClient();
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const [createdLog] = parseEventLogs({
        abi: factoryArtifact.abi,
        logs: receipt.logs,
        eventName: "YieldVaultCreated",
        strict: false,
      });
      const vaultAddress = createdLog?.args.proxy as Address | undefined;

      console.log(`[yvf:create] factory=${params.factory}`);
      console.log(`[yvf:create] asset=${params.asset}`);
      console.log(`[yvf:create] admin=${params.admin}`);
      console.log(`[yvf:create] counterparty=${params.counterparty}`);
      console.log(`[yvf:create] feeRecipient=${params.feeRecipient}`);
      console.log(`[yvf:create] name=${params.name}`);
      console.log(`[yvf:create] symbol=${params.symbol}`);
      console.log(`[yvf:create] txHash=${hash}`);

      if (vaultAddress !== undefined) {
        console.log(`[yvf:create] vault=${vaultAddress}`);
      }
    } finally {
      await connection.close();
    }
  })
  .build();
