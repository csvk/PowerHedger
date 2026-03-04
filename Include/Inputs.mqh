//+------------------------------------------------------------------+
//|                                                       Inputs.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include "Defines.mqh"

// Group 1: Position Sizing & Core Hedging (PRD 5.1)
input double   LotSize              = 0.01;      // Fixed Lot Size for standard entries
input double   MaxLots              = 10.0;      // Maximum directional lot limit
input double   HedgePips            = 30.0;      // Trigger distance for defensive hedges
input double   InsidePipMultiplier  = 2.0;       // Multiplier for MinGapPips calculation
input int      MagicNumber          = 123456;    // Unique identifier for the EA instance

// Group 2: Trade Management & Trimming (PRD 5.2)
input double   LockProfitPips       = 10.0;      // Profit level to trigger trailing and trimming
input double   TrailingStopPips     = 5.0;       // Distance to trail price
input double   KeepProfitPercent    = 0.2;       // Ratio of profit to retain (0.0-1.0)
input double   SqueezePips          = 5.0;       // Distance used to trail Post-Trim Hedge Point

// Group 3: Market/Session Filters (Flat Market Only) (PRD 5.3)
input bool     SydneyActive         = true;      // 22:00 - 07:00 UTC
input bool     TokyoActive          = true;      // 00:00 - 09:00 UTC
input bool     LondonActive         = true;      // 08:00 - 17:00 UTC
input bool     NewYorkActive        = true;      // 13:00 - 22:00 UTC
input bool     MondayActive         = true;      // Tuesday to Friday Active
input bool     TuesdayActive        = true;
input bool     WednesdayActive      = true;
input bool     ThursdayActive       = true;
input bool     FridayActive         = true;

// Group 4: Strategy 1 Indicators (PRD 5.4)
input bool            S1UseRSI          = true;
input ENUM_TF_OPTIONS S1RSITimeframe    = TF_M15;
input int             S1RSIPeriod       = 14;
input double          S1RSISellLevel    = 70.0;     // Buy level = 100 - SellLevel

input bool            S1UseEMA          = true;
input ENUM_TF_OPTIONS S1EMATimeframe    = TF_M15;
input ENUM_EMA_SETS   S1EMAPeriods      = EMA_P1;
input ENUM_TREND_RULE S1EMATrendRule    = RULE_ALIGNMENT;

input bool            S1UseADX          = false;
input ENUM_TF_OPTIONS S1ADXTimeframe    = TF_M15;
input int             S1ADXPeriod       = 14;
input double          S1ADXThreshold    = 25.0;
input ENUM_TREND_RULE S1ADXTrendRule    = RULE_CROSS_LEVEL;

input bool            S1UseBB           = false;
input ENUM_TF_OPTIONS S1BBTimeframe     = TF_M15;
input double          S1BBDeviations    = 2.0;
input ENUM_BB_RULE    S1BBRule          = BB_TOUCH_OUTSIDE;

// Group 5: Strategy 2 Indicators (PRD 5.5)
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
