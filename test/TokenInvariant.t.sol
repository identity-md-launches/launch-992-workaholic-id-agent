// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "../src/Token.sol";

/// @dev Exercises arbitrary sequences without creating tokens or editing token storage.
contract TokenHandler is Test {
    Token private immutable token;
    address[4] private actors;
    // Expected state comes from the initial allocation and requested operations,
    // never from token getters. A wrong balance cannot silently change our inputs.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    constructor(Token token_, address[4] memory actors_, uint256 initialBalance) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            ghostBalance[actors[i]] = initialBalance;
        }
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, ghostBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 boundary) external {
        uint256[4] memory amounts = [uint256(0), uint256(1), type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[boundary % 4]);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 balance = ghostBalance[owner];
        uint256 amount = bound(rawAmount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] -= amount;
    }

    function moveAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = ghostBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: the invariants require every balance and allowance to survive failure.
    }

    function spendAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = ghostAllowance[owner][spender];
        // Infinite allowance cannot be exceeded; replace it with the largest finite allowance.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            _approve(owner, spender, allowed);
        }
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
    }

    function spendAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = ghostBalance[owner];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, ghostBalance[owner]);
        if (delegated) {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function revokeThenSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract TokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Token private token;
    address[4] private actors;
    TokenHandler private handler;

    function setUp() public {
        token = new Token();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
        handler = new TokenHandler(token, actors, SUPPLY / actors.length);
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        selectors[3] = TokenHandler.approveBoundary.selector;
        selectors[4] = TokenHandler.moveAboveBalance.selector;
        selectors[5] = TokenHandler.spendAboveAllowance.selector;
        selectors[6] = TokenHandler.spendAboveBalance.selector;
        selectors[7] = TokenHandler.rejectZeroRecipient.selector;
        selectors[8] = TokenHandler.rejectZeroSpender.selector;
        selectors[9] = TokenHandler.revokeThenSpend.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_eachHolderReceivesExactlyWhatWasTransferred() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "incorrect holder balance");
        }
    }

    function invariant_allowancesMatchApprovalsAndAuthorizedSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "incorrect allowance or failed-call rollback"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(actors[i], address(this)), 0);
            assertEq(token.allowance(actors[i], address(handler)), 0);
        }
    }
}
