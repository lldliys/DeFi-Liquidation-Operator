# Atomic Flash Loan Liquidation Bot on Aave V2

## Overview
This project was to engineer a smart contract capable of executing a complex, multi-step Decentralized Finance (DeFi) liquidation using flash loans. The core objective was to algorithmically identify an under-collateralized debt position on Aave V2, borrow the necessary funds via a Uniswap V2 flash loan without any upfront capital, execute the liquidation, and swap the seized collateral back to ETH for a profit—all within a single, atomic blockchain transaction.

### Architectural Approach
To ensure a clean and fault-tolerant execution flow, I designed the contract around a unified entry point. By simply calling the `operate()` function, the entire lifecycle of the flash loan, liquidation, and arbitrage exchange is triggered and executed seamlessly.

```solidity
function operate() external;

```

### Target Scenario
To validate my liquidation logic, I tested the contract against a historical underwater position on Aave V2 mainnet. Reference: [Original Liquidation Transaction](https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077)

## Strategies

### Sourcing Capital via Uniswap Flash Swaps
To perform the liquidation without upfront token balances, I leveraged Uniswap V2's flash swap mechanism. By calling the `swap` function on a Uniswap pair, I optimistically borrowed the required debt asset. The Uniswap pair contract temporarily hands over the tokens and immediately invokes the `uniswapV2Call` callback function on my smart contract to handle the core logic.

### Executing the Aave Liquidation
Once my contract received the flash-loaned debt asset, the execution flow inside `uniswapV2Call` immediately routed the funds to Aave's `liquidationCall`. I specified the target `user`, the `debtAsset` I was repaying on their behalf, and the `collateralAsset` I wanted to claim as a reward for securing the protocol.

### Advanced Optimizations
While a naive liquidation execution yields around 21 ETH, I rigorously optimized the contract execution to maximize capital efficiency, resulting in a net profit of >43 ETH. Key optimizations include:
* **Precision Debt Calculation**: Dynamically calculated the exact, maximum permissible `debtToCover` instead of relying on static estimates, extracting the absolute maximum collateral bonus allowed by Aave's liquidation penalty.
* **Optimal Routing & Slippage Control**: Engineered the arbitrage execution to select the most liquid DEX pools for swapping the seized collateral back to the debt asset, satisfying the flash loan's `K` constant with minimal slippage.
* **Gas-Efficient State Management**: Minimized redundant external calls during the execution pipeline, optimizing memory variable storage to reduce gas consumption.
The entire logic, including state management, path optimization, and security checks, is cleanly encapsulated within `contracts/LiquidationOperator.sol`.

## How to Reproduce

### Prerequsite
You need an Alchemy archive Ethereum node API key to fork the mainnet state at block `12489620`. For security reasons, the API key is not hardcoded. You must provide it as an environment variable (`ALCHE_API`).

### Execution via Docker
1. Build the docker image:
   ```
   docker build -t defi-mooc-lab2 .
   ```
2. Run the test suite by injecting your Alchemy API key:
   ```
   docker run -e ALCHE_API="$YOUR_ALCHEMY_ETHEREUM_MAINNET_API" -it defi-mooc-lab2 npm test
   ```
If the execution is successful, the console will output the final optimized profit (>= 43 ETH) at the end of the transaction.

## License
This project is for academic purposes as part of COMPSCI 294 177 coursework at UC Berkeley.
