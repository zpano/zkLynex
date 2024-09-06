# zkLynex

## Overview
`zkLynex` is an innovative decentralized exchange (DEX) that leverages zk-SNARKs technology to address two critical issues in decentralized finance (DeFi): `privacy` and `scalability`. As a leading DEX on Linea, zkLynex introduces the concept of a `dark pool`, a trading environment where transaction details remain undisclosed to the public until after the trade is executed. This approach offers unparalleled security and privacy protection, especially for users executing large transactions.

### Core Objectives
The primary goal of zkLynex is to provide users with a `secure`, `efficient`, and `privacy-protected` trading environment. Leveraging zk-SNARKs technology, zkLynex ensures that transaction details, including prices and volumes, remain private during the verification process.

### Key Features

- **Concealing Price Information**: In limit orders, only the required balance for the order is exposed, while the price remains concealed.
- **Preventing Market Reactions**: Users' trading intentions remain hidden, preventing market reactions that could otherwise affect prices, ensuring price stability.

### Order Structure

An order is represented as follows:
```
O=(t,s) ,where t :=(φ,χ,d), s:=(p,v,α)
```
```
φ: side of the order, 0 when it’s a bid, 1 when it’s an ask
χ: token address for the target project
d: denomination, either the token address of USDC or ETH. Set 0x0 represent USDC and 0x1 represent ETH.
p: price, denominated in d
v: volume, the number of tokens to trade
α: access key, a random element in bn128’s prime field, which mainly used as a blinding factor to prevent brute force attacks
```

This structure ensures that price information is concealed and user intentions are protected, enabling a highly private and secure trading experience.

## Foundry

## Usage

### Build

```shell
$ forge build --via-ir
```

### Test

```shell
$ forge test --via-ir
```

### Deploy

```shell
$ forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast --via-ir -vv
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
