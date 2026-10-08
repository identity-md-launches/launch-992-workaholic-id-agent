// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Workaholic ID Agent (WORKER)
/// @notice Fixed supply ERC-20 with 18 decimals, minted entirely to its deployer.
contract Token is ERC20 {
    /// @notice One billion WORKER, expressed in the smallest token units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev A factory deployment credits the factory, which is msg.sender here.
    constructor() ERC20("Workaholic ID Agent", "WORKER") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
