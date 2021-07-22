// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./WhirlpoolConsumer.sol";
import "./security/SafeEntry.sol";
import "./utils/TransferWithCommission.sol";

enum SaladStatus {
  BowlCreated,
  Prepared,
  Served
}

struct SaladBet {
  uint8 bet;
  uint8 bet2;
  uint256 value;
}

struct SaladBowl {
  uint256[6] sum;
  uint256 createdOn;
  uint256 expiresOn;
  uint256 maxBet;
  address maxBetter;
  SaladStatus status;
  uint8 result;
}

// solhint-disable not-rely-on-time
contract Salad is TransferWithCommission, WhirlpoolConsumer, SafeEntry {
  using Address for address;
  using Math for uint256;

  mapping(uint256 => SaladBowl) public salads;
  mapping(uint256 => mapping(address => SaladBet)) public saladBets;

  uint256 public constant MAX_EXPIRY = 4 days;
  uint256 public constant MIN_EXPIRY = 5 minutes;

  uint256 public minBet = 0.01 ether;
  uint256 public expiry = 1 days;

  uint256 public currentSalad = 0;

  event IngredientAdded(uint256 id, address creator, uint8 bet, uint8 bet2, uint256 value);
  event IngredientIncreased(uint256 id, address creator, uint8 bet2, uint256 newValue);
  event Claimed(uint256 id, address creator, uint256 value, address referrer);

  event SaladBowlCreated(uint256 id, uint256 expiresOn);
  event SaladPrepared(uint256 id);
  event SaladServed(uint256 id, uint8 result);

  // solhint-disable no-empty-blocks
  constructor(address _whirlpool) WhirlpoolConsumer(_whirlpool) {}

  function addIngredient(
    uint256 id,
    uint8 bet,
    uint8 bet2,
    address referrer
  ) external payable nonReentrant notContract {
    require(currentSalad == id, "Can only bet in current salad");
    require(salads[id].status == SaladStatus.BowlCreated, "Already prepared");
    require(bet >= 0 && bet <= 5 && bet2 >= 0 && bet2 <= 5, "Can only bet 0-5");
    require(msg.value >= minBet, "Value is less than minimum");
    require(saladBets[id][msg.sender].value == 0, "Already placed bet");

    if (salads[currentSalad].createdOn == 0) createNewSalad(false);

    require(salads[currentSalad].expiresOn > block.timestamp, "Time is up!");

    salads[id].sum[bet] += msg.value;
    saladBets[id][msg.sender].bet = bet;
    saladBets[id][msg.sender].bet2 = bet2;
    saladBets[id][msg.sender].value = msg.value;

    referrers[msg.sender] = referrer;

    setMaxBetForSalad(id, msg.value);

    emit IngredientAdded(id, msg.sender, bet, bet2, msg.value);
  }

  function increaseIngredient(uint256 id, uint8 bet2) external payable nonReentrant notContract {
    require(msg.value > 0, "Value must be greater than 0");
    require(saladBets[id][msg.sender].value > 0, "No bet placed yet");
    require(salads[id].status == SaladStatus.BowlCreated, "Already prepared");
    require(salads[id].expiresOn > block.timestamp, "Time is up!");

    salads[id].sum[saladBets[id][msg.sender].bet] += msg.value;
    saladBets[id][msg.sender].bet2 = bet2;
    saladBets[id][msg.sender].value += msg.value;

    setMaxBetForSalad(id, saladBets[id][msg.sender].value);

    emit IngredientIncreased(id, msg.sender, bet2, saladBets[id][msg.sender].value);
  }

  function prepareSalad(uint256 id) external nonReentrant notContract {
    require(salads[id].expiresOn < block.timestamp, "Time is not up yet!");
    require(salads[id].status == SaladStatus.BowlCreated, "Already prepared");

    salads[id].status = SaladStatus.Prepared;

    _requestRandomness(id);

    emit SaladPrepared(id);
  }

  function claim(uint256 id) external nonReentrant notContract {
    require(salads[id].status == SaladStatus.Served, "Not ready to serve yet");
    require(saladBets[id][msg.sender].value > 0, "Nothing to claim");
    require(saladBets[id][msg.sender].bet != salads[id].result, "You didn't win!");

    uint256[6] storage s = salads[id].sum;
    uint8 myBet = saladBets[id][msg.sender].bet;
    uint256 myValue = saladBets[id][msg.sender].value;

    bool jackpot = salads[id].result != saladBets[id][salads[id].maxBetter].bet &&
      salads[id].result == saladBets[id][salads[id].maxBetter].bet2;

    uint256 myReward;

    if (jackpot && salads[id].maxBetter == msg.sender) {
      myReward = s[0] + s[1] + s[2] + s[3] + s[4] + s[5];
    } else if (!jackpot) {
      myReward = ((5 * s[myBet] + s[salads[id].result]) * myValue) / (5 * s[myBet]);
    }

    require(myReward > 0, "You didn't win!");

    delete saladBets[id][msg.sender];

    send(msg.sender, myReward);

    emit Claimed(id, msg.sender, myReward, referrers[msg.sender]);
  }

  function betSum(uint256 id, uint8 bet) external view returns (uint256) {
    return salads[id].sum[bet];
  }

  function sum(uint256 id) external view returns (uint256) {
    uint256[6] storage s = salads[id].sum;
    return s[0] + s[1] + s[2] + s[3] + s[4] + s[5];
  }

  function setMinBet(uint256 val) external onlyOwner {
    minBet = val;
  }

  function setExpiry(uint256 val) external onlyOwner {
    require(val <= MAX_EXPIRY, "Value exceeds max amount");
    require(val >= MIN_EXPIRY, "Value is less than min amount");

    expiry = val;
  }

  function setMaxBetForSalad(uint256 id, uint256 amount) internal {
    salads[id].maxBet = Math.max(salads[id].maxBet, amount);
    if (salads[id].maxBet == amount) salads[id].maxBetter = msg.sender;
  }

  function serveSalad(uint256 id, uint8 result) internal {
    salads[id].result = result;
    salads[id].status = SaladStatus.Served;

    emit SaladServed(id, result);

    createNewSalad(true);
  }

  function createNewSalad(bool increment) internal {
    if (increment) currentSalad += 1;

    salads[currentSalad].createdOn = block.timestamp;
    salads[currentSalad].expiresOn = block.timestamp + expiry;

    emit SaladBowlCreated(currentSalad, block.timestamp + expiry);
  }

  function _consumeRandomness(uint256 id, uint256 randomness) internal override {
    serveSalad(id, uint8(randomness % 6));
  }
}
