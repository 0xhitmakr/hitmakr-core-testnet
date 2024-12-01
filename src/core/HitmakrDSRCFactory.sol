// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/accesscontrol/IHitmakrControlCenter.sol";
import "../interfaces/core/IHitmakrCreativeID.sol";
import "./HitmakrDSRC.sol";
import "../utils/DSRCSignatureUtils.sol";

/**
 * @title HitmakrDSRCFactory
 * @author Hitmakr Protocol
 * @notice This contract is a factory for creating HitmakrDSRC contracts.
 * @dev This factory manages the creation and registration of new DSRCs (Decentralized Standard Recording Codes). It uses ECDSA for signature verification, AccessControl for authorization, and enforces uniqueness of DSRC IDs.  It also tracks DSRC creation counts per creator per year.
 */
contract HitmakrDSRCFactory is AccessControl {
    using DSRCSignatureUtils for DSRCSignatureUtils.DSRCParams;

    /// @notice Error when the caller is not authorized
    error Unauthorized();
    /// @notice Error when attempting to create a DSRC with an ID that already exists
    error DSRCExists();
    /// @notice Error when invalid parameters are provided
    error InvalidParams();
    /// @notice Error when the maximum DSRC count per year is exceeded for a creator
    error CountExceeded();
    /// @notice Error when attempting to create a DSRC for a creator without a Creative ID
    error NoCreativeID();
    /// @notice Error when an invalid year value is used
    error InvalidYear();
    /// @notice Error when a zero address is passed as parameter
    error ZeroAddress();


    /// @notice Event emitted when a new DSRC is created
    event DSRCCreated(string dsrcId, address dsrcAddress, address creator, string selectedChain);
    /// @notice Event emitted when a new year is initialized for a creator's DSRC count
    event YearInitialized(address indexed creator, uint64 indexed year);

    /// @notice Role for factory administrators
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");
    /// @notice Maximum number of DSRCs a creator can mint per year
    uint32 private constant MAX_COUNT_PER_YEAR = 99999;
    /// @notice Name of the contract
    string private constant CONTRACT_NAME = "HitmakrDSRCFactory";
    /// @notice Version of the contract
    string private constant CONTRACT_VERSION = "1.0.0";
    /// @notice Number of seconds in a year (used for calculating year-based counts)
    uint256 private constant YEAR_IN_SECONDS = 31536000;

    /// @notice Address of the USDC ERC20 token used for DSRC purchases
    address private immutable USDC;
    /// @notice The HitmakrControlCenter contract for access control
    IHitmakrControlCenter public immutable controlCenter;
    /// @notice The HitmakrCreativeID contract for managing Creative IDs
    IHitmakrCreativeID public immutable creativeID;
    /// @notice The address of the purchase indexer contract
    address public immutable purchaseIndexer;

    /// @notice Mapping from DSRC ID hash to DSRC contract address
    mapping(bytes32 => address) public dsrcs;
    /// @notice Mapping from creator address to their current nonce (used for signature verification)
    mapping(address => uint256) public nonces;                   
    /// @notice Mapping from creator address to year to DSRC count for that year
    mapping(address => mapping(uint64 => uint32)) public yearCounts;
    /// @notice Mapping from chain ID hash to DSRC ID hash to DSRC contract address
    mapping(bytes32 => mapping(bytes32 => address)) public chainDsrcs;
    /// @notice Mapping to indicate validity of DSRCs by their address.
    mapping(address => bool) public isValidDSRC;


    /**
     * @notice Structure for parameters used in DSRC deployment.
     * @param dsrcId The generated DSRC ID.
     * @param dsrcIdHash The keccak256 hash of the DSRC ID.
     * @param chainHash The keccak256 hash of the selected chain.
     * @param creator The address of the DSRC creator.
     * @param percentages The array of royalty percentages for the DSRC.
     */
    struct DeploymentParams {
        string dsrcId;
        bytes32 dsrcIdHash;
        bytes32 chainHash;
        address creator;
        uint16[] percentages;
    }

    /**
     * @notice Constructor initializes the factory with necessary contract addresses.
     * @param _controlCenter The address of the HitmakrControlCenter contract.
     * @param _creativeID The address of the HitmakrCreativeID contract.
     * @param _usdc The address of the USDC ERC20 token.
     * @param _indexer The address of the DSRCPurchaseIndexer contract.
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

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Creates a new HitmakrDSRC contract.
     * @param params Struct containing the parameters for DSRC creation.  See `DSRCSignatureUtils.DSRCParams`.
     * @param signature The signature of the creator, verifying the parameters.
     * @dev Only callable by factory admins or verifiers from the `controlCenter`.
     *      Reverts if parameters are invalid, the DSRC already exists, or other checks fail. 
     *      Emits a `DSRCCreated` event upon successful deployment.
     */
    function createDSRC(
        DSRCSignatureUtils.DSRCParams calldata params,
        bytes calldata signature
    ) external {
        if (!hasRole(FACTORY_ADMIN_ROLE, msg.sender) && 
            !IAccessControl(address(controlCenter)).hasRole(controlCenter.VERIFIER_ROLE(), msg.sender)) 
            revert Unauthorized();
        
        DeploymentParams memory deployParams = _prepareDeployment(params, signature);
        _deployAndRegister(deployParams, params);
    }

    /**
     * @dev Internal function to prepare deployment parameters and validate inputs.
     * @param params The DSRC creation parameters.
     * @param signature The creator's signature.
     * @return deployParams A struct containing the validated and prepared deployment parameters.
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
        if (params.nonce != nonces[creator]) revert InvalidParams();

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
     * @dev Converts an array of uint256 percentages to uint16 percentages.
     * @param originalPercentages The original array of uint256 percentages.
     * @return An array of uint16 percentages.
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
     * @dev Internal function to deploy a new HitmakrDSRC contract and register it.
     * @param deployParams The prepared deployment parameters.
     * @param params The original DSRC creation parameters.
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
            ++nonces[deployParams.creator];
        }

        emit DSRCCreated(
            deployParams.dsrcId, 
            dsrcAddress, 
            deployParams.creator, 
            params.selectedChain
        );
    }

    /**
     * @notice Generates a unique DSRC ID for the creator.
     * @param creator The address of the DSRC creator.
     * @return The generated DSRC ID string.
     * @dev Uses the creator's Creative ID, the last two digits of the current year, and a sequential count.
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
     * @dev Internal helper function to format a number with leading zeros.
     * @param number The number to format.
     * @param digits The desired number of digits in the output string.
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