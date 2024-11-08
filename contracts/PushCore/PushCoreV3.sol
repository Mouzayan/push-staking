pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "../interfaces/IPUSH.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IEPNSCommV1.sol";
import "../interfaces/ITokenBridge.sol";
import "../interfaces/IPushStaking.sol";

import "./PushCoreStorageV3.sol";
import "./PushCoreStorageV2.sol";
import "./PushCoreStorageV1_5.sol";

/**
 * @title PushCoreV3
 * @notice PushCoreV3 upgrades PushCoreV2 with a modular architecture, separating core protocol
 *         functions (channel creation, notification management, fee collection) from staking
 *         and reward distribution. PushCoreV3 primarily focuses on managing channel-related
 *         functionality.
 *
 * @dev While PushCoreV2 handled all protocol functions — including staking and rewards —
 *      PushCoreV3 offloads staking-related tasks to a dedicated `PushStaking` contract,
 *      retaining only channel and notification management.
 *
 *      PushCoreV3 includes two key functions to interface with the new `PushStaking` contract:
 *      - `setPushStaking()`: Sets the address of the `PushStaking` contract.
 *      - `transferProtocolFees()`: Transfers protocol fees to `PushStaking` for reward distribution.
 */
contract PushCoreV3 is
    Initializable,
    PausableUpgradeable,
    PushCoreStorageV3,
    PushCoreStorageV2,
    PushCoreStorageV1_5
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ***************
        EVENTS
     *************** */
    event UpdateChannel(
        address indexed channel,
        bytes identity,
        uint256 indexed amountDeposited
    );
    event RewardsClaimed(address indexed user, uint256 rewardAmount);
    event ChannelVerified(address indexed channel, address indexed verifier);
    event ChannelVerificationRevoked(
        address indexed channel,
        address indexed revoker
    );
    event DeactivateChannel(
        address indexed channel,
        uint256 indexed amountRefunded
    );
    event ReactivateChannel(
        address indexed channel,
        uint256 indexed amountDeposited
    );
    event ChannelBlocked(address indexed channel);
    event AddChannel(
        address indexed channel,
        ChannelType indexed channelType,
        bytes identity
    );
    event ChannelNotifcationSettingsAdded(
        address _channel,
        uint256 totalNotifOptions,
        string _notifSettings,
        string _notifDescription
    );
    event AddSubGraph(address indexed channel, bytes _subGraphData);
    event TimeBoundChannelDestroyed(
        address indexed channel,
        uint256 indexed amountRefunded
    );
    event ChannelOwnershipTransfer(
        address indexed channel,
        address indexed newOwner
    );
    event IncentivizeChatReqReceived(
        address requestSender,
        address requestReceiver,
        uint256 amountForReqReceiver,
        uint256 feePoolAmount,
        uint256 timestamp
    );
    event ChatIncentiveClaimed(
        address indexed user,
        uint256 indexed amountClaimed
    );

    /* ***************
        INITIALIZER
    *************** */

    function initialize(
        address _pushChannelAdmin,
        address _pushTokenAddress,
        address _wethAddress,
        address _uniswapRouterAddress,
        address _lendingPoolProviderAddress,
        address _daiAddress,
        address _pushStakingAddress,
        address _aDaiAddress,
        uint256 _referralCode
    ) public initializer returns (bool success) {
        // setup addresses
        pushChannelAdmin = _pushChannelAdmin;
        governance = _pushChannelAdmin; // Will be changed on-Chain governance Address later
        daiAddress = _daiAddress;
        pushStakingAddress = _pushStakingAddress;
        aDaiAddress = _aDaiAddress;
        WETH_ADDRESS = _wethAddress;
        REFERRAL_CODE = _referralCode;
        PUSH_TOKEN_ADDRESS = _pushTokenAddress;
        UNISWAP_V2_ROUTER = _uniswapRouterAddress;
        lendingPoolProviderAddress = _lendingPoolProviderAddress;
        FEE_AMOUNT = 10 ether; // PUSH Amount that will be charged as Protocol Pool Fees
        MIN_POOL_CONTRIBUTION = 50 ether; // Channel's poolContribution should never go below MIN_POOL_CONTRIBUTION
        ADD_CHANNEL_MIN_FEES = 50 ether; // can never be below MIN_POOL_CONTRIBUTION

        ADJUST_FOR_FLOAT = 10**7;
        groupLastUpdate = block.number;
        groupNormalizedWeight = ADJUST_FOR_FLOAT; // Always Starts with 1 * ADJUST FOR FLOAT

        // Create Channel
        success = true;
    }

    /* ***************

    SETTER & HELPER FUNCTIONS

    *************** */
    function onlyPushChannelAdmin() private {
        require(
            msg.sender == pushChannelAdmin,
            "PushCoreV2::onlyPushChannelAdmin: Invalid Caller"
        );
    }

    function onlyGovernance() private {
        require(
            msg.sender == governance,
            "PushCoreV2::onlyGovernance: Invalid Caller"
        );
    }

    function onlyActivatedChannels(address _channel) private {
        require(
            channels[_channel].channelState == 1,
            "PushCoreV2::onlyActivatedChannels: Invalid Channel"
        );
    }

    function onlyChannelOwner(address _channel) private {
        require(
            ((channels[_channel].channelState == 1 && msg.sender == _channel) ||
                (msg.sender == pushChannelAdmin && _channel == address(0x0))),
            "PushCoreV2::onlyChannelOwner: Invalid Channel Owner"
        );
    }

    function addSubGraph(bytes calldata _subGraphData) external {
        onlyActivatedChannels(msg.sender);
        emit AddSubGraph(msg.sender, _subGraphData);
    }

    function setEpnsCommunicatorAddress(address _commAddress) external {
        onlyPushChannelAdmin();
        epnsCommunicator = _commAddress;
    }

    function setGovernanceAddress(address _governanceAddress) external {
        onlyPushChannelAdmin();
        governance = _governanceAddress;
    }

    function setFeeAmount(uint256 _newFees) external {
        onlyGovernance();
        require(
            _newFees > 0 && _newFees < ADD_CHANNEL_MIN_FEES,
            "PushCoreV2::setFeeAmount: Invalid Fee"
        );
        FEE_AMOUNT = _newFees;
    }

    function setMinPoolContribution(uint256 _newAmount) external {
        onlyGovernance();
        require(
            _newAmount > 0,
            "PushCoreV2::setMinPoolContribution: Invalid Amount"
        );
        MIN_POOL_CONTRIBUTION = _newAmount;
    }

    function pauseContract() external {
        onlyGovernance();
        _pause();
    }

    function unPauseContract() external {
        onlyGovernance();
        _unpause();
    }

    /**
     * @notice Allows to set the Minimum amount threshold for Creating Channels
     *
     * @dev    Minimum required amount can never be below MIN_POOL_CONTRIBUTION
     *
     * @param _newFees new minimum fees required for Channel Creation
     **/
    function setMinChannelCreationFees(uint256 _newFees) external {
        onlyGovernance();
        require(
            _newFees >= MIN_POOL_CONTRIBUTION,
            "PushCoreV2::setMinChannelCreationFees: Invalid Fees"
        );
        ADD_CHANNEL_MIN_FEES = _newFees;
    }

    function transferPushChannelAdminControl(address _newAdmin) external {
        onlyPushChannelAdmin();
        require(
            _newAdmin != address(0),
            "PushCoreV2::transferPushChannelAdminControl: Invalid Address"
        );
        require(
            _newAdmin != pushChannelAdmin,
            "PushCoreV2::transferPushChannelAdminControl: Similar Admnin Address"
        );
        pushChannelAdmin = _newAdmin;
    }

    /* ***********************************

        CHANNEL RELATED FUNCTIONALTIES

    **************************************/
    /**
     * @notice Allows Channel Owner to update their Channel's Details like Description, Name, Logo, etc by passing in a new identity bytes hash
     *
     * @dev  Only accessible when contract is NOT Paused
     *       Only accessible when Caller is the Channel Owner itself
     *       If Channel Owner is updating the Channel Meta for the first time:
     *       Required Fees => 50 PUSH tokens
     *
     *       If Channel Owner is updating the Channel Meta for the N time:
     *       Required Fees => (50 * N) PUSH Tokens
     *
     *       Total fees goes to PROTOCOL_POOL_FEES
     *       Updates the channelUpdateCounter
     *       Updates the channelUpdateBlock
     *       Records the Block Number of the Block at which the Channel is being updated
     *       Emits an event with the new identity for the respective Channel Address
     *
     * @param _channel     address of the Channel
     * @param _newIdentity bytes Value for the New Identity of the Channel
     * @param _amount amount of PUSH Token required for updating channel details.
     **/
    function updateChannelMeta(
        address _channel,
        bytes calldata _newIdentity,
        uint256 _amount
    ) external whenNotPaused {
        onlyChannelOwner(_channel);
        uint256 updateCounter = channelUpdateCounter[_channel].add(1);
        uint256 requiredFees = ADD_CHANNEL_MIN_FEES.mul(updateCounter);

        require(
            _amount >= requiredFees,
            "PushCoreV2::updateChannelMeta: Insufficient Deposit Amount"
        );
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_amount);
        channelUpdateCounter[_channel] = updateCounter;
        channels[_channel].channelUpdateBlock = block.number;

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            _channel,
            address(this),
            _amount
        );
        emit UpdateChannel(_channel, _newIdentity, _amount);
    }

    /**
     * @notice An external function that allows users to Create their Own Channels by depositing a valid amount of PUSH
     * @dev    Only allows users to Create One Channel for a specific address.
     *         Only allows a Valid Channel Type to be assigned for the Channel Being created.
     *         Validates and Transfers the amount of PUSH  from the Channel Creator to the EPNS Core Contract
     *
     * @param  _channelType the type of the Channel Being created
     * @param  _identity the bytes value of the identity of the Channel
     * @param  _amount Amount of PUSH  to be deposited before Creating the Channel
     * @param  _channelExpiryTime the expiry time for time bound channels
     **/
    function createChannelWithPUSH(
        ChannelType _channelType,
        bytes calldata _identity,
        uint256 _amount,
        uint256 _channelExpiryTime
    ) external whenNotPaused {
        require(
            _amount >= ADD_CHANNEL_MIN_FEES,
            "PushCoreV2::_createChannelWithPUSH: Insufficient Deposit Amount"
        );
        require(
            channels[msg.sender].channelState == 0,
            "PushCoreV2::onlyInactiveChannels: Channel already Activated"
        );
        require(
            (_channelType == ChannelType.InterestBearingOpen ||
                _channelType == ChannelType.InterestBearingMutual ||
                _channelType == ChannelType.TimeBound ||
                _channelType == ChannelType.TokenGaited),
            "PushCoreV2::onlyUserAllowedChannelType: Invalid Channel Type"
        );

        emit AddChannel(msg.sender, _channelType, _identity);

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _createChannel(msg.sender, _channelType, _amount, _channelExpiryTime);
    }

    /**
     * @notice Base Channel Creation Function that allows users to Create Their own Channels and Stores crucial details about the Channel being created
     * @dev    -Initializes the Channel Struct
     *         -Subscribes the Channel's Owner to Imperative EPNS Channels as well as their Own Channels
     *         - Updates the CHANNEL_POOL_FUNDS and PROTOCOL_POOL_FEES in the contract.
     *
     * @param _channel         address of the channel being Created
     * @param _channelType     The type of the Channel
     * @param _amountDeposited The total amount being deposited while Channel Creation
     * @param _channelExpiryTime the expiry time for time bound channels
     **/
    function _createChannel(
        address _channel,
        ChannelType _channelType,
        uint256 _amountDeposited,
        uint256 _channelExpiryTime
    ) private {
        uint256 poolFeeAmount = FEE_AMOUNT;
        uint256 poolFundAmount = _amountDeposited.sub(poolFeeAmount);
        //store funds in pool_funds & pool_fees
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.add(poolFundAmount);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(poolFeeAmount);

        // Calculate channel weight
        uint256 _channelWeight = poolFundAmount.mul(ADJUST_FOR_FLOAT).div(
            MIN_POOL_CONTRIBUTION
        );
        // Next create the channel and mark user as channellized
        channels[_channel].channelState = 1;
        channels[_channel].poolContribution = poolFundAmount;
        channels[_channel].channelType = _channelType;
        channels[_channel].channelStartBlock = block.number;
        channels[_channel].channelUpdateBlock = block.number;
        channels[_channel].channelWeight = _channelWeight;
        // Add to map of addresses and increment channel count
        uint256 _channelsCount = channelsCount;
        channelsCount = _channelsCount.add(1);

        if (_channelType == ChannelType.TimeBound) {
            require(
                _channelExpiryTime > block.timestamp,
                "PushCoreV2::createChannel: Invalid channelExpiryTime"
            );
            channels[_channel].expiryTime = _channelExpiryTime;
        }

        // Subscribe them to their own channel as well
        address _epnsCommunicator = epnsCommunicator;
        if (_channel != pushChannelAdmin) {
            IEPNSCommV1(_epnsCommunicator).subscribeViaCore(_channel, _channel);
        }

        // All Channels are subscribed to EPNS Alerter as well, unless it's the EPNS Alerter channel iteself
        if (_channel != address(0x0)) {
            IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
                address(0x0),
                _channel
            );
            IEPNSCommV1(_epnsCommunicator).subscribeViaCore(
                _channel,
                pushChannelAdmin
            );
        }
    }

    /**
     * @notice Function that allows Channel Owners to Destroy their Time-Bound Channels
     * @dev    - Can only be called the owner of the Channel or by the EPNS Governance/Admin.
     *         - EPNS Governance/Admin can only destory a channel after 14 Days of its expriation timestamp.
     *         - Can only be called if the Channel is of type - TimeBound
     *         - Can only be called after the Channel Expiry time is up.
     *         - If Channel Owner destroys the channel after expiration, he/she recieves back refundable amount & CHANNEL_POOL_FUNDS decreases.
     *         - If Channel is destroyed by EPNS Governance/Admin, No refunds for channel owner. Refundable Push tokens are added to PROTOCOL_POOL_FEES.
     *         - Deletes the Channel completely
     *         - It transfers back refundable tokenAmount back to the USER.
     **/

    function destroyTimeBoundChannel(address _channelAddress)
        external
        whenNotPaused
    {
        onlyActivatedChannels(_channelAddress);
        Channel memory channelData = channels[_channelAddress];

        require(
            channelData.channelType == ChannelType.TimeBound,
            "PushCoreV2::destroyTimeBoundChannel: Channel not TIME BOUND"
        );
        require(
            (msg.sender == _channelAddress &&
                channelData.expiryTime < block.timestamp) ||
                (msg.sender == pushChannelAdmin &&
                    channelData.expiryTime.add(14 days) < block.timestamp),
            "PushCoreV2::destroyTimeBoundChannel: Invalid Caller or Channel Not Expired"
        );
        uint256 totalRefundableAmount = channelData.poolContribution;

        if (msg.sender != pushChannelAdmin) {
            CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(totalRefundableAmount);
            IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(
                msg.sender,
                totalRefundableAmount
            );
        } else {
            CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(totalRefundableAmount);
            PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(totalRefundableAmount);
        }
        // Unsubscribing from imperative Channels
        address _epnsCommunicator = epnsCommunicator;
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            address(0x0),
            _channelAddress
        );
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            _channelAddress,
            _channelAddress
        );
        IEPNSCommV1(_epnsCommunicator).unSubscribeViaCore(
            _channelAddress,
            pushChannelAdmin
        );
        // Decrement Channel Count and Delete Channel Completely
        channelsCount = channelsCount.sub(1);
        delete channels[_channelAddress];

        emit TimeBoundChannelDestroyed(msg.sender, totalRefundableAmount);
    }

    /** @notice - Deliminated Notification Settings string contains -> Total Notif Options + Notification Settings
     * For instance: 5+1-0+2-50-20-100+1-1+2-78-10-150
     *  5 -> Total Notification Options provided by a Channel owner
     *
     *  For Boolean Type Notif Options
     *  1-0 -> 1 stands for BOOLEAN type - 0 stands for Default Boolean Type for that Notifcation(set by Channel Owner), In this case FALSE.
     *  1-1 stands for BOOLEAN type - 1 stands for Default Boolean Type for that Notifcation(set by Channel Owner), In this case TRUE.
     *
     *  For SLIDER TYPE Notif Options
     *   2-50-20-100 -> 2 stands for SLIDER TYPE - 50 stands for Default Value for that Option - 20 is the Start Range of that SLIDER - 100 is the END Range of that SLIDER Option
     *  2-78-10-150 -> 2 stands for SLIDER TYPE - 78 stands for Default Value for that Option - 10 is the Start Range of that SLIDER - 150 is the END Range of that SLIDER Option
     *
     *  @param _notifOptions - Total Notification options provided by the Channel Owner
     *  @param _notifSettings- Deliminated String of Notification Settings
     *  @param _notifDescription - Description of each Notification that depicts the Purpose of that Notification
     *  @param _amountDeposited - Fees required for setting up channel notification settings
     **/
    function createChannelSettings(
        uint256 _notifOptions,
        string calldata _notifSettings,
        string calldata _notifDescription,
        uint256 _amountDeposited
    ) external {
        onlyActivatedChannels(msg.sender);
        require(
            _amountDeposited >= ADD_CHANNEL_MIN_FEES,
            "PushCoreV2::createChannelSettings: Insufficient Funds Passed"
        );

        string memory notifSetting = string(
            abi.encodePacked(
                Strings.toString(_notifOptions),
                "+",
                _notifSettings
            )
        );
        channelNotifSettings[msg.sender] = notifSetting;

        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(_amountDeposited);
        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amountDeposited
        );
        emit ChannelNotifcationSettingsAdded(
            msg.sender,
            _notifOptions,
            notifSetting,
            _notifDescription
        );
    }

    /**
     * @notice Allows Channel Owner to Deactivate his/her Channel for any period of Time. Channels Deactivated can be Activated again.
     * @dev    - Function can only be Called by Already Activated Channels
     *         - Calculates the totalRefundableAmount for the Channel Owner.
     *         - The function deducts MIN_POOL_CONTRIBUTION from refundAble amount to ensure that channel's weight & poolContribution never becomes ZERO.
     *         - Updates the State of the Channel(channelState) and the New Channel Weight in the Channel's Struct
     *         - In case, the Channel Owner wishes to reactivate his/her channel, they need to Deposit at least the Minimum required PUSH  while reactivating.
     **/

    function deactivateChannel() external whenNotPaused {
        onlyActivatedChannels(msg.sender);
        Channel storage channelData = channels[msg.sender];

        uint256 minPoolContribution = MIN_POOL_CONTRIBUTION;
        uint256 totalRefundableAmount = channelData.poolContribution.sub(
            minPoolContribution
        );

        uint256 _newChannelWeight = minPoolContribution
            .mul(ADJUST_FOR_FLOAT)
            .div(minPoolContribution);

        channelData.channelState = 2;
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(totalRefundableAmount);
        channelData.channelWeight = _newChannelWeight;
        channelData.poolContribution = minPoolContribution;

        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(
            msg.sender,
            totalRefundableAmount
        );

        emit DeactivateChannel(msg.sender, totalRefundableAmount);
    }

    /**
     * @notice Allows Channel Owner to Reactivate his/her Channel again.
     * @dev    - Function can only be called by previously Deactivated Channels
     *         - Channel Owner must Depost at least minimum amount of PUSH  to reactivate his/her channel.
     *         - Deposited PUSH amount is distributed between CHANNEL_POOL_FUNDS and PROTOCOL_POOL_FEES
     *         - Calculation of the new Channel Weight and poolContribution is performed and stored
     *         - Updates the State of the Channel(channelState) in the Channel's Struct.
     * @param _amount Amount of PUSH to be deposited
     **/

    function reactivateChannel(uint256 _amount) external whenNotPaused {
        require(
            _amount >= ADD_CHANNEL_MIN_FEES,
            "PushCoreV2::reactivateChannel: Insufficient Funds"
        );
        require(
            channels[msg.sender].channelState == 2,
            "PushCoreV2::onlyDeactivatedChannels: Channel is Active"
        );

        IERC20(PUSH_TOKEN_ADDRESS).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        uint256 poolFeeAmount = FEE_AMOUNT;
        uint256 poolFundAmount = _amount.sub(poolFeeAmount);
        //store funds in pool_funds & pool_fees
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.add(poolFundAmount);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(poolFeeAmount);

        Channel storage channelData = channels[msg.sender];

        uint256 _newPoolContribution = channelData.poolContribution.add(
            poolFundAmount
        );
        uint256 _newChannelWeight = _newPoolContribution
            .mul(ADJUST_FOR_FLOAT)
            .div(MIN_POOL_CONTRIBUTION);

        channelData.channelState = 1;
        channelData.poolContribution = _newPoolContribution;
        channelData.channelWeight = _newChannelWeight;

        emit ReactivateChannel(msg.sender, _amount);
    }

    /**
     * @notice ALlows the pushChannelAdmin to Block any particular channel Completely.
     *
     * @dev    - Can only be called by pushChannelAdmin
     *         - Can only be Called for Activated Channels
     *         - Can only Be Called for NON-BLOCKED Channels
     *
     *         - Updates channel's state to BLOCKED ('3')
     *         - Decreases the Channel Count
     *         - Since there is no refund, the channel's poolContribution is added to PROTOCOL_POOL_FEES and Removed from CHANNEL_POOL_FUNDS
     *         - Emit 'ChannelBlocked' Event
     * @param _channelAddress Address of the Channel to be blocked
     **/

    function blockChannel(address _channelAddress) external whenNotPaused {
        onlyPushChannelAdmin();
        require(
            ((channels[_channelAddress].channelState != 3) &&
                (channels[_channelAddress].channelState != 0)),
            "PushCoreV2::onlyUnblockedChannels: Invalid Channel"
        );
        uint256 minPoolContribution = MIN_POOL_CONTRIBUTION;
        Channel storage channelData = channels[_channelAddress];
        // add channel's currentPoolContribution to PoolFees - (no refunds if Channel is blocked)
        // Decrease CHANNEL_POOL_FUNDS by currentPoolContribution
        uint256 currentPoolContribution = channelData.poolContribution.sub(
            minPoolContribution
        );
        CHANNEL_POOL_FUNDS = CHANNEL_POOL_FUNDS.sub(currentPoolContribution);
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(currentPoolContribution);

        uint256 _newChannelWeight = minPoolContribution
            .mul(ADJUST_FOR_FLOAT)
            .div(minPoolContribution);

        channelsCount = channelsCount.sub(1);
        channelData.channelState = 3;
        channelData.channelWeight = _newChannelWeight;
        channelData.channelUpdateBlock = block.number;
        channelData.poolContribution = minPoolContribution;

        emit ChannelBlocked(_channelAddress);
    }

    /* **************
    => CHANNEL VERIFICATION FUNCTIONALTIES <=
    *************** */

    /**
     * @notice    Function is designed to tell if a channel is verified or not
     * @dev       Get if channel is verified or not
     * @param    _channel Address of the channel to be Verified
     * @return   verificationStatus  Returns 0 for not verified, 1 for primary verification, 2 for secondary verification
     **/
    function getChannelVerfication(address _channel)
        public
        view
        returns (uint8 verificationStatus)
    {
        address verifiedBy = channels[_channel].verifiedBy;
        bool logicComplete = false;

        // Check if it's primary verification
        if (
            verifiedBy == pushChannelAdmin ||
            _channel == address(0x0) ||
            _channel == pushChannelAdmin
        ) {
            // primary verification, mark and exit
            verificationStatus = 1;
        } else {
            // can be secondary verification or not verified, dig deeper
            while (!logicComplete) {
                if (verifiedBy == address(0x0)) {
                    verificationStatus = 0;
                    logicComplete = true;
                } else if (verifiedBy == pushChannelAdmin) {
                    verificationStatus = 2;
                    logicComplete = true;
                } else {
                    // Upper drill exists, go up
                    verifiedBy = channels[verifiedBy].verifiedBy;
                }
            }
        }
    }

    function batchVerification(
        uint256 _startIndex,
        uint256 _endIndex,
        address[] calldata _channelList
    ) external returns (bool) {
        onlyPushChannelAdmin();
        for (uint256 i = _startIndex; i < _endIndex; i++) {
            verifyChannel(_channelList[i]);
        }
        return true;
    }

    /**
     * @notice    Function is designed to verify a channel
     * @dev       Channel will be verified by primary or secondary verification, will fail or upgrade if already verified
     * @param    _channel Address of the channel to be Verified
     **/
    function verifyChannel(address _channel) public {
        onlyActivatedChannels(_channel);
        // Check if caller is verified first
        uint8 callerVerified = getChannelVerfication(msg.sender);
        require(
            callerVerified > 0,
            "PushCoreV2::verifyChannel: Caller is not verified"
        );

        // Check if channel is verified
        uint8 channelVerified = getChannelVerfication(_channel);
        require(
            channelVerified == 0 || msg.sender == pushChannelAdmin,
            "PushCoreV2::verifyChannel: Channel already verified"
        );

        // Verify channel
        channels[_channel].verifiedBy = msg.sender;

        // Emit event
        emit ChannelVerified(_channel, msg.sender);
    }

    /**
     * @notice    Function is designed to unverify a channel
     * @dev       Channel who verified this channel or Push Channel Admin can only revoke
     * @param    _channel Address of the channel to be unverified
     **/
    function unverifyChannel(address _channel) public {
        require(
            channels[_channel].verifiedBy == msg.sender ||
                msg.sender == pushChannelAdmin,
            "PushCoreV2::unverifyChannel: Invalid Caller"
        );

        // Unverify channel
        channels[_channel].verifiedBy = address(0x0);

        // Emit Event
        emit ChannelVerificationRevoked(_channel, msg.sender);
    }

    /*** Core-V3: Incentivized Chat Request Functions ***/
    /**
     * @notice Designed to handle the incoming Incentivized Chat Request Data and PUSH tokens.
     * @dev    This function currently handles the PUSH tokens that enters the contract due to any
     *         activation of incentivizied chat request from Communicator contract.
     *          - Can only be called by Communicator contract
     *          - Records and keeps track of Pool Funds and Pool Fees
     *          - Stores the PUSH tokens for the Celeb User, which can be claimed later only by that specific user.
     * @param  requestSender    Address that initiates the incentivized chat request
     * @param  requestReceiver  Address of the target user for whom the request is activated.
     * @param  amount           Amount of PUSH tokens deposited for activating the chat request
     */
    function handleChatRequestData(
        address requestSender,
        address requestReceiver,
        uint256 amount
    ) external {
        require(
            msg.sender == epnsCommunicator,
            "PushCoreV2:handleChatRequestData::Unauthorized caller"
        );
        uint256 poolFeeAmount = FEE_AMOUNT;
        uint256 requestReceiverAmount = amount.sub(poolFeeAmount);

        celebUserFunds[requestReceiver] += requestReceiverAmount;
        PROTOCOL_POOL_FEES = PROTOCOL_POOL_FEES.add(poolFeeAmount);

        emit IncentivizeChatReqReceived(
            requestSender,
            requestReceiver,
            requestReceiverAmount,
            poolFeeAmount,
            block.timestamp
        );
    }

    /**
     * @notice Allows the Celeb User(for whom chat requests were triggered) to claim their PUSH token earings.
     * @dev    Only accessible if a particular user has a non-zero PUSH token earnings in contract.
     * @param  _amount Amount of PUSH tokens to be claimed
     */
    function claimChatIncentives(uint256 _amount) external {
        require(
            celebUserFunds[msg.sender] >= _amount,
            "PushCoreV2:claimChatIncentives::Invalid Amount"
        );

        celebUserFunds[msg.sender] -= _amount;
        IERC20(PUSH_TOKEN_ADDRESS).safeTransfer(msg.sender, _amount);

        emit ChatIncentiveClaimed(msg.sender, _amount);
    }

    /* **************
    => STAKING INTERFACE FUNCTIONALTY <=
    *************** */

    /**
     * @notice Sets the address of the PushStaking contract.
     *
     * @dev This function can only be called by the governance address. It assigns `_pushStakingAddress`
     *      to `pushStakingAddress`, enabling PushCoreV3 to interact with the PushStaking contract.
     *
     * @param _pushStakingAddress       The address of the PushStaking contract to be set.
     *
     * @return bool                     Returns `true` if the address was successfully set.
     */
    function setPushStaking(address _pushStakingAddress) external returns (bool) {
        onlyGovernance();
        pushStakingAddress = _pushStakingAddress;

        return true;
    }

    /**
     * @notice Transfers a specified amount of protocol fees to PushStaking. Ensures that only
     *         the designated PushStaking contract can initiate the transfer. `_amount` must be less
     *         than or equal to `PROTOCOL_POOL_FEES`.
     *
     * @dev This function is restricted to being called only by the `PushStaking` contract. It deducts
     *      the specified `_amount` from `PROTOCOL_POOL_FEES` and transfers it to PushStaking.
     *
     * @param _amount                   The amount of protocol fees to transfer.
     */
    function transferProtocolFees(uint256 _amount) external {
        require(msg.sender == pushStakingAddress, "Only PushStaking can transfer fees");
        require(_amount <= PROTOCOL_POOL_FEES, "Insufficient fees");

        PROTOCOL_POOL_FEES -= _amount;
        IERC20(PUSH_TOKEN_ADDRESS).transfer(msg.sender, _amount);
    }
}