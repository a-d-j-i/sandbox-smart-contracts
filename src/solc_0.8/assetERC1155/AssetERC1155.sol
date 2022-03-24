//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./AssetBaseERC1155.sol";
import "../asset/libraries/AssetHelper.sol";
import "../common/interfaces/IAssetAttributesRegistry.sol";
import "../common/interfaces/IMintableERC1155.sol";

// solhint-disable-next-line no-empty-blocks
contract AssetERC1155 is AssetBaseERC1155, IMintableERC1155 {
    event PredicateSet(address predicate);

    /// @notice fulfills the purpose of a constructor in upgradeable contracts
    function initialize(
        address trustedForwarder,
        address admin,
        address bouncerAdmin,
        uint8 chainIndex
    ) external {
        init(trustedForwarder, admin, bouncerAdmin, chainIndex);
    }

    /**
     * @notice Creates `amount` tokens of token type `id`, and assigns them to `account`.
     * @dev Should be callable only by MintableERC1155Predicate
     * Make sure minting is done only by this function
     * @param account user address for whom token is being minted
     * @param id token which is being minted
     * @param amount amount of token being minted
     * @param data extra byte data to be accompanied with minted tokens
     */
    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external override {
        require(_msgSender() == _predicate, "!PREDICATE");
        uint256 uriId = id & ERC1155ERC721Helper.URI_ID;
        _metadataHash[uriId] = abi.decode(data, (bytes32));
        _mint(_msgSender(), account, id, amount, data);
    }

    /// @notice called by predicate to mint tokens transferred from L2
    /// @param to address to mint to
    /// @param ids ids to mint
    /// @param amounts supply for each token type
    /// @param data extra data to accompany the minting call
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external override {
        require(_msgSender() == _predicate, "!PREDICATE");
        bytes32[] memory hashes = abi.decode(data, (bytes32[]));
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 uriId = ids[i] & ERC1155ERC721Helper.URI_ID;
            _metadataHash[uriId] = hashes[i]; // To Review
        }
        _mintBatch(to, ids, amounts, data);
    }

    /// @notice Set address which will have minting privelages on L1 which is currently limited to tunnels.
    /// @param predicate address that will be given minting rights for L1.
    function setPredicate(address predicate) external {
        require(_msgSender() == _admin, "!ADMIN");
        _predicate = predicate;
        emit PredicateSet(predicate);
    }
}
