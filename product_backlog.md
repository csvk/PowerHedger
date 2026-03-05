# Product Backlog - PowerHedger

This document tracks the features and improvements for the PowerHedger Expert Advisor.

## Features

### 1. Strategy Parameters and Mechanism
- **Description**: Formally define and implement strategy-specific parameters and the underlying mechanism for selecting and executing strategies.
- **Goal**: Improved modularity and clarity in how different trading strategies are handled by the EA.

### 2. Better Persistency for Restarts
- **Description**: Enhance the EA's ability to recover state after a platform restart or crash.
- **Goal**: Ensure that positions, profit tallies, and internal states (like sequence numbers) are correctly restored without manual intervention.

### 3. SMA Indicator for Outside Trades
- **Description**: Implement logic to restrict or allow "outside" trades based on a trend indicator, such as the 200-period Simple Moving Average (SMA).
- **Goal**: Align hedge/entry logic with the broader market trend to reduce risk.

### 4. Symbol Migration and Manual Trade Handling
- **Description**: Transition the EA's tracking logic from being based primarily on Magic Numbers to being based on Symbols. Also, define how the EA should interact with trades opened manually on the same symbol.
- **Goal**: Greater flexibility in managing multiple instances and better integration with manual trading activities.

### 5. Enhanced Trade Comments
- **Description**: Improve the readability and informativeness of trade comments, specifically including "Buy" or "Sell" labels and other relevant metadata.
- **Goal**: Easier debugging and analysis of trade logs and history.
