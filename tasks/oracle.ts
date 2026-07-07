import { task } from "hardhat/config";
import {
  encodeFunctionData,
  getContract,
  isAddress,
  type Abi,
  type Address,
  type PublicClient,
  type WalletClient,
} from "viem";

import { Mainnet, TESTNET } from "../contants/index.js";
import mainnetProxyAdminDeployment from "../deployments/mainnet/DefaultProxyAdmin.json" with { type: "json" };
import testnetProxyAdminDeployment from "../deployments/testnet/DefaultProxyAdmin.json" with { type: "json" };

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
    return Mainnet.ORACLE;
  }

  if (networkName === "testnet") {
    return TESTNET.ORACLE;
  }

  return undefined;
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

const PROXY_ADMIN_UPGRADE_ABI = [
  {
    type: "function",
    name: "upgrade",
    stateMutability: "nonpayable",
    inputs: [
      { name: "proxy", type: "address" },
      { name: "implementation", type: "address" },
    ],
    outputs: [],
  },
] as const;

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

const ORACLE_INITIALIZE_V2_ABI = [
  {
    type: "function",
    name: "initializeV2",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_slp", type: "address" },
      { name: "_vToken", type: "address" },
      { name: "_maxUpdateAmount", type: "uint256" },
      { name: "_updateInterval", type: "uint256" },
    ],
    outputs: [],
  },
] as const;

const ERC1967_IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc" as const;

async function getProxyImplementation(
  publicClient: PublicClient,
  proxy: Address,
): Promise<Address> {
  const storage = await publicClient.getStorageAt({
    address: proxy,
    slot: ERC1967_IMPLEMENTATION_SLOT,
  });

  if (storage === undefined) {
    throw new Error(`Failed to read implementation slot for proxy ${proxy}`);
  }

  return (`0x${storage.slice(-40)}`) as Address;
}

function getProxyAdminDeploymentAbi(networkName: string): readonly unknown[] {
  if (networkName === "testnet") {
    return testnetProxyAdminDeployment.abi;
  }

  if (networkName === "mainnet") {
    return mainnetProxyAdminDeployment.abi;
  }

  throw new Error(`No deployed ProxyAdmin ABI for network ${networkName}`);
}

function proxyAdminUsesV5ImplUpgrade(abi: readonly { name?: string }[]): boolean {
  return abi.some((item) => item.name === "UPGRADE_INTERFACE_VERSION");
}

function getDeployedProxyAdminContract(
  proxyAdminAbi: readonly unknown[],
  proxyAdmin: Address,
  publicClient: PublicClient,
  walletClient: WalletClient,
) {
  return getContract({
    address: proxyAdmin,
    abi: proxyAdminAbi as Abi,
    client: {
      public: publicClient,
      wallet: walletClient,
    },
  });
}

function buildImplUpgradeCalldata(
  oracleProxy: Address,
  implementation: Address,
  useV5Upgrade: boolean,
): string {
  if (useV5Upgrade) {
    return encodeFunctionData({
      abi: PROXY_ADMIN_UPGRADE_AND_CALL_ABI,
      functionName: "upgradeAndCall",
      args: [oracleProxy, implementation, "0x"],
    });
  }

  return encodeFunctionData({
    abi: PROXY_ADMIN_UPGRADE_ABI,
    functionName: "upgrade",
    args: [oracleProxy, implementation],
  });
}

