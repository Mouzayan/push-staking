// Load Libraries
const chalk = require('chalk');
const fs = require("fs");

require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-gas-reporter");
// require('hardhat-contract-sizer');
require("@nomicfoundation/hardhat-verify");

const { ethers } = require("ethers");
const { isAddress, getAddress, formatUnits, parseUnits } = ethers.utils;

// Check ENV File first and load ENV
verifyENV();
async function verifyENV() {
  const envVerifierLoader = require('./loaders/envVerifier');
  envVerifierLoader(true);
}

require('dotenv').config();

const defaultNetwork = "hardhat";

function mnemonic() {
  try {
    return fs.readFileSync("./mnemonic.txt").toString().trim();
  } catch (e) {
    if (defaultNetwork !== "localhost") {
      console.log(
        "☢️ WARNING: No mnemonic file created for a deploy account. Try `yarn run generate` and then `yarn run account`."
      );
    }
  }
  return "";
}

module.exports = {
  contractSizer: {
    alphaSort: false,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
    only: [],
  },
  defaultNetwork,

  // don't forget to set your provider like:
  // REACT_APP_PROVIDER=https://dai.poa.network in packages/react-app/.env
  // (then your frontend will talk to your contracts on the live network!)
  // (you will need to restart the `yarn run start` dev server after editing the .env)

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      forking: {
        url:
          `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API}`,
          blockNumber: 15917401
      },
    },
    localhost: {
      url: "http://localhost:8545",
      /*
        notice no mnemonic here? it will just use account 0 of the buidler node to deploy
        (you can put in a mnemonic here to set the deployer locally)
      */
    },

  // // ETH Network
  //   sepolia: {
  //     url: `https://sepolia.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
  //     accounts: [process.env.PRIVATE]

    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`, // <---- YOUR INFURA ID! (or it won't work)
      aaccounts: {
        mnemonic: mnemonic(),
      },
    },

    // // Polygon Chain
    // polygonMumbai: {
    //   url: `https://rpc-mumbai.maticvigil.com/`, // <---- YOUR INFURA ID! (or it won't work)
    //   accounts: [process.env.PRIVATE]

    // },
    // polygon: {
    //   url: `https://polygon-rpc.com/`, // <---- YOUR INFURA ID! (or it won't work)
    //   accounts: [process.env.PRIVATE]

    // },

    // polygonAmoy: {
    //   url: `https://rpc-amoy.polygon.technology/`, // <---- YOUR INFURA ID! (or it won't work)
    //   accounts:[process.env.PRIVATE],
    // },

    // // BSC Chain
    // bscTestnet: {
    //   url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
    //   accounts: {
    //     mnemonic: mnemonic(),
    //   }
    // },
    // bscMainnet: {
    //   url: "https://bsc-dataseed1.binance.org/",
    //   accounts: [process.env.PRIVATE]

    // },

    // // Polygon zkEVM Chain
    // polygonZkEVMTestnet: {
    //   url: "https://rpc.cardona.zkevm-rpc.com/",
    //   accounts: [process.env.PRIVATE]

    // },
    // zkEVMMainnet: {
    //   url: "https://zkevm-rpc.com	",
    //   accounts: [process.env.PRIVATE]

    // },

    // // Optimisim Chain
    // optimismSepolia: {
    //   url: "https://sepolia.optimism.io",
    //   accounts: [process.env.PRIVATE]

    // },
    // optimismMainnet: {
    //   url: "https://mainnet.optimism.io",
    //   accounts: [process.env.PRIVATE]

    // },

    // // Arbitrum Chain
    // arbitrumSepolia: {
    //   url: "https://arbitrum-sepolia.blockpi.network/v1/rpc/public",
    //   accounts: [process.env.PRIVATE]
    // },

    // arbitrumMainnet : {
    //   url: 'https://arb1.arbitrum.io/rpc',
    //   accounts: [process.env.PRIVATE]
    // },

    // // Linea Chain
    // lineaSepolia: {
    //   url: `https://rpc.sepolia.linea.build`,
    //   accounts: [process.env.PRIVATE]

    // },
    // lineaMainnet: {
    //   url: `https://rpc.linea.build`,
    //   accounts: [process.env.PRIVATE]

    // },

    // //Fuse Mainnet
    // fuse:{
    //   url:"https://rpc.fuse.io",
    //   accounts: [process.env.PRIVATE],
    // },

    // //Fuse Testnet
    // fuseSpark:{
    //   url:"https://rpc.fusespark.io",
    //   accounts: [process.env.PRIVATE],
    // },
    // //Shardeum Testnet
    // sphinx:{
    //   url: "https://sphinx.shardeum.org/",
    //   chainId: 8082,
    //   accounts:[process.env.PRIVATE]

    // },
    // //Bera Chain testnet
    //   berachainTestnet: {
    //   url: "https://artio.rpc.berachain.com/",
    //   chainId: 80085,
    //   accounts: [process.env.PRIVATE],
    // },

    // //OKX testnet X1
    // X1: {
    //   url: "https://testrpc.x1.tech",
    //   accounts:[process.env.PRIVATE]
    // },

    // // Cyber Chain
    // cyberTestnet: {
    //   url: "https://cyber-testnet.alt.technology/",
    //   accounts:[process.env.PRIVATE]
    // },
    // cyberMainnet: {
    //   url: "https://cyber.alt.technology/",
    //   chainId: 7560,
    //   accounts:[process.env.PRIVATE]
    // },
    // //Base Chain
    // baseMainnet: {
    //   url: 'https://mainnet.base.org',
    //   accounts: [process.env.PRIVATE],
    // },
    // baseSepolia: {
    //   url: 'https://sepolia.base.org',
    //   accounts: [process.env.PRIVATE],
    // }
  // },
  etherscan: {
    apiKey: {
      lineaSepolia: process.env.ETHERSCAN_API,
      mainnet: process.env.ETHERSCAN_API,
      polygon: process.env.POLYGONSCAN_API,
      sepolia:process.env.ETHERSCAN_API,
      bscTestnet: process.env.BNBSCAN_API,
      fuse: process.env.FUSE_API,
      fuseSpark: process.env.FUSE_API,
      arbitrumSepolia:process.env.ARBISCAN_API,
      arbitrumOne: process.env.ARBISCAN_API,
      optimismSepolia :process.env.OPTIMISM_API,
      polygonZkEVMTestnet: process.env.POLYGONzkEVMSCAN_API,
      berachainTestnet: "apiNotRequired",
      polygonAmoy:"OKLINK",
      X1: "Not required",
      cyber_testnet: "Not Required",
      cyber:"Not Required",
      "base-sepolia": "PLACEHOLDER_STRING"
    },
    customChains: [
      {
        network: "lineaSepolia",
        chainId: 59141,
        urls: {
          apiURL: "https://explorer.sepolia.linea.build/api",
          browserURL: "https://sepolia.lineascan.build/",
        },
      },

      {
        network: "lineaMainnet",
        chainId: 59144,
        urls: {
          apiURL: "https://api.lineascan.build/api",
          browserURL: "https://lineascan.build/",
        },
      },

      {
        network: "fuse",
        chainId: 122,
        urls:{
          apiURL: "https://explorer.fuse.io/api",
          browserURL: "https://explorer.fuse.io/",
        }
      },

      {
        network: "fuseSpark",
        chainId: 123,
        urls:{
          apiURL: "https://explorer.fusespark.io/api",
          browserURL: "https://explorer.fusespark.io/",
        },
      },
      {
        network: "berachainTestnet",
        chainId: 80085,
        urls: {
          apiURL:
            "https://api.routescan.io/v2/network/testnet/evm/80085/etherscan/api/",
          browserURL: "https://artio.beratrail.io/",
        },
      },
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL:
            "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io//",
        },
      },
      {
        network: "optimismSepolia",
        chainId: 11155420,
        urls: {
          apiURL:
            "https://api-sepolia-optimistic.etherscan.io/api",
          browserURL: "https://sepolia-optimistic.etherscan.io/",
        },
      },
      {
        network: "polygonAmoy",
        chainId: 80002,
        urls: {
          apiURL: "https://www.oklink.com/api/explorer/v1/contract/verify/async/api/polygon_amoy",
          browserURL: "https://www.oklink.com/amoy"
        }
      },
      {
        network: "X1",
        chainId: 195,
        urls: {
            apiURL: "https://www.oklink.com/api/explorer/v1/contract/verify/async/api/x1_test",
            browserURL: "https://www.oklink.com/x1-test"
        }
      },
      {
        network: "polygonZkEVMTestnet",
        chainId: 2442,
        urls: {
            apiURL: "https://api-zkevm.polygonscan.com/api",
            browserURL: "https://cardona-zkevm.polygonscan.com/"
        }
      },
      {
        network: "cyber_testnet",
        chainId: 111557560,
        urls: {
          apiURL: "https://testnet.cyberscan.co/api",
          browserURL: "https://testnet.cyberscan.co"
        }
      },
      {
        network: "base-sepolia",
        chainId: 84532,
        urls: {
         apiURL: "https://api-sepolia.basescan.org/api",
         browserURL: "https://sepolia.basescan.org"
        }
      },
      {
        network: "cyber",
        chainId: 7560,
        urls: {
          apiURL: "https://cyberscan.co/api",
          browserURL: "https://cyberscan.co"
        }
      }
    ],
  },

  solidity: {
    compilers: [
      {
        version: "0.6.11",
      },
      {
        version: "0.6.12",
      },
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 99999,
      },
    },
  },
};
// ENABLE / DISABLE DEBUG
const DEBUG = true;

