// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "./IHitmakrDSRCFactory.sol";

/**
 * @title IHitmakrDSRC
 * @author Hitmakr Protocol
 * @notice Interface for the Digital Scarcity Rights Contract (DSRC)
 */
interface IHitmakrDSRC is IERC2981 {
    /**
     * @notice Enumeration representing the different edition types for the DSRC.
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

    /**
     * @notice Returns the unique identifier for the DSRC.
     * @return The DSRC ID
     */
    function dsrcId() external view returns (string memory);

    /**
     * @notice Returns the address of the DSRC creator.
     * @return The creator's address
     */
    function creator() external view returns (address);

    /**
     * @notice Returns the URI for the DSRC metadata.
     * @return The token URI
     */
    function tokenURI_() external view returns (string memory);

    /**
     * @notice Returns the currently selected chain.
     * @return The selected chain identifier
     */
    function selectedChain() external view returns (string memory);

    /**
     * @notice Returns the earnings information for the DSRC.
     * @return The earnings struct
     */
    function earnings() external view returns (Earnings memory);

    /**
     * @notice Returns the total supply of minted tokens for this DSRC.
     * @return The total supply
     */
    function totalSupply_() external view returns (uint256);
} 