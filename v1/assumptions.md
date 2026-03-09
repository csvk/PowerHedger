# Assumptions and Detailed Requirements

This document outlines the assumptions made during the implementation of the PowerHedger EA to fulfill the PRD.

## 1. Indicator Rules (Section 4/5)
The PRD mentions "rules" (e.g., `S1RSISellLevel`, `S1EMATrendRule`) without defining the exact signal logic. We assume the following standard behaviors:
- **RSI**: 
    - BUY Signal: RSI cross above (100 - `SellLevel`) from below.
    - SELL Signal: RSI cross below `SellLevel` from above.
- **EMA Trend Rule**:
    - `Fast > Medium > Slow` for BUY trend.
    - `Fast < Medium < Slow` for SELL trend.
- **ADX Trend Rule**:
    - `ADX > Threshold` and `+DI > -DI` for BUY.
    - `ADX > Threshold` and `-DI > +DI` for SELL.
- **Bollinger Bands**:
    - BUY: Price touches or crosses below the lower band.
    - SELL: Price touches or crosses above the upper band.

## 2. Session Filters (Section 5)
- **Time Source**: The sessions are defined in UTC. The EA will use `TimeGMT()` to evaluate these filters, ensuring consistency regardless of broker server time.
- **Active Range**: A session filter triggers if the current GMT time falls within the defined range (inclusive of start, exclusive of end).

## 3. Position Sizing and Trimming
- **Broker Constraints**: Trimming (partial closes) will be adjusted to the nearest valid `LOT_STEP` provided by the broker. If a trim amount is less than `MIN_LOT`, it will be added to the `ProfitTally` until it reaches a valid volume.
- **Farthest First**: "Farthest" is defined as the entry price furthest from the current market price (Highest price for Sells, Lowest price for Buys).

## 4. Sequence Tracking
- **Reset Logic**: A direction's sequence resets to 1 only when *all* positions in that direction are closed.
- **Hedge Keyword**: The word "Hedge" is used for *any* trade that is NOT the initial indicator entry in a flat market or an "Inside" trade. This includes balancing trades and any follow-up recovery trades.

## 5. Persistence (JSON)
- Since MQL5 doesn't have a native JSON parser for all types, we will implement a simple, robust key-value persistence in a JSON-formatted string to ensure compatibility with Section 3.4.

## 7. Single-File Organization
- To maintain readability within a single large file, the EA will be organized into logical blocks using `#region` or clear comment dividers:
    - Inputs and Global State
    - Indicator Modules (S1 & S2)
    - Trade Management Utilities
    - Hedging and Recovery Core
    - Event Handlers (OnInit, OnTick, etc.)
- Standard MQL5 classes (e.g., `CTrade`, `CFileTxt`) will be used to keep the code concise.
