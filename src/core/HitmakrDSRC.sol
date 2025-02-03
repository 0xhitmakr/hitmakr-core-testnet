// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "../interfaces/core/indexers/IHitmakrDSRCPurchaseIndexer.sol";
import "./ERC7066.sol";

/**
 * @title HitmakrDSRC
 * @author Hitmakr Protocol
 * @notice This contract implements a Digital Scarcity Rights Contract (DSRC) for Hitmakr, allowing creators to mint and sell unique digital assets with different edition types (Streaming, Collectors, Licensing).
 * @dev The contract uses ERC7066 for NFT functionality, integrates with a payment token, and includes royalty distribution logic. It also features an indexer for tracking purchases and supports locking NFTs for cross-chain functionality.
 */
contract HitmakrDSRC is ERC7066, ReentrancyGuard, IERC2981 {
    using SafeERC20 for IERC20;

    /**
     * @notice Enumeration representing the different edition types for the DSRC.
     * @dev Streaming: Free edition for streaming purposes.
     * @dev Collectors: Limited edition for collectors.
     * @dev Licensing: Edition for licensing purposes.
     */
    enum Edition {
        Streaming,
        Collectors,
        Licensing
    }

    /**
     * @notice Structure for defining a royalty split.
     * @member recipient The address of the royalty recipient.
     * @member percentage The percentage of royalties allocated to this recipient (expressed in basis points).
     */
    struct RoyaltySplit {
        address recipient;
        uint16 percentage;
    }

    /**
     * @notice Structure for tracking earnings from the DSRC.
     * @member purchase Total earnings from primary sales.
     * @member royalty Total earnings from royalties.
     * @member pending Pending earnings that haven't been distributed yet.
     */
    struct Earnings {
        uint256 purchase;
        uint256 royalty;
        uint256 pending;
    }

    /**
     * @notice Structure for configuring an edition.
     * @member price The price of the edition.
     * @member isEnabled Whether the edition is currently enabled for purchase.
     * @member isCreated Whether the edition has been created.
     */
    struct EditionConfig {
        uint256 price;
        bool isEnabled;
        bool isCreated;
    }

    /// @notice Error: User has already purchased an edition of this DSRC.
    error AlreadyPurchased();
    /// @notice Error: ERC20 token transfer failed.
    error TransferFailed();
    /// @notice Error: Caller is not authorized to perform the action.
    error Unauthorized();
    /// @notice Error: Invalid royalty percentages provided. The sum must equal BASIS_POINTS.
    error InvalidPercentages();
    /// @notice Error: No royalties are available to distribute.
    error NoRoyaltiesToDistribute();
    /// @notice Error: Function can only be called on the primary chain.
    error NotPrimaryChain();
    /// @notice Error: Invalid chain parameter provided.
    error InvalidChainParam();
    /// @notice Error: Zero address provided where it's not allowed.
    error ZeroAddress();
    /// @notice Error: Invalid edition type provided.
    error InvalidEdition();
    /// @notice Error: The specified edition is not enabled for purchase.
    error EditionNotEnabled();
    /// @notice Error: The specified edition has not been created.
    error EditionNotCreated();
    /// @notice Error: The specified edition has already been created.
    error EditionAlreadyCreated();
    /// @notice Error: The Streaming edition must have a price of zero.
    error StreamingMustBeFree();
    /// @notice Error: Invalid parameters provided to a function.
    error InvalidParams();

    /// @notice Event emitted when a user purchases an edition of the DSRC.
    event Purchased(address indexed buyer, uint256 amount, string selectedChain, Edition edition);
    /// @notice Event emitted when a new edition is created.
    event EditionCreated(Edition indexed edition, uint256 price);
    /// @notice Event emitted when an edition's status (enabled/disabled) is updated.
    event EditionStatusUpdated(Edition indexed edition, bool isEnabled);
    /// @notice Event emitted when an edition's price is updated.
    event EditionPriceUpdated(Edition indexed edition, uint256 newPrice);
    /// @notice Event emitted when royalties are received by the contract.
    event RoyaltyReceived(uint256 amount);
    /// @notice Event emitted when royalties are distributed to a recipient.
    event RoyaltyDistributed(address indexed recipient, uint256 amount, bool isPurchaseEarning);
    /// @notice Event emitted after all royalties for a given distribution are sent.
    event RoyaltiesDistributed(uint256 totalAmount, bool isPurchaseEarning);


    /// @notice The platform fee percentage (10%).
    uint16 public constant PLATFORM_FEE = 1000;
    /// @notice Basis points for percentage calculations (100%).
    uint16 public constant BASIS_POINTS = 10000;
    /// @notice Keccak256 hash of the primary chain identifier.
    bytes32 public constant PRIMARY_CHAIN_ID = keccak256("SKL");
    /// @notice String identifier of the primary chain.
    string public constant PRIMARY_CHAIN = "SKL";
    /// @notice Address of the treasury wallet.
    address public constant TREASURY = 0x699FBF0054B72EF2a85A7f587342B620E49f7f46;

    /// @notice Unique identifier for the DSRC.
    string public dsrcId;
    /// @notice Address of the DSRC creator.
    address public immutable creator;
    /// @notice ERC20 token used for payments.
    IERC20 public immutable paymentToken;
    /// @notice Indexer contract for tracking DSRC purchases.
    IHitmakrDSRCPurchaseIndexer public immutable purchaseIndexer;

    /// @notice URI for the DSRC metadata.
    string public tokenURI_;
    /// @notice Identifier of the currently selected chain.
    string public selectedChain;
    /// @notice Earnings information for the DSRC.
    Earnings public earnings;
    /// @notice Array of royalty splits.
    RoyaltySplit[] public royaltySplits;
    
    /// @notice Mapping to track whether a user has purchased an edition.
    mapping(address => bool) public hasPurchased;
    /// @notice Mapping from edition type to its configuration.
    mapping(Edition => EditionConfig) public editionConfigs;
    /// @notice Mapping from token ID to its edition type.
    mapping(uint256 => Edition) public tokenEditions;
    /// @notice Total supply of minted tokens for this DSRC.
    uint256 public totalSupply_;

    /// @notice Modifier to restrict function calls to the primary chain.
    modifier onlyPrimaryChain() {
        if (keccak256(abi.encodePacked(selectedChain)) != PRIMARY_CHAIN_ID) 
            revert NotPrimaryChain();
        _;
    }

    /// @notice Modifier to restrict function calls to the DSRC creator.
    modifier onlyCreator() {
        if (msg.sender != creator) revert Unauthorized();
        _;
    }

    /**
     * @notice Constructor initializes the DSRC contract.
     * @param _dsrcId Unique identifier for the DSRC.
     * @param uri URI for the DSRC metadata.
     * @param _creator Address of the DSRC creator.
     * @param _paymentToken Address of the ERC20 payment token.
     * @param initialEditions Array of initial edition types to create.
     * @param editionPrices Array of prices for the initial editions.
     * @param recipients Array of royalty recipient addresses.
     * @param percentages Array of royalty percentages for each recipient.
     * @param _selectedChain Identifier of the initially selected chain.
     * @param _purchaseIndexer Address of the purchase indexer contract.
     * @dev Initializes the contract with provided parameters, creates initial editions, and sets up royalty splits.
     */
    constructor(
        string memory _dsrcId,
        string memory uri,
        address _creator,
        address _paymentToken,
        Edition[] memory initialEditions,
        uint256[] memory editionPrices,
        address[] memory recipients,
        uint16[] memory percentages,
        string memory _selectedChain,
        address _purchaseIndexer
    ) ERC721(_dsrcId, _dsrcId) {
        if (bytes(_selectedChain).length == 0) revert InvalidChainParam();
        if (_creator == address(0) || _paymentToken == address(0) || _purchaseIndexer == address(0)) 
            revert ZeroAddress();
        if (recipients.length == 0 || recipients.length != percentages.length) 
            revert InvalidPercentages();
        if (initialEditions.length != editionPrices.length) revert InvalidParams();

        dsrcId = _dsrcId;
        tokenURI_ = uri;
        selectedChain = _selectedChain;
        creator = _creator;
        paymentToken = IERC20(_paymentToken);
        purchaseIndexer = IHitmakrDSRCPurchaseIndexer(_purchaseIndexer);

        // Streaming edition is always free and enabled by default
        editionConfigs[Edition.Streaming] = EditionConfig({
            price: 0,
            isEnabled: true,
            isCreated: true
        });

        for(uint256 i = 0; i < initialEditions.length; i++) {
            Edition edition = initialEditions[i];
            if(edition == Edition.Streaming) {
                if(editionPrices[i] != 0) revert StreamingMustBeFree();
                continue;
            }
            _createEdition(edition, editionPrices[i]);
        }

        uint16 totalPercentage;
        for(uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            totalPercentage += percentages[i];
            royaltySplits.push(RoyaltySplit(recipients[i], percentages[i]));
        }

        if(totalPercentage != BASIS_POINTS) revert InvalidPercentages();
    }

    /**
     * @notice Creates a new edition for the DSRC.
     * @param edition The type of edition to create.
     * @param price The price of the edition.
     * @dev Only callable by the creator on the primary chain. Emits an `EditionCreated` event.
     */
    function createEdition(Edition edition, uint256 price) external onlyPrimaryChain onlyCreator {
        _createEdition(edition, price);
    }

    /**
     * @dev Internal function to create a new edition.
     * @param edition The type of edition to create.
     * @param price The price of the edition.
     */
    function _createEdition(Edition edition, uint256 price) internal {
        if(edition == Edition.Streaming) revert InvalidEdition();
        if(editionConfigs[edition].isCreated) revert EditionAlreadyCreated();
        
        editionConfigs[edition] = EditionConfig({
            price: price,
            isEnabled: true,
            isCreated: true
        });

        emit EditionCreated(edition, price);
    }

    /**
     * @notice Allows a user to purchase a specific edition of the DSRC.
     * @param edition The type of edition to purchase.
     * @dev Only callable on the primary chain. Reverts if the user has already purchased, the edition is not enabled or created, or the transfer fails. 
     *      Mints a new NFT to the buyer, updates purchase tracking, and emits a `Purchased` event.
     */
    function purchase(Edition edition) external nonReentrant onlyPrimaryChain {
        if(hasPurchased[msg.sender]) revert AlreadyPurchased();
        
        EditionConfig storage config = editionConfigs[edition];
        if(!config.isCreated) revert EditionNotCreated();
        if(!config.isEnabled) revert EditionNotEnabled();

        uint256 price = config.price;
        if(price > 0) {
            paymentToken.safeTransferFrom(msg.sender, address(this), price);

            uint256 platformFee = (price * PLATFORM_FEE) / BASIS_POINTS;
            paymentToken.safeTransfer(TREASURY, platformFee);

            uint256 netAmount = price - platformFee;
            
            unchecked {
                earnings.purchase += uint256(netAmount);
                earnings.pending += uint256(netAmount);
            }
        }

        uint256 tokenId;
        unchecked {
            tokenId = ++totalSupply_;
        }
        
        _safeMint(msg.sender, tokenId);
        tokenEditions[tokenId] = edition;
        
        hasPurchased[msg.sender] = true;
        purchaseIndexer.indexPurchase(msg.sender, dsrcId, price);

        emit Purchased(msg.sender, price, selectedChain, edition);
    }

    /**
     * @notice Updates the price of a specific edition.
     * @param edition The edition type to update.
     * @param newPrice The new price for the edition.
     * @dev Only callable by the creator on the primary chain. Emits an `EditionPriceUpdated` event.
     */
    function updateEditionPrice(Edition edition, uint256 newPrice) external onlyPrimaryChain onlyCreator {
        if(edition == Edition.Streaming) revert InvalidEdition();
        if(!editionConfigs[edition].isCreated) revert EditionNotCreated();
        editionConfigs[edition].price = newPrice;
        emit EditionPriceUpdated(edition, newPrice);
    }

    /**
     * @notice Updates the enabled status of a specific edition.
     * @param edition The edition type to update.
     * @param isEnabled The new enabled status for the edition.
     * @dev Only callable by the creator on the primary chain. Emits an `EditionStatusUpdated` event.
     */
    function updateEditionStatus(Edition edition, bool isEnabled) external onlyPrimaryChain onlyCreator {
        if(!editionConfigs[edition].isCreated) revert EditionNotCreated();
        editionConfigs[edition].isEnabled = isEnabled;
        emit EditionStatusUpdated(edition, isEnabled);
    }

    /**
     * @notice Retrieves the configuration of a specific edition.
     * @param edition The edition type to retrieve the config for.
     * @return price The price of the edition.
     * @return isEnabled Whether the edition is enabled.
     * @return isCreated Whether the edition has been created.
     */
    function getEditionConfig(Edition edition) external view returns (
        uint256 price, 
        bool isEnabled, 
        bool isCreated
    ) {
        EditionConfig storage config = editionConfigs[edition];
        return (config.price, config.isEnabled, config.isCreated);
    }

    /**
     * @notice Retrieves the edition type of a specific token.
     * @param tokenId The ID of the token.
     * @return The edition type of the token.
     */
    function getTokenEdition(uint256 tokenId) external view returns (Edition) {
        return tokenEditions[tokenId];
    }

    /**
     * @notice Transfers a token and locks it, used for cross-chain functionality.
     * @param tokenId The ID of the token to transfer.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param setApprove Whether to approve the caller for the token.
     * @dev Overrides the ERC7066 implementation. Reverts if the caller is not authorized.
     */
    function transferAndLock(
        uint256 tokenId, 
        address from, 
        address to, 
        bool setApprove
    ) external override {
        if (!_isAuthorized(_ownerOf(tokenId), _msgSender(), tokenId)) revert Unauthorized();
        transferFrom(from, to, tokenId);
        if (setApprove) {
            _approve(_msgSender(), tokenId, _msgSender());
        }
        _lock(tokenId, _msgSender());
    }

    /**
     * @notice Retrieves earnings information for the DSRC.
     * @return purchaseEarnings Total earnings from primary sales.
     * @return royaltyEarnings Total earnings from royalties.
     * @return pendingAmount Current pending earnings.
     * @return totalEarnings Total earnings (purchase + royalty).
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
     * @notice Implements the ERC2981 royalty standard.
     * @param salePrice The sale price of the token.
     * @return receiver The address of the royalty receiver (this contract).
     * @return royaltyAmount The royalty amount calculated based on the sale price.
     */
    function royaltyInfo(uint256, uint256 salePrice) external view override returns (
        address receiver, 
        uint256 royaltyAmount
    ) {
        receiver = address(this);
        royaltyAmount = (salePrice * (BASIS_POINTS - PLATFORM_FEE)) / BASIS_POINTS;
    }

    /**
     * @notice Returns the token URI for the DSRC.
     * @return The token URI.
     */
    function tokenURI(uint256) public view override returns (string memory) {
        return tokenURI_;
    }

    /**
     * @notice Distributes pending royalties to the specified recipients based on distribute type.
     * @param distributeType An integer representing the distribution logic to use:
     *                       0: Distribute pending royalties from purchase earnings to royalty splits.
     *                       1: Distribute pending royalties from royalty earnings to royalty splits.
     *                       2: Distribute pending royalties to royalty splits based on which earning type has a higher balance (purchase or royalty).
     * @dev Reverts if there are no pending royalties to distribute. Emits `RoyaltyDistributed` and `RoyaltiesDistributed` events.
     */
    function distributeRoyalties(uint8 distributeType) external nonReentrant {
        uint256 pendingAmount = earnings.pending;
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
     * @notice Receives and distributes royalties earned from secondary sales.
     * @dev Calculates the new royalties received, updates earnings, and distributes them to royalty recipients.
     *      Emits `RoyaltyReceived`, `RoyaltyDistributed`, and `RoyaltiesDistributed` events.
     */
    function onRoyaltyReceived() external nonReentrant {
        uint256 currentBalance = paymentToken.balanceOf(address(this));
        uint256 newRoyalties = currentBalance - earnings.pending;

        if (newRoyalties > 0) {
            unchecked {
                earnings.royalty += uint256(newRoyalties);
            }
            uint256 totalDistributed;

            for (uint256 i = 0; i < royaltySplits.length; i++) {
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
     * @notice Checks if the contract supports a given interface.
     * @param interfaceId The interface identifier.
     * @return True if the interface is supported, false otherwise.
     * @dev Overrides the ERC7066 implementation to include support for IERC2981.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC7066, IERC165) returns (bool) {
        return 
            interfaceId == type(IERC2981).interfaceId || 
            super.supportsInterface(interfaceId);
    }
}