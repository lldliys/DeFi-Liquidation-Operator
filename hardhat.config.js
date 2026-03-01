require("dotenv").config();
require("@nomiclabs/hardhat-waffle");

process.env.HARDHAT_USE_NODEJS_ENGINE = process.env.HARDHAT_USE_NODEJS_ENGINE || "true";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: process.env.ALCHE_API || "https://eth-mainnet.alchemyapi.io/v2/YOUR_ALCHEMY_API_KEY_HERE",
        blockNumber: 12489619
      },
      hardfork: "berlin", 
      chainId: 1,
      mining: {
        auto: true,
      },
      gasPrice: 0,
      accounts: {
        mnemonic: "swap swap swap swap swap swap swap swap swap swap swap swap"
      },
    },
  },
  solidity: {
    version: "0.8.7",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  mocha: {
    timeout: 600000
  },
};