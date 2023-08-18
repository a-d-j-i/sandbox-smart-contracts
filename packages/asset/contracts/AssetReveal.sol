//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {
    AccessControlUpgradeable,
    ContextUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {TokenIdUtils} from "./libraries/TokenIdUtils.sol";
import {AuthSuperValidator} from "./AuthSuperValidator.sol";
import {
    ERC2771HandlerUpgradeable
} from "@sandbox-smart-contracts/dependency-metatx/contracts/ERC2771HandlerUpgradeable.sol";
import {IAsset} from "./interfaces/IAsset.sol";
import {IAssetReveal} from "./interfaces/IAssetReveal.sol";

/// @title AssetReveal
/// @author The Sandbox
/// @notice Contract for burning and revealing assets
contract AssetReveal is
    IAssetReveal,
    Initializable,
    AccessControlUpgradeable,
    ERC2771HandlerUpgradeable,
    EIP712Upgradeable,
    PausableUpgradeable
{
    using TokenIdUtils for uint256;
    IAsset private assetContract;
    AuthSuperValidator private authValidator;

    // mapping of creator to asset id to asset's reveal nonce
    mapping(address => mapping(uint256 => uint16)) internal revealIds;

    // mapping for showing whether a revealHash has been used
    // revealHashes are generated by the TSB backend from reveal burn events and are used for reveal minting
    mapping(bytes32 => bool) internal revealHashesUsed;

    // allowance list for tier to be revealed in a single transaction
    mapping(uint8 => bool) internal tierInstantRevealAllowed;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant REVEAL_TYPEHASH =
        keccak256(
            "Reveal(address recipient,uint256 prevTokenId,uint256[] amounts,string[] metadataHashes,bytes32[] revealHashes)"
        );
    bytes32 public constant BATCH_REVEAL_TYPEHASH =
        keccak256(
            "BatchReveal(address recipient,uint256[] prevTokenIds,uint256[][] amounts,string[][] metadataHashes,bytes32[][] revealHashes)"
        );
    bytes32 public constant INSTANT_REVEAL_TYPEHASH =
        keccak256(
            "InstantReveal(address recipient,uint256 prevTokenId,uint256[] amounts,string[] metadataHashes,bytes32[] revealHashes)"
        );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param _assetContract The address of the asset contract
    /// @param _authValidator The address of the AuthSuperValidator contract
    /// @param _forwarder The address of the forwarder contract
    function initialize(
        string memory _name,
        string memory _version,
        address _assetContract,
        address _authValidator,
        address _forwarder,
        address _defaultAdmin
    ) public initializer {
        assetContract = IAsset(_assetContract);
        authValidator = AuthSuperValidator(_authValidator);
        __ERC2771Handler_init(_forwarder);
        __EIP712_init(_name, _version);
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
    }

    /// @notice Reveal an asset to view its abilities and enhancements
    /// @dev the reveal mechanism works through burning the asset and minting a new one with updated tokenId
    /// @param tokenId the tokenId of id idasset to reveal
    /// @param amount the amount of tokens to reveal
    function revealBurn(uint256 tokenId, uint256 amount) external whenNotPaused {
        _burnAsset(tokenId, amount);
        emit AssetRevealBurn(_msgSender(), tokenId, amount);
    }

    /// @notice Burn multiple assets to be able to reveal them later
    /// @dev Can be used to burn multiple copies of the same token id, each copy will be revealed separately
    /// @param tokenIds the tokenIds of the assets to burn
    /// @param amounts the amounts of the assets to burn
    function revealBatchBurn(uint256[] calldata tokenIds, uint256[] calldata amounts) external whenNotPaused {
        _burnAssetBatch(tokenIds, amounts);
        emit AssetRevealBatchBurn(_msgSender(), tokenIds, amounts);
    }

    /// @notice Reveal assets to view their abilities and enhancements
    /// @dev Can be used to reveal multiple copies of the same token id
    /// @param signature Signature created on the TSB backend containing REVEAL_TYPEHASH and associated data, must be signed by authorized signer
    /// @param prevTokenId The tokenId of the unrevealed asset
    /// @param amounts The amount of assets to reveal (length reflects the number of types of reveal tokens and must be equal to the length of revealHashes)
    /// @param metadataHashes The array of hashes for revealed asset metadata
    /// @param revealHashes A revealHash array providing a random bytes32 generated by the TSB backend for each new tokenId
    function revealMint(
        bytes memory signature,
        uint256 prevTokenId,
        uint256[] calldata amounts,
        string[] calldata metadataHashes,
        bytes32[] calldata revealHashes
    ) external whenNotPaused {
        require(amounts.length == metadataHashes.length, "AssetReveal: Invalid amounts length");
        require(amounts.length == revealHashes.length, "AssetReveal: Invalid revealHashes length");
        require(
            authValidator.verify(
                signature,
                _hashReveal(_msgSender(), prevTokenId, amounts, metadataHashes, revealHashes)
            ),
            "AssetReveal: Invalid revealMint signature"
        );
        uint256[] memory newTokenIds = _revealAsset(prevTokenId, metadataHashes, amounts, revealHashes);
        emit AssetRevealMint(_msgSender(), prevTokenId, amounts, newTokenIds, revealHashes);
    }

    /// @notice Mint multiple assets with revealed abilities and enhancements
    /// @dev Can be used to reveal multiple copies of the same token id
    /// @param signature Signatures created on the TSB backend containing REVEAL_TYPEHASH and associated data, must be signed by authorized signer
    /// @param prevTokenIds The tokenId of the unrevealed asset
    /// @param amounts The amount of assets to reveal (must be equal to the length of revealHashes)
    /// @param metadataHashes The array of hashes for asset metadata
    /// @param revealHashes Array of revealHash arrays providing random bytes32 generated by the TSB backend for each new tokenId
    function revealBatchMint(
        bytes calldata signature,
        uint256[] calldata prevTokenIds,
        uint256[][] calldata amounts,
        string[][] calldata metadataHashes,
        bytes32[][] calldata revealHashes
    ) external whenNotPaused {
        require(prevTokenIds.length == amounts.length, "AssetReveal: Invalid amounts length");
        require(amounts.length == metadataHashes.length, "AssetReveal: Invalid metadataHashes length");
        require(prevTokenIds.length == revealHashes.length, "AssetReveal: Invalid revealHashes length");
        require(
            authValidator.verify(
                signature,
                _hashBatchReveal(_msgSender(), prevTokenIds, amounts, metadataHashes, revealHashes)
            ),
            "AssetReveal: Invalid revealBatchMint signature"
        );
        uint256[][] memory newTokenIds = new uint256[][](prevTokenIds.length);
        for (uint256 i = 0; i < prevTokenIds.length; i++) {
            newTokenIds[i] = _revealAsset(prevTokenIds[i], metadataHashes[i], amounts[i], revealHashes[i]);
        }
        emit AssetRevealBatchMint(_msgSender(), prevTokenIds, amounts, newTokenIds, revealHashes);
    }

    /// @notice Reveal assets to view their abilities and enhancements and mint them in a single transaction
    /// @dev Should be used where it is not required to keep the metadata secret, e.g. mythical assets where users select their desired abilities and enhancements
    /// @param signature Signature created on the TSB backend containing INSTANT_REVEAL_TYPEHASH and associated data, must be signed by authorized signer
    /// @param prevTokenId The tokenId of the unrevealed asset
    /// @param burnAmount The amount of assets to burn
    /// @param amounts The amount of assets to reveal (sum must be equal to the burnAmount)
    /// @param metadataHashes The array of hashes for asset metadata
    /// @param revealHashes A revealHash array providing a random bytes32 generated by the TSB backend for each new tokenId
    function burnAndReveal(
        bytes memory signature,
        uint256 prevTokenId,
        uint256 burnAmount,
        uint256[] calldata amounts,
        string[] calldata metadataHashes,
        bytes32[] calldata revealHashes
    ) external whenNotPaused {
        require(amounts.length == metadataHashes.length, "AssetReveal: Invalid amounts length");
        require(amounts.length == revealHashes.length, "AssetReveal: Invalid revealHashes length");
        uint8 tier = prevTokenId.getTier();
        require(tierInstantRevealAllowed[tier], "AssetReveal: Tier not allowed for instant reveal");
        require(
            authValidator.verify(
                signature,
                _hashInstantReveal(_msgSender(), prevTokenId, amounts, metadataHashes, revealHashes)
            ),
            "AssetReveal: Invalid burnAndReveal signature"
        );
        _burnAsset(prevTokenId, burnAmount);
        uint256[] memory newTokenIds = _revealAsset(prevTokenId, metadataHashes, amounts, revealHashes);
        emit AssetRevealMint(_msgSender(), prevTokenId, amounts, newTokenIds, revealHashes);
    }

    /// @notice Generate new tokenIds for revealed assets and mint them
    /// @param prevTokenId The tokenId of the unrevealed asset
    /// @param metadataHashes The array of hashes for asset metadata
    /// @param amounts The array of amounts to mint
    function _revealAsset(
        uint256 prevTokenId,
        string[] calldata metadataHashes,
        uint256[] calldata amounts,
        bytes32[] calldata revealHashes
    ) internal returns (uint256[] memory) {
        uint256[] memory newTokenIds = getRevealedTokenIds(metadataHashes, prevTokenId);
        for (uint256 i = 0; i < revealHashes.length; i++) {
            require(revealHashesUsed[revealHashes[i]] == false, "AssetReveal: RevealHash already used");
            revealHashesUsed[revealHashes[i]] = true;
        }
        if (newTokenIds.length == 1) {
            assetContract.mint(_msgSender(), newTokenIds[0], amounts[0], metadataHashes[0]);
        } else {
            assetContract.mintBatch(_msgSender(), newTokenIds, amounts, metadataHashes);
        }
        return newTokenIds;
    }

    /// @notice Burns an asset to be able to reveal it later
    /// @param tokenId the tokenId of the asset to burn
    /// @param amount the amount of the asset to burn
    function _burnAsset(uint256 tokenId, uint256 amount) internal {
        _verifyBurnData(tokenId, amount);
        assetContract.burnFrom(_msgSender(), tokenId, amount);
    }

    function _burnAssetBatch(uint256[] calldata tokenIds, uint256[] calldata amounts) internal {
        require(tokenIds.length == amounts.length, "AssetReveal: Invalid input");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _verifyBurnData(tokenIds[i], amounts[i]);
        }
        assetContract.burnBatchFrom(_msgSender(), tokenIds, amounts);
    }

    function _verifyBurnData(uint256 tokenId, uint256 amount) internal pure {
        IAsset.AssetData memory data = tokenId.getData();
        require(!data.revealed, "AssetReveal: Asset is already revealed");
        require(amount > 0, "AssetReveal: Burn amount should be greater than 0");
    }

    /// @notice Creates a hash of the reveal data
    /// @param recipient The address of the recipient
    /// @param prevTokenId The unrevealed token id
    /// @param amounts The amount of tokens to mint
    /// @param metadataHashes The array of hashes for new asset metadata
    /// @param revealHashes The revealHashes used for revealing this particular prevTokenId (length corresponds to the new tokenIds)
    /// @return digest The hash of the reveal data
    function _hashInstantReveal(
        address recipient,
        uint256 prevTokenId,
        uint256[] calldata amounts,
        string[] calldata metadataHashes,
        bytes32[] calldata revealHashes
    ) internal view returns (bytes32 digest) {
        digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    INSTANT_REVEAL_TYPEHASH,
                    recipient,
                    prevTokenId,
                    keccak256(abi.encodePacked(amounts)),
                    _encodeHashes(metadataHashes),
                    keccak256(abi.encodePacked(revealHashes))
                )
            )
        );
    }

    /// @notice Creates a hash of the reveal data
    /// @param recipient The intended recipient of the revealed token
    /// @param prevTokenId The previous token id
    /// @param amounts The amount of tokens to mint
    /// @param metadataHashes The array of hashes for new asset metadata
    /// @param revealHashes The revealHashes used for revealing this particular prevTokenId (length corresponds to the new tokenIds)
    /// @return digest The hash of the reveal data
    function _hashReveal(
        address recipient,
        uint256 prevTokenId,
        uint256[] calldata amounts,
        string[] calldata metadataHashes,
        bytes32[] calldata revealHashes
    ) internal view returns (bytes32 digest) {
        digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REVEAL_TYPEHASH,
                    recipient,
                    prevTokenId,
                    keccak256(abi.encodePacked(amounts)),
                    _encodeHashes(metadataHashes),
                    keccak256(abi.encodePacked(revealHashes))
                )
            )
        );
    }

    /// @notice Creates a hash of the reveal data
    /// @param recipient The intended recipient of the revealed tokens
    /// @param prevTokenIds The previous token id
    /// @param amounts The amounts of tokens to mint
    /// @param metadataHashes The arrays of hashes for new asset metadata
    /// @param revealHashes The revealHashes used for these prevTokenIds, (lengths corresponds to the new tokenIds)
    /// @return digest The hash of the reveal data
    function _hashBatchReveal(
        address recipient,
        uint256[] calldata prevTokenIds,
        uint256[][] calldata amounts,
        string[][] calldata metadataHashes,
        bytes32[][] calldata revealHashes
    ) internal view returns (bytes32 digest) {
        digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    BATCH_REVEAL_TYPEHASH,
                    recipient,
                    keccak256(abi.encodePacked(prevTokenIds)),
                    _encodeBatchAmounts(amounts),
                    _encodeBatchHashes(metadataHashes),
                    _encodeBatchRevealHashes(revealHashes)
                )
            )
        );
    }

    /// @notice Encodes the hashes of the metadata for signature verification
    /// @param metadataHashes The hashes of the metadata
    /// @return encodedHashes The encoded hashes of the metadata
    function _encodeHashes(string[] memory metadataHashes) internal pure returns (bytes32) {
        bytes32[] memory encodedHashes = new bytes32[](metadataHashes.length);
        for (uint256 i = 0; i < metadataHashes.length; i++) {
            encodedHashes[i] = keccak256((abi.encodePacked(metadataHashes[i])));
        }
        return keccak256(abi.encodePacked(encodedHashes));
    }

    /// @notice Encodes the hashes of the metadata for signature verification
    /// @param metadataHashes The hashes of the metadata
    /// @return encodedHashes The encoded hashes of the metadata
    function _encodeBatchHashes(string[][] memory metadataHashes) internal pure returns (bytes32) {
        bytes32[] memory encodedHashes = new bytes32[](metadataHashes.length);
        for (uint256 i = 0; i < metadataHashes.length; i++) {
            encodedHashes[i] = _encodeHashes(metadataHashes[i]);
        }
        return keccak256(abi.encodePacked(encodedHashes));
    }

    /// @notice Encodes the hashes of the metadata for signature verification
    /// @param revealHashes The revealHashes
    /// @return encodedRevealHashes The encoded hashes of the metadata
    function _encodeBatchRevealHashes(bytes32[][] memory revealHashes) internal pure returns (bytes32) {
        bytes32[] memory encodedHashes = new bytes32[](revealHashes.length);
        for (uint256 i = 0; i < revealHashes.length; i++) {
            encodedHashes[i] = keccak256(abi.encodePacked(revealHashes[i]));
        }
        return keccak256(abi.encodePacked(encodedHashes));
    }

    /// @notice Encodes the amounts of the tokens for signature verification
    /// @param amounts The amounts of the tokens
    /// @return encodedAmounts The encoded amounts of the tokens
    function _encodeBatchAmounts(uint256[][] memory amounts) internal pure returns (bytes32) {
        bytes32[] memory encodedAmounts = new bytes32[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            encodedAmounts[i] = keccak256(abi.encodePacked(amounts[i]));
        }
        return keccak256(abi.encodePacked(encodedAmounts));
    }

    /// @notice Checks if each metadatahash has been used before to either get the tokenId that was already created for it or generate a new one if it hasn't
    /// @dev This function also validates that we're not trying to reveal a tokenId that has already been revealed
    /// @param metadataHashes The hashes of the metadata
    /// @param prevTokenId The previous token id from which the assets are revealed
    /// @return tokenIdArray The array of tokenIds to mint
    function getRevealedTokenIds(string[] calldata metadataHashes, uint256 prevTokenId)
        internal
        returns (uint256[] memory)
    {
        IAsset.AssetData memory data = prevTokenId.getData();
        require(!data.revealed, "AssetReveal: already revealed");
        uint256[] memory tokenIdArray = new uint256[](metadataHashes.length);
        for (uint256 i = 0; i < metadataHashes.length; i++) {
            uint256 tokenId = assetContract.getTokenIdByMetadataHash(metadataHashes[i]);
            if (tokenId == 0) {
                uint16 revealNonce = ++revealIds[data.creator][prevTokenId];
                tokenId = TokenIdUtils.generateTokenId(
                    data.creator,
                    data.tier,
                    data.creatorNonce,
                    revealNonce,
                    data.bridged
                );
            }
            tokenIdArray[i] = tokenId;
        }
        return tokenIdArray;
    }

    /// @notice Get the status of a revealHash
    /// @return Whether it has been used
    function revealHashUsed(bytes32 revealHash) external view returns (bool) {
        return revealHashesUsed[revealHash];
    }

    /// @notice Get the asset contract address
    /// @return The asset contract address
    function getAssetContract() external view returns (address) {
        return address(assetContract);
    }

    /// @notice Get the auth validator address
    /// @return The auth validator address
    function getAuthValidator() external view returns (address) {
        return address(authValidator);
    }

    /// @notice Set permission for instant reveal for a given tier
    /// @param tier the tier to set the permission for
    /// @param allowed allow or disallow instant reveal for the given tier
    function setTierInstantRevealAllowed(uint8 tier, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tierInstantRevealAllowed[tier] = allowed;
    }

    /// @notice Get permission for instant reveal for a given tier
    /// @param tier The tier to check
    /// @return Whether instant reveal is allowed for the given tier
    function getTierInstantRevealAllowed(uint8 tier) external view returns (bool) {
        return tierInstantRevealAllowed[tier];
    }

    /// @notice Pause the contracts mint and burn functions
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the contracts mint and burn functions
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Set a new trusted forwarder address, limited to DEFAULT_ADMIN_ROLE only
    /// @dev Change the address of the trusted forwarder for meta-TX
    /// @param trustedForwarder The new trustedForwarder
    function setTrustedForwarder(address trustedForwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(trustedForwarder != address(0), "AssetReveal: trusted forwarder can't be zero address");
        _setTrustedForwarder(trustedForwarder);
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771HandlerUpgradeable)
        returns (address sender)
    {
        return ERC2771HandlerUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771HandlerUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771HandlerUpgradeable._msgData();
    }
}
