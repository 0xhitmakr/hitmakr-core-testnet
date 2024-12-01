// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../utils/DSRCSignatureUtils.sol";

/**
 * @title IHitmakrDSRCFactory
 * @author Hitmakr Protocol
 * @notice Interface for the DSRC Factory contract that manages DSRC creation and tracking
 */
interface IHitmakrDSRCFactory {
    /**
     * @dev Struct to hold deployment parameters
     */
    struct DeploymentParams {
        string dsrcId;
        bytes32 dsrcIdHash;
        bytes32 chainHash;
        address creator;
        uint16[] percentages;
    }

    /**
     * @dev Struct to track yearly DSRC creation metrics
     */
    struct YearlyMetrics {
        uint32 count;          // Current year count
        uint32 lastYearCount;  // Previous year count
        uint40 lastUpdate;     // Last update timestamp
        bool initialized;      // Whether metrics are initialized
    }

    /**
     * @dev Custom errors
     */
    error Unauthorized();
    error DSRCExists();
    error InvalidParams();
    error CountExceeded();
    error NoCreativeID();
    error InvalidYear();
    error ZeroAddress();
    error InvalidSignature();
    error SignatureExpired();

    /**
     * @dev Events
     */
    event DSRCCreated(
        string indexed dsrcId,
        address indexed dsrcAddress,
        address indexed creator,
        string selectedChain
    );
    
    event YearlyMetricsUpdated(
        address indexed creator,
        uint32 count,
        uint16 indexed year
    );

    /**
     * @notice Creates a new DSRC contract
     * @param params The parameters for DSRC creation
     * @param signature The creator's signature
     */
    function createDSRC(
        DSRCSignatureUtils.DSRCParams calldata params,
        bytes calldata signature
    ) external;

    /**
     * @notice Gets DSRC address by chain and ID
     * @param chain The blockchain name
     * @param dsrcId The DSRC identifier
     * @return The DSRC contract address
     */
    function getDSRCByChain(
        string calldata chain,
        string calldata dsrcId
    ) external view returns (address);

    /**
     * @notice Gets the current nonce for a creator
     * @param creator The creator's address
     * @return The current nonce
     */
    function getNonce(address creator) external view returns (uint256);

    /**
     * @notice Gets yearly metrics for a creator
     * @param creator The creator's address
     * @return currentCount Current year's DSRC count
     * @return lastYearCount Previous year's DSRC count
     * @return lastUpdate Last update timestamp
     * @return initialized Whether metrics are initialized
     */
    function getYearlyMetrics(
        address creator
    ) external view returns (
        uint32 currentCount,
        uint32 lastYearCount,
        uint40 lastUpdate,
        bool initialized
    );

    /**
     * @notice Gets the factory contract name
     * @return The name of the factory contract
     */
    function name() external view returns (string memory);

    /**
     * @notice Gets the factory contract version
     * @return The version of the factory contract
     */
    function version() external view returns (string memory);

    /**
     * @notice Gets the USDC token address
     * @return The address of the USDC token contract
     */
    function USDC() external view returns (address);

    /**
     * @notice Gets the control center contract
     * @return The address of the control center contract
     */
    function controlCenter() external view returns (address);

    /**
     * @notice Gets the creative ID contract
     * @return The address of the creative ID contract
     */
    function creativeID() external view returns (address);

    /**
     * @notice Gets the purchase indexer address
     * @return The address of the purchase indexer contract
     */
    function purchaseIndexer() external view returns (address);

    /**
     * @notice Check if an address is a valid DSRC contract
     * @param dsrc The address to check
     * @return True if the address is a valid DSRC contract
     */
    function isValidDSRC(address dsrc) external view returns (bool);

    /**
     * @notice Gets a DSRC contract address by its ID hash
     * @param dsrcIdHash The hash of the DSRC ID
     * @return The address of the DSRC contract
     */
    function dsrcs(bytes32 dsrcIdHash) external view returns (address);

    /**
     * @notice Gets a DSRC contract address by chain and ID hashes
     * @param chainHash The hash of the chain name
     * @param dsrcIdHash The hash of the DSRC ID
     * @return The address of the DSRC contract
     */
    function chainDsrcs(bytes32 chainHash, bytes32 dsrcIdHash) external view returns (address);
}