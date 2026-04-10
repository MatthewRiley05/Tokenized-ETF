// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IKYC.sol";

contract ETFClearing is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable eHKD;
    IERC20 public immutable etfVault;
    IKYC public immutable kycRegistry;

    error InvalidAddress();
    error InvalidParticipants();
    error InvalidAmount();
    error InvalidPrice();
    error AuthorizationExpired();
    error TradeExpired();
    error NotBuyer();
    error BuyerNotWhitelisted();
    error SellerNotWhitelisted();
    error PriceMoved(uint256 expected, uint256 actual);
    error TradeNotAuthorized();

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

    uint256 public constant PRICE_SCALE = 1e18;
    uint256 public priceRatio = 1000 * PRICE_SCALE;

    mapping(bytes32 => bool) public authorizedTrades;

    constructor(address _eHKD, address _etfVault, address _kyc) Ownable(msg.sender) {
        if (_eHKD == address(0) || _etfVault == address(0) || _kyc == address(0)) {
            revert InvalidAddress();
        }

        eHKD = IERC20(_eHKD);
        etfVault = IERC20(_etfVault);
        kycRegistry = IKYC(_kyc);
    }

    function setPriceRatioScaled(uint256 _newPrice) public onlyOwner {
        if (_newPrice == 0) revert InvalidPrice();
        uint256 oldPriceRatio = priceRatio;
        priceRatio = _newPrice;
        emit PriceUpdated(oldPriceRatio, _newPrice);
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        setPriceRatioScaled(_newPrice);
    }

    function setPriceUnscaled(uint256 _newNominalPrice) external onlyOwner {
        if (_newNominalPrice == 0) revert InvalidPrice();
        setPriceRatioScaled(_newNominalPrice * PRICE_SCALE);
    }

    function transferAdmin(address newAdmin) external onlyOwner {
        transferOwnership(newAdmin);
    }

    function acceptAdmin() external {
        acceptOwnership();
    }

    function authorizeTrade(
        address buyer,
        uint256 etfAmount,
        uint256 expectedPriceRatio,
        uint256 deadline
    ) external {
        _validateParticipants(buyer, msg.sender);
        if (etfAmount == 0) revert InvalidAmount();
        if (expectedPriceRatio == 0) revert InvalidPrice();
        if (deadline < block.timestamp) revert AuthorizationExpired();
        if (!kycRegistry.isWhitelisted(msg.sender)) revert SellerNotWhitelisted();
        if (!kycRegistry.isWhitelisted(buyer)) revert BuyerNotWhitelisted();

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
    ) external nonReentrant {
        if (msg.sender != buyer) revert NotBuyer();
        _validateParticipants(buyer, seller);
        if (etfAmount == 0) revert InvalidAmount();
        if (expectedPriceRatio == 0) revert InvalidPrice();
        if (deadline < block.timestamp) revert TradeExpired();
        if (priceRatio != expectedPriceRatio) revert PriceMoved(expectedPriceRatio, priceRatio);
        if (!kycRegistry.isWhitelisted(buyer)) revert BuyerNotWhitelisted();
        if (!kycRegistry.isWhitelisted(seller)) revert SellerNotWhitelisted();

        bytes32 tradeId = _tradeId(buyer, seller, etfAmount, expectedPriceRatio, deadline);
        if (!authorizedTrades[tradeId]) revert TradeNotAuthorized();
        delete authorizedTrades[tradeId];

        uint256 eHKDAmount = _quote(etfAmount, priceRatio);

        eHKD.safeTransferFrom(buyer, seller, eHKDAmount);
        etfVault.safeTransferFrom(seller, buyer, etfAmount);

        emit TradeCompleted(buyer, seller, etfAmount, eHKDAmount, priceRatio);
    }

    function quoteEHKD(uint256 etfAmount) external view returns (uint256) {
        return _quote(etfAmount, priceRatio);
    }

    function _quote(uint256 etfAmount, uint256 ratio) internal pure returns (uint256) {
        return (etfAmount * ratio) / PRICE_SCALE;
    }

    function _validateParticipants(address buyer, address seller) internal pure {
        if (buyer == address(0) || seller == address(0)) revert InvalidAddress();
        if (buyer == seller) revert InvalidParticipants();
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

}
