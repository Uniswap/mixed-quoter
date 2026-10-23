# MixedRouteQuoterV2

`MixedRouteQuoterV2` quotes exact input swaps along a path that mixes Uniswap v2, v3 and v4 pools. The quote functions are not meant to be called on-chain.

## Gas estimate after Glamsterdam

The deployed contract does not change. The meaning of its `gasEstimate` on Ethereum mainnet changes after the Glamsterdam activation (EIP-7773). Other chains keep their current gas rules until they adopt the same changes.

After the activation, a new storage slot costs 97,920 state gas and a new account costs 183,600 state gas (EIP-8037). The `GAS` opcode (`gasleft()`) does not include state gas that comes from the reservoir, and a frame that reverts returns its state gas.

How `gasEstimate` is built for each segment of the path:

- v3 and v4 segments: `gasleft()` before and after a swap call that always reverts. The revert returns all state gas of the simulated swap, so this part never includes state gas. It still increases after the activation because of the higher cost of cold state access (EIP-8038).
- v2 segments: the quote comes from the pair reserves. No swap runs and nothing is added to `gasEstimate`.
- Segments with protocol version 0: a fixed 20,000 is added for an ERC-20 transfer. This is the cost of a new storage slot before the activation. After the activation, a transfer to a holder with no balance costs more than 100,000 gas.

`gasEstimate` includes the execution cost of the work inside the simulated swaps, which can include token transfers (a v3 pool sends the output before the callback reverts). It does not include state gas, the intrinsic gas, or work of the real transaction outside the simulated swaps. Do not add the execution cost of transfers that the estimate already contains. Examples are a balance slot for a first-time holder of the output token and native ETH sent to a new account. Integrators that build a gas limit from `gasEstimate` must add these costs, or estimate the full transaction with `eth_estimateGas` on a node that runs the new rules.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
