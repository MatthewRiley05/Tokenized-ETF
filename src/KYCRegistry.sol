// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IKYC.sol";

/**
 * @title KYCRegistry
 * @dev Implementation of the IKYC interface to manage a whitelist of verified users.
 * This contract acts as the source of truth for compliance across the ETF ecosystem.
 */
contract KYCRegistry is IKYC, Ownable {
    mapping(address => bool) private _whitelist;

    event AddedToWhitelist(address indexed account);
    event RemovedFromWhitelist(address indexed account);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Adds an address to the whitelist. Only the owner (e.g., a regulator or bank) can call this.
     * @param account The address to be whitelisted.
     */
    function addAddress(address account) external onlyOwner {
        _whitelist[account] = true;
        emit AddedToWhitelist(account);
    }

    /**
     * @dev Removes an address from the whitelist. Only the owner can call this.
     * @param account The address to be removed from the whitelist.
     */
    function removeAddress(address account) external onlyOwner {
        _whitelist[account] = false;
        emit RemovedFromWhitelist(account);
    }

    /**
     * @dev Implementation of the IKYC interface.
     * Returns true if the account is whitelisted, false otherwise.
     */
    function isWhitelisted(address account) external view override returns (bool) {
        return _whitelist[account];
    }

    /**
     * @dev Helper to add multiple addresses to the whitelist in a single transaction.
     * @param accounts An array of addresses to be whitelisted.
     */
    function batchAddAddresses(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _whitelist[accounts[i]] = true;
            emit AddedToWhitelist(accounts[i]);
        }
    }
}
