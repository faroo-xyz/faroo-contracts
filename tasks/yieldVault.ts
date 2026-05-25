import { task } from "hardhat/config";
import { formatUnits, isAddress, type Address } from "viem";

const ERC20_METADATA_ABI = [
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
] as const;

const FACTORY_PAUSED_ABI = [
  {
    type: "function",
    name: "paused",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

const DEFAULT_ADMIN_ROLE =
  "0x0000000000000000000000000000000000000000000000000000000000000000";
const PHASE_NAMES = [
  "SUBSCRIBING",
  "LOCKED",
  "SETTLE_PROPOSED",
  "SETTLED",
  "CANCELLED",
] as const;
const SETTLE_MODE_NAMES = ["PROFIT", "LOSS"] as const;

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

function getEnumName(names: readonly string[], index: number): string {
  return names[index] ?? `UNKNOWN(${index})`;
}

export const yieldVaultInfoTask = task(
  "yv:info",
  "Query core YieldVault state and configuration",
)
  /**
   * Usage:
   * pnpm hardhat yv:info --network testnet <vaultAddress>
   *
   * Example:
   * pnpm hardhat yv:info --network testnet \
   *   0xYourYieldVaultAddress
   */
  .addPositionalArgument({
    name: "vault",
    description: "YieldVault proxy address",
  })
  .setInlineAction(async ({ vault }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const vaultAddress = getRequiredAddress(vault, "vault address");
      const vaultContract = await connection.viem.getContractAt(
        "YieldVault",
        vaultAddress,
      );

      const [
        name,
        symbol,
        shareDecimals,
        assetAddress,
        factory,
        counterparty,
        feeRecipient,
        lockDuration,
        subscriptionWindow,
        epochCap,
        perAddressCap,
        minSubscription,
        performanceFeeBps,
        settleTimelockWindow,
        phase,
        settleMode,
        subscriptionStartedAt,
        subscriptionDeadline,
        lockedAt,
        settleProposedAt,
        settledAt,
        settleAmount,
        profitFunded,
        profitFunder,
        totalUserPrincipal,
        settledTotalShares,
        settledTotalClaimableAssets,
        settledFeeAmount,
        settledNetProfit,
        counterpartyClaimed,
        totalSupply,
        totalAssets,
        settlerRole,
      ] = await Promise.all([
        vaultContract.read.name(),
        vaultContract.read.symbol(),
        vaultContract.read.decimals(),
        vaultContract.read.asset(),
        vaultContract.read.factory(),
        vaultContract.read.counterparty(),
        vaultContract.read.feeRecipient(),
        vaultContract.read.lockDuration(),
        vaultContract.read.subscriptionWindow(),
        vaultContract.read.epochCap(),
        vaultContract.read.perAddressCap(),
        vaultContract.read.minSubscription(),
        vaultContract.read.performanceFeeBps(),
        vaultContract.read.settleTimelockWindow(),
        vaultContract.read.phase(),
        vaultContract.read.settleMode(),
        vaultContract.read.subscriptionStartedAt(),
        vaultContract.read.subscriptionDeadline(),
        vaultContract.read.lockedAt(),
        vaultContract.read.settleProposedAt(),
        vaultContract.read.settledAt(),
        vaultContract.read.settleAmount(),
        vaultContract.read.profitFunded(),
        vaultContract.read.profitFunder(),
        vaultContract.read.totalUserPrincipal(),
        vaultContract.read.settledTotalShares(),
        vaultContract.read.settledTotalClaimableAssets(),
        vaultContract.read.settledFeeAmount(),
        vaultContract.read.settledNetProfit(),
        vaultContract.read.counterpartyClaimed(),
        vaultContract.read.totalSupply(),
        vaultContract.read.totalAssets(),
        vaultContract.read.SETTLER_ROLE(),
      ]);

      const [assetDecimals, assetSymbol, factoryPaused, block] = await Promise.all([
        publicClient.readContract({
          address: assetAddress,
          abi: ERC20_METADATA_ABI,
          functionName: "decimals",
        }),
        publicClient.readContract({
          address: assetAddress,
          abi: ERC20_METADATA_ABI,
          functionName: "symbol",
        }),
        publicClient.readContract({
          address: factory,
          abi: FACTORY_PAUSED_ABI,
          functionName: "paused",
        }),
        publicClient.getBlock(),
      ]);

      console.log(`[yv:info] vault=${vaultAddress}`);
      console.log(`[yv:info] name=${name}`);
      console.log(`[yv:info] symbol=${symbol}`);
      console.log(`[yv:info] shareDecimals=${shareDecimals}`);
      console.log(`[yv:info] asset=${assetAddress}`);
      console.log(`[yv:info] assetSymbol=${assetSymbol}`);
      console.log(`[yv:info] assetDecimals=${assetDecimals}`);
      console.log(`[yv:info] factory=${factory}`);
      console.log(`[yv:info] factoryPaused=${factoryPaused}`);
      console.log(`[yv:info] counterparty=${counterparty}`);
      console.log(`[yv:info] feeRecipient=${feeRecipient}`);
      console.log(`[yv:info] phase=${phase} (${getEnumName(PHASE_NAMES, Number(phase))})`);
      console.log(
        `[yv:info] settleMode=${settleMode} (${getEnumName(SETTLE_MODE_NAMES, Number(settleMode))})`,
      );
      console.log(`[yv:info] currentTimestamp=${block.timestamp}`);
      console.log(`[yv:info] subscriptionStartedAt=${subscriptionStartedAt}`);
      console.log(`[yv:info] subscriptionDeadline=${subscriptionDeadline}`);
      console.log(`[yv:info] lockedAt=${lockedAt}`);
      console.log(`[yv:info] settleProposedAt=${settleProposedAt}`);
      console.log(`[yv:info] settledAt=${settledAt}`);
      console.log(`[yv:info] lockDuration=${lockDuration}`);
      console.log(`[yv:info] subscriptionWindow=${subscriptionWindow}`);
      console.log(`[yv:info] settleTimelockWindow=${settleTimelockWindow}`);
      console.log(`[yv:info] epochCapRaw=${epochCap}`);
      console.log(`[yv:info] epochCapFormatted=${formatUnits(epochCap, assetDecimals)}`);
      console.log(`[yv:info] perAddressCapRaw=${perAddressCap}`);
      console.log(
        `[yv:info] perAddressCapFormatted=${formatUnits(perAddressCap, assetDecimals)}`,
      );
      console.log(`[yv:info] minSubscriptionRaw=${minSubscription}`);
      console.log(
        `[yv:info] minSubscriptionFormatted=${formatUnits(minSubscription, assetDecimals)}`,
      );
      console.log(`[yv:info] performanceFeeBps=${performanceFeeBps}`);
      console.log(`[yv:info] profitFunded=${profitFunded}`);
      console.log(`[yv:info] profitFunder=${profitFunder}`);
      console.log(`[yv:info] settleAmountRaw=${settleAmount}`);
      console.log(
        `[yv:info] settleAmountFormatted=${formatUnits(settleAmount, assetDecimals)}`,
      );
      console.log(`[yv:info] totalUserPrincipalRaw=${totalUserPrincipal}`);
      console.log(
        `[yv:info] totalUserPrincipalFormatted=${formatUnits(totalUserPrincipal, assetDecimals)}`,
      );
      console.log(`[yv:info] totalSupplyRaw=${totalSupply}`);
      console.log(`[yv:info] totalSupplyFormatted=${formatUnits(totalSupply, shareDecimals)}`);
      console.log(`[yv:info] totalAssetsRaw=${totalAssets}`);
      console.log(
        `[yv:info] totalAssetsFormatted=${formatUnits(totalAssets, assetDecimals)}`,
      );
      console.log(`[yv:info] settledTotalSharesRaw=${settledTotalShares}`);
      console.log(
        `[yv:info] settledTotalSharesFormatted=${formatUnits(settledTotalShares, shareDecimals)}`,
      );
      console.log(
        `[yv:info] settledTotalClaimableAssetsRaw=${settledTotalClaimableAssets}`,
      );
      console.log(
        `[yv:info] settledTotalClaimableAssetsFormatted=${formatUnits(settledTotalClaimableAssets, assetDecimals)}`,
      );
      console.log(`[yv:info] settledFeeAmountRaw=${settledFeeAmount}`);
      console.log(
        `[yv:info] settledFeeAmountFormatted=${formatUnits(settledFeeAmount, assetDecimals)}`,
      );
      console.log(`[yv:info] settledNetProfitRaw=${settledNetProfit}`);
      console.log(
        `[yv:info] settledNetProfitFormatted=${formatUnits(settledNetProfit, assetDecimals)}`,
      );
      console.log(`[yv:info] counterpartyClaimed=${counterpartyClaimed}`);
      console.log(`[yv:info] settlerRole=${settlerRole}`);
    } finally {
      await connection.close();
    }
  })
  .build();

export const yieldVaultAccountTask = task(
  "yv:account",
  "Query a user account against a YieldVault",
)
  /**
   * Usage:
   * pnpm hardhat yv:account --network testnet <vaultAddress> <accountAddress>
   *
   * Example:
   * pnpm hardhat yv:account --network testnet \
   *   0xYourYieldVaultAddress \
   *   0xYourAccountAddress
   */
  .addPositionalArgument({
    name: "vault",
    description: "YieldVault proxy address",
  })
  .addPositionalArgument({
    name: "account",
    description: "User address",
  })
  .setInlineAction(async ({ vault, account }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const vaultAddress = getRequiredAddress(vault, "vault address");
      const accountAddress = getRequiredAddress(account, "account address");
      const vaultContract = await connection.viem.getContractAt(
        "YieldVault",
        vaultAddress,
      );
      const [assetAddress, shareDecimals, settlerRole] = await Promise.all([
        vaultContract.read.asset(),
        vaultContract.read.decimals(),
        vaultContract.read.SETTLER_ROLE(),
      ]);
      const [assetDecimals, assetSymbol] = await Promise.all([
        publicClient.readContract({
          address: assetAddress,
          abi: ERC20_METADATA_ABI,
          functionName: "decimals",
        }),
        publicClient.readContract({
          address: assetAddress,
          abi: ERC20_METADATA_ABI,
          functionName: "symbol",
        }),
      ]);
      const [
        shareBalance,
        userPrincipal,
        maxDeposit,
        maxMint,
        maxRedeem,
        maxWithdraw,
        isAdmin,
        isSettler,
      ] = await Promise.all([
        vaultContract.read.balanceOf([accountAddress]),
        vaultContract.read.userPrincipal([accountAddress]),
        vaultContract.read.maxDeposit([accountAddress]),
        vaultContract.read.maxMint([accountAddress]),
        vaultContract.read.maxRedeem([accountAddress]),
        vaultContract.read.maxWithdraw([accountAddress]),
        vaultContract.read.hasRole([DEFAULT_ADMIN_ROLE, accountAddress]),
        vaultContract.read.hasRole([settlerRole, accountAddress]),
      ]);

      console.log(`[yv:account] vault=${vaultAddress}`);
      console.log(`[yv:account] account=${accountAddress}`);
      console.log(`[yv:account] asset=${assetAddress}`);
      console.log(`[yv:account] assetSymbol=${assetSymbol}`);
      console.log(`[yv:account] shareBalanceRaw=${shareBalance}`);
      console.log(
        `[yv:account] shareBalanceFormatted=${formatUnits(shareBalance, shareDecimals)}`,
      );
      console.log(`[yv:account] userPrincipalRaw=${userPrincipal}`);
      console.log(
        `[yv:account] userPrincipalFormatted=${formatUnits(userPrincipal, assetDecimals)}`,
      );
      console.log(`[yv:account] maxDepositRaw=${maxDeposit}`);
      console.log(
        `[yv:account] maxDepositFormatted=${formatUnits(maxDeposit, assetDecimals)}`,
      );
      console.log(`[yv:account] maxMintRaw=${maxMint}`);
      console.log(`[yv:account] maxMintFormatted=${formatUnits(maxMint, shareDecimals)}`);
      console.log(`[yv:account] maxRedeemRaw=${maxRedeem}`);
      console.log(
        `[yv:account] maxRedeemFormatted=${formatUnits(maxRedeem, shareDecimals)}`,
      );
      console.log(`[yv:account] maxWithdrawRaw=${maxWithdraw}`);
      console.log(
        `[yv:account] maxWithdrawFormatted=${formatUnits(maxWithdraw, assetDecimals)}`,
      );
      console.log(`[yv:account] defaultAdmin=${isAdmin}`);
      console.log(`[yv:account] settler=${isSettler}`);
    } finally {
      await connection.close();
    }
  })
  .build();

