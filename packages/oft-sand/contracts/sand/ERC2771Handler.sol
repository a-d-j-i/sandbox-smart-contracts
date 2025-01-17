// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity 0.8.23;

/// @title ERC2771Handler
/// @author The Sandbox
/// @notice Handle meta-transactions
/// @dev minimal ERC2771 handler to keep bytecode-size down
/// based on: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.6.0/contracts/metatx/ERC2771Context.sol
/// with an initializer for proxies and a mutable forwarder
abstract contract ERC2771Handler {
    address internal _trustedForwarder;

    event TrustedForwarderSet(address indexed newForwarder);

    /// @dev Initializes the contract
    /// @param forwarder trusted forwarder address
    function __ERC2771Handler_initialize(address forwarder) internal {
        _trustedForwarder = forwarder;
        emit TrustedForwarderSet(_trustedForwarder);
    }

    /// @notice Checks if an address is a trusted forwarder
    /// @param forwarder address to check
    /// @return is trusted
    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == _trustedForwarder;
    }

    /// @notice Get the current trusted forwarder
    /// @return trustedForwarder address of the trusted forwarder
    function getTrustedForwarder() external view returns (address) {
        return _trustedForwarder;
    }

    /// @dev if the call comes from the trusted forwarder, it gets the real sender by checking the encoded address in the data
    /// @return sender address of the real sender
    function _msgSender() internal view virtual returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            // solhint-disable-next-line no-inline-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return msg.sender;
        }
    }

    /// @dev if the call comes from the trusted forwarder, it substracts the sender address from `msg.data` to get the real `msg.data`
    /// @return the real `msg.data`
    function _msgData() internal view virtual returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }
}
