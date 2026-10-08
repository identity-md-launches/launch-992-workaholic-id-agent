// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "src/Token.sol";

/// forge-config: default.fuzz.runs = 1000
contract TokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Token private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new Token();
        alice = makeAddr("edge-alice");
        bob = makeAddr("edge-bob");
        spender = makeAddr("edge-spender");
    }

    function test_oneSmallestUnitTransfersWithoutRounding() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_selfTransferStillRequiresEnoughBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_ownerCallingTransferFromNeedsOwnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        _assertBalances(SUPPLY, 0, 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_largestFiniteAllowanceDecrementsAcrossRepeatedSpends() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        _assertBalances(0, 1, SUPPLY - 1);
    }

    function test_replacingInfiniteAllowanceImmediatelyLimitsSpender() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 2, 2, 0);
    }

    function test_failedDelegatedSelfTransferRestoresAllowance() public {
        uint256 amount = SUPPLY + 1;
        assertTrue(token.approve(spender, amount));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), amount);
        assertEq(token.allowance(address(this), spender), amount);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroDelegatedTransferToZeroReverts() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_zeroDelegatedTransferPreservesExistingAllowance(uint256 approved) public {
        assertTrue(token.approve(spender, approved));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_delegatedBalanceFailureRestoresFiniteOrInfiniteAllowance(
        uint256 rawBalance,
        uint256 rawAmount,
        bool infinite
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(SUPPLY - balance, balance, 0);

        // A rejected transfer must not prevent the still-authorized amount from being spent.
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, balance));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - balance);
        _assertBalances(SUPPLY - balance, 0, balance);
    }

    function testFuzz_allowanceFailureWithSufficientBalanceIsAtomic(uint256 rawAllowed, uint256 rawAmount) public {
        uint256 allowed = bound(rawAllowed, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, allowed + 1, SUPPLY);
        assertTrue(token.approve(spender, allowed));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), allowed);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_invalidRecipientRestoresAllowance(uint256 rawAmount, uint256 rawApproval) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 approved = bound(rawApproval, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_splitTransfersAndRoundTripPreserveValue(uint256 rawAmount, uint256 rawSplit) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 first = bound(rawSplit, 0, amount);
        assertTrue(token.transfer(alice, amount));
        vm.startPrank(alice);
        assertTrue(token.transfer(bob, first));
        assertTrue(token.transfer(bob, amount - first));
        vm.stopPrank();
        _assertBalances(SUPPLY - amount, 0, amount);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_approvalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(bob, first));
        vm.prank(alice);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), first);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.allowance(spender, address(this)), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
