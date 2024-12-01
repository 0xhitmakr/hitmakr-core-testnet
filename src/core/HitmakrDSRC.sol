// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "../interfaces/core/indexers/IHitmakrDSRCPurchaseIndexer.sol";
import "../interfaces/core/IERC7066.sol";

/**
 * @title HitmakrDSRC
 * @author Hitmakr Protocol
 * @notice This contract represents a Decentralized Standard Recording Code (DSRC) implemented as an ERC721 NFT.
 * @dev It includes functionality for purchasing DSRCs, distributing royalties, updating the price, and managing token locks according to IERC7066. The contract is optimized for gas efficiency and implements security measures like reentrancy guards.
 */
contract HitmakrDSRC is ERC721, ReentrancyGuard, IERC2981, IERC7066 {
    using SafeERC20 for IERC20;

    /**
     * @notice Structure representing a royalty recipient and their percentage share.
     * @param recipient The address of the royalty recipient.
     * @param percentage The percentage of royalties allocated to this recipient (in basis points).
     */
    struct RoyaltySplit {
        address recipient;
        uint16 percentage;
    }

    /**
     * @notice Structure for tracking earnings from DSRC sales and royalties.
     * @param purchase Total earnings from primary sales.
     * @param royalty Total earnings from secondary sales royalties.
     * @param pending Pending earnings that have not yet been distributed.
     */
    struct Earnings {
        uint96 purchase;
        uint96 royalty;
        uint64 pending;
    }

    /// @notice Error when attempting to lock a token that is already locked
    error AlreadyLocked();
    /// @notice Error when attempting to unlock a token that is not locked
    error NotLocked();
    /// @notice Error when a non-locker attempts to unlock a token
    error NotLocker();
    /// @notice Error when attempting an action on a locked token that is not allowed
    error LockedToken();
    /// @notice Error when a user attempts to purchase a DSRC they have already purchased
    error AlreadyPurchased();
    /// @notice Error when a transfer of ERC20 tokens fails
    error TransferFailed();
    /// @notice Error for unauthorized access
    error Unauthorized();
    /// @notice Error when attempting a transfer that is not allowed
    error TransferNotAllowed();
    /// @notice Error when the sum of royalty percentages does not equal 100% (BASIS_POINTS)
    error InvalidPercentages();
    /// @notice Error when there are no royalties to distribute
    error NoRoyaltiesToDistribute();
    /// @notice Error when a function restricted to the primary chain is called on a different chain
    error NotPrimaryChain();
    /// @notice Error for invalid parameters related to the selected chain.
    error InvalidChainParam();
    /// @notice Error for when a zero address is passed as parameter.
    error ZeroAddress();

    /// @notice Event emitted when a DSRC is purchased
    event Purchased(address indexed buyer, uint256 amount, string selectedChain);
    /// @notice Event emitted when the DSRC price is updated
    event PriceUpdated(uint256 newPrice);
    /// @notice Event emitted when royalties are received by the contract
    event RoyaltyReceived(uint256 amount);
    /// @notice Event emitted when royalties are distributed to a recipient
    event RoyaltyDistributed(address indexed recipient, uint256 amount, bool isPurchaseEarning);
    /// @notice Event emitted when all pending royalties are distributed.
    event RoyaltiesDistributed(uint256 totalAmount, bool isPurchaseEarning);


    /// @notice Platform fee percentage (in basis points)
    uint16 public constant PLATFORM_FEE = 1000;
    /// @notice Total basis points (100%)
    uint16 public constant BASIS_POINTS = 10000;
    /// @notice Chain identifier for the primary chain where purchases are allowed
    bytes32 public constant PRIMARY_CHAIN_ID = keccak256("SKL");
    /// @notice Address of the treasury to receive platform fees
    address public constant TREASURY = 0x699FBF0054B72EF2a85A7f587342B620E49f7f46;

    /// @notice The unique identifier for this DSRC
    string public dsrcId;
    /// @notice The address of the DSRC creator
    address public immutable creator;
    /// @notice The ERC20 token used for payments
    IERC20 public immutable paymentToken;
    /// @notice The indexer contract for tracking DSRC purchases
    IHitmakrDSRCPurchaseIndexer public immutable purchaseIndexer;

    /// @notice The URI for the DSRC metadata
    string public tokenURI_;
    /// @notice Identifier for the blockchain where this DSRC is primarily used
    string public selectedChain;
    /// @notice The current price of the DSRC in payment tokens
    uint256 public price;
    /// @notice The total number of DSRCs minted
    uint256 public totalSupply_;
    /// @notice Earnings tracking structure
    Earnings public earnings;
    /// @notice Array of royalty splits
    RoyaltySplit[] public royaltySplits;
    
    /// @notice Mapping from token ID to the address that locked it (IERC7066)
    mapping(uint256 => address) public lockers;
    /// @notice Mapping from user address to a boolean indicating if they have purchased this DSRC
    mapping(address => bool) public hasPurchased;

    /// @notice Modifier to restrict functions to calls only from the primary chain
    modifier onlyPrimaryChain() {
        if (keccak256(abi.encodePacked(selectedChain)) != PRIMARY_CHAIN_ID) 
            revert NotPrimaryChain();
        _;
    }

    /// @notice Modifier to restrict functions to calls only from the creator address
    modifier onlyCreator() {
        if (msg.sender != creator) revert Unauthorized();
        _;
    }

    /**
     * @notice Constructor for the HitmakrDSRC contract
     * @param _dsrcId The unique identifier for the DSRC
     * @param uri The URI for the DSRC metadata
     * @param _creator The address of the DSRC creator
     * @param _paymentToken The address of the ERC20 payment token
     * @param _price The initial price of the DSRC
     * @param recipients An array of royalty recipient addresses
     * @param percentages An array of royalty percentages (in basis points) corresponding to the recipients
     * @param _selectedChain The identifier for the blockchain where this DSRC is primarily used
     * @param _purchaseIndexer The address of the purchase indexer contract
     */
    constructor(
        string memory _dsrcId,
        string memory uri,
        address _creator,
        address _paymentToken,
        uint256 _price,
        address[] memory recipients,
        uint16[] memory percentages,
        string memory _selectedChain,
        address _purchaseIndexer
    ) ERC721(_dsrcId, _dsrcId) {
        if (bytes(_selectedChain).length == 0) revert InvalidChainParam();
        if (_creator == address(0) || 
            _paymentToken == address(0) || 
            _purchaseIndexer == address(0)) revert ZeroAddress();
        if (recipients.length == 0 || recipients.length != percentages.length) 
            revert InvalidPercentages();

        dsrcId = _dsrcId;
        tokenURI_ = uri;
        selectedChain = _selectedChain;
        creator = _creator;
        paymentToken = IERC20(_paymentToken);
        purchaseIndexer = IHitmakrDSRCPurchaseIndexer(_purchaseIndexer);
        price = _price;

        uint16 totalPercentage;
        for(uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            totalPercentage += percentages[i];
            royaltySplits.push(RoyaltySplit(recipients[i], percentages[i]));
        }

        if(totalPercentage != BASIS_POINTS) revert InvalidPercentages();
    }

    /**
     * @notice Locks a specific token, preventing certain actions like transfers.
     * @param tokenId The ID of the token to lock.
     * @dev Implements IERC7066. Reverts if the caller is not authorized.
     */
    function lock(uint256 tokenId) external override {
        if (!isApprovedOrOwner(msg.sender, tokenId)) revert Unauthorized();
        if (lockers[tokenId] != address(0)) revert AlreadyLocked();
        
        lockers[tokenId] = msg.sender;
        emit Lock(tokenId, msg.sender);
    }

    /**
     * @notice Locks a given `tokenId` to the specified `_locker` address.
     * @param tokenId The ID of the token to lock.
     * @param _locker Address to which the token will be locked.
     * @dev Follows IERC7066 standard. Reverts if `tokenId` is already locked, if `_locker` is a zero address or if the caller is not authorized.
     */
    function lock(uint256 tokenId, address _locker) external override {
        if (!isApprovedOrOwner(msg.sender, tokenId)) revert Unauthorized();
        if (lockers[tokenId] != address(0)) revert AlreadyLocked();
        if (_locker == address(0)) revert ZeroAddress();

        lockers[tokenId] = _locker;
        emit Lock(tokenId, _locker);
    }

    /**
     * @notice Checks if an address is approved for a token or owns it.
     * @param spender The address to check.
     * @param tokenId The token ID.
     * @return True if approved or owner, false otherwise.
     */
    function isApprovedOrOwner(address spender, uint256 tokenId) public view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || 
                isApprovedForAll(owner, spender) || 
                getApproved(tokenId) == spender);
    }

    /**
     * @notice Unlocks a previously locked token.
     * @param tokenId The ID of the token to unlock.
     * @dev Implements IERC7066. Reverts if the token is not locked or if the caller is not the locker.
     */
    function unlock(uint256 tokenId) external override {
        if (lockers[tokenId] == address(0)) revert NotLocked();
        if (lockers[tokenId] != msg.sender) revert NotLocker();

        delete lockers[tokenId];
        emit Unlock(tokenId);
    }

    /**
     * @notice `transferAndLock` function is disabled in the `HitmakrDSRC` implementation.
     */
    function transferAndLock(
        uint256,
        address,
        address,
        bool
    ) external pure override {
        revert TransferNotAllowed();
    }

    /**
     * @notice Returns the address of the locker for a given token ID, adhering to IERC7066.
     * @param tokenId The ID of the token.
     * @return address The address of the locker, or the zero address if unlocked.
     */
    function lockerOf(uint256 tokenId) external view override returns (address) {
        return lockers[tokenId];
    }

    /**
     * @notice Allows a user to purchase a DSRC.
     * @dev Transfers payment tokens, mints a new DSRC to the buyer, updates earnings, and indexes the purchase.
     *      Reverts if the user has already purchased, the transfer fails, or if not called on the primary chain.
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
            _safeMint(msg.sender, ++totalSupply_);
        }
        
        hasPurchased[msg.sender] = true;
        purchaseIndexer.indexPurchase(msg.sender, dsrcId, price);

        emit Purchased(msg.sender, price, selectedChain);
    }

    /**
     * @dev Internal function to update ownership of a token. Prevents transfers if the token is locked.
     * @inheritdoc ERC721
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        if (lockers[tokenId] != address(0)) revert LockedToken();
        address from = _ownerOf(tokenId);
        
        if (from != address(0) && to != address(0)) revert TransferNotAllowed();

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Overrides the `approve` function to prevent approval if the token is locked.
     * @inheritdoc ERC721
     */
    function approve(address operator, uint256 tokenId) public virtual override {
        if (lockers[tokenId] != address(0)) revert LockedToken();
        super.approve(operator, tokenId);
    }

    /**
     * @dev Disables setting approval for all tokens by reverting.
     * @inheritdoc ERC721
     */
    function setApprovalForAll(address, bool) public pure override {
        revert TransferNotAllowed();
    }

    /**
     * @notice Updates the price of the DSRC.
     * @param newPrice The new price in payment tokens.
     * @dev Only callable by the creator. Emits a `PriceUpdated` event.
     */
    function updatePrice(uint256 newPrice) external onlyPrimaryChain onlyCreator {
        price = newPrice;
        emit PriceUpdated(newPrice);
    }

    /**
     * @notice Returns detailed earnings information for the DSRC.
     * @return purchaseEarnings Total earnings from primary sales.
     * @return royaltyEarnings Total earnings from royalties.
     * @return pendingAmount Amount of pending earnings to be distributed.
     * @return totalEarnings Sum of purchase and royalty earnings.
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
     * @notice Returns royalty information according to the ERC2981 standard.
     * @param salePrice The sale price of the token.
     * @return receiver The address to receive royalties (this contract).
     * @return royaltyAmount The amount of royalties to be paid.
     * @dev The royalty amount is calculated as (salePrice * (BASIS_POINTS - PLATFORM_FEE)) / BASIS_POINTS.
     */
    function royaltyInfo(uint256, uint256 salePrice) external view override 
        returns (address receiver, uint256 royaltyAmount) 
    {
        receiver = address(this);
        royaltyAmount = (salePrice * (BASIS_POINTS - PLATFORM_FEE)) / BASIS_POINTS;
    }

    /**
     * @notice Returns the selected chain identifier for this DSRC.
     * @return The selected chain identifier as a string.
     */
    function getSelectedChain() external view returns (string memory) {
        return selectedChain;
    }

    /**
     * @notice Returns the identifier for the primary chain (SKL).
     * @return The primary chain identifier as a string.
     */
    function getPrimaryChain() external pure returns (string memory) {
        return "SKL";
    }

    /**
     * @notice Returns the array of royalty splits.
     * @return An array of `RoyaltySplit` structs.
     */
    function getRoyaltySplits() external view returns (RoyaltySplit[] memory) {
        return royaltySplits;
    }

     /**
     * @notice Returns the token URI for the DSRC.
     * @return The token URI as a string.
     * @dev This function overrides the ERC721 `tokenURI` function and returns the `tokenURI_` variable.
     */
    function tokenURI(uint256) public view override returns (string memory) {
        return tokenURI_;
    }

    /**
     * @notice Distributes pending royalties to the designated recipients.
     * @param distributeType Determines how to distribute royalties: 
     *                       0 for purchase earnings, 1 for royalty earnings, 2 for the larger of the two.
     * @dev Only callable if pending royalties exist. Reverts if not. Emits `RoyaltyDistributed` for each recipient and `RoyaltiesDistributed` for the total amount.
     */
    function distributeRoyalties(uint8 distributeType) external nonReentrant {
        uint64 pendingAmount = earnings.pending;
        if(pendingAmount == 0) revert NoRoyaltiesToDistribute();

        earnings.pending = 0;
        uint256 totalDistributed;
        bool isPurchaseEarning = distributeType == 0 || 
            (distributeType == 2 && earnings.purchase > earnings.royalty);

        for(uint256 i = 0; i < royaltySplits.length; i++) {
            uint256 recipientShare;
            
            if (i == royaltySplits.length - 1) {
                recipientShare = pendingAmount - totalDistributed;
            } else {
                recipientShare = (pendingAmount * royaltySplits[i].percentage) / BASIS_POINTS;
                totalDistributed += recipientShare;
            }
            
            if (recipientShare > 0) {
                paymentToken.safeTransfer(royaltySplits[i].recipient, recipientShare);
                emit RoyaltyDistributed(royaltySplits[i].recipient, recipientShare, isPurchaseEarning);
            }
        }
        
        emit RoyaltiesDistributed(pendingAmount, isPurchaseEarning);
    }

    /**
     * @notice Callback function for receiving royalties from marketplaces implementing ERC2981.
     * @dev Updates royalty earnings, distributes new royalties according to splits and emits relevant events.
     *       Only distributes if new royalties greater than zero.
     */
    function onRoyaltyReceived() external nonReentrant {
        uint256 currentBalance = paymentToken.balanceOf(address(this));
        uint256 newRoyalties = currentBalance - earnings.pending;
        
        if(newRoyalties > 0) {
            unchecked {
                earnings.royalty += uint96(newRoyalties);
            }
            
            uint256 totalDistributed;
            
            for(uint256 i = 0; i < royaltySplits.length; i++) {
                uint256 recipientShare;
                
                if (i == royaltySplits.length - 1) {
                    recipientShare = newRoyalties - totalDistributed;
                } else {
                    recipientShare = (newRoyalties * royaltySplits[i].percentage) / BASIS_POINTS;
                    totalDistributed += recipientShare;
                }
                
                if (recipientShare > 0) {
                    paymentToken.safeTransfer(royaltySplits[i].recipient, recipientShare);
                    emit RoyaltyDistributed(royaltySplits[i].recipient, recipientShare, false);
                }
            }
            
            emit RoyaltyReceived(newRoyalties);
            emit RoyaltiesDistributed(newRoyalties, false);
        }
    }

    /**
     * @notice Checks if this contract supports a given interface.
     * @dev Overrides the ERC721 and IERC165 `supportsInterface` functions to include IERC2981 and IERC7066 interfaces.
     * @inheritdoc ERC721
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return 
            interfaceId == type(IERC7066).interfaceId ||
            interfaceId == type(IERC2981).interfaceId || 
            super.supportsInterface(interfaceId);
    }
}