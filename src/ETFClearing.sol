// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IKYC {
    function isWhitelisted(address user) external view returns (bool);
}

contract ETFClearing {
    // 1. State Variables
    address public admin;
    IERC20 public eHKD;      // The eHKD Token contract
    IERC20 public etfVault;  // The ETF (ERC-4626) contract
    IKYC public kycRegistry; // The Whitelist contract

    event TradeCompleted(
        address indexed buyer,
        address indexed seller,
        uint256 etfAmount,
        uint256 eHKDAmount,
        uint256 priceRatio
    );

    // 2. The Exchange Ratio (Price)
    // Example: 1 ETF unit = 1000 eHKD
    uint256 public priceRatio = 1000;

    constructor(address _eHKD, address _etfVault, address _kyC) {
        require(_eHKD != address(0), "Invalid eHKD address");
        require(_etfVault != address(0), "Invalid ETF address");
        require(_kyC != address(0), "Invalid KYC address");

        admin = msg.sender;
        eHKD = IERC20(_eHKD);
        etfVault = IERC20(_etfVault);
        kycRegistry = IKYC(_kyC);
    }

    // 3. Function to update the price (Only Admin)
    function setPrice(uint256 _newPrice) external {
        require(msg.sender == admin, "Not Authorized");
        require(_newPrice > 0, "Invalid price");
        priceRatio = _newPrice;
    }

    function executeTrade(address buyer, address seller, uint256 etfAmount) external {
        require(msg.sender == buyer, "Caller must be buyer");
        require(buyer != address(0), "Invalid buyer address");
        require(seller != address(0), "Invalid seller address");
        require(buyer != seller, "Buyer and seller must differ");
        require(etfAmount > 0, "Invalid ETF amount");
        require(kycRegistry.isWhitelisted(buyer), "Buyer not whitelisted");
        require(kycRegistry.isWhitelisted(seller), "Seller not whitelisted");

        uint256 eHKDAmount = etfAmount * priceRatio;

        bool eHKDSent = eHKD.transferFrom(buyer, seller, eHKDAmount);
        require(eHKDSent, "eHKD transfer failed");

        bool etfSent = etfVault.transferFrom(seller, buyer, etfAmount);
        require(etfSent, "ETF transfer failed");

        emit TradeCompleted(buyer, seller, etfAmount, eHKDAmount, priceRatio);
    }
}
