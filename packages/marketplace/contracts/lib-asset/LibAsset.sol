// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/// @title library for Assets
/// @notice contains structs for Asset and AssetType
library LibAsset {
    enum AssetClassType {
        INVALID_ASSET_CLASS,
        ERC20_ASSET_CLASS,
        ERC721_ASSET_CLASS,
        ERC1155_ASSET_CLASS
    }

    enum FeeSide {
        NONE,
        LEFT,
        RIGHT
    }

    /// @dev AssetType is a type of a specific asset. For example AssetType is specific ERC-721 token (key is token + tokenId) or specific ERC-20 token (DAI for example).
    /// @dev It consists of asset class and generic data (format of data is different for different asset classes). For example, for asset class ERC20 data holds address of the token, for ERC-721 data holds smart contract address and tokenId.
    struct AssetType {
        AssetClassType assetClass;
        bytes data;
    }

    /// @dev Asset represents any asset on ethereum blockchain. Asset has type and value (amount of an asset).
    struct Asset {
        AssetType assetType;
        uint256 value;
    }

    bytes32 internal constant ASSET_TYPE_TYPEHASH = keccak256("AssetType(uint256 assetClass,bytes data)");

    bytes32 internal constant ASSET_TYPEHASH =
        keccak256("Asset(AssetType assetType,uint256 value)AssetType(uint256 assetClass,bytes data)");

    /// @notice decides if the fees will be taken and from which side
    /// @param leftClass left side asset class type
    /// @param rightClass right side asset class type
    /// @return side from which the fees will be taken or none
    function getFeeSide(AssetClassType leftClass, AssetClassType rightClass) internal pure returns (FeeSide) {
        if (leftClass == AssetClassType.ERC20_ASSET_CLASS && rightClass != AssetClassType.ERC20_ASSET_CLASS) {
            return FeeSide.LEFT;
        }
        if (rightClass == AssetClassType.ERC20_ASSET_CLASS && leftClass != AssetClassType.ERC20_ASSET_CLASS) {
            return FeeSide.RIGHT;
        }
        return FeeSide.NONE;
    }

    /// @notice calculate if Asset types match with each other
    /// @param leftType to be matched with rightAssetType
    /// @param rightType to be matched with leftAssetType
    /// @return AssetType of the match
    function matchAssets(
        AssetType calldata leftType,
        AssetType calldata rightType
    ) internal pure returns (AssetType memory) {
        AssetClassType classLeft = leftType.assetClass;
        AssetClassType classRight = rightType.assetClass;

        require(classLeft != AssetClassType.INVALID_ASSET_CLASS, "not found IAssetMatcher");
        require(classRight != AssetClassType.INVALID_ASSET_CLASS, "not found IAssetMatcher");
        require(classLeft == classRight, "assets don't match");

        bytes32 leftHash = keccak256(leftType.data);
        bytes32 rightHash = keccak256(rightType.data);
        require(leftHash == rightHash, "assets don't match");

        return leftType;
    }

    /// @notice calculate hash of asset type
    /// @param assetType to be hashed
    /// @return hash of assetType
    function hash(AssetType memory assetType) internal pure returns (bytes32) {
        return keccak256(abi.encode(ASSET_TYPE_TYPEHASH, assetType.assetClass, keccak256(assetType.data)));
    }

    ///    @notice calculate hash of asset
    ///    @param asset to be hashed
    ///    @return hash of asset
    function hash(Asset memory asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(ASSET_TYPEHASH, hash(asset.assetType), asset.value));
    }
}