export const oracleUpgradeTask = task(
  "oracle:upgrade",
  "Print calldata for upgrading Oracle implementation only (no initializeV2)",
)
  /**
   * Usage:
   * pnpm hardhat oracle:upgrade --network testnet \
   *   <oracleProxy> <newImplementation>
   *
   * Use after Oracle has already run initializeV2 once.
   * Multisig (v4 ProxyAdmin): ProxyAdmin.upgrade(oracleProxy, implementation)
   * Multisig (v5 ProxyAdmin): ProxyAdmin.upgradeAndCall(oracleProxy, implementation, "")
   */
  .addPositionalArgument({
    name: "oracleProxy",
    description: "Oracle transparent proxy address",
  })
  .addPositionalArgument({
    name: "implementation",
    description: "New Oracle implementation address",
  })
  .addOption({
    name: "proxyAdmin",
    description: "ProxyAdmin contract address",
    defaultValue: "",
  })
  .setInlineAction(async (taskArgs, hre) => {
    const connection = await hre.network.getOrCreate();

    try {
      const oracleProxy = getRequiredAddress(taskArgs.oracleProxy, "oracleProxy");
      const implementation = getRequiredAddress(taskArgs.implementation, "implementation");
      const proxyAdmin =
        getOptionalAddress(taskArgs.proxyAdmin, "proxyAdmin address")
        ?? getNetworkProxyAdmin(connection.networkName);

      if (proxyAdmin === undefined) {
        throw new Error("Missing proxyAdmin address. Pass --proxy-admin or use mainnet/testnet.");
      }

      const proxyAdminAbi = getProxyAdminDeploymentAbi(connection.networkName);
      const useV5Upgrade = proxyAdminUsesV5ImplUpgrade(
        proxyAdminAbi as readonly { name?: string }[],
      );
      const upgradeData = buildImplUpgradeCalldata(
        oracleProxy,
        implementation,
        useV5Upgrade,
      );

      console.log(`[oracle:upgrade] oracleProxy=${oracleProxy}`);
      console.log(`[oracle:upgrade] implementation=${implementation}`);
      console.log(`[oracle:upgrade] proxyAdmin=${proxyAdmin}`);
      console.log(`[oracle:upgrade] proxyAdminInterface=${useV5Upgrade ? "v5" : "v4"}`);
      console.log(`[oracle:upgrade] upgradeCalldata=${upgradeData}`);
      console.log(
        useV5Upgrade
          ? "[oracle:upgrade] multisig tx.to=ProxyAdmin function=upgradeAndCall(proxy, implementation, 0x)"
          : "[oracle:upgrade] multisig tx.to=ProxyAdmin function=upgrade(proxy, implementation)",
      );
    } finally {
      await connection.close();
    }
  })
  .build();

export const oracleExecuteUpgradeTask = task(
  "oracle:execute-upgrade",
  "Upgrade Oracle implementation only (no initializeV2)",
)
  /**
   * Usage (testnet defaults from contants/index.ts):
   * pnpm hardhat oracle:execute-upgrade --network testnet <implementation>
   *
   * Example:
   * pnpm hardhat oracle:execute-upgrade --network testnet \
   *   0x42723cd01ae5e7e0856c155f4b78a15a56f442e0
   *
   * Requires ProxyAdmin owner signer. Use when initializeV2 has already been executed.
   */
  .addPositionalArgument({
    name: "implementation",
    description: "New Oracle implementation address",
  })
  .addOption({
    name: "oracle",
    description: "Oracle proxy address; defaults to contants/index.ts on mainnet/testnet",
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
      const oracleProxy =
        getOptionalAddress(taskArgs.oracle, "oracle address")
        ?? getNetworkOracle(networkName);
      const proxyAdmin =
        getOptionalAddress(taskArgs.proxyAdmin, "proxyAdmin address")
        ?? getNetworkProxyAdmin(networkName);

      if (oracleProxy === undefined) {
        throw new Error("Missing oracle proxy. Pass --oracle or use mainnet/testnet.");
      }

      if (proxyAdmin === undefined) {
        throw new Error("Missing proxyAdmin address. Pass --proxy-admin or use mainnet/testnet.");
      }

      const proxyAdminAbi = getProxyAdminDeploymentAbi(networkName);
      const useV5Upgrade = proxyAdminUsesV5ImplUpgrade(
        proxyAdminAbi as readonly { name?: string }[],
      );

      const publicClient = await connection.viem.getPublicClient();
      const proxyAdminContract = getDeployedProxyAdminContract(
        proxyAdminAbi,
        proxyAdmin,
        publicClient,
        signer,
      );
      const proxyAdminOwner = (await proxyAdminContract.read.owner()) as Address;

      if (proxyAdminOwner.toLowerCase() !== signer.account.address.toLowerCase()) {
        throw new Error(
          `Signer ${signer.account.address} is not ProxyAdmin owner ${proxyAdminOwner}`,
        );
      }

      const previousImplementation = await getProxyImplementation(publicClient, oracleProxy);
      const hash = useV5Upgrade
        ? await proxyAdminContract.write.upgradeAndCall([
            oracleProxy,
            implementation,
            "0x",
          ])
        : await proxyAdminContract.write.upgrade([oracleProxy, implementation]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const currentImplementation = await getProxyImplementation(publicClient, oracleProxy);

      console.log(`[oracle:execute-upgrade] oracleProxy=${oracleProxy}`);
      console.log(`[oracle:execute-upgrade] implementation=${implementation}`);
      console.log(`[oracle:execute-upgrade] proxyAdmin=${proxyAdmin}`);
      console.log(`[oracle:execute-upgrade] proxyAdminInterface=${useV5Upgrade ? "v5" : "v4"}`);
      console.log(`[oracle:execute-upgrade] caller=${signer.account.address}`);
      console.log(`[oracle:execute-upgrade] previousImplementation=${previousImplementation}`);
      console.log(`[oracle:execute-upgrade] currentImplementation=${currentImplementation}`);
      console.log(`[oracle:execute-upgrade] txHash=${hash}`);
      console.log(`[oracle:execute-upgrade] blockNumber=${receipt.blockNumber}`);
    } finally {
      await connection.close();
    }
  })
  .build();

