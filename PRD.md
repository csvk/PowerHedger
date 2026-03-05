# Product Requirements Document (PRD): Advanced MT5 Hedging & Recovery EA

## 1. Product Overview

This Expert Advisor (EA) for MetaTrader 5 automates an advanced hedging and recovery strategy designed to systematically lock in profit and reduce drawdowns by trimming losing positions. It combines strict, dynamic mathematical trade management with entry filters derived from the POW Banker strategy (RSI, EMA, ADX, and Bollinger Bands).

The EA supports trading in flat markets or "from the inside" of a hedge when the price is trapped between long and short positions. To provide maximum flexibility, the EA runs two independent entry strategies concurrently, executing precise market orders to perfectly balance exposure when risk thresholds are breached.

## 2. Core Trading Logic & Rules

### 2.1 Entry Conditions & Mutual Exclusion

New indicator-based positions can only be entered under specific market conditions:
- **Flat Market**: There are currently zero open positions on the traded pair. Entries are subject to Session and Weekday filters.
- **Strategic Entry (Inside or Outside)**: New signalled trades are permitted under the following conditions:
  - **Inside Entry**: Allowed when the current market price is between existing Buy and Sell trades (i.e., both directions have open positions).
  - **Outside Entry**: Allowed when positions are open in only one direction (completely unbalanced). In this case, an entry is allowed only if:
    - The position nearest to the current market price is currently in a loss.
    - The current market price is at least `MinGapPips` away from that nearest position.
    - The entry direction is permitted by the `OutsideAllowed` parameter.
- Session and Weekday filters do **not** apply to these subsequent entries.

**Entry Rules**:
- **MinGapPips**: The minimum pip distance that must be maintained between the current market price and the nearest open trade in either direction. 
  - If positions are open on both sides (Buy and Sell), the distance must be checked against both.
  - If positions are open on only one side, it is checked against that side.
  - **Calculation**: `MinGapPips = InsidePipMultiplier * HedgePips`.
- **Strategies**: The EA runs multiple independent strategies simultaneously to identify entries:
  - **Strategy 1 (Trend)**: Default name "Trend".
  - **Strategy 2 (Reversal)**: Default name "Reversal".
  - **Random Signal Generator**: A placeholder strategy named "Random". 
    - **Default Mode**: For testing purposes, "Random" is the default mode. 
    - **Disabling**: Once Strategy 1 and Strategy 2 are properly defined/configured, the Random generator should be disabled.
    - **Strategy Naming**: It does not require an input name variable.
- **Mutual Exclusion**: At any given moment, if a new entry is permitted by market conditions, only one strategy can trigger an entry. If Random is enabled, it takes priority. Else, if multiple strategies generate a signal simultaneously, the EA prioritizes the strategy selected in the `PrioritizeStrategy` parameter. If both Strategy 1 and Strategy 2 give a signal, only the prioritized one is used.

### 2.2 Position Sizing

- **LotSize**: Fixed lot size for every new individual indicator-based entry.
- **MaxLots**: Maximum allowed total accumulated lot size in any one direction (total Buy lots or total Sell lots) for standard entries. If a new entry would cause the total volume to exceed `MaxLots`, the indicator entry is blocked.
- **MaxLots in Hedging**: The `MaxLots` limit now also applies to defensive hedge entries. If the total volume in a direction (the side needing the hedge) has reached `MaxLots`, or if opening a required hedge would cause the hedge side to exceed `MaxLots`, the EA must not open a new hedge position. Instead, it must reduce the unbalanced side by `LotSize` from the farthest open positions.
- **Hedge Exemption**: [DEPRECATED] Previously, `MaxLots` limits did not apply to defensive hedge entries. This exemption is now removed in favor of the reduction logic.

### 2.3 Hedging Logic

- **Event-Driven Balance Calculation**: The EA must calculate the balance between total open Buy lots and total open Sell lots whenever a trade event occurs (Position Open, Close, or Partial Close). The resulting total volumes must be stored in memory for efficient retrieval.
- **Constant Price Monitoring**: While the balance calculation is event-driven, the EA must constantly monitor the live market price on every tick to check if it has reached a hedge trigger point.
- **Perfect Hedging (Balancing)**: The core objective is to perfectly balance the total open volume.
  - `Hedge Volume Required = Absolute Value of (Total Buy Lots - Total Sell Lots)`.
- **HedgePips (Trigger Distance)**: The exact pip gap required to trigger the protective hedge, calculated from the nearest entry price of the unbalanced direction.
- **Market Order Execution**: Once the stored balance is unequal and the live price (monitored per tick) breaches the trigger distance, the EA must execute a Market Order for the exact missing volume. Pending Stop Orders are not permitted.