export const yieldVaultPreviewDepositTask = task(
  "yv:preview-deposit",
  "Preview YieldVault shares minted for an asset deposit",
)
  /**
   * Usage:
   * pnpm hardhat yv:preview-deposit --network testnet <vaultAddress> <assets>
   *
   * Example:
   * pnpm hardhat yv:preview-deposit --network testnet \
   *   0xYourYieldVaultAddress \
   *   1000000000000000000
   */
  .addPositionalArgument({
    name: "vault",
    description: "YieldVault proxy address",
  })
  .addPositionalArgument({
    name: "assets",
    description: "Asset amount in raw units",
  })
  .setInlineAction(async ({ vault, assets }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const vaultAddress = getRequiredAddress(vault, "vault address");
      const assetsAmount = getRequiredBigInt(assets, "assets amount");
      const vaultContract = await connection.viem.getContractAt(
        "YieldVault",
        vaultAddress,
      );
      const [assetAddress, shareDecimals] = await Promise.all([
        vaultContract.read.asset(),
        vaultContract.read.decimals(),
      ]);
      const assetDecimals = await publicClient.readContract({
        address: assetAddress,
        abi: ERC20_METADATA_ABI,
        functionName: "decimals",
      });
      const shares = await vaultContract.read.previewDeposit([assetsAmount]);

      console.log(`[yv:preview-deposit] vault=${vaultAddress}`);
      console.log(`[yv:preview-deposit] asset=${assetAddress}`);
      console.log(`[yv:preview-deposit] assetsRaw=${assetsAmount}`);
      console.log(
        `[yv:preview-deposit] assetsFormatted=${formatUnits(assetsAmount, assetDecimals)}`,
      );
      console.log(`[yv:preview-deposit] sharesRaw=${shares}`);
      console.log(
        `[yv:preview-deposit] sharesFormatted=${formatUnits(shares, shareDecimals)}`,
      );
    } finally {
      await connection.close();
    }
  })
  .build();

