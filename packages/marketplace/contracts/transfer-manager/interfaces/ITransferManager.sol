// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {ITransferExecutor} from "./ITransferExecutor.sol";
import {LibAsset} from "../../lib-asset/LibAsset.sol";
import {LibPart} from "../../lib-part/LibPart.sol";

abstract contract ITransferManager is ITransferExecutor {
    struct DealSide {
        LibAsset.Asset asset;
        LibPart.Part[] payouts;
        address from;
    }

    function doTransfers(DealSide memory left, DealSide memory right, LibAsset.FeeSide feeSide) internal virtual;
}