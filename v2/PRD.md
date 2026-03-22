# Product Requirements Document (PRD) v2: Symmetrical Hedging & Sequence Management

## 1. Product Overview

PowerHedger v2 is a high-performance MetaTrader 5 Expert Advisor (EA) designed for professional-grade risk management through **Symmetrical Sequence Isolation**. Unlike traditional hedging systems that unbalance positions to recover, v2 treats every hedged pair as a "Locked Sequence"—a fixed liability that is systematically reduced using profits from independent trade cycles.

The core objective is to prevent runaway drawdowns by ensuring that once a risk threshold is hit, the exposure is locked perfectly and only reduced symmetrically, maintaining a zero-sum delta for that specific sequence.

---

## 2. Core Trading Logic

### 2.1 Entry Strategy & Filters
The EA identifies trade opportunities using a combination of technical indicators but operates under a strict isolation rule.

- **One-Active-Trade Rule**: At any given time, only **one** Active (unhedged) trade is permitted on the chart.
    - An Active trade must either:
        1. Close in profit (via Trailing SL).
        2. Reach the hedge trigger distance (becoming a Locked Sequence).
    - Only then will the EA look for a new signal to open another trade.
- **Entry Rules**: High-probability signals are derived from Strategy 1 (Trend), Strategy 2 (Reversal), or Random (for testing).
- **Session & Weekday Filters**: Entries are subject to configurable Sydney, Tokyo, London, and New York session windows and specific weekdays.
- **No Distance Rule**: There is no minimum distance requirement (`MinPipGap`) between a new signal and existing hedged trades.

### 2.2 Indicator Logic & Combination Matrix

The EA uses a "Universal Alignment" principle.
1.  **Strict Rule Alignment**: If an indicator rule is directional (`WITH_TREND`, `AGAINST_TREND`, `AVOID_EXTREME`), it must produce the required direction. If it doesn't, it returns `NEUTRAL`, which **blocks** the trade.
2.  **Pass Allowance**: Only rules explicitly defined as `RANGING` can return a `PASS` state. `PASS` allows the trade to proceed if **other** indicators provide a clear direction.

#### Individual Indicator Outputs
| Indicator | Selected Rule | Result: BUY | Result: SELL | Result: PASS | Result: NEUTRAL |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RSI** | `AGAINST_TREND` | Crossover < 30 | Crossover > 70 | N/A | Else (Blocks) |
| **RSI** | `WITH_TREND` | Crossover > 70 | Crossover < 30 | N/A | Else (Blocks) |
| **EMA** | `WITH_TREND` | Fast > Mid > Slow | Fast < Mid < Slow | N/A | Else (Blocks) |
| **EMA** | `AGAINST_TREND` | Fast < Mid < Slow | Fast > Mid > Slow | N/A | Else (Blocks) |
| **EMA** | `RANGING` | N/A | N/A | Not Aligned | Aligned (Blocks) |
| **ADX** | `WITH_TREND` | ADX > Trend, +DI > -DI | ADX > Trend, -DI > +DI | N/A | Else (Blocks) |
| **ADX** | `AVOID_EXTREME` | Extreme > ADX > Trend, +DI > -DI | Extreme > ADX > Trend, -DI > +DI | N/A | Else (Blocks) |
| **ADX** | `AGAINST_TREND` | ADX > Extreme, -DI > +DI | ADX > Extreme, +DI > -DI | N/A | Else (Blocks) |
| **ADX** | `RANGING` | N/A | N/A | ADX < Range | Else (Blocks) |
| **ADX** | `EXTREME_ONLY` | ADX >= Extreme, +DI > -DI | ADX >= Extreme, -DI > +DI | N/A | Else (Blocks) |
| **BB** | `AVOID_EXTREME` | N/A | N/A | Lower < Price < Upper | Else (Blocks) |
| **BB** | `AGAINST_TREND` | Price <= Lower Band | Price >= Upper Band | N/A | Else (Blocks) |
| **BB** | `EXTREME_ONLY` | Price >= Upper Band | Price <= Lower Band | N/A | Else (Blocks) |

#### Directional Determination Policy
1.  Collect output from all `Use = True` indicators.
2.  If any indicator returns `NEUTRAL` (failed directional condition), discard signal.
3.  If any indicators return `BUY` and others return `SELL`, discard signal (Conflict).
4.  At least one indicator must provide a `BUY` or `SELL` output (All `PASS` = No Trade).
5.  A signal is only valid if all non-pass outputs are in the same direction.

---

## 3. Sequence & Magic Number Management

### 3.1 Sequence Isolation
Every trade cycle is isolated via a unique Magic Number.
- **BaseMagicNumber (Int)**: The root identifier (e.g., 1000).
- **SequenceID (Persistent Int)**: Increments for every new initial trade.
- **ID Assignment**: `UniqueMagic = BaseMagicNumber + SequenceID`.
- **Hedge Matching**: When an active trade is hedged, the protective position is opened with the **exact same UniqueMagic**.

### 3.2 Manual Trade Adoption
- **Scope**: The EA manages all trades opened manually (where `Magic == 0`) for the **same symbol** as the EA.
- **Adoption Process**:
    1. The EA scans all open positions on the account for the current symbol.
    2. Any position with `Magic == 0` is identified.
    3. The EA assigns a unique `SequenceID` to this ticket and stores the ticket-to-magic mapping in its persistent JSON file.
    4. **Management**: Once adopted, these positions are managed exactly like signal entries (Trailing Stops, Hedging, and Trimming).
    5. **Hedge Execution**: If a manual trade needs a hedge, the EA will open the hedge with the assigned `SequenceID`.

---

## 4. Risk Management: Hedging & Lockdown

