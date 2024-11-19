// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/accesscontrol/IHitmakrControlCenter.sol";
import "../interfaces/core/IHitmakrCreativeID.sol";
import "./HitmakrDSRC.sol";
import "../utils/DSRCSignatureUtils.sol";

/**
 * @title HitmakrDSRCFactory
 * @author Hitmakr Protocol
 * @notice Factory contract for creating and managing Decentralized Standard Recording Code (DSRC) contracts
 * @dev Handles the creation, tracking, and validation of DSRC contracts with signature-based deployment
 */
contract HitmakrDSRCFactory {
    using DSRCSignatureUtils for DSRCSignatureUtils.DSRCParams;

    /**
     * @dev Custom errors for better gas efficiency and clearer error handling
     */
    error Unauthorized();      // Caller doesn't have required permissions
    error DSRCExists();        // DSRC with given ID already exists
    error InvalidParams();     // Invalid parameters provided
    error CountExceeded();     // Exceeded maximum DSRCs per year
    error NoCreativeID();      // Creator doesn't have a Creative ID
    error InvalidYear();       // Invalid year parameter
    error ZeroAddress();       // Zero address provided for critical parameter

    /**
     * @dev Events emitted by the contract
     */
    event DSRCCreated(string dsrcId, address dsrcAddress, address creator, string selectedChain);
    event YearInitialized(address indexed creator, uint16 indexed year);

    /**
     * @dev Constants used throughout the contract
     */
    uint32 private constant MAX_COUNT_PER_YEAR = 99999;     // Maximum DSRCs per creator per year
    string private constant CONTRACT_NAME = "HitmakrDSRCFactory";
    string private constant CONTRACT_VERSION = "1.0.0";
    uint256 private constant YEAR_IN_SECONDS = 31536000;    // Number of seconds in a year

    /**
     * @dev Immutable state variables
     */
    address private immutable USDC;                         // USDC token contract address
    IHitmakrControlCenter public immutable controlCenter;   // Control center contract
    IHitmakrCreativeID public immutable creativeID;        // Creative ID contract
    address public immutable purchaseIndexer;               // Purchase indexer contract address

    /**
     * @dev Storage mappings for tracking DSRCs and related data
     */
    mapping(bytes32 => address) public dsrcs;              // DSRC ID hash to contract address
    mapping(address => uint256) private _nonces;           // Creator address to nonce
    mapping(address => mapping(uint16 => uint32)) private _yearCounts;  // Creator yearly DSRC counts
    mapping(bytes32 => mapping(bytes32 => address)) public chainDsrcs;  // Chain-specific DSRC tracking
    mapping(address => bool) public isValidDSRC;           // Valid DSRC contract addresses

    /**
     * @dev Struct for organizing deployment parameters
     */
    struct DeploymentParams {
        string dsrcId;         // Unique identifier for the DSRC
        bytes32 dsrcIdHash;    // Hash of the DSRC ID
        bytes32 chainHash;     // Hash of the selected chain
        address creator;       // Address of the DSRC creator
        uint16[] percentages;  // Revenue split percentages
    }

    /**
     * @notice Contract constructor
     * @param _controlCenter Address of the control center contract
     * @param _creativeID Address of the creative ID contract
     * @param _usdc Address of the USDC token contract
     * @param _indexer Address of the purchase indexer contract
     */
    constructor(
        address _controlCenter,
        address _creativeID,
        address _usdc,
        address _indexer
    ) {
        if (_controlCenter == address(0) || _creativeID == address(0) || 
            _usdc == address(0) || _indexer == address(0)) 
            revert InvalidParams();
            
        controlCenter = IHitmakrControlCenter(_controlCenter);
        creativeID = IHitmakrCreativeID(_creativeID);
        USDC = _usdc;
        purchaseIndexer = _indexer;
    }

    /**
     * @notice Creates a new DSRC contract
     * @dev Only authorized verifiers can call this function
     * @param params DSRC creation parameters
     * @param signature Creator's signature authorizing the deployment
     */
    function createDSRC(
        DSRCSignatureUtils.DSRCParams calldata params,
        bytes calldata signature
    ) external {
        if (!controlCenter.isVerifier(msg.sender)) revert Unauthorized();
        
        DeploymentParams memory deployParams = _prepareDeployment(params, signature);
        _deployAndRegister(deployParams, params);
    }

    /**
     * @dev Prepares deployment parameters and validates the request
     * @param params DSRC creation parameters
     * @param signature Creator's signature
     * @return deployParams Structured deployment parameters
     */
    function _prepareDeployment(
        DSRCSignatureUtils.DSRCParams calldata params,
        bytes calldata signature
    ) internal returns (DeploymentParams memory deployParams) {
        address creator = DSRCSignatureUtils.verify(
            params,
            signature,
            CONTRACT_NAME,
            CONTRACT_VERSION,
            address(this)
        );
        if (params.nonce != _nonces[creator]) revert InvalidParams();

        string memory dsrcId = generateDSRCId(creator);
        bytes32 dsrcIdHash = keccak256(bytes(dsrcId));
        bytes32 chainHash = keccak256(bytes(params.selectedChain));

        if (dsrcs[dsrcIdHash] != address(0)) revert DSRCExists();
        if (chainDsrcs[chainHash][dsrcIdHash] != address(0)) revert DSRCExists();
        if (bytes(params.selectedChain).length == 0) revert InvalidParams();

        uint16[] memory percentages = _convertPercentages(params.percentages);

        return DeploymentParams({
            dsrcId: dsrcId,
            dsrcIdHash: dsrcIdHash,
            chainHash: chainHash,
            creator: creator,
            percentages: percentages
        });
    }

    /**
     * @dev Converts uint256 percentages to uint16
     * @param originalPercentages Array of original percentages
     * @return Array of converted uint16 percentages
     */
    function _convertPercentages(uint256[] memory originalPercentages) 
        internal 
        pure 
        returns (uint16[] memory) 
    {
        uint16[] memory percentages = new uint16[](originalPercentages.length);
        for (uint256 i = 0; i < originalPercentages.length; i++) {
            if (originalPercentages[i] > type(uint16).max) revert InvalidParams();
            percentages[i] = uint16(originalPercentages[i]);
        }
        return percentages;
    }

    /**
     * @dev Deploys and registers a new DSRC contract
     * @param deployParams Structured deployment parameters
     * @param params Original DSRC creation parameters
     */
    function _deployAndRegister(
        DeploymentParams memory deployParams,
        DSRCSignatureUtils.DSRCParams calldata params
    ) internal {
        HitmakrDSRC newDSRC = new HitmakrDSRC(
            deployParams.dsrcId,
            params.tokenURI,
            deployParams.creator,
            USDC,
            params.price,
            params.recipients,
            deployParams.percentages,
            params.selectedChain,
            purchaseIndexer
        );

        address dsrcAddress = address(newDSRC);
        dsrcs[deployParams.dsrcIdHash] = dsrcAddress;
        chainDsrcs[deployParams.chainHash][deployParams.dsrcIdHash] = dsrcAddress;
        isValidDSRC[dsrcAddress] = true;
        
        unchecked {
            ++_nonces[deployParams.creator];
        }

        emit DSRCCreated(
            deployParams.dsrcId, 
            dsrcAddress, 
            deployParams.creator, 
            params.selectedChain
        );
    }

    /**
     * @notice Generates a unique DSRC ID for a creator
     * @dev Format: creativeID + yearLastTwo + count(padded to 5 digits)
     * @param creator Address of the DSRC creator
     * @return Unique DSRC identifier string
     */
    function generateDSRCId(address creator) internal returns (string memory) {
        (string memory userCreativeId, , bool exists) = creativeID.getCreativeID(creator);
        if (!exists) revert NoCreativeID();
        
        uint16 yearLastTwo;
        unchecked {
            yearLastTwo = uint16((block.timestamp / YEAR_IN_SECONDS + 1970) % 100);
        }

        uint32 newCount;
        unchecked {
            newCount = _yearCounts[creator][yearLastTwo] + 1;
        }
        if (newCount > MAX_COUNT_PER_YEAR) revert CountExceeded();
        
        _yearCounts[creator][yearLastTwo] = newCount;

        return string(abi.encodePacked(
            userCreativeId,
            _formatNumber(yearLastTwo, 2),
            _formatNumber(newCount, 5)
        ));
    }

    /**
     * @dev Formats a number with leading zeros
     * @param number Number to format
     * @param digits Number of digits to pad to
     * @return Formatted string
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

    /**
     * @notice Gets DSRC address by chain and DSRC ID
     * @param chain Chain identifier
     * @param dsrcId DSRC identifier
     * @return DSRC contract address
     */
    function getDSRCByChain(string calldata chain, string calldata dsrcId) 
        external 
        view 
        returns (address) 
    {
        return chainDsrcs[keccak256(bytes(chain))][keccak256(bytes(dsrcId))];
    }

    /**
     * @notice Gets the current nonce for a creator
     * @param creator Creator address
     * @return Current nonce
     */
    function getNonce(address creator) external view returns (uint256) {
        return _nonces[creator];
    }

    /**
     * @notice Gets the current year count for a creator
     * @param creator Creator address
     * @return year Current year (last two digits)
     * @return count Number of DSRCs created this year
     */
    function getCurrentYearCount(address creator) 
        external 
        view 
        returns (uint16 year, uint32 count) 
    {
        unchecked {
            year = uint16((block.timestamp / YEAR_IN_SECONDS + 1970) % 100);
        }
        count = _yearCounts[creator][year];
    }

    /**
     * @notice Gets the DSRC count for a specific year
     * @param creator Creator address
     * @param year Year to query (last two digits)
     * @return Number of DSRCs created in that year
     */
    function getYearCount(address creator, uint16 year) external view returns (uint32) {
        return _yearCounts[creator][year];
    }
}