function debug(text) {
  if (DEBUG) {
    console.log(text);
  }
}

// To Generate mnemonic
function mnemonic() {
  try {
    return fs.readFileSync("./wallets/main_mnemonic.txt").toString().trim();
  } catch (e) {
    if (defaultNetwork !== "localhost") {
      console.log(
        "☢️ WARNING: No mnemonic file created for a deploy account. Try `npx hardhat generate` and then `npx hardhat account`."
      );
    }
  }
  return "";
}

function getPrivateKey() {
  try {
    const key = fs.readFileSync("./wallets/main_privateKey.txt").toString().trim();
    return [key];
  } catch (e) {
    if (defaultNetwork !== "localhost") {
      console.log(
        "☢️ WARNING: No mnemonic / private key file created for a deploy account. Try `npx hardhat generate` and then `npx hardhat account`."
      );
    }
  }

  return "";
}

task(
  "generate",
  "Create a mnemonic for builder deploys",
  async (_, { ethers }) => {
    const generate = async (isSecondary) => {
      const bip39 = require("bip39");
      const { hdkey } = require('ethereumjs-wallet')

      const mnemonic = bip39.generateMnemonic();
      const seed = await bip39.mnemonicToSeed(mnemonic);
      const hdwallet = hdkey.fromMasterSeed(seed);
      const wallet_hdpath = "m/44'/60'/0'/0/";
      const account_index = 0;
      const fullPath = wallet_hdpath + account_index;
      const wallet = hdwallet.derivePath(fullPath).getWallet();
      const privateKey = "0x" + wallet.privateKey.toString("hex");


      if (DEBUG) console.log(chalk.bgGreen.bold.black(`\n\t\t\t`))
      if (DEBUG) console.log(chalk.bgBlack.bold.white(` 💰 Wallet - ${isSecondary ? "alt_wallet" : "main_wallet"} | ${privateKey} `))
      if (DEBUG) console.log(chalk.bgGreen.bold.black(`\t\t\t\n`))
      if (DEBUG) console.log("mnemonic", mnemonic);
      if (DEBUG) console.log("seed", seed);
      if (DEBUG) console.log("fullPath", fullPath);
      if (DEBUG) console.log("privateKey", privateKey);

      const EthUtil = require("ethereumjs-util");
      const address = "0x" + EthUtil.privateToAddress(wallet.privateKey).toString("hex");

      console.log(
        "🔐 Account Generated as " +
          address +
          ".txt and set as mnemonic in packages/buidler"
      );
      console.log(
        "💬 Use 'npx hardhat account' to get more information about the deployment account."
      );

      if (isSecondary) {
        fs.writeFileSync("./wallets/alt_" + address + ".txt", mnemonic.toString() + "\n" + privateKey);
        fs.writeFileSync("./wallets/alt_mnemonic.txt", mnemonic.toString());
        fs.writeFileSync("./wallets/alt_private.txt", privateKey.toString());
      }
      else {
        fs.writeFileSync("./wallets/main_" + address + ".txt", mnemonic.toString() + "\n" + privateKey);
        fs.writeFileSync("./wallets/main_mnemonic.txt", mnemonic.toString());
        fs.writeFileSync("./wallets/main_privatekey.txt", privateKey.toString());
      }

      if (DEBUG) console.log("\n------\n");
    }

    await generate()
    await generate(true)
  }
);

