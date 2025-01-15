// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/accesscontrol/IHitmakrControlCenter.sol";
import "../interfaces/core/IHitmakrCreativeID.sol";
import "./HitmakrDSRCUpgradeable.sol";
import "../utils/DSRCSignatureUtils.sol";

contract HitmakrDSRCFactoryUpgradeable is 
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable
     {
    using DSRCSignatureUtils for DSRCSignatureUtils.DSRCParams;

    error Unauthorized();
    error DSRCExists();
    error InvalidParams();
    error CountExceeded();
    error NoCreativeID();
    error InvalidYear();
    error ZeroAddress();
    error InvalidEditionPrice();
    error InvalidEdition();
    error InvalidEditionConfig();

    event DSRCCreated(
        string dsrcId,
        address dsrcAddress,
        address creator,
        string selectedChain
    );
    event YearInitialized(address indexed creator, uint64 indexed year);

    bytes32 public constant FACTORY_ADMIN_ROLE =
        keccak256("FACTORY_ADMIN_ROLE");
    uint32 private constant MAX_COUNT_PER_YEAR = 99999;
    string private constant CONTRACT_NAME = "HitmakrDSRCFactory";
    string private constant CONTRACT_VERSION = "1.0.0";
    uint256 private constant YEAR_IN_SECONDS = 31536000;

    address private USDC;
    IHitmakrControlCenter public controlCenter;
    IHitmakrCreativeID public creativeID;
    address public purchaseIndexer;

    mapping(bytes32 => address) public dsrcs;
    mapping(address => uint256) public nonces;
    mapping(address => mapping(uint64 => uint32)) public yearCounts;
    mapping(bytes32 => mapping(bytes32 => address)) public chainDsrcs;
    mapping(address => bool) public isValidDSRC;

    struct DeploymentConfig {
        string dsrcId;
        string tokenURI;
        address creator;
        address[] recipients;
        uint16[] percentages;
        string selectedChain;
        HitmakrDSRC.Edition[] editions;
        uint256[] prices;
        bool[] states;
    }

    struct EditionData {
        HitmakrDSRC.Edition[] editions;
        uint256[] prices;
        bool[] states;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _controlCenter,
        address _creativeID,
        address _usdc,
        address _indexer
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();


        if (
            _controlCenter == address(0) ||
            _creativeID == address(0) ||
            _usdc == address(0) ||
            _indexer == address(0)
        ) revert InvalidParams();

        controlCenter = IHitmakrControlCenter(_controlCenter);
        creativeID = IHitmakrCreativeID(_creativeID);
        USDC = _usdc;
        purchaseIndexer = _indexer;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ADMIN_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function createDSRC(
        DSRCSignatureUtils.DSRCParams calldata params,
        uint256 licensingPrice,
        bytes calldata signature
    ) external {
        if (
            !hasRole(FACTORY_ADMIN_ROLE, msg.sender) &&
            !IAccessControl(address(controlCenter)).hasRole(
                controlCenter.VERIFIER_ROLE(),
                msg.sender
            )
        ) revert Unauthorized();

        address creator = DSRCSignatureUtils.verify(
            params,
            signature,
            CONTRACT_NAME,
            CONTRACT_VERSION,
            address(this)
        );

        if (params.nonce != nonces[creator]) revert InvalidParams();

        string memory dsrcId = generateDSRCId(creator);
        bytes32 dsrcIdHash = keccak256(bytes(dsrcId));
        bytes32 chainHash = keccak256(bytes(params.selectedChain));

        if (dsrcs[dsrcIdHash] != address(0)) revert DSRCExists();
        if (chainDsrcs[chainHash][dsrcIdHash] != address(0))
            revert DSRCExists();
        if (bytes(params.selectedChain).length == 0) revert InvalidParams();

        DeploymentConfig memory config = _prepareDeploymentConfig(
            dsrcId,
            params,
            licensingPrice,
            creator
        );

        address dsrcAddress = _deployAndRegister(config, dsrcIdHash, chainHash);

        unchecked {
            ++nonces[creator];
        }

        emit DSRCCreated(dsrcId, dsrcAddress, creator, params.selectedChain);
    }

    function _prepareDeploymentConfig(
        string memory dsrcId,
        DSRCSignatureUtils.DSRCParams calldata params,
        uint256 licensingPrice,
        address creator
    ) private pure returns (DeploymentConfig memory) {
        uint16[] memory percentages = new uint16[](params.percentages.length);
        for (uint256 i = 0; i < params.percentages.length; i++) {
            if (params.percentages[i] > type(uint16).max)
                revert InvalidParams();
            percentages[i] = uint16(params.percentages[i]);
        }

        EditionData memory editionData = _createEditionData(
            params.price,
            licensingPrice
        );

        return
            DeploymentConfig({
                dsrcId: dsrcId,
                tokenURI: params.tokenURI,
                creator: creator,
                recipients: params.recipients,
                percentages: percentages,
                selectedChain: params.selectedChain,
                editions: editionData.editions,
                prices: editionData.prices,
                states: editionData.states
            });
    }

    function _createEditionData(
        uint256 collectorsPrice,
        uint256 licensingPrice
    ) private pure returns (EditionData memory) {
        HitmakrDSRC.Edition[] memory editions = new HitmakrDSRC.Edition[](3);
        uint256[] memory prices = new uint256[](3);
        bool[] memory states = new bool[](3);

        editions[0] = HitmakrDSRC.Edition.Streaming;
        editions[1] = HitmakrDSRC.Edition.Collectors;
        editions[2] = HitmakrDSRC.Edition.Licensing;

        prices[0] = 0;
        prices[1] = collectorsPrice;
        prices[2] = licensingPrice;

        states[0] = true;
        states[1] = collectorsPrice > 0;
        states[2] = licensingPrice > 0;

        return
            EditionData({editions: editions, prices: prices, states: states});
    }

    function _deployAndRegister(
        DeploymentConfig memory config,
        bytes32 dsrcIdHash,
        bytes32 chainHash
    ) private returns (address) {
        HitmakrDSRC newDSRC = new HitmakrDSRC(
            config.dsrcId,
            config.tokenURI,
            config.creator,
            USDC,
            config.editions,
            config.prices,
            config.recipients,
            config.percentages,
            config.selectedChain,
            purchaseIndexer
        );

        address dsrcAddress = address(newDSRC);
        dsrcs[dsrcIdHash] = dsrcAddress;
        chainDsrcs[chainHash][dsrcIdHash] = dsrcAddress;
        isValidDSRC[dsrcAddress] = true;

        return dsrcAddress;
    }

    function generateDSRCId(address creator) internal returns (string memory) {
        (string memory userCreativeId, , bool exists) = creativeID
            .getCreativeID(creator);
        if (!exists) revert NoCreativeID();

        uint64 yearLastTwo;
        unchecked {
            yearLastTwo = uint64(
                (block.timestamp / YEAR_IN_SECONDS + 1970) % 100
            );
        }

        uint32 newCount;
        unchecked {
            newCount = yearCounts[creator][yearLastTwo] + 1;
        }
        if (newCount > MAX_COUNT_PER_YEAR) revert CountExceeded();

        yearCounts[creator][yearLastTwo] = newCount;

        return
            string(
                abi.encodePacked(
                    userCreativeId,
                    _formatNumber(yearLastTwo, 2),
                    _formatNumber(newCount, 5)
                )
            );
    }

    function _formatNumber(
        uint256 number,
        uint256 digits
    ) internal pure returns (string memory) {
        bytes memory numbers = "0123456789";
        bytes memory buffer = new bytes(digits);

        unchecked {
            for (uint i = digits - 1; ; i--) {
                buffer[i] = numbers[number % 10];
                number /= 10;
                if (i == 0) break;
            }
        }

        return string(buffer);
    }
}
