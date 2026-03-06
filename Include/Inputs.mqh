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

//--- PRD 5.0: Group - General
input group "General"
input int      MagicNumber          = 123456;    // Magic Number

//--- PRD 5.1: Group - Position Sizing & Core Hedging
input group "Position Sizing & Core Hedging"
input double   LotSize              = 0.10;      // Lot Size
input double   MaxLots              = 1.0;       // Max Lots per direction
input double   HedgePips            = 30.0;      // Hedge Pips
input double   MinPipGapMultiplier  = 1.0;       // Min Gap Multiplier
input ENUM_OUTSIDE_ALLOWED OutsideAllowed = OUTSIDE_NO; // Allow Signal entries when only one side is open

//--- PRD 5.2: Group - Trade Management & Trimming
input group "Trade Management & Trimming"
input double   LockProfitPips       = 10.0;      // Lock Profit Pips
input double   TrailingStopPips     = 5.0;       // Trailing Stop Pips
input double   KeepProfitPercent    = 0.2;       // Keep Profit Percent
input double   IntermediateTrimPips = 10.0;      // Intermediate Trim Pips
input double   SqueezePips          = 1.0;       // Trailing Squeeze Pips

//--- PRD 5.3: Group - Market/Session Filters (Flat Market Only)
input group "Market Session Filters (Flat Market Only)"
input bool     SydneyActive         = true;      // Allow Sydney session
input bool     TokyoActive          = true;      // Allow Tokyo session
input bool     LondonActive         = true;      // Allow London session
input bool     NewYorkActive        = true;      // Allow New York session

input group "Market Day Filters (Flat Market Only)"
input bool     MondayActive         = true;      // Allow Monday
input bool     TuesdayActive        = true;      // Allow Tuesday
input bool     WednesdayActive      = true;      // Allow Wednesday
input bool     ThursdayActive       = true;      // Allow Thursday
input bool     FridayActive         = true;      // Allow Friday

//--- Strategy Configuration
input group "Strategy Priority & Random Mode"
input bool     EnableRandom         = true;      // Prioritize Random
input int      RandomSeed           = 12345;     // Random Seed
input ENUM_STRATEGY_PRIORITY PrioritizeStrategy = STRAT_1; // Strategy Priority

//--- PRD 5.4: Group - Strategy 1 Indicators
input group "=============== Strategy 1 Configuration ==============="
input string          S1Name            = "Trend"; // Strategy Name

input group "S1 RSI Rules"
input bool            S1UseRSI          = true;    // Use RSI
input ENUM_TF_OPTIONS S1RSITimeframe    = TF_M15;  // RSI Timeframe
input int             S1RSIPeriod       = 14;      // RSI Period
input double          S1RSISellLevel    = 70.0;    // Sell Level (Buy = 100 - SellLevel)

input group "S1 EMA Rules"
input bool            S1UseEMA          = true;    // Use EMA
input ENUM_TF_OPTIONS S1EMATimeframe    = TF_M15;  // EMA Timeframe
input ENUM_EMA_SETS   S1EMAPeriods      = EMA_P1;  // EMA Periods (Fast - Mid - Slow)
input ENUM_EMA_TREND_RULE S1EMATrendRule = EMA_WITH_TREND; // EMA Trend Rule

input group "S1 ADX Rules"
input bool            S1UseADX          = false;   // Use ADX
input ENUM_TF_OPTIONS S1ADXTimeframe    = TF_M15;  // ADX Timeframe
input int             S1ADXPeriod       = 14;      // ADX Period
input double          S1ADXTrendLevel   = 25.0;      // ADX Trend Level (Rule: With Trend)
input double          S1ADXExtremeLevel = 45.0;      // ADX Extreme Level (Rule: Against Trend)
input double          S1ADXRangeLevel   = 20.0;      // ADX Range Level (Rule: Ranging)
input ENUM_ADX_TREND_RULE S1ADXTrendRule = ADX_WITH_TREND; // ADX Trend Rule

input group "S1 Bollinger Band Rules"
input bool            S1UseBB           = false;   // Use Bollinger Bands
input ENUM_TF_OPTIONS S1BBTimeframe     = TF_M15;  // BB Timeframe
input double          S1BBDeviations    = 2.0;     // BB Deviations
input double          S1BBBufferPips    = 2.0;       // Bollinger Buffer Pips
input ENUM_BB_TREND_RULE S1BBRule       = BB_AGAINST_TREND; // BB Rule

//--- PRD 5.5: Group - Strategy 2 Indicators
input group "=============== Strategy 2 Configuration ==============="
input string          S2Name            = "Reversal"; // Strategy Name

input group "S2 RSI Rules"
input bool            S2UseRSI          = true;    // Use RSI
input ENUM_TF_OPTIONS S2RSITimeframe    = TF_M5;   // RSI Timeframe
input int             S2RSIPeriod       = 14;      // RSI Period
input double          S2RSISellLevel    = 70.0;    // Sell Level (Buy = 100 - SellLevel)

input group "S2 EMA Rules"
input bool            S2UseEMA          = true;    // Use EMA
input ENUM_TF_OPTIONS S2EMATimeframe    = TF_M5;   // EMA Timeframe
input ENUM_EMA_SETS   S2EMAPeriods      = EMA_P3;  // EMA Periods (Fast - Mid - Slow)
input ENUM_EMA_TREND_RULE S2EMATrendRule = EMA_WITH_TREND; // EMA Trend Rule

input group "S2 ADX Rules"
input bool            S2UseADX          = false;   // Use ADX
input ENUM_TF_OPTIONS S2ADXTimeframe    = TF_M5;   // ADX Timeframe
input int             S2ADXPeriod       = 14;      // ADX Period
input double          S2ADXTrendLevel   = 25.0;      // ADX Trend Level (Rule: With Trend)
input double          S2ADXExtremeLevel = 45.0;      // ADX Extreme Level (Rule: Against Trend)
input double          S2ADXRangeLevel   = 20.0;      // ADX Range Level (Rule: Ranging)
input ENUM_ADX_TREND_RULE S2ADXTrendRule = ADX_WITH_TREND; // ADX Trend Rule

input group "S2 Bollinger Band Rules"
input bool            S2UseBB           = false;   // Use Bollinger Bands
input ENUM_TF_OPTIONS S2BBTimeframe     = TF_M5;   // BB Timeframe
input double          S2BBDeviations    = 2.0;     // BB Deviations
input double          S2BBBufferPips    = 2.0;       // Bollinger Buffer Pips
input ENUM_BB_TREND_RULE S2BBRule       = BB_AGAINST_TREND; // BB Rule