task(
  "account",
  "Get balance informations for the deployment account.",
  async (_, { ethers }) => {
    const showAccount = async (walletName) => {

      const { hdkey } = require('ethereumjs-wallet')

      const bip39 = require("bip39");
      const mnemonic = fs.readFileSync(`./wallets/${walletName}_mnemonic.txt`).toString().trim();
      const seed = await bip39.mnemonicToSeed(mnemonic);
      const hdwallet = hdkey.fromMasterSeed(seed);
      const wallet_hdpath = "m/44'/60'/0'/0/";
      const account_index = 0;
      const fullPath = wallet_hdpath + account_index;
      const wallet = hdwallet.derivePath(fullPath).getWallet();
      const privateKey = "0x" + wallet.privateKey.toString("hex");
      const EthUtil = require("ethereumjs-util");
      const address =
        "0x" + EthUtil.privateToAddress(wallet.privateKey).toString("hex");


      if (DEBUG) console.log(chalk.bgGreen.bold.black(`\n\t\t\t`))
      if (DEBUG) console.log(chalk.bgBlack.bold.white(` 💰 Wallet - ${walletName} | ${privateKey} `))
      if (DEBUG) console.log(chalk.bgGreen.bold.black(`\t\t\t\n`))

      if (DEBUG) console.log("mnemonic", mnemonic);
      if (DEBUG) console.log("seed", seed);
      if (DEBUG) console.log("fullPath", fullPath);
      if (DEBUG) console.log("privateKey", privateKey);
      if (DEBUG) console.log("‍📬 Deployer Account is " + address);
      const qrcode = require("qrcode-terminal");
      qrcode.generate(address);

      for (const n in config.networks) {
        // console.log(config.networks[n],n)
        try {
          const provider = new ethers.providers.JsonRpcProvider(
            config.networks[n].url
          );
          const balance = await provider.getBalance(address);
          console.log(" -- " + n + " --  -- -- 📡 ");
          console.log("   balance: " + ethers.utils.formatEther(balance));
          console.log(
              // eslint-disable-next-line no-await-in-loop
            "   nonce: " + (await provider.getTransactionCount(address))
          );
        } catch (e) {
          if (DEBUG) {
            console.log(e);
          }
        }
      }

      if (DEBUG) console.log("\n------\n");
    }

    await showAccount("main")
    await showAccount("alt")
  }
);

