import { task } from "hardhat/config";
import { isAddress, parseEventLogs, type Address } from "viem";

const MAX_PERFORMANCE_FEE_BPS = 10_000n;
const MIN_LOCK_DURATION = 86_400n;
const MIN_SETTLE_TIMELOCK = 86_400n;

type YieldVaultInitParams = {
  asset: Address;
  factory: Address;
  admin: Address;
  counterparty: Address;
  feeRecipient: Address;
  name: string;
  symbol: string;
  firstRound: {
    openWindow: bigint;
    lockDuration: bigint;
    settleTimelockWindow: bigint;
    roundCap: bigint;
    perAddressCap: bigint;
    minSubscription: bigint;
    performanceFeeBps: bigint;
  };
};

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

    const value = BigInt(rawValue);
    if (value < 0n) {
      throw new Error(`Invalid ${label}: ${rawValue}`);
    }

    return value;
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
  const openWindow = getRequiredBigInt(
    taskArgs.subscriptionWindow,
    "subscriptionWindow",
  );
  const lockDuration = getRequiredBigInt(taskArgs.lockDuration, "lockDuration");
  const settleTimelockWindow = getRequiredBigInt(
    taskArgs.settleTimelockWindow,
    "settleTimelockWindow",
  );
  const roundCap = getRequiredBigInt(taskArgs.epochCap, "epochCap");
  const perAddressCap = getRequiredBigInt(taskArgs.perAddressCap, "perAddressCap");
  const minSubscription = getRequiredBigInt(taskArgs.minSubscription, "minSubscription");
  const performanceFeeBps = getRequiredBigInt(
    taskArgs.performanceFeeBps,
    "performanceFeeBps",
  );

  if (
    openWindow === 0n ||
    lockDuration < MIN_LOCK_DURATION ||
    settleTimelockWindow < MIN_SETTLE_TIMELOCK ||
    roundCap === 0n ||
    minSubscription === 0n ||
    performanceFeeBps > MAX_PERFORMANCE_FEE_BPS
  ) {
    throw new Error(
      "Invalid round params: subscriptionWindow/epochCap/minSubscription must be > 0, " +
      `lockDuration >= ${MIN_LOCK_DURATION}, settleTimelockWindow >= ${MIN_SETTLE_TIMELOCK}, ` +
      `performanceFeeBps <= ${MAX_PERFORMANCE_FEE_BPS}`,
    );
  }

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
    firstRound: {
      openWindow,
      lockDuration,
      settleTimelockWindow,
      roundCap,
      perAddressCap,
      minSubscription,
      performanceFeeBps,
    },
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
    const connection = await hre.network.getOrCreate();

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
    const connection = await hre.network.getOrCreate();

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

export const yvfListProxiesTask = task(
  "yvf:list-proxies",
  "List all YieldVault proxy addresses created by the factory",
)
  /**
   * Usage:
   * pnpm hardhat yvf:list-proxies --network testnet 0xc096F8e4B1cc222899752a5504fDE557A147c57b
   *
   * Example:
   * pnpm hardhat yvf:list-proxies --network testnet \
   *   0xc096F8e4B1cc222899752a5504fDE557A147c57b
   */
  .addPositionalArgument({
    name: "factory",
    description: "YieldVaultFactory proxy address",
  })
  .setInlineAction(async ({ factory }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const factoryAddress = getRequiredAddress(factory, "factory address");
      const factoryContract = await connection.viem.getContractAt(
        "YieldVaultFactory",
        factoryAddress,
      );
      const [totalProxies, proxies] = await Promise.all([
        factoryContract.read.totalProxies(),
        factoryContract.read.getAllProxies(),
      ]);

      console.log(`[yvf:list-proxies] factory=${factoryAddress}`);
      console.log(`[yvf:list-proxies] total=${totalProxies}`);

      if (proxies.length === 0) {
        console.log("[yvf:list-proxies] proxies=none");
        return;
      }

      proxies.forEach((proxy, index) => {
        console.log(`[yvf:list-proxies] proxy[${index}]=${proxy}`);
      });
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
   * - lockDuration and settleTimelockWindow must each be at least 86400 seconds.
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
    name: "subscriptionWindow",
    description: "Open window in seconds",
    defaultValue: "",
  })
  .addOption({
    name: "epochCap",
    description: "Epoch cap in asset units",
    defaultValue: "",
  })
  .addOption({
    name: "perAddressCap",
    description: "Per-address subscription cap in asset units",
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
    const connection = await hre.network.getOrCreate();

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
      ) as any;
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
      console.log(`[yvf:create] firstRound.openWindow=${params.firstRound.openWindow}`);
      console.log(`[yvf:create] firstRound.lockDuration=${params.firstRound.lockDuration}`);
      console.log(`[yvf:create] firstRound.roundCap=${params.firstRound.roundCap}`);
      console.log(`[yvf:create] firstRound.perAddressCap=${params.firstRound.perAddressCap}`);
      console.log(`[yvf:create] firstRound.minSubscription=${params.firstRound.minSubscription}`);
      console.log(`[yvf:create] firstRound.performanceFeeBps=${params.firstRound.performanceFeeBps}`);
      console.log(`[yvf:create] firstRound.settleTimelockWindow=${params.firstRound.settleTimelockWindow}`);
      console.log(`[yvf:create] txHash=${hash}`);

      if (vaultAddress !== undefined) {
        console.log(`[yvf:create] vault=${vaultAddress}`);
      }
    } finally {
      await connection.close();
    }
  })
  .build();
