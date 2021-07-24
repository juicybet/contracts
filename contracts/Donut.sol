// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./security/SafeEntry.sol";
import "./utils/ValueLimits.sol";
import "./utils/TransferWithCommission.sol";

struct DonutBet {
  uint8 bet;
  address creator;
  uint256 value;
  uint256 block;
}

contract Donut is TransferWithCommission, ValueLimits, SafeEntry {
  uint8 public multiplier = 15;

  uint256 public constant MAX_EXPIRY = 4 days;
  uint256 public constant MIN_EXPIRY = 5 minutes;

  mapping(uint64 => DonutBet) public bets;

  uint64 public numBets = 0;

  event BetPlaced(uint64 id, uint8 bet, address creator, uint256 value);
  event BetClaimed(uint64 id, address referrer);

  // solhint-disable no-empty-blocks
  constructor() ValueLimits(0.001 ether, 0.1 ether) {}

  function hasWon(uint64 id) public view returns (bool) {
    if (bets[id].value == 0) return false;

    bytes32 hash = getBlockHash(bets[id].block);

    if (hash == bytes32(0)) return false;

    return uint8(hash[31]) % 16 == bets[id].bet;
  }

  function placeBet(uint8 bet, address referrer) external payable nonReentrant notContract isMinValue isMaxValue {
    uint64 id = numBets;

    bets[id].bet = bet;
    bets[id].creator = msg.sender;
    bets[id].value = msg.value;
    bets[id].block = block.number;

    referrers[msg.sender] = referrer;

    emit BetPlaced(id, bet, msg.sender, msg.value);

    numBets += 1;
  }

  function claim(uint64 id) external nonReentrant notContract {
    require(bets[id].creator == msg.sender, "Donut: Nothing to claim");
    require(hasWon(id), "Donut: You didn't win");

    send(payable(msg.sender), bets[id].value * multiplier);

    emit BetClaimed(id, referrers[msg.sender]);

    delete bets[id];
  }

  function setMultiplier(uint8 val) external onlyOwner {
    multiplier = val;
  }

  // solhint-disable no-empty-blocks
  function deposit() external payable {}

  function withdraw(uint256 amount) external onlyOwner {
    Address.sendValue(payable(owner()), amount);
  }

  function getBlockHash(uint256 blockNumber) internal view virtual returns (bytes32) {
    return blockhash(blockNumber);
  }
}