async function addr(ethers, addr) {
  if (isAddress(addr)) {
    return getAddress(addr);
  }
  const accounts = await ethers.provider.listAccounts();
  if (accounts[addr] !== undefined) {
    return accounts[addr];
  }
  throw `Could not normalize address: ${addr}`;
}

task("accounts", "Prints the list of accounts", async (_, { ethers }) => {
  const accounts = await ethers.provider.listAccounts();
  accounts.forEach((account) => console.log(account));
});

task("blockNumber", "Prints the block number", async (_, { ethers }) => {
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log(blockNumber);
});

task("balance", "Prints an account's balance")
  .addPositionalParam("account", "The account's address")
  .setAction(async (taskArgs, { ethers }) => {
    const balance = await ethers.provider.getBalance(
      await addr(ethers, taskArgs.account)
    );
    console.log(formatUnits(balance, "ether"), "ETH");
  }
);

function send(signer, txparams) {
  return signer.sendTransaction(txparams, (error, transactionHash) => {
    if (error) {
      debug(`Error: ${error}`);
    }
    debug(`transactionHash: ${transactionHash}`);
    // checkForReceipt(2, params, transactionHash, resolve)
  });
}

task("send", "Send ETH")
  .addParam("from", "From address or account index")
  .addOptionalParam("to", "To address or account index")
  .addOptionalParam("amount", "Amount to send in ether")
  .addOptionalParam("data", "Data included in transaction")
  .addOptionalParam("gasPrice", "Price you are willing to pay in gwei")
  .addOptionalParam("gasLimit", "Limit of how much gas to spend")

  .setAction(async (taskArgs, { network, ethers }) => {
    const from = await addr(ethers, taskArgs.from);
    debug(`Normalized from address: ${from}`);
    const fromSigner = await ethers.provider.getSigner(from);

    let to;
    if (taskArgs.to) {
      to = await addr(ethers, taskArgs.to);
      debug(`Normalized to address: ${to}`);
    }

    const txRequest = {
      from: await fromSigner.getAddress(),
      to,
      value: parseUnits(
        taskArgs.amount ? taskArgs.amount : "0",
        "ether"
      ).toHexString(),
      nonce: await fromSigner.getTransactionCount(),
      gasPrice: parseUnits(
        taskArgs.gasPrice ? taskArgs.gasPrice : "1.001",
        "gwei"
      ).toHexString(),
      gasLimit: taskArgs.gasLimit ? taskArgs.gasLimit : 24000,
      chainId: network.config.chainId,
    };

    if (taskArgs.data !== undefined) {
      txRequest.data = taskArgs.data;
      debug(`Adding data to payload: ${txRequest.data}`);
    }
    debug(txRequest.gasPrice / 1000000000 + " gwei");
    debug(JSON.stringify(txRequest, null, 2));

    return send(fromSigner, txRequest);
  }
);
