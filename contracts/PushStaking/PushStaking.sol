pragma solidity >=0.6.12 < 0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../interfaces/IPUSH.sol";
import "../interfaces/IPushStaking.sol";

import "../PushCore/PushCoreV3.sol";
import "../PushCore/PushCoreStorageV1_5.sol";
import "../PushCore/PushCoreStorageV2.sol";

/**
 * @title PushStaking
 * @author em_mutable
 * @notice This contract implements an advancement in the Push Protocol staking mechanism,
 *         facilitating staking for both PUSH token holders and wallet integrators.
 *
 *         The contract can be paused by an admin in emergency situations. It implements
 *         OpenZeppelin's Pausable to halt operations during critical security incidents
 *         or when vulnerabilities are detected.
 *
 * @dev The contract operates independently from the PushCore contract, with its primary dependency
 *      being the ability to read the `PROTOCOL_POOL_FEE` state variable from the core contract.
 *
 * Key Features:
 *          - Dual Actor Staking: Supports staking for both PUSH token holders and wallets
 *            that integrate Push Protocol features.
 *          - Standalone Operation: Functions as a separate contract from PushCore, enhancing
 *            modularity and the separation of concerns.
 *          - Fee Pool Integration: Interacts with the core protocol's fee pool by reading the
 *            `PROTOCOL_POOL_FEE` state variable from Core, for reward calculations and distributions.
 *          - Reward Distribution: Calculates and distributes rewards to stakers.
 *          - Governance and Flexibility: Allows for future adjustments and enhancements through
 *            community governance, ensuring the staking mechanism remains adaptable to evolving
 *            protocol needs.
 *
 *         1. Integrator Wallet Staking:
 *            - Allows protocol integrators to receive a share of protocol fees
 *            - Uses a share-based system where integrators are allocated shares
 *            - Treasury wallet maintains base shares
 *            - Integrators can harvest rewards based on their share allocation
 *            - Rewards come from WALLET_FEE_POOL (30% of protocol fees at contract deployment)
 *
 *         2. Token Holder Staking:
 *            - Allows PUSH token holders to stake tokens and earn rewards
 *            - Uses an epoch-based reward system
 *            - Rewards are calculated based on stake weight and duration
 *            - Requires minimum 1 epoch duration for staking
 *            - Rewards come from HOLDER_FEE_POOL (70% of protocol fees at contract deployment)
 */
