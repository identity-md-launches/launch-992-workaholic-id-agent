// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

/// @dev Exercises arbitrary sequences without creating tokens or editing token storage.
contract TokenHandler is Test {
    Token private immutable token;
    address[4] private actors;

    constructor(Token token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 amount = bound(rawAmount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
    }
}

contract TokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Token private token;
    address[4] private actors;

    function setUp() public {
        token = new Token();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        TokenHandler handler = new TokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        uint256 trackedBalances;
        for (uint256 i; i < actors.length; ++i) {
            trackedBalances += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(trackedBalances, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
