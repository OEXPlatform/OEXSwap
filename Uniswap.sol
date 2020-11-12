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

contract OEXUniswap {
    using SafeMath for uint256;

    struct Pair {
        // bool bCreated; 
        uint256 firstAssetId;
        uint256 secondAssetId;
        uint256 firstAssetNumber;
        uint256 secondAssetNumber;
        // uint256 totalLiquid;   // 以第一种资产数额作为流动性比例进行计算
        // mapping(address => uint256) userLiquidMap;
    }

    Pair[] public pairList;
    mapping(uint256 => uint256) public pairTotalLiquidMap;   // index of pair => total liquid of pair
    mapping(uint256 => mapping(address => uint256)) pairUserLiquidMap;  // index of pair => user account => user liquid of pair
    
    mapping(uint256 => mapping(uint256 => uint256)) public pairMap;   // asset1 -> asset2 -> index of pair
    
    constructor() public {
    }

    // 用户不可直接向合约账号转账
    function transferable() public returns(bool) {
        return false;
    }

    function getUserLiquid(uint256 pairIndex) view public returns(uint256) {
        return pairUserLiquidMap[pairIndex][msg.sender];
    }
    // 功能：
    // 1：判断交易对是否存在
    // 1.1 存在的话，获取编号和资产ID
    function getPair(uint256 asset1, uint256 asset2) view public returns(bool, uint256, uint256) {
        bool exist = false;
        uint256 index = 0;//pairMap[asset1][asset2];
        uint256 firstAssetId = asset1;
        if (index > 0) {  // 此时交易对必然存在，并且可保证流动性>0，因为当流动性被移除干净后，index会被置为0
            exist = true;
        } else if (pairList.length > 0) {   // 当index=0时，还不能确定交易对是否存在，因为有可能交易对刚好在第0个位置
            Pair memory pair = pairList[0];
            if (pair.firstAssetId == asset1 && pair.secondAssetId == asset2) {
                exist = true;
            }
            if (pair.firstAssetId == asset2 && pair.secondAssetId == asset1) {
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
            Pair memory newPair = Pair({firstAssetId: msg.extassetid1, secondAssetId: msg.extassetid2, firstAssetNumber: msg.extvalue1, secondAssetNumber: msg.extvalue2});
            pairList.push(newPair);
            pairTotalLiquidMap[pairList.length - 1] = msg.extvalue1;
            pairUserLiquidMap[pairList.length - 1][msg.sender] = msg.extvalue1;
            pairMap[msg.extassetid1][msg.extassetid2] = pairList.length - 1;  
        } else {   // 交易对已经存在
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

    // 发起兑换交易
    // pairIndex: 交易对编号
    // minNumber: 可接受的最小兑换金额
    function exchange(uint256 pairIndex, uint256 minNumber) payable public {
        require(msg.extcount == 0, "DO NOT receive external asset.");
        Pair storage pair = pairList[pairIndex];
        require(pair.firstAssetId == msg.assetid || pair.secondAssetId == msg.assetid, "In-Asset must be one of assets in this exchange pair.");
        uint256 inValue; 
        uint256 outValue;
        uint256 x; 
        uint256 y;
        uint256 k;
        inValue = msg.value.mul(997).div(1000);   // 0.3%的手续费需要扣除
        k = pair.firstAssetNumber.mul(pair.secondAssetNumber);
        if (pair.firstAssetId == msg.assetid) {
            x = pair.firstAssetNumber.add(inValue);
            outValue = pair.secondAssetNumber.sub(k.div(x));
            require(outValue >= minNumber);

            pair.firstAssetNumber = pair.firstAssetNumber.add(msg.value);   // 此处计算了全部输入资产，包括分红
            pair.secondAssetNumber = pair.secondAssetNumber.sub(outValue);
            msg.sender.transfer(pair.secondAssetId, outValue);
        } else {
            y = pair.secondAssetNumber.add(inValue);
            outValue = pair.firstAssetNumber.sub(k.div(y));
            require(outValue >= minNumber);

            pair.firstAssetNumber = pair.firstAssetNumber.sub(outValue);   // 此处计算了全部输入资产，包括分红
            pair.secondAssetNumber = pair.secondAssetNumber.add(msg.value);
            msg.sender.transfer(pair.firstAssetId, outValue);
        }
    }
 }
