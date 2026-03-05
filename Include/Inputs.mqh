//+------------------------------------------------------------------+
//|                                                       Inputs.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Inputs
   Description: User-configurable parameters for risk, management, and strategy.
   PRD Sections: 5 (EA Input Parameters).
*/

#include "Defines.mqh"

//--- PRD 5.1: Group - Position Sizing & Core Hedging
input group "Position Sizing & Core Hedging"
input double   LotSize              = 0.10;      // Fixed lot size for individual standard entries
input double   MaxLots              = 1.0;       // Maximum total volume allowed per direction
input double   HedgePips            = 30.0;      // Tick-monitored trigger gap for defensive hedges
input double   InsidePipMultiplier  = 1.0;       // Multiplier to calculate MinGapPips (Gap = Multiplier * HedgePips)
input ENUM_OUTSIDE_ALLOWED OutsideAllowed = OUTSIDE_NO; // Permission for entries when only one side is open
input int      MagicNumber          = 123456;    // Unique identifier for the EA instance's trades

//--- PRD 5.2: Group - Trade Management & Trimming
input group "Trade Management & Trimming"
input double   LockProfitPips       = 10.0;      // Profit distance to activate trailing stop and trimming
input double   TrailingStopPips     = 5.0;       // Distance to trail price for profit locking
input double   KeepProfitPercent    = 0.2;       // Ratio (0.0-1.0) of profit to KEEEP (e.g., 0.2 means 80% used for trim)
input double   IntermediateTrimPips = 10.0;      // Locked Profit increment for subsequent intermediate trims
input double   SqueezePips          = 1.0;       // Distance to trail the Post-Trim Hedge Price Point

//--- PRD 5.3: Group - Market/Session Filters (Flat Market Only)
input group "Market/Session Filters (Flat Market Only)"
input bool     SydneyActive         = true;      // Enable entries during Sydney session (22:00 - 07:00 UTC)
input bool     TokyoActive          = true;      // Enable entries during Tokyo session (00:00 - 09:00 UTC)
input bool     LondonActive         = true;      // Enable entries during London session (08:00 - 17:00 UTC)
input bool     NewYorkActive        = true;      // Enable entries during New York session (13:00 - 22:00 UTC)
input bool     MondayActive         = true;      // Enable trading on Monday
input bool     TuesdayActive        = true;      // Enable trading on Tuesday
input bool     WednesdayActive      = true;      // Enable trading on Wednesday
input bool     ThursdayActive       = true;      // Enable trading on Thursday
input bool     FridayActive         = true;      // Enable trading on Friday

//--- Strategy Configuration
input group "Strategy Priority & Random Mode"
input bool     EnableRandom         = true;      // If true, Random takes priority. Else S1/S2 priority applies.
input int      RandomSeed           = 12345;     // Random generator seed for testing
input ENUM_STRATEGY_PRIORITY PrioritizeStrategy = STRAT_1; // Prioritized strategy when both give signals

//--- PRD 5.4: Group - Strategy 1 Indicators (Trend)
input group "Strategy 1 Indicators (Trend)"
input string          S1Name            = "Trend";
input bool            S1UseRSI          = true;  // Strategy 1: Use Relative Strength Index
input ENUM_TF_OPTIONS S1RSITimeframe    = TF_M15;
input int             S1RSIPeriod       = 14;
input double          S1RSISellLevel    = 70.0;  // Threshold for Sell signal (Buy = 100 - SellLevel)

input bool            S1UseEMA          = true;  // Strategy 1: Use Exponential Moving Averages
input ENUM_TF_OPTIONS S1EMATimeframe    = TF_M15;
input ENUM_EMA_SETS   S1EMAPeriods      = EMA_P1;
input ENUM_TREND_RULE S1EMATrendRule    = RULE_ALIGNMENT;

input bool            S1UseADX          = false; // Strategy 1: Use Average Directional Index
input ENUM_TF_OPTIONS S1ADXTimeframe    = TF_M15;
input int             S1ADXPeriod       = 14;
input double          S1ADXThreshold    = 25.0;
input ENUM_TREND_RULE S1ADXTrendRule    = RULE_CROSS_LEVEL;

input bool            S1UseBB           = false; // Strategy 1: Use Bollinger Bands
input ENUM_TF_OPTIONS S1BBTimeframe     = TF_M15;
input double          S1BBDeviations    = 2.0;
input ENUM_BB_RULE    S1BBRule          = BB_TOUCH_OUTSIDE;

//--- PRD 5.5: Group - Strategy 2 Indicators (Reversal)
input group "Strategy 2 Indicators (Reversal)"
input string          S2Name            = "Reversal";
input bool            S2UseRSI          = true;
input ENUM_TF_OPTIONS S2RSITimeframe    = TF_M5;
input int             S2RSIPeriod       = 14;
input double          S2RSISellLevel    = 70.0;

input bool            S2UseEMA          = true;
input ENUM_TF_OPTIONS S2EMATimeframe    = TF_M5;
input ENUM_EMA_SETS   S2EMAPeriods      = EMA_P3;
input ENUM_TREND_RULE S2EMATrendRule    = RULE_ALIGNMENT;

input bool            S2UseADX          = false;
input ENUM_TF_OPTIONS S2ADXTimeframe    = TF_M5;
input int             S2ADXPeriod       = 14;
input double          S2ADXThreshold    = 25.0;
input ENUM_TREND_RULE S2ADXTrendRule    = RULE_CROSS_LEVEL;

input bool            S2UseBB           = false;
input ENUM_TF_OPTIONS S2BBTimeframe     = TF_M5;
input double          S2BBDeviations    = 2.0;
input ENUM_BB_RULE    S2BBRule          = BB_TOUCH_OUTSIDE;
