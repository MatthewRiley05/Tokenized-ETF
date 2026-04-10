// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IKYC {
    function isWhitelisted(address user) external view returns (bool);
}

contract ETFVault is ERC4626 {
    IKYC public immutable kycRegistry;

    error KYC_NotWhitelisted(address account);
    error InvalidAddress();

    // Initialize contract
    constructor(IERC20 _asset, address _kycRegistry) ERC4626(_asset) ERC20("Tokenized 2800.HK", "t2800.HK") {
        if (address(_asset) == address(0) || _kycRegistry == address(0)) revert InvalidAddress();
        kycRegistry = IKYC(_kycRegistry);
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