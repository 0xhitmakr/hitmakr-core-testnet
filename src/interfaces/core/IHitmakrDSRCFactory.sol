// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../utils/DSRCSignatureUtils.sol";

/**
 * @title IHitmakrDSRCFactory
 * @author Hitmakr Protocol
 * @notice This interface defines the functions and events for the `HitmakrDSRCFactory` contract.
 * The factory is responsible for creating and managing DSRC (Decentralized Standard Recording Code) contracts.
 * It handles the deployment of new DSRCs, tracks DSRC creation metrics, and provides functions for retrieving
 * DSRC addresses and other relevant information.  The factory uses signatures to authorize DSRC creation
 * and integrates with other Hitmakr contracts like `HitmakrControlCenter` and `HitmakrCreativeID`.
 */
interface IHitmakrDSRCFactory {
    /**
     * @notice Struct to hold the parameters required for deploying a new DSRC contract.
     * @member dsrcId The string identifier of the DSRC.
     * @member dsrcIdHash The Keccak256 hash of the `dsrcId`.
     * @member chainHash The Keccak256 hash of the blockchain name where the DSRC will be deployed.
     * @member creator The address of the user creating the DSRC.
     * @member percentages An array of uint16 values representing the percentage royalties/splits for recipients (in basis points).
     * @dev Used as input for the `createDSRC` function.
     */
    struct DeploymentParams {
        string dsrcId;
        bytes32 dsrcIdHash;
        bytes32 chainHash;
        address creator;
        uint16[] percentages;
    }

    /**
     * @notice Struct to track yearly DSRC creation metrics for each creator.
     * @member count The number of DSRCs created by a user in the current year.
     * @member lastYearCount The number of DSRCs created by a user in the previous year.
     * @member lastUpdate The timestamp of the last update to the metrics.
     * @member initialized A boolean indicating whether the metrics have been initialized for a user.
     */
    struct YearlyMetrics {
        uint32 count;
        uint32 lastYearCount;
        uint40 lastUpdate;
        bool initialized;
    }


    /*
     * Custom errors for gas-efficient error handling and specific revert reasons.
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


    /*
     * Events emitted by the factory contract. These events provide a record of DSRC creations and metric updates,
     * which are useful for off-chain monitoring and analysis.  Indexed parameters enable efficient event filtering.
     */

    /**
     * @notice Emitted when a new DSRC contract is created.
     * @param dsrcId The string identifier of the newly created DSRC.
     * @param dsrcAddress The address of the newly deployed DSRC contract.
     * @param creator The address of the user who created the DSRC.
     * @param selectedChain The name of the blockchain where the DSRC was deployed.
     */
    event DSRCCreated(
        string indexed dsrcId,
        address indexed dsrcAddress,
        address indexed creator,
        string selectedChain
    );
    

    /**
     * @notice Emitted when yearly DSRC creation metrics are updated for a creator.
     * @param creator The address of the creator whose metrics were updated.
     * @param count The updated DSRC count for the current year.
     * @param year The year for which the metrics were updated.
     */
    event YearlyMetricsUpdated(
        address indexed creator,
        uint32 count,
        uint16 indexed year
    );



    /**
     * @notice Creates a new DSRC contract. This function is called by a verifier on behalf of a user after verifying
     * the user's signature.
     * @param params The DSRC parameters, including token URI, price, recipients, percentages, nonce, deadline, and
     * selected chain. See `DSRCSignatureUtils.DSRCParams` for details.
     * @param signature The user's signature, authorizing the DSRC creation. This signature is verified using the
     * `DSRCSignatureUtils` library.
     * @dev Emits a `DSRCCreated` event upon successful DSRC creation.  Reverts if the DSRC already exists, parameters
     * are invalid, the user has exceeded their yearly DSRC creation limit, or the signature is invalid.
     */
    function createDSRC(
        DSRCSignatureUtils.DSRCParams calldata params,
        bytes calldata signature
    ) external;

    /**
     * @notice Retrieves the address of a deployed DSRC contract by its blockchain name and ID.
     * @param chain The name of the blockchain where the DSRC is deployed.
     * @param dsrcId The string identifier of the DSRC.
     * @return The address of the DSRC contract, or the zero address if no such DSRC exists.
     */
    function getDSRCByChain(
        string calldata chain,
        string calldata dsrcId
    ) external view returns (address);

    /**
     * @notice Retrieves the current nonce for a given creator address. Nonces are used to prevent replay attacks
     * in the signature verification process.
     * @param creator The address of the creator.
     * @return The current nonce for the creator.
     */
    function getNonce(address creator) external view returns (uint256);

    /**
     * @notice Retrieves the yearly DSRC creation metrics for a given creator address.
     * @param creator The address of the creator.
     * @return currentCount The current year's DSRC count for the creator.
     * @return lastYearCount The previous year's DSRC count for the creator.
     * @return lastUpdate The timestamp of the last metrics update for the creator.
     * @return initialized A boolean indicating whether the metrics have been initialized for the creator.
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
     * @notice Returns the name of the factory contract. Primarily used for EIP-712 signature verification.
     * @return The name string.
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the version of the factory contract. Used for EIP-712 signature verification.
     * @return The version string.
     */
    function version() external view returns (string memory);


    /**
     * @notice Returns the address of the USDC token contract.  This is likely used for payments related to DSRC creation.
     * @return The address of the USDC contract.
     */
    function USDC() external view returns (address);


    /**
     * @notice Returns the address of the `HitmakrControlCenter` contract.  Used for access control and authorization.
     * @return The address of the control center contract.
     */
    function controlCenter() external view returns (address);


    /**
     * @notice Returns the address of the `HitmakrCreativeID` contract. Used for managing Creative IDs associated with creators.
     * @return The address of the Creative ID contract.
     */
    function creativeID() external view returns (address);


    /**
     * @notice Returns the address of the `HitmakrDSRCPurchaseIndexer` contract. Used for tracking DSRC purchases.
     * @return The address of the purchase indexer contract.
     */
    function purchaseIndexer() external view returns (address);

    /**
     * @notice Checks if a given address is a valid DSRC contract deployed by this factory.
     * @param dsrc The address to check.
     * @return True if the address is a valid DSRC, false otherwise.
     */
    function isValidDSRC(address dsrc) external view returns (bool);


    /**
     * @notice Retrieves a DSRC contract address by its ID hash.
     * @param dsrcIdHash The Keccak256 hash of the DSRC ID.
     * @return The address of the DSRC contract, or the zero address if no DSRC with that ID hash exists.
     */
    function dsrcs(bytes32 dsrcIdHash) external view returns (address);



    /**
     * @notice Retrieves a DSRC contract address by the hash of the chain name and the hash of the DSRC ID.
     * This function is useful for cross-chain lookups.
     * @param chainHash The Keccak256 hash of the blockchain name.
     * @param dsrcIdHash The Keccak256 hash of the DSRC ID.
     * @return The address of the DSRC contract, or the zero address if no DSRC exists for the given chain and ID.
     */
    function chainDsrcs(bytes32 chainHash, bytes32 dsrcIdHash) external view returns (address);
}