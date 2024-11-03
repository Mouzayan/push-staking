pragma solidity >=0.6.12 < 0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../PushCore/PushCoreV3.sol";

interface IPushStaking {
    // Structs
    /**
     * @notice Struct containing an integrator's data.
     * @param shares                The actual number of shares an integrator has (not the percentage).
     * @param lastRewardBlock       Block number when rewards were last calculated
     * @param rewardsPerShare       Accumulated rewards per share (scaled by 1e12 for precision).
     * @param rewardDebt            Amount of rewards already claimed, prevents double claiming.
     */
    struct IntegratorData {
        uint256 shares;
        uint256 lastRewardBlock;
        uint256 rewardsPerShare;
        uint256 rewardDebt;
    }

    // Events
    event Staked(address indexed user, uint256 amountStaked);
    event Unstaked(address indexed user, uint256 amountUnstaked);
    event RewardsHarvested(
        address indexed user,
        uint256 rewardAmount,
        uint256 fromEpoch,
        uint256 tillEpoch
    );
    event IntegratorAdded(address indexed integratorAddress, uint256 shares, uint256 newTotalShares);
    event IntegratorRemoved(address indexed integratorAddress, uint256 shares, uint256 newTotalShares);
    event IntegratorRewardsHarvested(address indexed integratorAddress, uint256 rewards);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);

    // Integrator Staking Functions
    function addIntegrator(address _integratorAddress, uint256 _sharePercentage) external;
    function removeIntegrator(address _integratorAddress) external;
    function harvestIntegratorRewards() external;

    // Token Holder Staking Functions
    function initializeStake() external;
    function stake(uint256 _amount) external;
    function unstake() external;
    function harvestAll() external;
    function harvestPaginated(uint256 _tillEpoch) external;
    function daoHarvestPaginated(uint256 _tillEpoch) external;

    // View Functions
    function calculateEpochRewards(address _user, uint256 _epochId) external view returns (uint256 rewards);
    function lastEpochRelative(uint256 _from, uint256 _to) external view returns (uint256);
    function getProtocolPoolFees() external view returns (uint256);
    function pendingIntegratorRewards(address _integratorAddress) external view returns (uint256 pending);

    // Admin Functions
    function addPoolFees(uint256 _rewardAmount) external;
    function pauseContract() external;
    function unPauseContract() external;
    function setAdmin(address _newAdmin) external;
    function updateFeePoolPercentages(uint256 _walletFeePercentage, uint256 _holderFeePercentage) external;

    // State Variable Getters
    function pushCoreV3() external view returns (PushCoreV3);
    function pushToken() external view returns (IERC20);
    function WALLET_FEE_POOL() external view returns (uint256);
    function HOLDER_FEE_POOL() external view returns (uint256);
    function WALLET_FP_TOTAL_SHARES() external view returns (uint256);
    function WALLET_FEE_PERCENTAGE() external view returns (uint256);
    function HOLDER_FEE_PERCENTAGE() external view returns (uint256);
    function TREASURY_WALLET() external view returns (address);
    function admin() external view returns (address);
    function integrators(address) external view returns (
        uint256 shares,
        uint256 lastRewardBlock,
        uint256 rewardsPerShare,
        uint256 rewardDebt
    );
}