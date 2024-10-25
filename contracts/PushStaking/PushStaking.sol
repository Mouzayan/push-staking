pragma solidity >=0.6.12 < 0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../PushCore/PushCoreV3.sol";
import "../PushCore/PushCoreStorageV1_5.sol";
import "../PushCore/PushCoreStorageV2.sol";
import "../interfaces/IPUSH.sol";

// TODO: Add contract description
// TODO:Create Interface for PushStaking
// TODO: NEXT: Address Integrator staking
contract PushStaking is PushCoreStorageV1_5, PushCoreStorageV2, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    PushCoreV3 public pushCoreV3;
    IERC20 public pushToken;

    uint256 public WALLET_FEE_POOL;
    uint256 public HOLDER_FEE_POOL;

    uint256 public WALLET_FEE_PERCENTAGE = 30;
    uint256 public HOLDER_FEE_PERCENTAGE = 70;
    uint256 private constant PERCENTAGE_DIVISOR = 100;

    address public admin;

    event Staked(address indexed user, uint256 indexed amountStaked);
    event Unstaked(address indexed user, uint256 indexed amountUnstaked);
    event RewardsHarvested(
        address indexed user,
        uint256 indexed rewardAmount,
        uint256 fromEpoch,
        uint256 tillEpoch
    );

    modifier onlyGovernance() {
        require(msg.sender == governance, "PushStaking: caller is not the governance");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "PushStaking: caller is not the admin");
        _;
    }

    constructor(address _pushCoreV3Address, address _governance, address _admin) public {
        pushCoreV3 = PushCoreV3(_pushCoreV3Address);
        pushToken = IERC20(pushCoreV3.PUSH_TOKEN_ADDRESS());
        governance = _governance;
        admin = _admin;
    }

    function getProtocolPoolFees() public view returns (uint256) {
        return pushCoreV3.PROTOCOL_POOL_FEES();
    }

    function updateFeePoolPercentages(uint256 _walletFeePercentage, uint256 _holderFeePercentage) public onlyGovernance {
        require(_walletFeePercentage.add(_holderFeePercentage) == PERCENTAGE_DIVISOR, "PushStaking: percentages must add up to 100");

        WALLET_FEE_PERCENTAGE = _walletFeePercentage;
        HOLDER_FEE_PERCENTAGE = _holderFeePercentage;

        updateFeePools();
    }

    function updateFeePools() public {
        uint256 totalFees = getProtocolPoolFees();

        WALLET_FEE_POOL = totalFees.mul(WALLET_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
        HOLDER_FEE_POOL = totalFees.mul(HOLDER_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
    }

    // =============================== STAKING AND REWARDS CLAIMING FUNCTIONS =============================
    /** // TODO: Add Natspec
     * @notice Function to initialize the staking procedure in Core contract
     * @dev    Requires caller to deposit/stake 1 PUSH token to ensure staking pool is never zero.
     **/
    function initializeStake() external {
        require(
            genesisEpoch == 0,
            "PushCoreV3::initializeStake: Already Initialized"
        );
        genesisEpoch = block.number;
        lastEpochInitialized = genesisEpoch;

        _stake(address(this), 1e18);
    }

    /** // TODO: Add Natspec
     * @notice Function to allow users to stake in the protocol
     * @dev    Records total Amount staked so far by a particular user
     *         Triggers weight adjustents functions
     * @param  _amount represents amount of tokens to be staked
     **/
    function stake(uint256 _amount) external {
        _stake(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    /** // TODO: Add Natspec
     * @notice Function to allow users to Unstake from the protocol
     * @dev    Allows stakers to claim rewards before unstaking their tokens
     *         Triggers weight adjustents functions
     *         Allows users to unstake all amount at once
     **/
    function unstake() external {
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

    /** // TODO: Add Natspec
     * @notice Allows users to harvest/claim their earned rewards from the protocol
     * @dev    Computes nextFromEpoch and currentEpoch and uses them as startEPoch and endEpoch respectively.
     *         Rewards are claculated from start epoch till endEpoch(currentEpoch - 1).
     *         Once calculated, user's total claimed rewards and nextFromEpoch details is updated.
     **/
    function harvestAll() public {
        uint256 currentEpoch = lastEpochRelative(genesisEpoch, block.number);

        uint256 rewards = _harvest(msg.sender, currentEpoch - 1);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, rewards);
    }

    /** // TODO: Add Natspec
     * @notice Allows paginated harvests for users between a particular number of epochs.
     * @param  _tillEpoch   - the end epoch number till which rewards shall be counted.
     * @dev    _tillEpoch should never be equal to currentEpoch.
     *         Transfers rewards to caller and updates user's details.
     **/
    function harvestPaginated(uint256 _tillEpoch) external {
        uint256 rewards = _harvest(msg.sender, _tillEpoch);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, rewards);
    }

    /** // TODO: Add Natspec
     * @notice Allows Push Governance to harvest/claim the earned rewards for its stake in the protocol
     * @param  _tillEpoch   - the end epoch number till which rewards shall be counted.
     * @dev    only accessible by Push Admin
     *         Unlike other harvest functions, this is designed to transfer rewards to Push Governance.
     **/
    function daoHarvestPaginated(uint256 _tillEpoch) onlyGovernance external {
        uint256 rewards = _harvest(address(this), _tillEpoch);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(governance, rewards);
    }

    // ========================================== VIEW FUNCTIONS =========================================
    /** // TODO: Add Natspec
     * @notice Calculates and returns the claimable reward amount for a user at a given EPOCH ID.
     * @dev    Formulae for reward calculation:
     *         rewards = ( userStakedWeight at Epoch(n) * avalailable rewards at EPOCH(n) ) / totalStakedWeight at EPOCH(n)
     **/
    function calculateEpochRewards(address _user, uint256 _epochId)
        public
        view
        returns (uint256 rewards)
    {
        rewards = userFeesInfo[_user]
            .epochToUserStakedWeight[_epochId]
            .mul(epochRewards[_epochId])
            .div(epochToTotalStakedWeight[_epochId]);
    }

    /** // TODO: Add Natspec
     * @notice Returns the epoch ID based on the start and end block numbers passed as input
     **/
    function lastEpochRelative(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        require(
            _to >= _from,
            "PushCoreV3:lastEpochRelative:: Relative Block Number Overflow"
        );
        return uint256((_to - _from) / epochDuration + 1);
    }

    // ========================================= HELPER FUNCTIONS =======================================
    /** // TODO: Add Natspec
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

    /** // TODO: Add Natspec
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

    /** // TODO: Revisit Description
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
            uint256 availableRewardsPerEpoch = (PROTOCOL_POOL_FEES -
                previouslySetEpochRewards);
            uint256 _epochGap = _currentEpoch.sub(_lastEpochInitiliazed);

            if (_epochGap > 1) {
                epochRewards[_currentEpoch - 1] += availableRewardsPerEpoch;
            } else {
                epochRewards[_currentEpoch] += availableRewardsPerEpoch;
            }

            // pull fees from core
            _pullProtocolFees();

            lastEpochInitialized = block.number;
            previouslySetEpochRewards = PROTOCOL_POOL_FEES;
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

    /** // TODO: Revisit Natspec
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

    // TODO: Revisit Natspec
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

    // TODO: add Natspec
    function _pullProtocolFees() internal {
        uint256 feesToTransfer = pushCoreV3.PROTOCOL_POOL_FEES();
        pushCoreV3.transferProtocolFees(address(this), feesToTransfer);

        uint256 walletFeeAmount = feesToTransfer.mul(WALLET_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
        uint256 holderFeeAmount = feesToTransfer.sub(walletFeeAmount);

        WALLET_FEE_POOL = WALLET_FEE_POOL.add(walletFeeAmount);
        HOLDER_FEE_POOL = HOLDER_FEE_POOL.add(holderFeeAmount);
    }

    // ===================================== RESTRICTED FUNCTIONS =======================================
    /** // TODO: Add Natspec.
     * Allows caller to add pool_fees at any given epoch
     **/
    function addPoolFees(uint256 _rewardAmount) external {
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardAmount
        );
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_rewardAmount);
    }

    // TODO: Add Natspec.
    function setGovernanceAddress(address _governanceAddress) onlyAdmin external {
        governance = _governanceAddress;
    }

    // TODO: Add Natspec.
    function pauseContract() onlyGovernance external {
        _pause();
    }

    // TODO: Add Natspec.
    function unPauseContract() onlyGovernance external {
        _unpause();
    }
}