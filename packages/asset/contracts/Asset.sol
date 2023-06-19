//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {AccessControlUpgradeable, ContextUpgradeable, IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC1155BurnableUpgradeable, ERC1155Upgradeable, IERC1155Upgradeable, IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {ERC1155URIStorageUpgradeable, IERC1155MetadataURIUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {OperatorFiltererUpgradeable} from "./OperatorFilter/OperatorFiltererUpgradeable.sol";
import {ERC2771Handler} from "./ERC2771Handler.sol";
import {TokenIdUtils} from "./libraries/TokenIdUtils.sol";
import {IAsset} from "./interfaces/IAsset.sol";
import {ICatalyst} from "./interfaces/ICatalyst.sol";

contract Asset is
    IAsset,
    Initializable,
    ERC2771Handler,
    ERC1155BurnableUpgradeable,
    AccessControlUpgradeable,
    ERC1155SupplyUpgradeable,
    ERC1155URIStorageUpgradeable,
    OperatorFiltererUpgradeable
{
    using TokenIdUtils for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BRIDGE_MINTER_ROLE =
        keccak256("BRIDGE_MINTER_ROLE");

    // a ratio for the amount of copies to burn to retrieve single catalyst for each tier
    mapping(uint256 => uint256) public recyclingAmounts;
    // mapping of creator address to creator nonce, a nonce is incremented every time a creator mints a new token
    mapping(address => uint16) public creatorNonces;
    // mapping of old bridged tokenId to creator nonce
    mapping(uint256 => uint16) public bridgedTokensNonces;
    // mapping of ipfs metadata token hash to token ids
    mapping(string => uint256) public hashUsed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address forwarder,
        uint256[] calldata catalystTiers,
        uint256[] calldata catalystRecycleCopiesNeeded,
        string memory baseUri,
        address commonSubscription
    ) external initializer {
        _setBaseURI(baseUri);
        __AccessControl_init();
        __ERC1155Supply_init();
        __ERC2771Handler_initialize(forwarder);
        __ERC1155Burnable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        __OperatorFilterer_init(commonSubscription, true);

        for (uint256 i = 0; i < catalystTiers.length; i++) {
            recyclingAmounts[catalystTiers[i]] = catalystRecycleCopiesNeeded[i];
        }
    }

    /// @notice Mint new tokens
    /// @dev Only callable by the minter role
    /// @param to The address of the recipient
    /// @param id The id of the token to mint
    /// @param amount The amount of the token to mint
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        string memory metadataHash
    ) external onlyRole(MINTER_ROLE) {
        _setMetadataHash(id, metadataHash);
        _mint(to, id, amount, "");
    }

    /// @notice Mint new tokens with catalyst tier chosen by the creator
    /// @dev Only callable by the minter role
    /// @param to The address of the recipient
    /// @param ids The ids of the tokens to mint
    /// @param amounts The amounts of the tokens to mint
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        string[] memory metadataHashes
    ) external onlyRole(MINTER_ROLE) {
        require(
            ids.length == metadataHashes.length,
            "ids and metadataHash length mismatch"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            _setMetadataHash(ids[i], metadataHashes[i]);
        }
        _mintBatch(to, ids, amounts, "");
    }

    /// @notice Mint TSB special tokens
    /// @dev Only callable by the minter role
    /// @dev Those tokens are minted by TSB admins and do not adhere to the normal minting rules
    /// @param recipient The address of the recipient
    /// @param assetData The data of the asset to mint
    /// @param metadataHash The ipfs hash for asset's metadata
    function mintSpecial(
        address recipient,
        AssetData calldata assetData,
        string memory metadataHash
    ) external onlyRole(MINTER_ROLE) {
        // increment nonce
        unchecked {
            creatorNonces[assetData.creator]++;
        }
        // get current creator nonce
        uint16 creatorNonce = creatorNonces[assetData.creator];

        // minting a tsb exclusive token which are already revealed, have their supply increased and are not recyclable
        uint256 id = TokenIdUtils.generateTokenId(
            assetData.creator,
            assetData.tier,
            creatorNonce,
            1
        );
        _mint(recipient, id, assetData.amount, "");
        require(hashUsed[metadataHash] == 0, "metadata hash already used");
        hashUsed[metadataHash] = id;
        _setURI(id, metadataHash);
    }

    /// @notice Special mint function for the bridge contract to mint assets originally created on L1
    /// @dev Only the special minter role can call this function
    /// @dev This function skips the catalyst burn step
    /// @dev Bridge should be able to mint more copies of the same asset
    /// @param originalTokenId The original token id of the asset
    /// @param amount The amount of assets to mint
    /// @param tier The tier of the catalysts to burn
    /// @param recipient The recipient of the asset
    /// @param metadataHash The ipfs hash of asset's metadata
    function bridgeMint(
        uint256 originalTokenId,
        uint256 amount,
        uint8 tier,
        address recipient,
        string memory metadataHash
    ) external onlyRole(BRIDGE_MINTER_ROLE) {
        // extract creator address from the last 160 bits of the original token id
        address originalCreator = address(uint160(originalTokenId));
        // extract isNFT from 1 bit after the creator address
        bool isNFT = (originalTokenId >> 95) & 1 == 1;
        require(amount > 0, "Amount must be > 0");
        if (isNFT) {
            require(amount == 1, "Amount must be 1 for NFTs");
        }
        // check if this asset has been bridged before to make sure that we increase the copies count for the same assers rather than minting a new one
        // we also do this to avoid a clash between bridged asset nonces and non-bridged asset nonces
        if (bridgedTokensNonces[originalTokenId] == 0) {
            // increment nonce
            unchecked {
                creatorNonces[originalCreator]++;
            }
            // get current creator nonce
            uint16 nonce = creatorNonces[originalCreator];

            // store the nonce
            bridgedTokensNonces[originalTokenId] = nonce;
        }

        uint256 id = TokenIdUtils.generateTokenId(
            originalCreator,
            tier,
            bridgedTokensNonces[originalTokenId],
            1
        );
        _mint(recipient, id, amount, "");
        if (hashUsed[metadataHash] != 0) {
            require(
                hashUsed[metadataHash] == id,
                "metadata hash mismatch for tokenId"
            );
        } else {
            hashUsed[metadataHash] = id;
        }
        _setURI(id, metadataHash);
    }

    /// @notice Extract the catalyst by burning assets of the same tier
    /// @param tokenIds the tokenIds of the assets to extract, must be of same tier
    /// @param amounts the amount of each asset to extract catalyst from
    /// @param catalystTier the catalyst tier to extract
    /// @return amountOfCatalystExtracted the amount of catalyst extracted
    function recycleBurn(
        address recycler,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint256 catalystTier
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 amountOfCatalystExtracted)
    {
        uint256 totalAmount = 0;
        // how many assets of a given tier are needed to recycle a catalyst
        uint256 recyclingAmount = recyclingAmounts[catalystTier];
        require(
            recyclingAmount > 0,
            "Catalyst tier is not eligible for recycling"
        );
        // make sure the tokens that user is trying to extract are of correct tier and user has enough tokens
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 extractedTier = (tokenIds[i]).getTier();
            require(
                extractedTier == catalystTier,
                "Catalyst id does not match"
            );
            totalAmount += amounts[i];
        }

        // total amount should be a modulo of recyclingAmounts[catalystTier] to make sure user is recycling the correct amount of tokens
        require(
            totalAmount % recyclingAmounts[catalystTier] == 0,
            "Incorrect amount of tokens to recycle"
        );
        // burn batch of tokens
        _burnBatch(recycler, tokenIds, amounts);

        // calculate how many catalysts to mint
        uint256 catalystsExtractedCount = totalAmount /
            recyclingAmounts[catalystTier];

        emit AssetsRecycled(
            recycler,
            tokenIds,
            amounts,
            catalystTier,
            catalystsExtractedCount
        );

        return catalystsExtractedCount;
    }

    /// @notice Burn a token from a given account
    /// @dev Only the minter role can burn tokens
    /// @dev This function was added with token recycling and bridging in mind but may have other use cases
    /// @param account The account to burn tokens from
    /// @param id The token id to burn
    /// @param amount The amount of tokens to burn
    function burnFrom(
        address account,
        uint256 id,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        _burn(account, id, amount);
    }

    /// @notice Burn a batch of tokens from a given account
    /// @dev Only the minter role can burn tokens
    /// @dev This function was added with token recycling and bridging in mind but may have other use cases
    /// @dev The length of the ids and amounts arrays must be the same
    /// @param account The account to burn tokens from
    /// @param ids An array of token ids to burn
    /// @param amounts An array of amounts of tokens to burn
    function burnBatchFrom(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external onlyRole(MINTER_ROLE) {
        _burnBatch(account, ids, amounts);
    }

    /// @notice Set the amount of tokens that can be recycled for a given one catalyst of a given tier
    /// @dev Only the admin role can set the recycling amount
    /// @param catalystTokenId The catalyst token id
    /// @param amount The amount of tokens needed to receive one catalyst
    function setRecyclingAmount(
        uint256 catalystTokenId,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // catalyst 0 is restricted for tsb exclusive tokens
        require(catalystTokenId > 0, "Catalyst token id cannot be 0");
        recyclingAmounts[catalystTokenId] = amount;
    }

    /// @notice Set a new URI for specific tokenid
    /// @param tokenId The token id to set URI for
    /// @param metadata The new uri for asset's metadata
    function setTokenUri(
        uint256 tokenId,
        string memory metadata
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(tokenId, metadata);
    }

    /// @notice Set a new base URI
    /// @param baseURI The new base URI
    function setBaseURI(
        string memory baseURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBaseURI(baseURI);
    }

    /// @notice returns full token URI, including baseURI and token metadata URI
    /// @param tokenId The token id to get URI for
    /// @return tokenURI the URI of the token
    function uri(
        uint256 tokenId
    )
        public
        view
        override(ERC1155Upgradeable, ERC1155URIStorageUpgradeable)
        returns (string memory)
    {
        return ERC1155URIStorageUpgradeable.uri(tokenId);
    }

    function getTokenIdByMetadataHash(
        string memory metadataHash
    ) public view returns (uint256) {
        return hashUsed[metadataHash];
    }

    function _setMetadataHash(
        uint256 tokenId,
        string memory metadataHash
    ) internal onlyRole(MINTER_ROLE) {
        if (hashUsed[metadataHash] != 0) {
            require(
                hashUsed[metadataHash] == tokenId,
                "metadata hash mismatch for tokenId"
            );
        } else {
            hashUsed[metadataHash] = tokenId;
            _setURI(tokenId, metadataHash);
        }
    }

    function getIncrementedCreatorNonce(
        address creator
    ) public onlyRole(MINTER_ROLE) returns (uint16) {
        unchecked {
            creatorNonces[creator]++;
        }
        return creatorNonces[creator];
    }

    /// @notice Query if a contract implements interface `id`.
    /// @param id the interface identifier, as specified in ERC-165.
    /// @return `true` if the contract implements `id`.
    function supportsInterface(
        bytes4 id
    )
        public
        view
        virtual
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            id == type(IERC165Upgradeable).interfaceId ||
            id == type(IERC1155Upgradeable).interfaceId ||
            id == type(IERC1155MetadataURIUpgradeable).interfaceId ||
            id == type(IAccessControlUpgradeable).interfaceId ||
            id == 0x572b6c05; // ERC2771
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771Handler)
        returns (address sender)
    {
        return ERC2771Handler._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771Handler)
        returns (bytes calldata)
    {
        return ERC2771Handler._msgData();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function getRecyclingAmount(
        uint256 catalystTokenId
    ) public view returns (uint256) {
        return recyclingAmounts[catalystTokenId];
    }

    /// @notice batch transfers assets
    /// @param from address of the owner of assets
    /// @param to address of the new owner of assets
    /// @param ids of assets to be transfered
    /// @param amounts of assets to be transfered
    /// @param data for trasfer
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /// @notice set approval for asset transfer
    /// @param operator operator to be approved
    /// @param approved bool value for giving and canceling approval
    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override onlyAllowedOperatorApproval(operator) {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /// @notice transfers asset
    /// @param from address of the owner of asset
    /// @param to address of the new owner of asset
    /// @param id of asset to be transfered
    /// @param amount of asset to be transfered
    /// @param data for trasfer
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override onlyAllowedOperator(from) {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        _safeTransferFrom(from, to, id, amount, data);
    }
}