contract PushStaking is IPushStaking, PushCoreStorageV1_5, PushCoreStorageV2, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Constants TODO: DOUBLE CHECK FORMAT
    uint256 private constant PRECISION_FACTOR = 1e12;
    uint256 private constant PERCENTAGE_DIVISOR = 1e2;

    // State variables
    PushCoreV3 public override pushCoreV3;
    IERC20 public override pushToken; // TODO: DOUBLE CHECK if this is redudnant vis a vis inehritance tree

    uint256 public override WALLET_FEE_POOL;
    uint256 public override HOLDER_FEE_POOL;
    uint256 public override WALLET_FP_TOTAL_SHARES;

    uint256 public override WALLET_FEE_PERCENTAGE = 30; // TODO: DOUBLE CHECK FORMAT
    uint256 public override HOLDER_FEE_PERCENTAGE = 70; // TODO: DOUBLE CHECK FORMAT

    address public override TREASURY_WALLET;
    address public override admin; // TODO: add way for governance to set admin

    mapping(address => IntegratorData) public override integrators;

    // =========================================== CONSTRUCTOR ===========================================
    /**
     * @notice Initializes the PushStaking contract with the given addresses and sets up the initial
     *         state. Initializes `WALLET_FP_TOTAL_SHARES` to 100 and assigns the shares to the
     *         `TREASURY_WALLET`.
     *
     * @param _pushCoreV3Address        The address of the PushCoreV3 contract.
     * @param _admin                    The address of the contract admin who will have special privileges,
     *                                  such as pausing the contract.
     * @param _pushTokenAddress         Address of the PUSH ERC20 token contract.
     * @param _treasuryWallet           Address that will receive base integrator shares (permanent integrator).
     */
    constructor(
        address _pushCoreV3Address,
        address _admin,
        address _pushTokenAddress,
        address _treasuryWallet
    ) public {
        pushCoreV3 = PushCoreV3(_pushCoreV3Address);
        pushToken = IERC20(pushCoreV3.PUSH_TOKEN_ADDRESS());
        admin = _admin;
        TREASURY_WALLET = _treasuryWallet;

        // Initialize treasury wallet with 100 shares
        WALLET_FP_TOTAL_SHARES = 100;
        IntegratorData storage treasury = integrators[TREASURY_WALLET];
        treasury.shares = WALLET_FP_TOTAL_SHARES;
        treasury.lastRewardBlock = block.number;

        emit IntegratorAdded(TREASURY_WALLET, WALLET_FP_TOTAL_SHARES, WALLET_FP_TOTAL_SHARES);
    }

    // =================================== INTEGRATOR STAKING FUNCTIONS ==================================
    /**
     * @notice Adds a new integrator with a specified percentage of total shares.
     *
     * @dev This function calculates and allocates new shares to an integrator based on the share
     *      percentage. `addIntegrator()` is akin to `stake()` for token holders, enabling integrator
     *      wallets to participate in staking and earn rewards.
     *
     * @param _integratorAddress       The address of the new integrator to be added.
     * @param _sharePercentage         The percentage of total shares for the integrator.
     */
    function addIntegrator(address _integratorAddress, uint256 _sharePercentage) external override onlyGovernance {
        require(integrators[_integratorAddress].shares == 0, "PushStaking: already an integrator");
        require(_integratorAddress != address(0), "PushStaking: invalid address");
        require(_sharePercentage > 0 && _sharePercentage < 100, "PushStaking: invalid percentage");

        // Formula to calculate new shares: (x / (x + total_shares)) * 100 = desired_percentage
        uint256 newShares = (_sharePercentage * WALLET_FP_TOTAL_SHARES) / (100 - _sharePercentage);

        IntegratorData storage integrator = integrators[_integratorAddress];
        integrator.shares = newShares;
        integrator.lastRewardBlock = block.number;

        WALLET_FP_TOTAL_SHARES = WALLET_FP_TOTAL_SHARES.add(newShares);

        emit IntegratorAdded(_integratorAddress, newShares, WALLET_FP_TOTAL_SHARES);
    }

    /**
     * @notice Removes an integrator and distributes their final rewards.
     *
     * @dev This function harvests any remaining rewards for the integrator and deletes their data.
     *      `removeIntegrator()` is akin to `unstake()` for token holders, ending the integrator's
     *      participation in the reward system.
     *
     * @param _integratorAddress      The address of the integrator to be removed.
     */
    function removeIntegrator(address _integratorAddress) external override onlyGovernance {
        require(integrators[_integratorAddress].shares > 0, "PushStaking: not an integrator");
        require(_integratorAddress != TREASURY_WALLET, "PushStaking: cannot remove treasury wallet");

        // Harvest final rewards
        _harvestIntegratorRewards(_integratorAddress);

        uint256 oldShares = integrators[_integratorAddress].shares;
        WALLET_FP_TOTAL_SHARES = WALLET_FP_TOTAL_SHARES.sub(oldShares);

        // Complete deletion of integrator data
        delete integrators[_integratorAddress];

        emit IntegratorRemoved(_integratorAddress, oldShares, WALLET_FP_TOTAL_SHARES);
    }

    /**
     * @notice Allows integrators to manually harvest their rewards.
     *
     * @dev Integrators can call this function to collect any accumulated rewards up to the current
     *      block.
     */
    function harvestIntegratorRewards() external override whenNotPaused {
        _harvestIntegratorRewards(msg.sender);
    }

    // ================================== TOKEN HOLDER STAKING FUNCTIONS ================================
    /** // TODO: Improve Natspec
     * @notice Function to initialize the staking procedure in Core contract
     * @dev    Requires caller to deposit/stake 1 PUSH token to ensure staking pool is never zero.
     **/
    function initializeStake() external override whenNotPaused {
        require(
            genesisEpoch == 0,
            "PushCoreV3::initializeStake: Already Initialized"
        );
        genesisEpoch = block.number;
        lastEpochInitialized = genesisEpoch;

        _stake(address(this), 1e18);
    }

    /** // TODO: Improve Natspec
     * @notice Function to allow users to stake in the protocol
     * @dev    Records total Amount staked so far by a particular user
     *         Triggers weight adjustents functions
     * @param  _amount represents amount of tokens to be staked
     **/
    function stake(uint256 _amount) external override whenNotPaused {
        _stake(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    /** // TODO: Improve Natspec
     * @notice Function to allow users to Unstake from the protocol
     * @dev    Allows stakers to claim rewards before unstaking their tokens
     *         Triggers weight adjustents functions
     *         Allows users to unstake all amount at once
     **/
    function unstake() external override whenNotPaused {
        require(
            block.number >
                userFeesInfo[msg.sender].lastStakedBlock + epochDuration,
            "PushCoreV3::unstake: Can't Unstake before 1 complete EPOCH"
        );
        require(
            userFeesInfo[msg.sender].stakedAmount > 0,
            "PushCoreV3::unstake: Invalid Caller"
        );
        harvestAll();
        uint256 stakedAmount = userFeesInfo[msg.sender].stakedAmount;
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, stakedAmount);

        // Adjust user and total rewards, piggyback method
        _adjustUserAndTotalStake(
            msg.sender,
            -userFeesInfo[msg.sender].stakedWeight
        );

        userFeesInfo[msg.sender].stakedAmount = 0;
        userFeesInfo[msg.sender].stakedWeight = 0;
        totalStakedAmount -= stakedAmount;

        emit Unstaked(msg.sender, stakedAmount);
    }

    /** // TODO: Improve Natspec
     * @notice Allows users to harvest/claim their earned rewards from the protocol
     * @dev    Computes nextFromEpoch and currentEpoch and uses them as startEPoch and endEpoch respectively.
     *         Rewards are claculated from start epoch till endEpoch(currentEpoch - 1).
     *         Once calculated, user's total claimed rewards and nextFromEpoch details is updated.
     **/
    function harvestAll() public override whenNotPaused {
        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);

        uint256 rewards = _harvest(msg.sender, currentEpoch - 1);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, rewards);
    }

    /** // TODO: Improve Natspec
     * @notice Allows paginated harvests for users between a particular number of epochs.
     * @param  _tillEpoch   - the end epoch number till which rewards shall be counted.
     * @dev    _tillEpoch should never be equal to currentEpoch.
     *         Transfers rewards to caller and updates user's details.
     **/
    function harvestPaginated(uint256 _tillEpoch) external override whenNotPaused {
        uint256 rewards = _harvest(msg.sender, _tillEpoch);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, rewards);
    }

    /** // TODO: Improve Natspec
     * @notice Allows Push Governance to harvest/claim the earned rewards for its stake in the protocol
     * @param  _tillEpoch   - the end epoch number till which rewards shall be counted.
     * @dev    only accessible by Push Admin
     *         Unlike other harvest functions, this is designed to transfer rewards to Push Governance.
     **/
    function daoHarvestPaginated(uint256 _tillEpoch) external override onlyGovernance {
        uint256 rewards = _harvest(address(this), _tillEpoch);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(governance, rewards);
    }

    // ========================================== VIEW FUNCTIONS =========================================
    /** // TODO: Improve Natspec
     * @notice Calculates and returns the claimable reward amount for a user at a given EPOCH ID.
     * @dev    Formulae for reward calculation:
     *         rewards = ( userStakedWeight at Epoch(n) * avalailable rewards at EPOCH(n) ) / totalStakedWeight at EPOCH(n)
     **/
    function calculateEpochRewards(address _user, uint256 _epochId)
        public
        view
        override
        returns (uint256 rewards)
    {
        rewards = userFeesInfo[_user]
            .epochToUserStakedWeight[_epochId]
            .mul(epochRewards[_epochId])
            .div(epochToTotalStakedWeight[_epochId]);
    }

    /** // TODO: Improve Natspec
     * @notice Returns the epoch ID based on the start and end block numbers passed as input
     **/
    function lastEpochRelative(uint256 _from, uint256 _to)
        public
        view
        override
        returns (uint256)
    {
        require(
            _to >= _from,
            "PushCoreV3:lastEpochRelative:: Relative Block Number Overflow"
        );
        return uint256((_to - _from) / epochDuration + 1);
    }

    /**
     * @notice Retrieves the current total amount of `PROTOCOL_POOL_FEES`, from the PushCoreV3 contract.
     *
     * @return                         The total amount of protocol pool fees currently available in
     *                                 the PushCoreV3 contract.
     */
    function getProtocolPoolFees() public view override returns (uint256) {
        return pushCoreV3.PROTOCOL_POOL_FEES();
    }

    /**
     * @notice Calculates the pending rewards for a specified integrator.
     *
     * @dev This function returns the amount of rewards that are currently pending and can be claimed
     *      by the specified integrator.
     *
     * @param _integratorAddress       The address of the integrator whose pending rewards are to be
     *                                 calculated.
     *
     * @return pending                 The calculated amount of pending rewards for the integrator.
     */
    function pendingIntegratorRewards(address _integratorAddress) external view override returns (uint256 pending) {
        IntegratorData storage integrator = integrators[_integratorAddress];
        if (integrator.shares == 0) {
            return 0;
        }

        uint256 _rewardsPerShare = integrator.rewardsPerShare;

        if (block.number > integrator.lastRewardBlock && WALLET_FP_TOTAL_SHARES > 0) {
            uint256 newRewards = WALLET_FEE_POOL
                .mul(integrator.shares)
                .div(WALLET_FP_TOTAL_SHARES);

            _rewardsPerShare = _rewardsPerShare.add(
                newRewards.mul(PRECISION_FACTOR).div(WALLET_FP_TOTAL_SHARES)
            );
        }

        pending = integrator.shares
            .mul(_rewardsPerShare)
            .div(PRECISION_FACTOR)
            .sub(integrator.rewardDebt);
    }

    // ========================================= HELPER FUNCTIONS =======================================
    /** // TODO: Improve Natspec
     * @notice Function to return User's Push Holder weight based on amount being staked & current block number
     **/
    function _returnPushTokenWeight(
        address _account,
        uint256 _amount,
        uint256 _atBlock
    ) internal view returns (uint256) {
        return
            _amount.mul(
                _atBlock.sub(IPUSH(PUSH_TOKEN_ADDRESS).holderWeight(_account))
            );
    }

    /** // TODO: Improve Natspec
     * @notice Internal harvest function that is called for all types of harvest procedure.
     * @param  _user       - The user address for which the rewards will be calculated.
     * @param  _tillEpoch   - the end epoch number till which rewards shall be counted.
     * @dev    _tillEpoch should never be equal to currentEpoch.
     *         Transfers rewards to caller and updates user's details.
     **/
    function _harvest(address _user, uint256 _tillEpoch)
        internal
        returns (uint256 rewards)
    {
        IPUSH(PUSH_TOKEN_ADDRESS).resetHolderWeight(address(this));

        _adjustUserAndTotalStake(_user, 0);

        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);
        uint256 nextFromEpoch = lastEpochRelative(
            genesisEpoch,
            userFeesInfo[_user].lastClaimedBlock
        );

        require(
            currentEpoch > _tillEpoch,
            "PushCoreV3::harvestPaginated::Invalid _tillEpoch w.r.t currentEpoch"
        );
        require(
            _tillEpoch >= nextFromEpoch,
            "PushCoreV3::harvestPaginated::Invalid _tillEpoch w.r.t nextFromEpoch"
        );
        for (uint256 i = nextFromEpoch; i <= _tillEpoch; i++) {
            uint256 claimableReward = calculateEpochRewards(_user, i);
            rewards = rewards.add(claimableReward);
        }

        usersRewardsClaimed[_user] = usersRewardsClaimed[_user].add(rewards);
        // set the lastClaimedBlock to blocknumer at the end of `_tillEpoch`
        uint256 _epoch_to_block_number = genesisEpoch +
            _tillEpoch *
            epochDuration;
        userFeesInfo[_user].lastClaimedBlock = _epoch_to_block_number;

        emit RewardsHarvested(_user, rewards, nextFromEpoch, _tillEpoch);
    }

    /** // TODO: Improve Description
     * @notice Internal function that allows setting up the rewards for specific EPOCH IDs
     * @dev    Initializes (sets reward) for every epoch ID that falls between the lastEpochInitialized and currentEpoch
     *         Reward amount for specific EPOCH Ids depends on newly available Protocol_Pool_Fees.
                - If no new fees was accumulated, rewards for particular epoch ids can be zero
                - Records the Pool_Fees value used as rewards.
                - Records the last epoch id whose rewards were set.
     */
    function _setupEpochsRewardAndWeights(
        uint256 _userWeight,
        uint256 _currentEpoch
    ) private {
        uint256 _lastEpochInitiliazed = lastEpochRelative(
            genesisEpoch,
            lastEpochInitialized
        );
        // Setting up Epoch Based Rewards
        if (_currentEpoch > _lastEpochInitiliazed || _currentEpoch == 1) {
            // Calculate available rewards from HOLDER_FEE_POOL instead of PROTOCOL_POOL_FEES
            uint256 availableRewardsPerEpoch = (HOLDER_FEE_POOL - previouslySetEpochRewards);
            uint256 _epochGap = _currentEpoch.sub(_lastEpochInitiliazed);

            if (_epochGap > 1) {
                epochRewards[_currentEpoch - 1] += availableRewardsPerEpoch;
            } else {
                epochRewards[_currentEpoch] += availableRewardsPerEpoch;
            }

            // pull fees from core
            _pullProtocolFees();

            lastEpochInitialized = block.number;
            // Track previously set rewards against HOLDER_FEE_POOL instead of PROTOCOL_POOL_FEES
            previouslySetEpochRewards = HOLDER_FEE_POOL;
        }
        // Setting up Epoch Based TotalWeight
        if (
            lastTotalStakeEpochInitialized == 0 ||
            lastTotalStakeEpochInitialized == _currentEpoch
        ) {
            epochToTotalStakedWeight[_currentEpoch] += _userWeight;
        } else {
            for (
                uint256 i = lastTotalStakeEpochInitialized + 1;
                i <= _currentEpoch - 1;
                i++
            ) {
                if (epochToTotalStakedWeight[i] == 0) {
                    epochToTotalStakedWeight[i] = epochToTotalStakedWeight[
                        lastTotalStakeEpochInitialized
                    ];
                }
            }
            epochToTotalStakedWeight[_currentEpoch] =
                epochToTotalStakedWeight[lastTotalStakeEpochInitialized] +
                _userWeight;
        }
        lastTotalStakeEpochInitialized = _currentEpoch;
    }

    /** // TODO: Improve Natspec
     * @notice  This functions helps in adjustment of user's as well as totalWeigts, both of which are imperative for reward calculation at a particular epoch.
     * @dev     Enables adjustments of user's stakedWeight, totalStakedWeight, epochToTotalStakedWeight as well as epochToTotalStakedWeight.
     *          triggers _setupEpochsReward() to adjust rewards for every epoch till the current epoch
     *
     *          Includes 2 main cases of weight adjustments
     *          1st Case: User stakes for the very first time:
     *              - Simply update userFeesInfo, totalStakedWeight and epochToTotalStakedWeight of currentEpoch
     *
     *          2nd Case: User is NOT staking for first time - 2 Subcases
     *              2.1 Case: User stakes again but in Same Epoch
     *                  - Increase user's stake and totalStakedWeight
     *                  - Record the epochToUserStakedWeight for that epoch
     *                  - Record the epochToTotalStakedWeight of that epoch
     *
     *              2.2 Case: - User stakes again but in different Epoch
     *                  - Update the epochs between lastStakedEpoch & (currentEpoch - 1) with the old staked weight amounts
     *                  - While updating epochs between lastStaked & current Epochs, if any epoch has zero value for totalStakedWeight, update it with current totalStakedWeight value of the protocol
     *                  - For currentEpoch, initialize the epoch id with updated weight values for epochToUserStakedWeight & epochToTotalStakedWeight
     */
    function _adjustUserAndTotalStake(address _user, uint256 _userWeight)
        internal
    {
        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);
        _setupEpochsRewardAndWeights(_userWeight, currentEpoch);
        uint256 userStakedWeight = userFeesInfo[_user].stakedWeight;

        // Initiating 1st Case: User stakes for first time
        if (userStakedWeight == 0) {
            userFeesInfo[_user].stakedWeight = _userWeight;
        } else {
            // Initiating 2.1 Case: User stakes again but in Same Epoch
            uint256 lastStakedEpoch = lastEpochRelative(
                genesisEpoch,
                userFeesInfo[_user].lastStakedBlock
            );
            if (currentEpoch == lastStakedEpoch) {
                userFeesInfo[_user].stakedWeight =
                    userStakedWeight +
                    _userWeight;
            } else {
                // Initiating 2.2 Case: User stakes again but in Different Epoch
                for (uint256 i = lastStakedEpoch; i <= currentEpoch; i++) {
                    if (i != currentEpoch) {
                        userFeesInfo[_user].epochToUserStakedWeight[
                                i
                            ] = userStakedWeight;
                    } else {
                        userFeesInfo[_user].stakedWeight =
                            userStakedWeight +
                            _userWeight;
                        userFeesInfo[_user].epochToUserStakedWeight[
                                i
                            ] = userFeesInfo[_user].stakedWeight;
                    }
                }
            }
        }

        if (_userWeight != 0) {
            userFeesInfo[_user].lastStakedBlock = block.number;
        }
    }

    /** // TODO: Improve Natspec
     * @notice Internal function to stake tokens for a user
     * @dev Calculates user weight, transfers tokens, and updates staking info
     * @param _staker Address of the staking user
     * @param _amount Amount of tokens to stake
     */
    function _stake(address _staker, uint256 _amount) private {
        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);
        uint256 blockNumberToConsider = genesisEpoch.add(
            epochDuration.mul(currentEpoch)
        );
        uint256 userWeight = _returnPushTokenWeight(
            _staker,
            _amount,
            blockNumberToConsider
        );

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        userFeesInfo[_staker].stakedAmount =
            userFeesInfo[_staker].stakedAmount +
            _amount;
        userFeesInfo[_staker].lastClaimedBlock = userFeesInfo[_staker]
            .lastClaimedBlock == 0
            ? genesisEpoch
            : userFeesInfo[_staker].lastClaimedBlock;
        totalStakedAmount += _amount;
        // Adjust user and total rewards, piggyback method
        _adjustUserAndTotalStake(_staker, userWeight);
    }

    /**
     * @notice Pull protocol fees from the PushCoreV3 contract and distribute them
     *         into the wallet and holder fee pools. This function retrieves the total
     *         protocol fees from the PushCoreV3 contract, transfers them to address(this),
     *         and allocates them between `WALLET_FEE_POOL` and `HOLDER_FEE_POOL` based
     *         on the defined percentages.
     */
    function _pullProtocolFees() internal {
        uint256 feesToTransfer = pushCoreV3.PROTOCOL_POOL_FEES();
        pushCoreV3.transferProtocolFees(address(this), feesToTransfer);

        uint256 walletFeeAmount = feesToTransfer.mul(WALLET_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
        uint256 holderFeeAmount = feesToTransfer.sub(walletFeeAmount);

        WALLET_FEE_POOL = WALLET_FEE_POOL.add(walletFeeAmount);
        HOLDER_FEE_POOL = HOLDER_FEE_POOL.add(holderFeeAmount);
    }

    /**
     * @notice Function to calculate and distribute pending rewards for an integrator.
     *
     * @dev This function:
     *      1. Updates rewards based on new blocks mined since last harvest
     *      2. Calculates pending rewards using precision-scaled accounting
     *      3. Transfers rewards to the integrator
     *      4. Updates state to prevent double claiming
     *
     * @param _integratorAddress        The address of the integrator claiming rewards.
     *
     * @return rewards                  The amount of PUSH tokens transferred to the integrator.
     */
    function _harvestIntegratorRewards(address _integratorAddress) internal returns (uint256 rewards) {
        IntegratorData storage integrator = integrators[_integratorAddress];
        require(integrator.shares > 0, "PushStaking: not an integrator");

        uint256 currentBlock = block.number;

        // Update rewards if new blocks have been mined
        if (currentBlock > integrator.lastRewardBlock) {
            _pullProtocolFees();

            if (WALLET_FP_TOTAL_SHARES > 0) {
                // Calculate this integrator's share of new rewards
                uint256 newRewards = WALLET_FEE_POOL
                    .mul(integrator.shares)
                    .div(WALLET_FP_TOTAL_SHARES);

                // Update rewardsPerShare with precision scaling
                integrator.rewardsPerShare = integrator.rewardsPerShare.add(
                    newRewards.mul(PRECISION_FACTOR).div(WALLET_FP_TOTAL_SHARES)
                );
            }
            integrator.lastRewardBlock = currentBlock;
        }

        // Calculate pending rewards using precision scaling
        uint256 pending = integrator.shares
            .mul(integrator.rewardsPerShare)
            .div(PRECISION_FACTOR)
            .sub(integrator.rewardDebt);

        if (pending > 0) {
            rewards = pending;
            pushToken.safeTransfer(_integratorAddress, rewards);
            WALLET_FEE_POOL = WALLET_FEE_POOL.sub(rewards);

            // Update reward debt to prevent double claiming
            integrator.rewardDebt = integrator.shares
                .mul(integrator.rewardsPerShare)
                .div(PRECISION_FACTOR);

            emit IntegratorRewardsHarvested(_integratorAddress, rewards);
        }
    }

    /**
     * @notice Internal function to update the fee pools for wallets and token holders.
     *
     * @dev This function recalculates the distribution of total protocol pool fees between the
     *      `WALLET_FEE_POOL` and `HOLDER_FEE_POOL` based on their respective percentages.
     */
    function _updateFeePools() internal {
        uint256 totalFees = getProtocolPoolFees();

        WALLET_FEE_POOL = totalFees.mul(WALLET_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
        HOLDER_FEE_POOL = totalFees.mul(HOLDER_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
    }

    // ===================================== RESTRICTED FUNCTIONS =======================================

    /**
     * @notice Adds a specified amount of rewards to the protocol pool fees.
     *
     * @dev This function allows the admin to transfer a specified `_rewardAmount` of PUSH tokens
     *      from the caller's address to the contract, increasing the `PROTOCOL_POOL_FEES`.
     *
     * @param _rewardAmount             The amount of PUSH tokens to be added to the protocol pool fees.
     */
    function addPoolFees(uint256 _rewardAmount) external override onlyAdmin {
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardAmount
        );
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_rewardAmount);
    }

    /**
     * @notice Pauses the contract temporarily halting all critical operations.
     *
     * @dev This function can only be called by the admin. It sets the contract to a
     *      paused state, preventing functions like staking and reward distribution from
     *      being executed until unpaused.
     */
    function pauseContract() external override onlyAdmin {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming all normal operations.
     *
     * @dev This function can only be called by the contract admin. It lifts the paused
     *      state of the contract, allowing staking and other functions to be resumed.
     */
    function unPauseContract() external override onlyAdmin {
        _unpause();
    }

    /**
     * @notice Updates the contract's admin to a new address.
     *
     * @dev This function allows governance to set a new admin for the contract. The new
     *      admin must be a valid, non-zero address and different from the current admin.
     *
     * @param _newAdmin                 The address of the new admin to be assigned.
     */
    function setAdmin(address _newAdmin) external override onlyGovernance {
        require(_newAdmin != address(0), "PushStaking: invalid admin address");
        require(_newAdmin != admin, "PushStaking: new admin same as current admin");

        address oldAdmin = admin;
        admin = _newAdmin;

        emit AdminChanged(oldAdmin, _newAdmin);
    }

    /**
     * @notice Updates the fee distribution percentages for the wallet fee pool and the holder fee pool.
     *
     * @dev This function allows governance to set new percentages for distributing fees between
     *      the wallet and holder fee pools. The sum of `_walletFeePercentage` and `_holderFeePercentage`
     *      must add up to 100%.
     *
     * @param _walletFeePercentage      The new percentage of fees to be allocated to the wallet fee pool.
     * @param _holderFeePercentage      The new percentage of fees to be allocated to the holder fee pool.
     */
    function updateFeePoolPercentages(uint256 _walletFeePercentage, uint256 _holderFeePercentage) public override onlyAdmin {
        require(_walletFeePercentage.add(_holderFeePercentage) == PERCENTAGE_DIVISOR, "PushStaking: percentages must add up to 100");

        WALLET_FEE_PERCENTAGE = _walletFeePercentage;
        HOLDER_FEE_PERCENTAGE = _holderFeePercentage;

        _updateFeePools();
    }

    // TODO: Add Natspec
    modifier onlyGovernance() {
        require(msg.sender == governance, "PushStaking: caller is not the governance");
        _;
    }

    // TODO: Add Natspec
    modifier onlyAdmin() {
        require(msg.sender == admin, "PushStaking: caller is not the admin");
        _;
    }
}