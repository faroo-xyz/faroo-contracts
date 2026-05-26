import type { UserConfig } from "rocketh/types";

export const config = {
  accounts: {
    deployer: {
      default: 0,
    },
    owner: {
      default: 0,
    },
  },
  data: {},
} as const satisfies UserConfig;

import * as deployExtension from "@rocketh/deploy";
import * as proxyExtension from "@rocketh/proxy";
import * as readExecuteExtension from "@rocketh/read-execute";
import * as viemExtension from "@rocketh/viem";

const extensions = {
  ...deployExtension,
  ...proxyExtension,
  ...readExecuteExtension,
  ...viemExtension,
};

export { extensions };

type Extensions = typeof extensions;
type Accounts = typeof config.accounts;
type Data = typeof config.data;

export type { Accounts, Data, Extensions };
