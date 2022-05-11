//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import {ERC721} from "@openzeppelin/contracts-0.8/token/ERC721/ERC721.sol";
import "../common/Libraries/MapLib.sol";

/// @dev This is NOT a secure ERC721
/// DO NOT USE in production.
contract MockGameToken is ERC721 {
    using MapLib for MapLib.Map;
    mapping(uint256 => MapLib.Map) private template;
    mapping(address => uint256) public fakeBalance;

    // solhint-disable-next-line no-empty-blocks
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function balanceOf(address owner) public view override returns (uint256) {
        if (fakeBalance[owner] != 0) {
            return fakeBalance[owner];
        }
        return ERC721.balanceOf(owner);
    }

    function setFakeBalance(address owner, uint256 balance) external {
        fakeBalance[owner] = balance;
    }

    // Used by the game token!!!
    function getTemplate(uint256 gameId) external view returns (TileWithCoordLib.TileWithCoord[] memory) {
        return template[gameId].getMap();
    }

    function setQuad(
        uint256 gameId,
        uint256 xi,
        uint256 yi,
        uint256 size
    ) external {
        template[gameId].setQuad(xi, yi, size);
    }

    function clearQuad(
        uint256 gameId,
        uint256 xi,
        uint256 yi,
        uint256 size
    ) external {
        template[gameId].clearQuad(xi, yi, size);
    }
}
