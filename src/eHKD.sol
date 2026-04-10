// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IKYC {
    function isWhitelisted(address user) external view returns (bool);
}

contract eHKD is ERC20, Ownable {
    IKYC public immutable kycRegistry;

    error KYC_NotWhitelisted(address account);
    error InvalidKYCAddress();

    // Initialize contract
    constructor(address _kycRegistry) ERC20("Digital Hong Kong Dollar", "eHKD") Ownable(msg.sender) {
        if (_kycRegistry == address(0)) revert InvalidKYCAddress();
        kycRegistry = IKYC(_kycRegistry);
    }

    // Mint
    function mint(address to, uint256 amount) external onlyOwner {
        if (!kycRegistry.isWhitelisted(to)) {
            revert KYC_NotWhitelisted(to);
        }
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0)) {
            if (!kycRegistry.isWhitelisted(from)) revert KYC_NotWhitelisted(from);
        }

        if (to != address(0)) {
            if (!kycRegistry.isWhitelisted(to)) revert KYC_NotWhitelisted(to);
        }
        super._update(from, to, value);
    }
}