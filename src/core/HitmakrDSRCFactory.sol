// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/accesscontrol/IControlCenter.sol";
import "../interfaces/core/IHitmakrCreativeID.sol";
import "./HitmakrDSRC.sol";
import "../utils/DSRCSignatureUtils.sol";

/**
 * @title HitmakrDSRCFactory
 * @author Hitmakr Protocol
 * @notice This contract serves as a factory for deploying HitmakrDSRC contracts, which represent Digital Scarcity Rights Contracts.
 * @dev This factory manages the creation of DSRCs, ensuring unique identifiers and integrating with other Hitmakr protocol components like `HitmakrControlCenter` for access control and `HitmakrCreativeID` for creator identification.
 */
contract HitmakrDSRCFactory is AccessControl {
    using DSRCSignatureUtils for DSRCSignatureUtils.DSRCParams;

    /// @notice Error: Caller is not authorized to perform the action.
    error Unauthorized();
    /// @notice Error: A DSRC with the given ID already exists.
    error DSRCExists();
    /// @notice Error: Invalid parameters provided.
    error InvalidParams();
    /// @notice Error: Maximum DSRC creation count for the year exceeded.
    error CountExceeded();
    /// @notice Error: Creator does not have a Creative ID.
    error NoCreativeID();
    /// @notice Error: Invalid year provided.
    error InvalidYear();
    /// @notice Error: Zero address provided where it's not allowed.
    error ZeroAddress();
    /// @notice Error: Invalid price specified for an edition.
    error InvalidEditionPrice();
    /// @notice Error: Invalid edition type specified.
    error InvalidEdition();
    /// @notice Error: Invalid edition configuration provided.
    error InvalidEditionConfig();
    /// @notice Error: Empty token URI provided.
    error InvalidTokenURI();


    /// @notice Event emitted when a new DSRC is created.
    event DSRCCreated(string dsrcId, address dsrcAddress, address creator, string selectedChain);
    /// @notice Event emitted when a year is initialized for a creator (for counting DSRCs).
    event YearInitialized(address indexed creator, uint64 indexed year);
    /// @notice Event emitted when an edition is configured for a DSRC.
    event EditionConfigured(
        string indexed dsrcId,
        HitmakrDSRC.Edition indexed edition,
        uint256 price,
        bool enabled
    );

    /// @notice Role for factory administrators.
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");
    /// @notice Maximum number of DSRCs allowed per creator per year.
    uint32 private constant MAX_COUNT_PER_YEAR = 99999;
    /// @notice Name of the contract.
    string private constant CONTRACT_NAME = "HitmakrDSRCFactory";
    /// @notice Version of the contract.
    string private constant CONTRACT_VERSION = "1.0.0";
    /// @notice Number of seconds in a year.
    uint256 private constant YEAR_IN_SECONDS = 31536000;

    /// @notice Address of the USDC token contract.
    address private immutable USDC;
    /// @notice Instance of the HitmakrControlCenter contract.
    IHitmakrControlCenter public immutable controlCenter;
    /// @notice Instance of the HitmakrCreativeID contract.
    IHitmakrCreativeID public immutable creativeID;
    /// @notice Address of the purchase indexer contract.
    address public immutable purchaseIndexer;

    /// @notice Mapping from DSRC ID hash to DSRC contract address.
    mapping(bytes32 => address) public dsrcs;
    /// @notice Mapping from creator address to their current nonce.
    mapping(address => uint256) public nonces;
    /// @notice Mapping from creator address to a mapping of year to DSRC count for that year.
    mapping(address => mapping(uint64 => uint32)) public yearCounts;
    /// @notice Mapping from chain ID hash to a mapping of DSRC ID hash to DSRC contract address.
    mapping(bytes32 => mapping(bytes32 => address)) public chainDsrcs;
    /// @notice Mapping of DSRC address to validity status.
    mapping(address => bool) public isValidDSRC;

    /**
     * @notice Structure containing the configuration parameters for deploying a DSRC.
     * @member dsrcId The unique identifier for the DSRC.
     * @member tokenURI The URI for the DSRC metadata.
     * @member creator The address of the DSRC creator.
     * @member recipients Array of royalty recipient addresses.
     * @member percentages Array of royalty percentages for each recipient.
     * @member selectedChain The blockchain where the DSRC is being deployed.
     * @member editions Array of edition types for the DSRC.
     * @member prices Array of prices for each edition.
     * @member states Array of boolean values indicating whether each edition is enabled.
     */
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


    /**
     * @notice Structure used to organize edition data during DSRC creation.
     * @member editions An array of Edition enums.
     * @member prices An array of prices corresponding to each edition.
     * @member states An array of booleans representing the enabled/disabled status of each edition.
     */
    struct EditionData {
        HitmakrDSRC.Edition[] editions;
        uint256[] prices;
        bool[] states;
    }

    /**
     * @notice Constructor initializes the factory contract.
     * @param _controlCenter Address of the HitmakrControlCenter contract.
     * @param _creativeID Address of the HitmakrCreativeID contract.
     * @param _usdc Address of the USDC token contract.
     * @param _indexer Address of the purchase indexer contract.
     * @dev Sets up necessary contract instances and grants default admin roles.
     */
    constructor(
        address _controlCenter,
        address _creativeID,
        address _usdc,
        address _indexer
    ) {
        if (_controlCenter == address(0) || 
            _creativeID == address(0) || 
            _usdc == address(0) || 
            _indexer == address(0)) 
            revert ZeroAddress();
            
        controlCenter = IHitmakrControlCenter(_controlCenter);
        creativeID = IHitmakrCreativeID(_creativeID);
        USDC = _usdc;
        purchaseIndexer = _indexer;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Creates a new DSRC contract.
     * @param params Struct containing DSRC parameters. See `DSRCSignatureUtils.DSRCParams`.
     * @param licensingPrice The price for the Licensing edition.
     * @param signature The ECDSA signature of the creator, verifying the DSRC parameters.
     * @dev This function deploys a new `HitmakrDSRC` contract with the specified parameters after verifying the creator's signature. 
     *      It ensures the uniqueness of the DSRC ID and updates internal tracking mechanisms.
     */
    function createDSRC(
        DSRCSignatureUtils.DSRCParams calldata params,
        uint256 licensingPrice,
        bytes calldata signature
    ) external {
        if (!hasRole(FACTORY_ADMIN_ROLE, msg.sender) && 
            !IAccessControl(address(controlCenter)).hasRole(controlCenter.VERIFIER_ROLE(), msg.sender)) 
            revert Unauthorized();

        if (params.price == 0 && licensingPrice == 0) revert InvalidEditionPrice();
        if (bytes(params.tokenURI).length == 0) revert InvalidTokenURI();
        if (bytes(params.selectedChain).length == 0) revert InvalidParams();
        
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
        if (chainDsrcs[chainHash][dsrcIdHash] != address(0)) revert DSRCExists();

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

    /**
     * @dev Internal function to prepare the deployment configuration for a new DSRC.
     * @param dsrcId The ID of the DSRC.
     * @param params The DSRC parameters.
     * @param licensingPrice The price of the licensing edition.
     * @param creator The address of the creator.
     * @return A `DeploymentConfig` struct containing the validated and prepared deployment parameters.
     */
    function _prepareDeploymentConfig(
        string memory dsrcId,
        DSRCSignatureUtils.DSRCParams calldata params,
        uint256 licensingPrice,
        address creator
    ) private pure returns (DeploymentConfig memory) {
        if (params.percentages.length == 0 || 
            params.recipients.length != params.percentages.length) 
            revert InvalidParams();

        uint16[] memory percentages = new uint16[](params.percentages.length);
        for (uint256 i = 0; i < params.percentages.length; i++) {
            if (params.percentages[i] > type(uint16).max) revert InvalidParams();
            percentages[i] = uint16(params.percentages[i]);
        }

        EditionData memory editionData = _createEditionData(params.price, licensingPrice);

        return DeploymentConfig({
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

    /**
     * @dev Internal function to create edition data for DSRC deployment.
     * @param collectorsPrice The price for the collector's edition.
     * @param licensingPrice The price for the licensing edition.
     * @return editionData A struct containing edition details.
     */
    function _createEditionData(
        uint256 collectorsPrice,
        uint256 licensingPrice
    ) private pure returns (EditionData memory editionData) {
        if(collectorsPrice == 0 && licensingPrice == 0) revert InvalidEditionConfig();

        HitmakrDSRC.Edition[] memory editions = new HitmakrDSRC.Edition[](3);
        uint256[] memory prices = new uint256[](3);
        bool[] memory states = new bool[](3);

        editions[0] = HitmakrDSRC.Edition.Streaming;
        editions[1] = HitmakrDSRC.Edition.Collectors;
        editions[2] = HitmakrDSRC.Edition.Licensing;

        prices[0] = 0; // Streaming must be free
        prices[1] = collectorsPrice;
        prices[2] = licensingPrice;

        states[0] = true; // Streaming must be enabled
        states[1] = collectorsPrice > 0;
        states[2] = licensingPrice > 0;

        if (!_validateEditionConfig(prices, states)) revert InvalidEditionConfig();

        editionData.editions = editions;
        editionData.prices = prices;
        editionData.states = states;
    }

    /**
     * @dev Internal function to validate the edition configuration.
     * @param prices An array of prices for each edition.
     * @param states An array of booleans indicating whether each edition is enabled.
     * @return True if the configuration is valid, false otherwise.
     */
    function _validateEditionConfig(
        uint256[] memory prices,
        bool[] memory states
    ) private pure returns (bool) {
        return (
            prices[0] == 0 && // Streaming must be free
            states[0] == true && // Streaming must be enabled
            (prices[1] > 0 || prices[2] > 0) // At least one paid edition
        );
    }


    /**
     * @dev Internal function to deploy a new DSRC contract and register it.
     * @param config The deployment configuration.
     * @param dsrcIdHash The hash of the DSRC ID.
     * @param chainHash The hash of the chain ID.
     * @return The address of the newly deployed DSRC contract.
     */
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

        for(uint256 i = 0; i < config.editions.length; i++) {
            emit EditionConfigured(
                config.dsrcId,
                config.editions[i],
                config.prices[i],
                config.states[i]
            );
        }

        return dsrcAddress;
    }

    /**
     * @notice Generates a unique DSRC ID for a creator.
     * @param creator The address of the creator.
     * @return The generated DSRC ID.
     * @dev The DSRC ID is generated based on the creator's Creative ID, the last two digits of the current year, and a sequential count.
     */
    function generateDSRCId(address creator) internal returns (string memory) {
        (string memory userCreativeId, , bool exists) = creativeID.getCreativeID(creator);
        if (!exists) revert NoCreativeID();
        
        uint64 yearLastTwo;
        unchecked {
            yearLastTwo = uint64((block.timestamp / YEAR_IN_SECONDS + 1970) % 100);
        }

        uint32 newCount;
        unchecked {
            newCount = yearCounts[creator][yearLastTwo] + 1;
        }
        if (newCount > MAX_COUNT_PER_YEAR) revert CountExceeded();
        
        yearCounts[creator][yearLastTwo] = newCount;

        return string(abi.encodePacked(
            userCreativeId,
            _formatNumber(yearLastTwo, 2),
            _formatNumber(newCount, 5)
        ));
    }

    /**
     * @dev Internal function to format a number with leading zeros.
     * @param number The number to format.
     * @param digits The number of digits to format to.
     * @return The formatted number as a string.
     */
    function _formatNumber(uint256 number, uint256 digits) internal pure returns (string memory) {
        bytes memory numbers = "0123456789";
        bytes memory buffer = new bytes(digits);
        
        unchecked {
            for(uint i = digits - 1; ; i--) {
                buffer[i] = numbers[number % 10];
                number /= 10;
                if (i == 0) break;
            }
        }
        
        return string(buffer);
    }
}