export const oracleUpgradeV2Task = task(
  "oracle:upgrade-v2",
  "Print calldata for upgrading Oracle and calling initializeV2 atomically",
)
  /**
   * Usage:
   * pnpm hardhat oracle:upgrade-v2 --network mainnet \
   *   <oracleProxy> <newImplementation> <slp> <vToken> <maxUpdateAmount> <updateInterval>
   *
   * Owner multisig one-shot:
   * ProxyAdmin.upgradeAndCall(oracleProxy, implementation, initializeV2(slp, vToken, maxUpdateAmount, updateInterval))
   *
   * Example (100 ether max, 1 hour interval):
   * pnpm hardhat oracle:upgrade-v2 --network mainnet \
   *   0x051713fd66845a13bf23baca008c5c22c27ccb58 \
   *   0xNewImplementation \
   *   0xSlpAddress \
   *   0x6b0a44c64190279f7034b77c13a566e914fe5ec4 \
   *   100000000000000000000 \
   *   3600
   */
  .addPositionalArgument({
    name: "oracleProxy",
    description: "Oracle transparent proxy address",
  })
  .addPositionalArgument({
    name: "implementation",
    description: "New Oracle implementation address",
  })
  .addPositionalArgument({
    name: "slp",
    description: "SLP contract allowed to call Oracle.update",
  })
  .addPositionalArgument({
    name: "vToken",
    description: "vToken contract allowed to manage its asset pool",
  })
  .addPositionalArgument({
    name: "maxUpdateAmount",
    description: "Maximum token amount per update; 0 disables update",
  })
  .addPositionalArgument({
    name: "updateInterval",
    description: "Minimum seconds between updates per token; 0 disables interval check",
  })
  .addOption({
    name: "proxyAdmin",
    description: "ProxyAdmin contract address",
    defaultValue: "0x4238ea4adfa2bd6a5fc9b5e245dc1900cf0258aa",
  })
  .setInlineAction(async (taskArgs, hre) => {
    const oracleProxy = getRequiredAddress(taskArgs.oracleProxy, "oracleProxy");
    const implementation = getRequiredAddress(taskArgs.implementation, "implementation");
    const slp = getRequiredAddress(taskArgs.slp, "slp");
    const vToken = getRequiredAddress(taskArgs.vToken, "vToken");
    const maxUpdateAmount = getRequiredBigInt(taskArgs.maxUpdateAmount, "maxUpdateAmount");
    const updateInterval = getRequiredBigInt(taskArgs.updateInterval, "updateInterval");
    const proxyAdmin = getRequiredAddress(taskArgs.proxyAdmin, "proxyAdmin");

    const initData = encodeFunctionData({
      abi: ORACLE_INITIALIZE_V2_ABI,
      functionName: "initializeV2",
      args: [slp, vToken, maxUpdateAmount, updateInterval],
    });

    const upgradeAndCallData = encodeFunctionData({
      abi: PROXY_ADMIN_UPGRADE_AND_CALL_ABI,
      functionName: "upgradeAndCall",
      args: [oracleProxy, implementation, initData],
    });

    console.log(`[oracle:upgrade-v2] oracleProxy=${oracleProxy}`);
    console.log(`[oracle:upgrade-v2] implementation=${implementation}`);
    console.log(`[oracle:upgrade-v2] slp=${slp}`);
    console.log(`[oracle:upgrade-v2] vToken=${vToken}`);
    console.log(`[oracle:upgrade-v2] maxUpdateAmount=${maxUpdateAmount}`);
    console.log(`[oracle:upgrade-v2] updateInterval=${updateInterval}`);
    console.log(`[oracle:upgrade-v2] proxyAdmin=${proxyAdmin}`);
    console.log(`[oracle:upgrade-v2] initializeV2Calldata=${initData}`);
    console.log(`[oracle:upgrade-v2] upgradeAndCallCalldata=${upgradeAndCallData}`);
    console.log(
      "[oracle:upgrade-v2] multisig tx.to=ProxyAdmin function=upgradeAndCall(proxy, implementation, initializeV2Data)",
    );
  })
  .build();

