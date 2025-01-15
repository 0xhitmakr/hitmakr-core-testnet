// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/core/indexers/IHitmakrDSRCPurchaseIndexer.sol";
import "./IERC7066.sol";

contract HitmakrDSRCUpgradeable is 
    Initializable,
    ERC721Upgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    enum Edition {
        Streaming,
        Collectors,
        Licensing
    }

    struct RoyaltySplit {
        address recipient;
        uint16 percentage;
    }

    struct Earnings {
        uint96 purchase;
        uint96 royalty;
        uint64 pending;
    }

    struct EditionConfig {
        uint256 price;
        bool isEnabled;
        bool isCreated;
    }

    error AlreadyPurchased();
    error TransferFailed();
    error Unauthorized();
    error InvalidPercentages();
    error NoRoyaltiesToDistribute();
    error NotPrimaryChain();
    error InvalidChainParam();
    error ZeroAddress();
    error InvalidEdition();
    error EditionNotEnabled();
    error EditionNotCreated();
    error EditionAlreadyCreated();
    error StreamingMustBeFree();
    error InvalidParams();

    event Purchased(address indexed buyer, uint256 tokenId, uint256 amount, string selectedChain, Edition edition);
    event EditionCreated(Edition indexed edition, uint256 price);
    event EditionStatusUpdated(Edition indexed edition, bool isEnabled);
    event EditionPriceUpdated(Edition indexed edition, uint256 newPrice);
    event RoyaltyReceived(uint256 amount);
    event RoyaltyDistributed(address indexed recipient, uint256 amount, bool isPurchaseEarning);
    event RoyaltiesDistributed(uint256 totalAmount, bool isPurchaseEarning);

    uint16 public constant PLATFORM_FEE = 1000;
    uint16 public constant BASIS_POINTS = 10000;
    bytes32 public constant PRIMARY_CHAIN_ID = keccak256("SKL");
    address public constant TREASURY = 0x699FBF0054B72EF2a85A7f587342B620E49f7f46;

    string public dsrcId;
    address public creator;
    IERC20Upgradeable public paymentToken;
    IHitmakrDSRCPurchaseIndexer public purchaseIndexer;

    string public tokenURI_;
    string public selectedChain;
    Earnings public earnings;
    RoyaltySplit[] public royaltySplits;
    
    mapping(address => bool) public hasPurchased;
    mapping(Edition => EditionConfig) public editionConfigs;
    mapping(uint256 => Edition) public tokenEditions;
    uint256 public totalSupply_;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
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
    ) public initializer {
        __ERC721_init(_dsrcId, _dsrcId);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();


        if (bytes(_selectedChain).length == 0) revert InvalidChainParam();
        if (_creator == address(0) || _paymentToken == address(0) || _purchaseIndexer == address(0)) revert ZeroAddress();
        if (recipients.length == 0 || recipients.length != percentages.length) revert InvalidPercentages();
        if (initialEditions.length != editionPrices.length) revert InvalidParams();

        dsrcId = _dsrcId;
        tokenURI_ = uri;
        selectedChain = _selectedChain;
        creator = _creator;
        paymentToken = IERC20Upgradeable(_paymentToken);
        purchaseIndexer = IHitmakrDSRCPurchaseIndexer(_purchaseIndexer);

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

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}


    modifier onlyPrimaryChain() {
        if (keccak256(abi.encodePacked(selectedChain)) != PRIMARY_CHAIN_ID) revert NotPrimaryChain();
        _;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert Unauthorized();
        _;
    }

    function createEdition(Edition edition, uint256 price) external onlyPrimaryChain onlyRole(DEFAULT_ADMIN_ROLE) {
        _createEdition(edition, price);
    }

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
                earnings.purchase += uint96(netAmount);
                earnings.pending += uint64(netAmount);
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

        emit Purchased(msg.sender, tokenId, price, selectedChain, edition);
    }

    function updateEditionPrice(Edition edition, uint256 newPrice) external onlyPrimaryChain onlyRole(DEFAULT_ADMIN_ROLE) {
        if(edition == Edition.Streaming) revert InvalidEdition();
        if(!editionConfigs[edition].isCreated) revert EditionNotCreated();
        editionConfigs[edition].price = newPrice;
        emit EditionPriceUpdated(edition, newPrice);
        emit EditionStatusUpdated(edition, editionConfigs[edition].isEnabled);
    }

    function updateEditionStatus(Edition edition, bool isEnabled) external onlyPrimaryChain onlyRole(DEFAULT_ADMIN_ROLE) {
        if(!editionConfigs[edition].isCreated) revert EditionNotCreated();
        editionConfigs[edition].isEnabled = isEnabled;
        emit EditionStatusUpdated(edition, isEnabled);
    }

    function getEditionConfig(Edition edition) external view returns (uint256 price, bool isEnabled, bool isCreated) {
        EditionConfig storage config = editionConfigs[edition];
        return (config.price, config.isEnabled, config.isCreated);
    }

    function getTokenEdition(uint256 tokenId) external view returns (Edition) {
        return tokenEditions[tokenId];
    }

    function transferAndLock(uint256 tokenId, address from, address to, bool setApprove) external override {
        if (!_isAuthorized(_ownerOf(tokenId), _msgSender(), tokenId)) revert Unauthorized();
        transferFrom(from, to, tokenId);
        if (setApprove) {
            _approve(_msgSender(), tokenId, _msgSender());
        }
        _lock(tokenId, _msgSender());
    }

    function getEarningsInfo() external view returns (uint256 purchaseEarnings, uint256 royaltyEarnings, uint256 pendingAmount, uint256 totalEarnings) {
        return (earnings.purchase, earnings.royalty, earnings.pending, earnings.purchase + earnings.royalty);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address receiver, uint256 royaltyAmount) {
        if (salePrice == 0) {
            return (_ownerOf(tokenId), 0);
        }
        receiver = address(this);
        royaltyAmount = (salePrice * (BASIS_POINTS - PLATFORM_FEE)) / BASIS_POINTS;
    }

    function getSelectedChain() external view returns (string memory) {
        return selectedChain;
    }

    function getPrimaryChain() external pure returns (string memory) {
        return "SKL";
    }

    function getRoyaltySplits() external view returns (RoyaltySplit[] memory) {
        return royaltySplits;
    }

    function tokenURI(uint256) public view override returns (string memory) {
        return tokenURI_;
    }

    function distributeRoyalties(uint8 distributeType) external nonReentrant {
        uint64 pendingAmount = earnings.pending;
        if(pendingAmount == 0) revert NoRoyaltiesToDistribute();

        earnings.pending = 0;
        uint256 totalDistributed;
        bool isPurchaseEarning = distributeType == 0 || (distributeType == 2 && earnings.purchase > earnings.royalty);

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

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC7066, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}