**Trigger Scenarios**:
- **Unbalanced BUY**: (Buy Lots > Sell Lots). Requires a Sell Hedge. Trigger point is `HedgePips` below the lowest (nearest to price) open Buy entry.
  - *If a Sell Hedge would exceed `MaxLots` or if Buy side already at `MaxLots`: Reduce BUY side by `LotSize` from farthest positions.*
- **Unbalanced SELL**: (Sell Lots > Buy Lots). Requires a Buy Hedge. Trigger point is `HedgePips` above the highest (nearest to price) open Sell entry.
  - *If a Buy Hedge would exceed `MaxLots` or if Sell side already at `MaxLots`: Reduce SELL side by `LotSize` from farthest positions.*

### 2.4 Modular Entry Generation

- **Conditional Invocation**: The modular entry generation logic must only be called if the EA has already verified that valid entry conditions exist (e.g., in a Flat Market or Inside a Hedge) and all active filters (Session/Weekday) and distance rules (MinGapPips) are satisfied. The EA should not waste resources calculating indicators if a trade is not permitted by these factors.
- **Abstraction**: The entry signal generation logic must be modularized. The core EA trade management and hedging logic should be decoupled from the specific indicator-based trigger.
- **Future-Proofing**: Modifications or exports of entry logic to external triggers in the future must not require changes to the core EA logic.

- To facilitate trade monitoring, every order must include a specific comment formatted as: `<N> [Keyword/Strategy]`.

- **Sequence Counters (Open Position Count)**: 
  - The serial number `<N>` represents the total number of positions currently open in that direction, including the new position.
  - **Example**: 
    - First trade in any direction: `<1>`.
    - If two more trades are opened: `<2>` and `<3>`.
    - If trade `<3>` is closed and another trade is opened in the same direction, the new trade is labeled `<3>`.
  - This counter tracks only active open positions at the moment of trade entry, irrespective of the reason for the trade.

- **Keywords and Strategy Names**:
  - **Flat Market Entry**: The first trade entered in a flat market uses the triggering strategy's name with context "New" (e.g., `<1> Trend [New]`).
  - **Subsequent Strategic Entry**: Entries triggered by a strategy while other positions are open use the strategy name and the market context:
    - **Inside**: Signal occurred between existing trades (e.g., `<2> Trend [Inside]`).
    - **Outside**: Signal occurred outside existing trades or when one-sided (e.g., `<3> Reversal [Outside]`).
  - **Hedge Entry**: Any trade executed as a defensive hedge (balancing trade) uses the keyword `Hedge`, unless opened during a "Hedge Squeeze" (Section 3.5).
    - **Trailing Hedge**: If a hedge is entered while a Post-Trim Hedge Point is active (Squeezing), the keyword must be `Trailing Hedge`. 
      - **Price Difference**: A Trailing Hedge (during squeezing) is always at a **worse** (further) price than the standard trigger point defined in Section 2.3. As the price trails towards the standard point, the keyword remains `Trailing Hedge` until it reaches the standard point, where it reverts to `Hedge`.
- **Trimming/Reduction Comments**:
  - Partial closures for trimming must use the comment: `Trim`.
  - Theoretical partial closures during trailing must use the comment: `Intermediate Trim`.
  - Volume reductions due to `MaxLots` breach must use the comment: `Reduction`.

## 3. Trade Management & Trimming Logic

Systematically generate profit by trimming the outside boundaries of the hedge using internal profits.

### 3.1 Independent Trailing Stops

- **LockProfitPips & Trailing Stop Loss**: Managed for each position separately. Once an individual position reaches `LockProfitPips`, its independent trailing stop is activated.

### 3.2 Profit Trimming Mechanics

Profits from closed positions are distributed according to the `KeepProfitPercent` attribute.
- **Pocketed Profit**: `Total Booked Profit * KeepProfitPercent`.
- **Trim Amount**: The remainder is used to partially close (trim) the open losing positions.
- **Farthest First**: Trimming always starts from the trade with the farthest entry price from the current market price.
- **Trimming Guard**: Trimming only applies to losing positions where the entry price is at least `HedgePips` away from the current market price.
- **Continuity**: If the available trim amount is sufficient to fully close the farthest position, the EA will close it entirely and use any remaining trim amount to proceed to the next qualifying farthest position.

### 3.3 Intermediate (Theoretical) Profit Trimming

