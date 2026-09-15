import { defineConfig } from "hardhat/config";

// Isolated production-shaped compile profile. No deployment tasks, networks or secrets.
export default defineConfig({
  paths: {
    sources: { solidity: "./contracts/tbpros" },
    artifacts: "./cache/tbpros-core/hardhat-artifacts",
    cache: "./cache/tbpros-core/hardhat-cache",
    tests: { solidity: "./cache/tbpros-core/no-solidity-tests" },
  },
  solidity: {
    profiles: {
      default: { version: "0.8.28", path: process.env.TBPROS_SOLC },
      production: {
        version: "0.8.28",
        path: process.env.TBPROS_SOLC,
        settings: {
          optimizer: { enabled: true, runs: 200 },
          viaIR: false,
          evmVersion: "cancun",
          outputSelection: { "*": { "*": ["abi", "evm.bytecode", "evm.deployedBytecode", "storageLayout"], "": ["ast"] } },
        },
      },
    },
  },
});
