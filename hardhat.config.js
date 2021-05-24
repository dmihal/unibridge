require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("hardhat-deploy");
require('@eth-optimism/plugins/hardhat/compiler');
require('@eth-optimism/plugins/hardhat/ethers');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: '0.7.6',
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },

  networks: {
    optimism: {
      url: 'https://kovan.optimism.io',
      chainId: 69,
      gasPrice: 0,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
    },
    kovan: {
      url: `https://kovan.infura.io/v3/${process.env.INFURA_KEY}`,
      accounts: {
        mnemonic: process.env.MNEMONIC,
      },
      gasPrice: 1000000000,
    },
  },

  namedAccounts: {
    deployer: {
      default: 0,
    },
  },

  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