export const oracleExecuteUpgradeV2Task = task(
  "oracle:execute-upgrade-v2",
  "Upgrade Oracle via ProxyAdmin.upgradeAndCall and initializeV2",
)
  /**
   * Usage (testnet defaults from contants/index.ts):
   * pnpm hardhat oracle:execute-upgrade-v2 --network testnet <implementation>
   *
   * Full override:
   * pnpm hardhat oracle:execute-upgrade-v2 --network testnet \
   *   <implementation> \
   *   --oracle 0x6bd39d03d2fbbf14aee362977a09c293b282b0bc \
   *   --slp 0x464017CDC3c2af2b5B525FDe03Ac93F15172Db43 \
   *   --v-token 0xb1437aeea18189eb6d02dc46cd4d28613d582e9a \
   *   --max-update-amount 100000000000000000000 \
   *   --update-interval 3600 \
   *   --proxy-admin 0x79d6028229f2d819a1a4bb52a05bc97f5f37d667
   *
   * Requires ProxyAdmin owner signer. Run before stpros:execute-upgrade-v2.
   */
  .addPositionalArgument({
    name: "implementation",
    description: "New Oracle implementation address",
  })
  .addOption({
    name: "oracle",
    description: "Oracle proxy address; defaults to contants/index.ts on mainnet/testnet",
    defaultValue: "",
  })
  .addOption({
    name: "slp",
    description: "SLP address; defaults to TESTNET.SLP on testnet",
    defaultValue: "",
  })
  .addOption({
    name: "vToken",
    description: "vToken address; defaults to contants/index.ts STPROS on mainnet/testnet",
    defaultValue: "",
  })
  .addOption({
    name: "maxUpdateAmount",
    description: "Maximum token amount per update; 0 disables update",
    defaultValue: "100000000000000000000",
  })
  .addOption({
    name: "updateInterval",
    description: "Minimum seconds between updates per token; 0 disables interval check",
    defaultValue: "3600",
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
      const oracleProxy =
        getOptionalAddress(taskArgs.oracle, "oracle address")
        ?? getNetworkOracle(networkName);
      const slp =
        getOptionalAddress(taskArgs.slp, "slp address")
        ?? getNetworkSlp(networkName);
      const vToken =
        getOptionalAddress(taskArgs.vToken, "vToken address")
        ?? getNetworkStPros(networkName);
      const maxUpdateAmount = getRequiredBigInt(taskArgs.maxUpdateAmount, "maxUpdateAmount");
      const updateInterval = getRequiredBigInt(taskArgs.updateInterval, "updateInterval");
      const proxyAdmin =
        getOptionalAddress(taskArgs.proxyAdmin, "proxyAdmin address")
        ?? getNetworkProxyAdmin(networkName);

      if (oracleProxy === undefined) {
        throw new Error("Missing oracle proxy. Pass --oracle or use mainnet/testnet.");
      }

      if (slp === undefined) {
        throw new Error("Missing slp address. Pass --slp or use testnet defaults.");
      }

      if (vToken === undefined) {
        throw new Error("Missing vToken address. Pass --v-token or use mainnet/testnet.");
      }

      if (proxyAdmin === undefined) {
        throw new Error("Missing proxyAdmin address. Pass --proxy-admin or use mainnet/testnet.");
      }

      const initData = encodeFunctionData({
        abi: ORACLE_INITIALIZE_V2_ABI,
        functionName: "initializeV2",
        args: [slp, vToken, maxUpdateAmount, updateInterval],
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
        oracleProxy,
        implementation,
        initData,
      ]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const oracleContract = await connection.viem.getContractAt("Oracle", oracleProxy);
      const [slpOnChain, vTokenRegistered, maxOnChain, intervalOnChain] = await Promise.all([
        oracleContract.read.slp(),
        oracleContract.read.vTokenAddresses([vToken]),
        oracleContract.read.maxUpdateAmount(),
        oracleContract.read.updateInterval(),
      ]);

      console.log(`[oracle:execute-upgrade-v2] oracleProxy=${oracleProxy}`);
      console.log(`[oracle:execute-upgrade-v2] implementation=${implementation}`);
      console.log(`[oracle:execute-upgrade-v2] proxyAdmin=${proxyAdmin}`);
      console.log(`[oracle:execute-upgrade-v2] caller=${signer.account.address}`);
      console.log(`[oracle:execute-upgrade-v2] slp=${slpOnChain}`);
      console.log(`[oracle:execute-upgrade-v2] vToken=${vToken}`);
      console.log(`[oracle:execute-upgrade-v2] vTokenRegistered=${vTokenRegistered}`);
      console.log(`[oracle:execute-upgrade-v2] maxUpdateAmount=${maxOnChain}`);
      console.log(`[oracle:execute-upgrade-v2] updateInterval=${intervalOnChain}`);
      console.log(`[oracle:execute-upgrade-v2] initializeV2Calldata=${initData}`);
      console.log(`[oracle:execute-upgrade-v2] txHash=${hash}`);
      console.log(`[oracle:execute-upgrade-v2] blockNumber=${receipt.blockNumber}`);
    } finally {
      await connection.close();
    }
  })
  .build();
