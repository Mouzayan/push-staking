<h1 align="center">
    <a href="https://push.org/#gh-light-mode-only">
    <img width='20%' height='10%' src="https://res.cloudinary.com/drdjegqln/image/upload/v1686227557/Push-Logo-Standard-Dark_xap7z5.png">
    </a>
    <a href="https://push.org/#gh-dark-mode-only">
    <img width='20%' height='10%' src="https://res.cloudinary.com/drdjegqln/image/upload/v1686227558/Push-Logo-Standard-White_dlvapc.png">
    </a>
</h1>

<p align="center">
  <i align="center">Push Protocol is a web3 communication network, enabling cross-chain notifications, messaging, video, and NFT chat for dapps, wallets, and services. 🚀</i>
</p>

# Transition to PushCoreV3: Modular Architecture and Staking Integration

The purpose of this repo is to implement the upgrade from PushCoreV2 to PushCoreV3, introducing a more modular contract architecture. This transition separates the core protocol logic from the staking and fee distribution mechanics, with the creation of PushStaking as a key component of this shift.

### PushCoreV2:
Handles core protocol functionality including channel management, staking, and fee collection.  It also manages epochs and rewards distribution as well as stores and manages PROTOCOL_POOL_FEES which contribute to staking rewards.

### Key Differences Between PushCoreV2 and PushCoreV3 + PushStaking:
1. Separation of concerns: PushCoreV3 offloads staking and fee distribution to PushStaking.
2. New interface for fee transfer: PushCoreV3 allows PushStaking to pull protocol fees from it, which stakers earn as staking rewards.
3. The new PushStaking contract will not only manage staking for PUSH token holders but will also include staking for Wallets, meaning Wallets of projects that integrate Push Protocol features. Staking rewards are divided into two distinct pools: one for Token Holders and one for Integrator Wallets.
4. Integrator Wallets are added or removed by governance, and this action serves as the equivalent of staking or unstaking for those wallets.
5. Staking rewards are distributed proportionally between the Token Holder and Integrator Wallet pools. For example, 70% of the pool fees may go to token holders, while the remaining 30% is allocated to Wallet integrators.
For more details, please refer to the [Push Staking Specification](https://pushprotocol.notion.site/Push-Staking-v3-111188aea7f4806c94edd1d85d2eadbb#111188aea7f48024ba1fd6e26bbbaef5).

### PushStaking:
PushStaking is a new contract that takes over some responsibilities from PushCoreV2/V3.
1. Manages staking mechanics (stake, unstake, etc.)
2. Handles fee distribution between WALLET_FEE_POOL and HOLDER_FEE_POOL.
3. Implements pullProtocolFees() to retrieve fees from PushCoreV3.
4. Calculates and distributes rewards to stakers.
5. Manages the separation of fees into different pools based on configurable percentages.

Key Functions of PushStaking:
1. Fee Management: Pulls fees from PushCoreV3 and divides them into separate pools.
2. Staking Logic: Handles staking, unstaking, and reward calculations for users.
3. Reward Distribution: Manages the distribution of rewards from the fee pools to stakers.
4. Configuration: Allows adjustment of fee distribution percentages (with governance control).

---

### 🖥 To Run

1. Install the dependencies:
```sh
npm install
```

### 🧪 Running Tests
```sh
npx hardhat test
```
OR
```sh
forge test
```
---

## Resources
- **[Website](https://push.org)** To checkout our Product.
- **[Docs](https://push.org/docs/)** For comprehensive documentation.
- **[Blog](https://medium.com/push-protocol)** To learn more about our partners, new launches, etc.
- **[Discord](https://discord.gg/pushprotocol)** for support and discussions with the community and the team.
- **[GitHub](https://github.com/push-protocol)** for source code, project board, issues, and pull requests.
- **[Twitter](https://twitter.com/pushprotocol)** for the latest updates on the product and published blogs.

<h4 align="center">

  <a href="https://discord.gg/pushprotocol">
    <img src="https://img.shields.io/badge/discord-7289da.svg?style=flat-square" alt="discord">
  </a>
  <a href="https://twitter.com/pushprotocol">
    <img src="https://img.shields.io/badge/twitter-18a1d6.svg?style=flat-square" alt="twitter">
  </a>
  <a href="https://www.youtube.com/@pushprotocol">
    <img src="https://img.shields.io/badge/youtube-d95652.svg?style=flat-square&" alt="youtube">
  </a>
</h4>
