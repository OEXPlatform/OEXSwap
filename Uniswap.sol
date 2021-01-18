pragma solidity ^0.4.24;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor (address owner) internal {
        address msgSender = owner;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }
    
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract SpreadInfo {
    mapping(address => address) private down2upMap;
    mapping(address => address[]) private up2downSet;

    function registerUpAccount(address _upAccount) public {
        require (down2upMap[msg.sender] == address(0));
        down2upMap[msg.sender] = _upAccount;
        up2downSet[_upAccount].push(msg.sender);
    }

    function getUpAccount(address account) view public returns(address) {
        address upAccount = down2upMap[account];
        return upAccount;
    }

    function getDownAccountsNumber(address account) view  public returns(uint256) {
        address[] memory downAccounts = up2downSet[account];
        return downAccounts.length;
    }

    function getDownAccount(address account, uint256 index) view public returns(address) {
        address[] memory downAccounts = up2downSet[account];
        require(index < downAccounts.length);
        return downAccounts[index];
    }
}

contract ExchangeMiner is Ownable {
    using SafeMath for uint256;

    struct RewardSetting {
        uint256 reward;
        uint256 startValidBlock;
    }

    uint256 public constant MinAddressCount = 7;
    uint256 public genesisReward = 5e18;
    uint256 public genesisBlock = 0;
    RewardSetting[] public rewardSettingList;
    address public oexSwapAddress;
    uint256 constant OEXAssetId = 0;
    uint256 public upAccountRewardFactor = 20;
    SpreadInfo public spreadInfo;
    mapping(uint256 => uint256) public block2OEXAmountMap;  // 区块对应的总的oex交易量，如区块高度为100时，总的OEX交易量为1000
    mapping(uint256 => mapping(address => uint256)) public block2Account2OEXAmountMap;  // 区块对应某个账户的oex交易量，如账户A在区块高度为100的时候交易了100个OEX
    mapping(address => uint256) public accountWithdrawMap;  // 记录账户最新领取激励的区块高度

    mapping(address => uint256) public accountSpreadRewardMap;  // 记录账户总领取的推广激励

    mapping(uint256 => mapping(address => bool)) public assetAddressMap;  // 记录参与某个资产交易的地址数量
    mapping(uint256 => uint256) public assetAddressCountMap; // 记录参与某资产交易的地址数量

    modifier onlyOexSwap() {
        require(msg.sender == oexSwapAddress);
        _;
    }

    constructor(address owner) Ownable(owner) public {
        genesisBlock = block.number;
    }

    function setSpreadInfoAddress(address _spreadInfoAddress) public onlyOwner {
        spreadInfo = SpreadInfo(_spreadInfoAddress);
    }

    function setUpAccountRewardFactor(uint256 _factor) public onlyOwner {
        require(_factor <= 20);
        upAccountRewardFactor = _factor;
    }

    // 用户可直接向合约账号转账
    function transferable() public returns(bool) {
        return true;
    }

    function setOexSwapAddress(address _oexSwapAddress) public onlyOwner {
        oexSwapAddress = _oexSwapAddress;
    }

    // 设置新的挖矿奖励时，新区块高度必须高于当前区块28800个块，即必须至少提前一天设置新的区块奖励；
    // 同时，每个新区块奖励必须间隔一天以上，以让矿工有反应时间
    function setReward(uint256 _newReward, uint256 _startValidBlock) public onlyOwner {
        require(_startValidBlock - block.number >= 28800);  // 至少提前1天设置，给矿工留出调整时间
        if (rewardSettingList.length > 0) {
            RewardSetting memory lastRewardSetting = rewardSettingList[rewardSettingList.length - 1];
            require(_startValidBlock >= lastRewardSetting.startValidBlock + 28800);
        }
        RewardSetting memory rewardSetting = RewardSetting({reward: _newReward, startValidBlock: _startValidBlock});
        rewardSettingList.push(rewardSetting);
    }

    function getReward(uint256 _blockNumber) view public returns(uint256) {
        int256 length = int256(rewardSettingList.length);
        if (length == 0) return 0;
        for(int256 i = length - 1; i >= 0; i--) {
            RewardSetting memory rewardSetting = rewardSettingList[uint256(i)];
            if (_blockNumber >= rewardSetting.startValidBlock) {
                return rewardSetting.reward;
            }
        }
        return 0;
    }

    function addMiningInfo(address account, uint256 amount, uint256 assetId) external onlyOexSwap {
        if (!assetAddressMap[assetId][account]) {
            assetAddressMap[assetId][account] = true;
            assetAddressCountMap[assetId] += 1;
        }
        if (assetAddressCountMap[assetId] >= MinAddressCount) {
            block2OEXAmountMap[block.number] = block2OEXAmountMap[block.number].add(amount);
            block2Account2OEXAmountMap[block.number][account] = block2Account2OEXAmountMap[block.number][account].add(amount);
        }
    }

    function getAmount() view public returns(uint256) {
        uint256 startBlockNumber = accountWithdrawMap[msg.sender] == 0 ? genesisBlock : accountWithdrawMap[msg.sender] + 1;
        uint256 totalOEXAmont = 0;
        for (uint256 i = startBlockNumber; i < block.number; i++) {
            uint256 oexOfBlock = block2OEXAmountMap[i];
            uint256 myOexOfBlock = block2Account2OEXAmountMap[i][msg.sender];
            if (myOexOfBlock > 0) {
                uint256 rewardOfBlock = getReward(i);
                uint256 curOEXOfBlock = rewardOfBlock.mul(myOexOfBlock).div(oexOfBlock);
                totalOEXAmont = totalOEXAmont.add(curOEXOfBlock);
            }
        }
        return totalOEXAmont;
    }

    function withdraw() public {
        uint256 totalOEXAmont = getAmount();
        require(this.balanceex(OEXAssetId) >= totalOEXAmont);
        msg.sender.transfer(OEXAssetId, totalOEXAmont);
        accountWithdrawMap[msg.sender] = block.number - 1;

        address upAccount = spreadInfo.getUpAccount(msg.sender);
        if (spreadInfo != address(0) && upAccount != address(0)) {
            uint256 upAccountReward = totalOEXAmont.mul(upAccountRewardFactor).div(100);
            upAccount.transfer(OEXAssetId, upAccountReward);
            accountSpreadRewardMap[upAccount] = accountSpreadRewardMap[upAccount].add(upAccountReward);
        }
    }
}

