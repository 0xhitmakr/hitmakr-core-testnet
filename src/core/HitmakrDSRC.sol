// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC2981} from "openzeppelin-contracts/contracts/interfaces/IERC2981.sol";
import {IERC165} from "openzeppelin-contracts/contracts/interfaces/IERC165.sol";
import "../interfaces/core/indexers/IHitmakrDSRCPurchaseIndexer.sol";

/**
 * @title HitmakrDSRC
 * @author Hitmakr Protocol
 * @notice This contract represents a Decentralized Standard Recording Code (DSRC) 
 * implemented as a Soulbound ERC721 NFT.
 * @dev Optimized for gas efficiency and security with packed storage
 */
contract HitmakrDSRC is ERC721, ReentrancyGuard, IERC2981 {
    using SafeERC20 for IERC20;

    /**
     * @notice Represents how royalties are split among recipients
     * @dev Packed for gas optimization
     */
    struct RoyaltySplit {
        address recipient;
        uint16 percentage; // Basis points (0-10000)
    }

    /**
     * @notice Tracks various types of earnings
     * @dev Packed into a single storage slot
     */
    struct Earnings {
        uint96 purchase;  // Supports high values while optimizing gas
        uint96 royalty;   // Secondary market royalties
        uint64 pending;   // Pending distributions
    }

    /// @dev Custom errors
    error AlreadyPurchased();
    error TransferFailed();
    error Unauthorized();
    error TransferNotAllowed();
    error InvalidPercentages();
    error NoRoyaltiesToDistribute();
    error NotPrimaryChain();
    error InvalidChainParam();
    error ZeroAddress();

    /// @dev Events
    event Purchased(address indexed buyer, uint256 amount, string selectedChain);
    event PriceUpdated(uint256 newPrice);
    event RoyaltyReceived(uint256 amount);
    event RoyaltyDistributed(
        address indexed recipient, 
        uint256 amount, 
        bool isPurchaseEarning
    );
    event RoyaltiesDistributed(uint256 totalAmount, bool isPurchaseEarning);

    /// @dev Constants for basis points calculations and platform fee
    uint16 private constant PLATFORM_FEE = 1000;  // 10%
    uint16 private constant BASIS_POINTS = 10000;
    bytes32 private constant PRIMARY_CHAIN_ID = keccak256("SKL");
    address private constant TREASURY = 0x699FBF0054B72EF2a85A7f587342B620E49f7f46;

    /// @dev Immutable state variables
    string public dsrcId;
    address public immutable creator;
    IERC20 public immutable paymentToken;
    IHitmakrDSRCPurchaseIndexer public immutable purchaseIndexer;

    /// @dev Storage variables
    string private _tokenURI;
    string private _selectedChain;
    uint256 public price;
    uint256 private _totalSupply;
    Earnings public earnings;
    RoyaltySplit[] private _royaltySplits;

    /// @dev Mappings
    mapping(address => bool) public hasPurchased;

    /**
     * @dev Modifier to restrict actions to primary chain only
     */
    modifier onlyPrimaryChain() {
        if (keccak256(abi.encodePacked(_selectedChain)) != PRIMARY_CHAIN_ID) 
            revert NotPrimaryChain();
        _;
    }

    /**
     * @dev Modifier to restrict actions to creator only
     */
    modifier onlyCreator() {
        if (msg.sender != creator) revert Unauthorized();
        _;
    }

    /**
     * @notice Constructor for the HitmakrDSRC contract
     * @dev Sets up immutable state and validates inputs
     */
    constructor(
        string memory _dsrcId,
        string memory uri,
        address _creator,
        address _paymentToken,
        uint256 _price,
        address[] memory recipients,
        uint16[] memory percentages,
        string memory selectedChain,
        address _purchaseIndexer
    ) ERC721(_dsrcId, _dsrcId) {
        if (bytes(selectedChain).length == 0) revert InvalidChainParam();
        if (_creator == address(0) || 
            _paymentToken == address(0) || 
            _purchaseIndexer == address(0)) revert ZeroAddress();
        if (recipients.length == 0 || recipients.length != percentages.length) 
            revert InvalidPercentages();

        dsrcId = _dsrcId;
        _tokenURI = uri;
        _selectedChain = selectedChain;
        creator = _creator;
        paymentToken = IERC20(_paymentToken);
        purchaseIndexer = IHitmakrDSRCPurchaseIndexer(_purchaseIndexer);
        price = _price;

        uint16 totalPercentage;
        for(uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            totalPercentage += percentages[i];
            _royaltySplits.push(RoyaltySplit(recipients[i], percentages[i]));
        }

        if(totalPercentage != BASIS_POINTS) revert InvalidPercentages();
    }

    /**
     * @notice Allows purchase of the DSRC
     * @dev Handles payment processing, minting, and purchase indexing
     */
    function purchase() external nonReentrant onlyPrimaryChain {
        if(hasPurchased[msg.sender]) revert AlreadyPurchased();

        if(price > 0) {
            paymentToken.safeTransferFrom(msg.sender, address(this), price);

            uint256 platformFee = (price * PLATFORM_FEE) / BASIS_POINTS;
            paymentToken.safeTransfer(TREASURY, platformFee);

            uint256 netAmount = price - platformFee;
            
            unchecked {
                earnings.purchase += uint96(netAmount);
                earnings.pending += uint64(netAmount);
            }
        }

        unchecked {
            _safeMint(msg.sender, ++_totalSupply);
        }
        
        hasPurchased[msg.sender] = true;
        purchaseIndexer.indexPurchase(msg.sender, dsrcId, price);

        emit Purchased(msg.sender, price, _selectedChain);
    }

    /**
     * @notice Receives and distributes royalties
     * @dev Processes incoming royalties and distributes them according to splits
     */
    function onRoyaltyReceived() external nonReentrant {
        uint256 currentBalance = paymentToken.balanceOf(address(this));
        uint256 newRoyalties = currentBalance - earnings.pending;
        
        if(newRoyalties > 0) {
            unchecked {
                earnings.royalty += uint96(newRoyalties);
            }
            
            uint256 totalDistributed;
            
            for(uint256 i = 0; i < _royaltySplits.length; i++) {
                uint256 recipientShare;
                
                if (i == _royaltySplits.length - 1) {
                    recipientShare = newRoyalties - totalDistributed;
                } else {
                    recipientShare = (newRoyalties * _royaltySplits[i].percentage) / BASIS_POINTS;
                    totalDistributed += recipientShare;
                }
                
                if (recipientShare > 0) {
                    paymentToken.safeTransfer(_royaltySplits[i].recipient, recipientShare);
                    emit RoyaltyDistributed(_royaltySplits[i].recipient, recipientShare, false);
                }
            }
            
            emit RoyaltyReceived(newRoyalties);
            emit RoyaltiesDistributed(newRoyalties, false);
        }
    }

    /**
     * @notice Distributes pending earnings to recipients
     * @param distributeType 0 for purchase, 1 for royalty, 2 for larger amount
     */
    function distributeRoyalties(uint8 distributeType) external nonReentrant {
        uint64 pendingAmount = earnings.pending;
        if(pendingAmount == 0) revert NoRoyaltiesToDistribute();

        earnings.pending = 0;
        uint256 totalDistributed;
        bool isPurchaseEarning = distributeType == 0 || 
            (distributeType == 2 && earnings.purchase > earnings.royalty);

        for(uint256 i = 0; i < _royaltySplits.length; i++) {
            uint256 recipientShare;
            
            if (i == _royaltySplits.length - 1) {
                recipientShare = pendingAmount - totalDistributed;
            } else {
                recipientShare = (pendingAmount * _royaltySplits[i].percentage) / BASIS_POINTS;
                totalDistributed += recipientShare;
            }
            
            if (recipientShare > 0) {
                paymentToken.safeTransfer(_royaltySplits[i].recipient, recipientShare);
                emit RoyaltyDistributed(_royaltySplits[i].recipient, recipientShare, isPurchaseEarning);
            }
        }
        
        emit RoyaltiesDistributed(pendingAmount, isPurchaseEarning);
    }

    /**
     * @notice Updates the DSRC price
     * @param newPrice The new price in payment tokens
     */
    function updatePrice(uint256 newPrice) external onlyPrimaryChain onlyCreator {
        price = newPrice;
        emit PriceUpdated(newPrice);
    }

    /**
     * @notice Returns earnings information
     * @return purchaseEarnings Total earnings from primary sales
     * @return royaltyEarnings Total earnings from royalties
     * @return pendingAmount Amount pending distribution
     * @return totalEarnings Combined total of all earnings
     */
    function getEarningsInfo() external view returns (
        uint256 purchaseEarnings,
        uint256 royaltyEarnings,
        uint256 pendingAmount,
        uint256 totalEarnings
    ) {
        return (
            earnings.purchase,
            earnings.royalty,
            earnings.pending,
            earnings.purchase + earnings.royalty
        );
    }

    /**
     * @notice Implements ERC2981 royalty standard
     */
    function royaltyInfo(uint256, uint256 salePrice) external view override 
        returns (address receiver, uint256 royaltyAmount) 
    {
        receiver = address(this);
        royaltyAmount = (salePrice * (BASIS_POINTS - PLATFORM_FEE)) / BASIS_POINTS;
    }

    /**
     * @notice View functions for DSRC information
     */
    function getSelectedChain() external view returns (string memory) {
        return _selectedChain;
    }

    function getPrimaryChain() external pure returns (string memory) {
        return "SKL";
    }

    function getRoyaltySplits() external view returns (RoyaltySplit[] memory) {
        return _royaltySplits;
    }

    function tokenURI(uint256) public view override returns (string memory) {
        return _tokenURI;
    }

    /**
     * @dev Implementation of soulbound token behavior
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        if (from != address(0) && to != address(0)) revert TransferNotAllowed();

        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Disabled transfer functions (Soulbound implementation)
     */
    function transferFrom(address, address, uint256) public virtual override {
        revert TransferNotAllowed();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public virtual override {
        revert TransferNotAllowed();
    }

    function approve(address, uint256) public virtual override {
        revert TransferNotAllowed();
    }

    function setApprovalForAll(address, bool) public virtual override {
        revert TransferNotAllowed();
    }

    /**
     * @notice Interface support
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return 
            interfaceId == type(IERC2981).interfaceId || 
            super.supportsInterface(interfaceId);
    }
}