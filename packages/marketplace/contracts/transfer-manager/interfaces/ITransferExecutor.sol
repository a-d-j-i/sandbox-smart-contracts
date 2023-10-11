// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {LibAsset} from "../../lib-asset/LibAsset.sol";

abstract contract ITransferExecutor {
    /// @notice function should be able to transfer any supported Asset
    /// @param asset Asset to be transferred
    /// @param from account holding the asset
    /// @param to account that will receive the asset
    /// @dev this is the main entry point, when used as a separated contract this method will be external
    function transfer(LibAsset.Asset memory asset, address from, address to) internal virtual;
}