- **Proactive Risk Reduction**: Trims are executed even before a winning trade is fully closed.
- **Activation**: Once `LockProfitPips` is reached, a theoretical profit is calculated based on the current trailing stop loss level.
- **Proactive Trim**: Apply the `KeepProfitPercent` rule to this theoretical profit and immediately trim the farthest loss positions using the comment `Intermediate Trim`.
- **Incremental Trimming**: After the initial intermediate trim, subsequent trims are triggered only when the Trailing Stop Loss moves by at least the value of `IntermediateTrimPips`.
- **Excess Profit Reconciliation**: Upon actual closure, if `Actual Booked Profit > Theoretical Profit Used`, the excess is processed through the trimming logic again using the comment `Trim`.

### 3.4 Persistence & Profit Tally

- **ProfitTally System**: Stores unspent profit (amounts too small to cover the broker's minimum lot size, e.g., 0.01) in a persistent `ProfitTally` variable.
- **JSON Persistence**: All persistent data must be saved to a JSON file: `<MagicNumber>.json`.
  - **Path**: `MQL5\Files\` (per MT5 sandbox rules).
  - **Update Frequency**: The file must be updated whenever `ProfitTally` or `PostTrimHedgePricePoint` changes.
  - **Safety**: Updates must be handled carefully to avoid data corruption of other variables in the file.
- **ProfitTally Reset**: If there are no open positions at least `HedgePips` away from the current market price (on either side), the `ProfitTally` must be reset to 0. 
- **Startup Logic**: Upon initialization, the EA must check for the existence of its `<MagicNumber>.json` file and load the stored values.

### 3.5 Squeezing the Hedge (Post-Trim Hedge Adjustment)

- **Post-Trim Balance Check**: If the volume remains unbalanced after trimming, a temporary `PostTrimHedgePricePoint` is established.
- **Calculation**: Set at `HedgePips` from the exit price of the closed profitable trade, in the direction of the required hedge.
- **Trailing Adjustment (Squeezing)**: If the price moves away from this point, the `PostTrimHedgePricePoint` must dynamically trail the price by the distance defined in `SqueezePips`.
- **Recalculation with New Entries**: If a new strategic entry occurs while a `PostTrimHedgePricePoint` is active, the hedge price point must be recalculated. It is tracked based on the current unbalanced volume and the entry price of the nearest opposite trade(s) to ensure the hedge trigger remains accurate relative to the updated balance.
- **Handover to Standard Hedging**: If a new strategic entry occurs while a `PostTrimHedgePricePoint` (Squeezing) is active, the squeezing logic must immediately hand over to standard hedging logic (Section 2.3). The hedge trigger point is then recalculated based on `HedgePips` from the nearest position.
- **Inactive State**: When no Post-Trim Hedge is required, the value in the JSON file should be maintained as a negative value.

## 4. Indicator Logic

Uses two independent sets of indicators (Strategy 1 and Strategy 2).

### 4.1 Timeframe Enumeration
All indicators must support the following timeframe options:
- M1 (PERIOD_M1)
- M5 (PERIOD_M5)
- M15 (PERIOD_M15)
- M30 (PERIOD_M30)
- H1 (PERIOD_H1)
- H4 (PERIOD_H4)
- H12 (PERIOD_H12)
- D1 (PERIOD_D1)

### 4.2 EMA Sets (EMA Periods)
Instead of individual inputs, EMA periods are driven by a single `EMAPeriods` Enum:
1. EMA_P1: 5 - 10 - 20
2. EMA_P2: 4 - 8 - 60
3. EMA_P3: 8 - 13 - 21
4. EMA_P4: 5 - 20 - 50
5. EMA_P5: 7 - 21 - 50
6. EMA_P6: 9 - 21 - 55
7. EMA_P7: 10 - 21 - 50
8. EMA_P8: 10 - 50 - 100
9. EMA_P9: 10 - 50 - 200
10. EMA_P10: 20 - 50 - 200
11. EMA_P11: 50 - 100 - 200

> [!IMPORTANT]
> The EA logic must derive the three individual EMA period values programmatically from the selected Enum value.

## 5. EA Input Parameters (Single Source of Truth)

#### Group: Position Sizing & Core Hedging
- **LotSize (Double)**: Fixed lot size for standard entries.
- **MaxLots (Double)**: Maximum directional lot limit.
- **HedgePips (Double)**: Trigger distance for defensive hedges.
- **InsidePipMultiplier (Double)**: Multiplier used to calculate `MinGapPips` (`MinGapPips = InsidePipMultiplier * HedgePips`).
- **PrioritizeStrategy (Enum)**: Strategy 1, Strategy 2. When both strategies give a signal, the one which is prioritized will be used.
- **OutsideAllowed (Enum)**: No, Both Sides, Same Direction, Against Direction. 
  - `No`: Outside trade is not allowed at all.
  - `Both Sides`: Both buy and sell allowed.
  - `Same Direction`: Only allowed in the same direction of existing trades.
  - `Against Direction`: Only allowed in opposite direction of existing trades.
- **MagicNumber (Int)**: Unique identifier for the EA instance.

#### Group: Trade Management & Trimming
- **LockProfitPips (Double)**: Profit level to trigger trailing and theoretical trimming.
- **TrailingStopPips (Double)**: Distance to trail price.
- **KeepProfitPercent (Double 0.0-1.0)**: Ratio of profit to retain vs. use for trimming.
- **IntermediateTrimPips (Double)**: Trailing distance required to trigger subsequent intermediate trims.
- **SqueezePips (Double)**: Distance used to trail the Post-Trim Hedge Price Point.

#### Group: Market/Session Filters (Flat Market Only)
- **SydneyActive (22:00 - 07:00 UTC) (Bool)**: Enable/Disable entries during Sydney session.
- **TokyoActive (00:00 - 09:00 UTC) (Bool)**: Enable/Disable entries during Tokyo session.
- **LondonActive (08:00 - 17:00 UTC) (Bool)**: Enable/Disable entries during London session.
- **NewYorkActive (13:00 - 22:00 UTC) (Bool)**: Enable/Disable entries during New York session.
- **MondayActive (Bool)** to **FridayActive (Bool)**: Individual weekday toggles.

#### Group: Strategy 1 Indicators (Trend)
- **S1Name (String)**: Default "Trend".
- **S1UseRSI (Bool)**, **S1RSITimeframe (Enum)**, **S1RSIPeriod (Int)**, **S1RSISellLevel (Double)**.
- **S1UseEMA (Bool)**, **S1EMATimeframe (Enum)**, **S1EMAPeriods (Enum)**, **S1EMATrendRule (Enum)**.
- **S1UseADX (Bool)**, **S1ADXTimeframe (Enum)**, **S1ADXPeriod (Int)**, **S1ADXThreshold (Double)**, **S1ADXTrendRule (Enum)**.
- **S1UseBB (Bool)**, **S1BBTimeframe (Enum)**, **S1BBDeviations (Double)**, **S1BBRule (Enum)**.

#### Group: Strategy 2 Indicators (Reversal)
- **S2Name (String)**: Default "Reversal".
- (Duplicate of Group 4 with **S2** prefix).

## 7. Genetic Optimization Considerations

To facilitate efficient and safe genetic optimization in MT5, the EA must adhere to the following:

### 7.1 Framework Performance
- **Handle Caching**: All indicator handles must be initialized once and cached to avoid the overhead of re-creating handles on every tick.
- **I/O Optimization**: Data persistence (SaveState) should be disabled when the EA is running in `MQL_OPTIMIZATION` mode to maximize throughput.

### 7.2 Strategy Tester Compatibility
- **Time Synchronization**: Session filters must use `TimeTradeServer()` when running in the Strategy Tester to ensure UTC-based filters align with the tester's internal clock.
- **Persistence Scope**: In live trading, state is saved to the MT5 "Common" folder. In the Strategy Tester, state must be kept local to the tester agent's folder to prevent write collisions between parallel optimization agents.

### 7.3 Custom Optimization Metrics
- The EA should implement the `OnTester()` handler to provide a custom fitness metric (e.g., Profit / Relative Drawdown) for selection in the Strategy Tester.

## 8. Coding Standards & Documentation

- **MQL5 Annotation**: The Expert Advisor code must contain very detailed, line-by-line or block-level annotations explaining the logic. 
- **PRD Alignment**: All comments and documentation within the code must strictly align with the definitions and logic described in this PRD.

## 9. Logging & Decision Transparency

To facilitate debugging and performance analysis, the EA must provide detailed, "reasoned" logs in the MetaTrader 5 Journal using `Print` or `PrintFormat`.

### 9.1 Logging Requirements

- **Trade Decisions**: Every time a trade signal is ignored or executed, the logs must explain the "why".
  - *Example*: "Indicator entry blocked: Price too close to existing position (Gap: 8.5 pips < MinGap: 10 pips)."
- **Hedge Triggers**: When a hedge or reduction is triggered, log the specific trigger point and the current market distance.
  - *Example*: "Hedge Triggered: Price 1.12345 reached standard trigger at 1.12350 (HedgePips: 20)."
- **Trailing Stops**: Log every update to a position's Stop Loss, showing the old vs. new level and the reason (Price movement).
- **Squeezing Logic**:
  - Log when a `PostTrimHedgePricePoint` is established or trailed.
  - Log the specific keyword decision ("Trailing Hedge" vs "Hedge") based on comparison with the standard trigger.
- **Trimming**: Log which position is being trimmed and the calculated distance/profit being used.
- **MaxLots & Reductions**: Explicitly log when `MaxLots` is breached and why a reduction was chosen over a hedge.
