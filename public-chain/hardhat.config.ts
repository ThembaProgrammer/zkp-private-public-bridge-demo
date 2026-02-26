import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ethers";
import * as dotenv from "dotenv";

dotenv.config({ path: "../.env" });

const DEPLOYER_PK =
  process.env.HARDHAT_DEPLOYER_PK ||
  // Hardhat built-in account #0 — safe default for local dev
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },

  networks: {
    // ── Public Hardhat local node ──────────────────────────────────────────
    // ⚠️  Port 8546 is intentional — GoQuorum occupies 8545.
    localhost: {
      url: "http://127.0.0.1:8546",
      chainId: 31337,
      accounts: [DEPLOYER_PK],
    },

    // ── Hardhat in-process network (tests) ────────────────────────────────
    hardhat: {
      chainId: 31337,
    },
  },

  paths: {
    sources:   "./contracts",
    tests:     "./test",
    cache:     "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
