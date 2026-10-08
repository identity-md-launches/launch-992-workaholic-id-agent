# Workaholic ID Agent (WORKER)

An immutable ERC-20 token. The deployable contract is `src/Token.sol:Token`.

| Parameter | Value |
| --- | --- |
| Name | Workaholic ID Agent |
| Symbol | WORKER |
| Decimals | 18 |
| Supply in WORKER | 1,000,000,000 |
| Supply in minor units | 1000000000000000000000000000 (`10^27`) |
| Constructor arguments | None (`[]`; ABI encoding `0x`) |
| Initial recipient | Constructor `msg.sender` |
| Deployment value | 0 ETH |

The constructor mints the full supply exactly once. An account deploying directly
receives everything; when a factory deploys the contract using CREATE or CREATE2,
the factory receives everything. The caller of that factory does not receive the
constructor mint. There is no separately configured recipient or owner.

## Behavior and assumptions

The brief specifies no special transfer rules, so WORKER uses the unmodified
OpenZeppelin ERC-20 implementation. Transfers deliver the exact requested amount,
with no tax, rebase, burn, callbacks, or address exemptions. There are no external
mint or burn functions, administrative roles, pause/blacklist powers, upgrades,
initialization calls, or external services. Supply remains constant for the
lifetime of this deployment.

Transfers and approvals return `true` on success and revert with ERC-6093 custom
errors on invalid addresses, insufficient balances, or insufficient allowances.
Zero-amount transfers between valid addresses and self-transfers are supported.
Transfers to the zero address and approvals to a zero spender revert. Finite
allowances decrease on `transferFrom`; a maximum `uint256` allowance remains
unchanged. A self-transfer via `transferFrom` still spends its allowance.

Minting and transfers emit `Transfer`. Explicit approvals emit `Approval`;
OpenZeppelin v5 does not emit `Approval` for allowance reductions during
`transferFrom`, so integrations should read `allowance` for its current value.

## Build and check

Install Foundry and have Solidity **0.8.26** available. All Solidity dependencies
are ordinary files in `lib/`, including their licenses; there are no submodules
or package-install steps. Once the pinned compiler is installed, builds and
tests require no network, RPC endpoint, keys, environment variables, FFI, or
filesystem cheatcode permissions.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins the compiler, Cancun EVM target, optimizer (200 runs), and
`bytecode_hash = "none"` for reproducible launch bytecode. The selected launch
chain must support Cancun, consistent with the supplied Uniswap v4 launch harness.

The tests cover metadata, the exact constructor mint and its event, direct and
CREATE2 factory deployment, transfers and approvals, failure atomicity, allowance
revocation and isolation, zero/max values, self-transfers, exact distribution and
claim transfers, absent privileged controls, and forbidden runtime opcodes.
Three fuzz tests cover amounts and recipients; a stateful invariant runs transfer,
approval, and delegated-transfer sequences while checking supply conservation.
Tests use local fixtures only and do not share environment state.

Dependency versions and archive SHA-256 hashes are in `lib/dependencies.json`:

- [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2): ERC-20 and its complete transitive source dependencies, MIT.
- [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7): test library sources, MIT/Apache-2.0.

## Deployment parameters and responsibilities

Use the creation bytecode for **`src/Token.sol:Token`**, with no appended constructor
arguments and no ETH. The compiled artifact is `out/Token.sol/Token.json`.
For inspection without sending a transaction:

```sh
forge inspect src/Token.sol:Token bytecode
forge inspect src/Token.sol:Token abi
```

The deployment operator selects the chain and deploying account/factory and, for
CREATE2, its salt. No chain-specific addresses are built into the token. The
operator must confirm that the actual deploying address can distribute the full
supply it receives. There is no token administrator who can recover a mistaken
allocation. No deployment or wallet access is performed by this project.

For an IdentityMD custom launch, the factory receives the entire supply and is
responsible for distributor, liquidity, and remainder transfers. Token transfers
need no special exemptions. This assignment supplies only the token: the launch
operator supplies the manifest, economics, factory, distributor, pool integration,
and chain-specific configuration. The supplied protected pool harness needs those
external contracts and launch inputs; the local suite checks the token behavior
but does not claim a real Uniswap seed or swap integration run.

## After launch

No owner settings, keepers, oracle configuration, or further minting are needed.
The operator should verify source and runtime against the pinned build and check
name, symbol, decimals, initial mint event, supply, and distribution. Holders
control transfers and allowances. Prefer bounded approvals, revoke unused ones,
and clear an existing allowance before replacing it to reduce the standard ERC-20
approval race. Sending tokens to an address or contract that cannot return them
is irreversible; the token has no rescue function or payable receive function.

Review against the supplied security reference focuses on the constructor-only
mint, transfer authorization, checked balance/allowance failures, exact units,
and lack of external calls or privileged execution paths. Foundry unit, fuzz,
and invariant tests are provided; Slither and Mythril are not part of this
validation. An independent adversarial review remains a release responsibility;
local test success is not a security audit.
