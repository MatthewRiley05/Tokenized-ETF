// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUnderlying
 * @dev This represents the physical underlying asset (e.g., 2800.HK Tracker Fund).
 * In a real scenario, this would be shares held by a custodian.
 * For an idea test, we use this to "mint" shares into the Vault.
 */
contract MockUnderlying is ERC20, Ownable {
    constructor() ERC20("Tracker Fund 2800.HK", "2800") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
