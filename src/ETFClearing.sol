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

    event PriceUpdated(uint256 oldPriceRatio, uint256 newPriceRatio);

    event TradeAuthorized(
        address indexed seller,
        address indexed buyer,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline,
        bytes32 tradeId
    );

    // 2. The Exchange Ratio (Price)
    // Example: 1 ETF unit = 1000 eHKD
    uint256 public priceRatio = 1000;

    mapping(bytes32 => bool) public authorizedTrades;

    constructor(address _eHKD, address _etfVault, address _kyc) {
        require(_eHKD != address(0), "Invalid eHKD address");
        require(_etfVault != address(0), "Invalid ETF address");
        require(_kyc != address(0), "Invalid KYC address");

        admin = msg.sender;
        eHKD = IERC20(_eHKD);
        etfVault = IERC20(_etfVault);
        kycRegistry = IKYC(_kyc);
    }

    // 3. Function to update the price (Only Admin)
    function setPrice(uint256 _newPrice) external {
        require(msg.sender == admin, "Not Authorized");
        require(_newPrice > 0, "Invalid price");
        uint256 oldPriceRatio = priceRatio;
        priceRatio = _newPrice;
        emit PriceUpdated(oldPriceRatio, _newPrice);
    }

    function authorizeTrade(
        address buyer,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline
    ) external {
        require(buyer != address(0), "Invalid buyer address");
        require(msg.sender != buyer, "Buyer and seller must differ");
        require(etfAmount > 0, "Invalid ETF amount");
        require(expectedPriceRatio > 0, "Invalid price");
        require(deadline >= block.timestamp, "Authorization expired");
        require(kycRegistry.isWhitelisted(msg.sender), "Seller not whitelisted");
        require(kycRegistry.isWhitelisted(buyer), "Buyer not whitelisted");

        bytes32 tradeId = _tradeId(buyer, msg.sender, etfAmount, expectedPriceRatio, deadline);
        authorizedTrades[tradeId] = true;

        emit TradeAuthorized(msg.sender, buyer, etfAmount, expectedPriceRatio, deadline, tradeId);
    }

    function executeTrade(
        address buyer,
        address seller,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline
    ) external {
        require(msg.sender == buyer, "Caller must be buyer");
        require(buyer != address(0), "Invalid buyer address");
        require(seller != address(0), "Invalid seller address");
        require(buyer != seller, "Buyer and seller must differ");
        require(etfAmount > 0, "Invalid ETF amount");
        require(expectedPriceRatio > 0, "Invalid price");
        require(deadline >= block.timestamp, "Trade expired");
        require(priceRatio == expectedPriceRatio, "Price moved");
        require(kycRegistry.isWhitelisted(buyer), "Buyer not whitelisted");
        require(kycRegistry.isWhitelisted(seller), "Seller not whitelisted");

        bytes32 tradeId = _tradeId(buyer, seller, etfAmount, expectedPriceRatio, deadline);
        require(authorizedTrades[tradeId], "Seller did not authorize trade");
        delete authorizedTrades[tradeId];

        uint256 eHKDAmount = etfAmount * priceRatio;

        _safeTransferFrom(eHKD, buyer, seller, eHKDAmount, "eHKD transfer failed");

        _safeTransferFrom(etfVault, seller, buyer, etfAmount, "ETF transfer failed");

        emit TradeCompleted(buyer, seller, etfAmount, eHKDAmount, priceRatio);
    }

    function _tradeId(
        address buyer,
        address seller,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(buyer, seller, etfAmount, expectedPriceRatio, deadline));
    }

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount,
        string memory errorMessage
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transferFrom.selector, from, to, amount)
        );

        require(success, errorMessage);
        if (data.length > 0) {
            require(abi.decode(data, (bool)), errorMessage);
        }
    }
}
