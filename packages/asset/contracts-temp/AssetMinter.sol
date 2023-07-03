//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "./AuthValidator.sol";
import "./libraries/TokenIdUtils.sol";
import "./ERC2771Handler.sol";
import "./interfaces/IAsset.sol";
import "./interfaces/IAssetMinter.sol";
import "./interfaces/ICatalyst.sol";

/// @title AssetMinter
/// @notice This contract is used as a user facing contract used to mint assets
contract AssetMinter is Initializable, IAssetMinter, EIP712Upgradeable, ERC2771Handler, AccessControlUpgradeable {
    AuthValidator private authValidator;
    using TokenIdUtils for uint256;
    address public assetContract;
    address public catalystContract;

    bytes32 public constant MINT_TYPEHASH = keccak256("Mint(MintableAsset mintableAsset)");
    bytes32 public constant MINT_BATCH_TYPEHASH = keccak256("MintBatch(MintableAsset[] mintableAssets)");

    string public constant name = "Sandbox Asset Minter";
    string public constant version = "1.0";
    mapping(address => bool) public bannedCreators;
    mapping(uint256 => address) public voxelCreators;

    bytes32 public constant EXCLUSIVE_MINTER_ROLE = keccak256("EXCLUSIVE_MINTER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _forwarder,
        address _assetContract,
        address _catalystContract,
        address _exclusiveMinter,
        AuthValidator _authValidator
    ) external initializer {
        __AccessControl_init();
        __ERC2771Handler_initialize(_forwarder);
        __EIP712_init(name, version);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXCLUSIVE_MINTER_ROLE, _exclusiveMinter);
        assetContract = _assetContract;
        catalystContract = _catalystContract;
        authValidator = _authValidator;
    }

    /// @notice Mints a new asset, the asset is minted to the caller of the function, the caller must have enough catalysts to mint the asset
    /// @dev The amount of catalysts owned by the caller must be equal or greater than the amount of tokens being minted
    /// @param signature Signature created on the TSB backend containing MINT_TYPEHASH and MintableAsset data, must be signed by authorized signer
    /// @param mintableAsset The asset to mint
    /// @param metadataHash the ipfs hash for asset's metadata
    function mintAsset(
        bytes memory signature,
        MintableAsset memory mintableAsset,
        string memory metadataHash
    ) external {
        address creator = _msgSender();
        require(creator == mintableAsset.creator, "Creator mismatch");
        require(!bannedCreators[creator], "Creator is banned");

        // verify signature
        require(authValidator.verify(signature, _hashMint(mintableAsset)), "Invalid signature");

        // amount must be > 0
        require(mintableAsset.amount > 0, "Amount must be > 0");
        // tier must be > 0
        require(mintableAsset.tier > 0, "Tier must be > 0");
        // burn the catalysts
        require(mintableAsset.voxelHash != 0, "Voxel hash must be non-zero");
        if (voxelCreators[mintableAsset.voxelHash] == address(0)) {
            voxelCreators[mintableAsset.voxelHash] = creator;
        } else {
            require(voxelCreators[mintableAsset.voxelHash] == creator, "Voxel hash already used");
        }
        ICatalyst(catalystContract).burnFrom(creator, mintableAsset.tier, mintableAsset.amount);

        // assets with catalyst id 0 - TSB Exclusive and 1 - Common are already revealed
        bool mintAsRevealed = !(mintableAsset.tier > 1);

        IAsset.AssetData memory assetData =
            IAsset.AssetData(
                creator,
                mintableAsset.amount,
                mintableAsset.tier,
                mintableAsset.creatorNonce,
                mintAsRevealed
            );

        IAsset(assetContract).mint(assetData, metadataHash);
    }

    /// @notice Mints a batch of new assets, the assets are minted to the caller of the function, the caller must have enough catalysts to mint the assets
    /// @dev The amount of catalysts owned by the caller must be equal or greater than the amount of tokens being minted
    /// @param signature Signature created on the TSB backend containing MINT_BATCH_TYPEHASH and MintableAsset[] data, must be signed by authorized signer
    /// @param mintableAssets The assets to mint
    /// @param metadataHashes The array of ipfs hash for asset metadata
    function mintAssetBatch(
        bytes memory signature,
        MintableAsset[] memory mintableAssets,
        string[] memory metadataHashes
    ) external {
        address creator = _msgSender();
        require(!bannedCreators[creator], "Creator is banned");

        // verify signature
        require(authValidator.verify(signature, _hashMintBatch(mintableAssets)), "Invalid signature");

        IAsset.AssetData[] memory assets = new IAsset.AssetData[](mintableAssets.length);
        uint256[] memory catalystsToBurn = new uint256[](mintableAssets.length);
        for (uint256 i = 0; i < mintableAssets.length; ) {
            require(creator == mintableAssets[i].creator, "Creator mismatch");
            require(mintableAssets[i].amount > 0, "Amount must be > 0");

            // tier must be > 0
            require(mintableAssets[i].tier > 0, "Tier must be > 0");
            if (voxelCreators[mintableAssets[i].voxelHash] == address(0)) {
                voxelCreators[mintableAssets[i].voxelHash] = creator;
            } else {
                require(voxelCreators[mintableAssets[i].voxelHash] == creator, "Voxel hash already used");
            }
            catalystsToBurn[mintableAssets[i].tier] += mintableAssets[i].amount;

            assets[i] = IAsset.AssetData(
                creator,
                mintableAssets[i].amount,
                mintableAssets[i].tier,
                mintableAssets[i].creatorNonce,
                !(mintableAssets[i].tier > 1)
            );
        }

        // burn the catalysts of each tier
        for (uint256 i = 0; i < catalystsToBurn.length; ) {
            if (catalystsToBurn[i] > 0) {
                ICatalyst(catalystContract).burnFrom(creator, i, catalystsToBurn[i]);
            }
        }
        IAsset(assetContract).mintBatch(assets, metadataHashes);
    }

    /// @notice Special mint function for TSB exculsive assets
    /// @dev TSB exclusive items cannot be recycled
    /// @dev TSB exclusive items are revealed by default
    /// @dev TSB exclusive items do not require catalysts to mint
    /// @dev Only the special minter role can call this function
    /// @dev Admin should be able to mint more copies of the same asset
    /// @param creator The address to use as the creator of the asset
    /// @param recipient The recipient of the asset
    /// @param amount The amount of assets to mint
    /// @param metadataHash The ipfs hash for asset metadata
    function mintExclusive(
        address creator,
        address recipient,
        uint256 amount,
        string memory metadataHash
    ) external onlyRole(EXCLUSIVE_MINTER_ROLE) {
        require(amount > 0, "Amount must be > 0");
        IAsset.AssetData memory asset = IAsset.AssetData(creator, amount, 0, 0, true);
        IAsset(assetContract).mintSpecial(recipient, asset, metadataHash);
    }

    /// @notice Recycles a batch of assets, to retireve catalyst at a defined ratio, the catalysts are minted to the caller of the function
    /// @dev The amount of copies that need to be burned in order to get the catalysts is defined in the asset contract
    /// @dev All tokensIds must be owned by the caller of the function
    /// @dev All tokenIds must be of the same tier
    /// @dev The sum of amounts must return zero from the modulo operation, for example if the amount of copies needed to retrieve a catalyst is 3, the sum of amounts must be a multiple of 3
    /// @param tokenIds The token ids of the assets to recycle
    /// @param amounts The amount of assets to recycle
    /// @param catalystTier The tier of the catalysts to mint
    function recycleAssets(
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint256 catalystTier
    ) external {
        require(catalystTier > 0, "Catalyst tier must be > 0");
        uint256 amountOfCatalystExtracted =
            IAsset(assetContract).recycleBurn(_msgSender(), tokenIds, amounts, catalystTier);
        // mint the catalysts
        ICatalyst(catalystContract).mint(_msgSender(), catalystTier, amountOfCatalystExtracted);
    }

    /// @notice Set the address of the catalyst contract
    /// @dev Only the admin role can set the catalyst contract
    /// @dev The catalysts are used in the minting process
    /// @param _catalystContract The address of the catalyst contract
    function changeCatalystContractAddress(address _catalystContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        catalystContract = _catalystContract;
        emit CatalystContractAddressChanged(_catalystContract);
    }

    /// @notice Set the address of the asset contract
    /// @dev Only the admin role can set the asset contract
    /// @param _catalystContract The address of the asset contract
    function changeAssetContractAddress(address _catalystContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        assetContract = _catalystContract;
        emit AssetContractAddressChanged(_catalystContract);
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _msgSender() internal view virtual override(ContextUpgradeable, ERC2771Handler) returns (address sender) {
        return ERC2771Handler._msgSender();
    }

    function _msgData() internal view virtual override(ContextUpgradeable, ERC2771Handler) returns (bytes calldata) {
        return ERC2771Handler._msgData();
    }

    /// @notice Creates a hash of the mint data
    /// @param asset The asset to mint
    /// @return digest The hash of the mint data
    function _hashMint(MintableAsset memory asset) internal view returns (bytes32 digest) {
        digest = _hashTypedDataV4(keccak256(abi.encode(MINT_TYPEHASH, asset)));
    }

    /// @notice Creates a hash of the mint batch data
    /// @param assets The assets to mint
    /// @return digest The hash of the mint batch data
    function _hashMintBatch(MintableAsset[] memory assets) internal view returns (bytes32 digest) {
        digest = _hashTypedDataV4(keccak256(abi.encode(MINT_BATCH_TYPEHASH, assets)));
    }
}