contract OEXSwap is Ownable {
    using SafeMath for uint256;

    struct Pair {
        // bool bCreated; 
        uint256 firstAssetId;
        uint256 secondAssetId;
        uint256 firstAssetNumber;
        uint256 secondAssetNumber;
        uint256 totalLiquidOfFirstAsset;
        uint256 totalLiquidOfSecondAsset;
    }

    uint256 constant OEXAssetId = 0;
    uint256 public feeRate = 3;  // 0.3%
    ExchangeMiner public exchangeMiner;
    Pair[] public pairList;
    uint256 public startMiningNumber = 0;
    uint256 public stopMiningNumber = 1e10;
    mapping(uint256 => uint256) public pairTotalLiquidMap;   // index of pair => total liquid of pair
    mapping(uint256 => mapping(address => uint256)) pairUserLiquidMap;  // index of pair => user account => user liquid of pair
    
    mapping(uint256 => mapping(uint256 => uint256)) public pairMap;   // asset1 -> asset2 -> index of pair
    
    constructor(address owner) Ownable(owner) public {
    }

    function setExchangeMiner(address _exchangeMiner) public onlyOwner {
        exchangeMiner = ExchangeMiner(_exchangeMiner);
    }

    function setFeeRate(uint256 _feeRate) public onlyOwner {
        require(_feeRate < 200);
        feeRate = _feeRate;
    }

    // 用户不可直接向合约账号转账
    function transferable() public returns(bool) {
        return false;
    }

    function getPairNumber() view public returns(uint256) {
        return pairList.length;
    }
    function getUserLiquid(uint256 pairIndex) view public returns(uint256) {
        return pairUserLiquidMap[pairIndex][msg.sender];
    }

    function setStartMiningNumber(uint256 _startMiningNumber) public onlyOwner {
        startMiningNumber = _startMiningNumber;
    }

    function setStopMiningNumber(uint256 _stopMiningNumber) public onlyOwner {
        stopMiningNumber = _stopMiningNumber;
    }

    function isInMiningDuration() public returns(bool) {
        return block.number >= startMiningNumber && block.number < stopMiningNumber;
    }
    // 功能：
    // 1：判断交易对是否存在
    // 1.1 存在的话，获取编号和资产ID
    function getPair(uint256 asset1, uint256 asset2) view public returns(bool, uint256, uint256) {
        bool exist = false;
        uint256 index = pairMap[asset1][asset2];
        uint256 firstAssetId = asset1;
        if (index > 0) {  // 此时交易对必然存在，并且可保证流动性>0，因为当流动性被移除干净后，index会被置为0
            exist = true;
        } else {   // 当index=0时，还不能确定交易对是否存在，因为有可能交易对刚好在第0个位置
            index = pairMap[asset2][asset1];
            if (index > 0) {
                exist = true;
                firstAssetId = asset2;
            }
        }
        return (exist, index, firstAssetId);
    }

    // 添加流动性，需同时提供两种资产
    function addLiquidity() payable public {
        require(msg.extcount == 2, "Just receive 2 assets.");
        require(msg.extvalue1 > 0 && msg.extvalue2 > 0, "The value of assets must be bigger than zero.");

        bool exist = false;
        uint256 index = 0; 
        uint256 firstAssetId = 0;
        (exist, index, firstAssetId) = getPair(msg.extassetid1, msg.extassetid2);
        if (!exist) {  // 无此交易对，需要添加
            Pair memory newPair = Pair({firstAssetId: msg.extassetid1, secondAssetId: msg.extassetid2, 
                                        firstAssetNumber: msg.extvalue1, secondAssetNumber: msg.extvalue2,
                                        totalLiquidOfFirstAsset: 0, totalLiquidOfSecondAsset: 0});
            pairList.push(newPair);
            pairTotalLiquidMap[pairList.length - 1] = msg.extvalue1;
            pairUserLiquidMap[pairList.length - 1][msg.sender] = msg.extvalue1;
            pairMap[msg.extassetid1][msg.extassetid2] = pairList.length;  
        } else {   // 交易对已经存在
            index -= 1;
            Pair storage pair = pairList[index];
            uint256 firstAssetValue = (firstAssetId == msg.extassetid1) ? msg.extvalue1 : msg.extvalue2;
            uint256 secondAssetValue = (firstAssetId == msg.extassetid1) ? msg.extvalue2 : msg.extvalue1;
            uint256 neededSecondAssetValue = firstAssetValue.mul(pair.secondAssetNumber).div(pair.firstAssetNumber).add(1);
            require(secondAssetValue >= neededSecondAssetValue, "Asset is not enough.");

            uint256 mintedLiquid = firstAssetValue.mul(pairTotalLiquidMap[index]).div(pair.firstAssetNumber);
            pairTotalLiquidMap[index] = pairTotalLiquidMap[index].add(mintedLiquid);
            pairUserLiquidMap[index][msg.sender] = pairUserLiquidMap[index][msg.sender].add(mintedLiquid);
            pair.firstAssetNumber = pair.firstAssetNumber.add(firstAssetValue);
            pair.secondAssetNumber = pair.secondAssetNumber.add(neededSecondAssetValue);

            if (secondAssetValue > neededSecondAssetValue) {
                msg.sender.transfer(pair.secondAssetId, secondAssetValue - neededSecondAssetValue);
            }
        }
    }

    function removeLiquidity(uint256 pairIndex, uint256 share) public {
        require(share > 0);
        Pair storage pair = pairList[pairIndex];
        uint256 liquid = pairUserLiquidMap[pairIndex][msg.sender];
        if (share > liquid) {
            share = liquid;
        }
        uint256 removedFirstAssetValue = share.mul(pair.firstAssetNumber).div(pairTotalLiquidMap[pairIndex]);
        uint256 removedSecondAssetValue = share.mul(pair.secondAssetNumber).div(pairTotalLiquidMap[pairIndex]);

        pairTotalLiquidMap[pairIndex] = pairTotalLiquidMap[pairIndex].sub(share);
        pairUserLiquidMap[pairIndex][msg.sender] = pairUserLiquidMap[pairIndex][msg.sender].sub(share);

        pair.firstAssetNumber = pair.firstAssetNumber.sub(removedFirstAssetValue);
        pair.secondAssetNumber = pair.secondAssetNumber.sub(removedSecondAssetValue);

        if (pairTotalLiquidMap[pairIndex] == 0) {
            pairMap[pair.firstAssetId][pair.secondAssetId] = 0;
        }
        msg.sender.transfer(pair.firstAssetId, removedFirstAssetValue);
        msg.sender.transfer(pair.secondAssetId, removedSecondAssetValue);
    }

    function getOutAmount(uint256 firstAssetNumber, uint256 secondAssetNumber, uint256 inValue) view public returns(uint256) {
        // if (!(firstAssetNumber > 0 && secondAssetNumber > 0 && inValue > 0)) {
        //     return 0;
        // }
        uint256 outValue;
        uint256 x; 
        uint256 y;
        uint256 k;

        inValue = inValue.mul(1000 - feeRate).div(1000);
        k = firstAssetNumber.mul(secondAssetNumber);
        x = firstAssetNumber.add(inValue);
        y = k.div(x);
        outValue = secondAssetNumber.sub(y);
        return outValue;
    }

    // 发起兑换交易
    // pairIndex: 交易对编号
    // minNumber: 可接受的最小兑换金额
    function exchange(uint256 pairIndex, uint256 minNumber) payable public {
        require(pairIndex < pairList.length && minNumber > 0);
        require(msg.extcount == 0, "DO NOT receive external asset.");
        Pair storage pair = pairList[pairIndex];
        require(pair.firstAssetId == msg.assetid || pair.secondAssetId == msg.assetid, "In-Asset must be one of assets in this exchange pair.");
        uint256 outValue;
        if (pair.firstAssetId == msg.assetid) {
            outValue = getOutAmount(pair.firstAssetNumber, pair.secondAssetNumber, msg.value);
            require(outValue >= minNumber);

            pair.firstAssetNumber = pair.firstAssetNumber.add(msg.value);   // 此处计算了全部输入资产，包括分红
            pair.secondAssetNumber = pair.secondAssetNumber.sub(outValue);
            pair.totalLiquidOfFirstAsset = pair.totalLiquidOfFirstAsset.add(msg.value);
            pair.totalLiquidOfSecondAsset = pair.totalLiquidOfSecondAsset.add(outValue);
            msg.sender.transfer(pair.secondAssetId, outValue);
        } else {
            outValue = getOutAmount(pair.secondAssetNumber, pair.firstAssetNumber, msg.value);
            require(outValue >= minNumber);

            pair.firstAssetNumber = pair.firstAssetNumber.sub(outValue);   // 此处计算了全部输入资产，包括分红
            pair.secondAssetNumber = pair.secondAssetNumber.add(msg.value);
            pair.totalLiquidOfFirstAsset = pair.totalLiquidOfFirstAsset.add(outValue);
            pair.totalLiquidOfSecondAsset = pair.totalLiquidOfSecondAsset.add(msg.value);
            msg.sender.transfer(pair.firstAssetId, outValue);
        }
        if (isInMiningDuration() && address(exchangeMiner) != address(0)) {
            if (pair.firstAssetId == OEXAssetId || pair.secondAssetId == OEXAssetId) {
                if (msg.assetid == OEXAssetId) {
                    exchangeMiner.addMiningInfo(msg.sender, msg.value, pair.firstAssetId != msg.assetid ? pair.firstAssetId : pair.secondAssetId);
                } else {
                    exchangeMiner.addMiningInfo(msg.sender, outValue, msg.assetid);
                }
            }
        }
    }
 }