export const yieldVaultPreviewWithdrawTask = task(
  "yv:preview-withdraw",
  "Preview YieldVault shares burned for an asset withdraw",
)
  /**
   * Usage:
   * pnpm hardhat yv:preview-withdraw --network testnet <vaultAddress> <assets>
   *
   * Example:
   * pnpm hardhat yv:preview-withdraw --network testnet \
   *   0xYourYieldVaultAddress \
   *   1000000000000000000
   */
  .addPositionalArgument({
    name: "vault",
    description: "YieldVault proxy address",
  })
  .addPositionalArgument({
    name: "assets",
    description: "Asset amount in raw units",
  })
  .setInlineAction(async ({ vault, assets }, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const publicClient = await connection.viem.getPublicClient();
      const vaultAddress = getRequiredAddress(vault, "vault address");
      const assetsAmount = getRequiredBigInt(assets, "assets amount");
      const vaultContract = await connection.viem.getContractAt(
        "YieldVault",
        vaultAddress,
      );
      const [assetAddress, shareDecimals] = await Promise.all([
        vaultContract.read.asset(),
        vaultContract.read.decimals(),
      ]);
      const assetDecimals = await publicClient.readContract({
        address: assetAddress,
        abi: ERC20_METADATA_ABI,
        functionName: "decimals",
      });
      const shares = await vaultContract.read.previewWithdraw([assetsAmount]);

      console.log(`[yv:preview-withdraw] vault=${vaultAddress}`);
      console.log(`[yv:preview-withdraw] asset=${assetAddress}`);
      console.log(`[yv:preview-withdraw] assetsRaw=${assetsAmount}`);
      console.log(
        `[yv:preview-withdraw] assetsFormatted=${formatUnits(assetsAmount, assetDecimals)}`,
      );
      console.log(`[yv:preview-withdraw] sharesRaw=${shares}`);
      console.log(
        `[yv:preview-withdraw] sharesFormatted=${formatUnits(shares, shareDecimals)}`,
      );
    } finally {
      await connection.close();
    }
  })
  .build();
