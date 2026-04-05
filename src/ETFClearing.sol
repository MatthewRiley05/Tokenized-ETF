// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IKYC {
    function isWhitelisted(address user) external view returns (bool);
}

contract ETFClearing {
    address public admin;
    address public pendingAdmin;
    IERC20 public immutable eHKD;
    IERC20 public immutable etfVault;
    IKYC public immutable kycRegistry;

    event TradeCompleted(
        address indexed buyer,
        address indexed seller,
        uint256 etfAmount,
        uint256 eHKDAmount,
        uint256 priceRatio
    );

    event PriceUpdated(uint256 oldPriceRatio, uint256 newPriceRatio);
    event AdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event AdminTransferAccepted(address indexed previousAdmin, address indexed newAdmin);

    event TradeAuthorized(
        address indexed seller,
        address indexed buyer,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline,
        bytes32 tradeId
    );

    uint256 public constant PRICE_SCALE = 1e18;
    uint256 public priceRatio = 1000 * PRICE_SCALE;

    mapping(bytes32 => bool) public authorizedTrades;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not Authorized");
        _;
    }

    constructor(address _eHKD, address _etfVault, address _kyc) {
        require(_eHKD != address(0), "Invalid eHKD address");
        require(_etfVault != address(0), "Invalid ETF address");
        require(_kyc != address(0), "Invalid KYC address");

        admin = msg.sender;
        eHKD = IERC20(_eHKD);
        etfVault = IERC20(_etfVault);
        kycRegistry = IKYC(_kyc);
    }

    function setPrice(uint256 _newPrice) external onlyAdmin {
        require(_newPrice > 0, "Invalid price");
        uint256 oldPriceRatio = priceRatio;
        priceRatio = _newPrice;
        emit PriceUpdated(oldPriceRatio, _newPrice);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin address");
        require(newAdmin != admin, "Already admin");
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(admin, newAdmin);
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "Not pending admin");
        address previousAdmin = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferAccepted(previousAdmin, msg.sender);
    }

    function authorizeTrade(
        address buyer,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline
    ) external {
        _validateParticipants(buyer, msg.sender);
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
        _validateParticipants(buyer, seller);
        require(etfAmount > 0, "Invalid ETF amount");
        require(expectedPriceRatio > 0, "Invalid price");
        require(deadline >= block.timestamp, "Trade expired");
        require(priceRatio == expectedPriceRatio, "Price moved");
        require(kycRegistry.isWhitelisted(buyer), "Buyer not whitelisted");
        require(kycRegistry.isWhitelisted(seller), "Seller not whitelisted");

        bytes32 tradeId = _tradeId(buyer, seller, etfAmount, expectedPriceRatio, deadline);
        require(authorizedTrades[tradeId], "Seller did not authorize trade");
        delete authorizedTrades[tradeId];

        uint256 eHKDAmount = _quote(etfAmount, priceRatio);

        _safeTransferFrom(eHKD, buyer, seller, eHKDAmount, "eHKD transfer failed");
        _safeTransferFrom(etfVault, seller, buyer, etfAmount, "ETF transfer failed");

        emit TradeCompleted(buyer, seller, etfAmount, eHKDAmount, priceRatio);
    }

    function quoteEHKD(uint256 etfAmount) external view returns (uint256) {
        return _quote(etfAmount, priceRatio);
    }

    function _quote(uint256 etfAmount, uint256 ratio) internal pure returns (uint256) {
        return (etfAmount * ratio) / PRICE_SCALE;
    }

    function _validateParticipants(address buyer, address seller) internal pure {
        require(buyer != address(0), "Invalid buyer address");
        require(seller != address(0), "Invalid seller address");
        require(buyer != seller, "Buyer and seller must differ");
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

        if (!success) {
            if (data.length > 0) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
            revert(errorMessage);
        }

        if (data.length > 0) {
            require(data.length == 32, errorMessage);
            require(abi.decode(data, (bool)), errorMessage);
        }
    }
}
