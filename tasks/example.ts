import { task } from "hardhat/config";

export const exampleTask = task("example", "Example task")
  .setAction(async () => ({
    default: async (_taskArgs, _hre) => {
      console.log("Example task");
    },
  }))
  .build();