### 4.1 Symmetrical Hedging
- **HedgePips (Double)**: The pip distance from the entry of an unbalanced position required to trigger a hedge.
- **Execution**: When price breaches `HedgePips`, a Market Order is opened for the exact missing volume to reach a perfectly balanced state (Buy Lots == Sell Lots).
- **Lockdown State**: Once balanced, the Sequence is "Locked". 
    - **No Trailing Stop**: All trailing functionality is disabled for Locked positions.
    - **Invariant Exposure**: The net lot size of the sequence remains 0 until a symmetrical trim occurs.

### 4.2 Chart-Level Limits
- **MaxLots (Double)**: The maximum total lot size allowed in one direction (Total Buy or Total Sell) across ALL Magic Numbers for this chart.
- If a new entry or hedge would breach `MaxLots`, the action is blocked.

---

## 5. Trade Management & Symmetrical Trimming

Efficient debt reduction via profit harvesting.

### 5.1 Active Trade Management
- [NEW] **HarvestsProfitPercent**: Percentage of realized/floating profit redirected to the `ProfitTally` (e.g., 50% used for trimming, 50% saved as equity).
- **LockProfitPips**: The profit level required to activate the Trailing SL. This is **relative to HedgePips** (Effective Lock Profit = HedgePips + LockProfitPips).
- **TrailingStopPips**: The distance used to trail the price.

### 5.2 Symmetrical Trimming Algorithm
"Trimming" is the process of closing equal volumes of the Buy and Sell legs of a Locked Sequence simultaneously.

- **Trimming Fund Sources**:
    1. **Booked Profit (At Close)**: When an active trade closes in profit, the total realized profit is calculated. A portion (`HarvestsProfitPercent`) of this profit is added to `ProfitTally` and immediately used to attempt a trim.
- **Conditional Harvesting**: Profit is ONLY added to `ProfitTally` or used for trims when a trade closes and there is at least one **Locked Sequence** on the chart at that exact moment.
- **Post-Trim Reduction**: Trimming equal volume from both legs results in two closed deals: one historically profitable, the other at a loss. The `ProfitTally` is updated strictly using the actual realized net PnL (profit + swap + commission) generated by these history deals *after* they are closed, ensuring the tally reflects the true exact account equity impact without theoretical drift.
- **Target Selection (Farthest Mid-Price)**:
    - Calculation: `MidPrice = (Entry_Buy + Entry_Sell) / 2`.
    - The EA always targets the Locked Sequence where the `MidPrice` is the numerically farthest from the current market price.
- **Profit Tally**: Unspent profit (below min lot size cost) is stored in a persistent `ProfitTally` JSON file.

### 5.3 Capitulation Rule
- If the total lot size or risk threshold is reached, the EA executes a **Capitulation**: fully closing the Locked Sequence with the **farthest Mid-Price** at a market loss.

### 5.4 Pyramiding Positions
Pyramiding allows adding more positions to an existing winning trade when profit is secured via Trailing SL.

- **Pyramiding Allowed (Bool)**: Enables adding additional positions.
- **Pyramid Risk Percent (Double)**: Percentage of secured profit to risk for each new position.
- **Pyramid Pips (Double)**: The distance the Stop Loss must move from its level at the previous pyramid entry before another position is allowed.
- **First Pyramid Condition**:
    - Active trade exists and has a Stop Loss set.
    - Stop Loss must be in profit (SL > Entry for Buy, SL < Entry for Sell).
- **Subsequent Pyramid Condition**:
    - Current Stop Loss has moved by at least `Pyramid Pips` from the SL price at the time of the last pyramid entry.
- **Risk Calculation**:
    - **TotalSecuredProfit**: The sum of profit locked by the current Stop Loss for **ALL** unhedged positions in the sequence.
        - `PositionSecuredProfit = ABS(StopLoss - PositionEntryPrice) * PositionVolume * TickValue`.
        - `TotalSecuredProfit = Σ (PositionSecuredProfit)`.
    - **RiskAmount**:
        - If **No Locked Sequences** exist on the chart: `RiskAmount = TotalSecuredProfit * (PyramidRiskPercent / 100)`.
        - If **Locked Sequences** exist: `RiskAmount = (TotalSecuredProfit * (1 - HarvestsProfitPercent / 100)) * (PyramidRiskPercent / 100)`.
- **Position Sizing**:
    - `PyramidLotSize = RiskAmount / (ABS(CurrentPrice - StopLoss) * TickValue)`.
    - If `PyramidLotSize < 0.01`, the trade is not entered.
- **Trade Attributes**:
    - **Magic Number**: Same as the original position.
    - **Stop Loss**: Always synced with the original position's current SL.
    - **Trailing Stop**: When the Trailing Stop triggers for the original position, it simultaneously updates the SL for all other unhedged positions in the same sequence.
    - **Tally**: Closed pyramid positions contribute to the `ProfitTally` and `UnharvestedProfit` in the same way as original positions.

---

## 6. Persistence & Logging

- **MagicNumber.json**: Stores `SequenceID`, `ProfitTally`, and `ManualTicketMaps`. 
- **Journal Categories**:
    - **[SIGNAL]**: New sequence identification.
    - **[MANUAL]**: Manual trade integration (adopting Magic 0 trades for the same symbol).
    - **[HEDGE]**: Sequence lockdown event.
    - **[TRIM]**: Debt reduction details (Profit used, volumes closed).
    - **[CAPITULATION]**: Emergency margin recovery.
    - **[PYRAMID]**: Pyramid entry details (Secured Profit, Risk Amount, Lot Size, SL level).
    - **[TRAILING]**: Updates to SL for Active trades.

---

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
