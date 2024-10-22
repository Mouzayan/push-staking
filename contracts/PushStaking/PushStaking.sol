pragma solidity >=0.6.12 < 0.7.0;
pragma experimental ABIEncoderV2;

import "../PushCore/PushCoreV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// Add contract description here
contract PushStaking {
    using SafeMath for uint256;

    PushCoreV2 public pushCoreV2;
    IERC20 public pushToken;

    uint256 public WALLET_FEE_POOL;
    uint256 public HOLDER_FEE_POOL;

    uint256 public WALLET_FEE_PERCENTAGE = 30;
    uint256 public HOLDER_FEE_PERCENTAGE = 70;
    uint256 private constant PERCENTAGE_DIVISOR = 100;

    address public governance;

    modifier onlyGovernance() {
        require(msg.sender == governance, "PushStaking: caller is not the governance");
        _;
    }

    modifier onlyPushCore() {
        require(msg.sender == address(pushCoreV2), "PushStaking: caller is not PushCore");
        _;
    }

    constructor(address _pushCoreV2Address, address _governance) public {
        pushCoreV2 = PushCoreV2(_pushCoreV2Address);
        pushToken = IERC20(pushCoreV2.PUSH_TOKEN_ADDRESS());
        governance = _governance;
    }

    function getProtocolPoolFees() public view returns (uint256) {
        return pushCoreV2.PROTOCOL_POOL_FEES();
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

    function receiveProtocolFees(uint256 _amount) external onlyPushCore {
        require(pushToken.transferFrom(address(pushCoreV2), address(this), _amount), "PushStaking: transfer failed");

        uint256 walletFeeAmount = _amount.mul(WALLET_FEE_PERCENTAGE).div(PERCENTAGE_DIVISOR);
        uint256 holderFeeAmount = _amount.sub(walletFeeAmount);

        WALLET_FEE_POOL = WALLET_FEE_POOL.add(walletFeeAmount);
        HOLDER_FEE_POOL = HOLDER_FEE_POOL.add(holderFeeAmount);
    }
}
