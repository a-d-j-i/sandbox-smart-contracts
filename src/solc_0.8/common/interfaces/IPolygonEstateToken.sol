//SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity 0.8.2;

import "../Libraries/TileWithCoordLib.sol";
import "./IEstateToken.sol";

/// @title Interface for the Estate token

interface IPolygonEstateToken {
    struct FreeLandData {
        uint256[][3] quads; //(size, x, y)
        TileWithCoordLib.TileWithCoord[] tiles;
    }

    struct RemoveGameData {
        uint256 gameId;
        uint256[][3] quadsToTransfer; //(size, x, y) transfer when adding
        uint256[][3] quadsToFree; //(size, x, y) take from free-lands
    }

    struct AddGameData {
        uint256 gameId;
        uint256[][3] transferQuads; //(size, x, y) transfer when adding
        FreeLandData freeLandData;
    }

    struct CreateEstateData {
        FreeLandData freeLandData;
        AddGameData[] gameData;
        bytes32 uri;
    }

    struct UpdateEstateData {
        uint256 estateId;
        bytes32 newUri;
        FreeLandData freeLandToAdd;
        uint256[][3] freeLandToRemove;
        RemoveGameData[] gamesToRemove;
        AddGameData[] gamesToAdd;
    }

    function createEstate(address from, CreateEstateData calldata data) external returns (uint256);

    function updateEstate(address from, UpdateEstateData calldata data) external returns (uint256);
}
