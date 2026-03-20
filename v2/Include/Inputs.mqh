#ifndef _INPUTS_MQH_
#define _INPUTS_MQH_

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

//--- PRD 3.1: Group - General
input group "General"
input int      BaseMagicNumber      = 1000;      // Base Magic Number (Sequence ID will be added)

//--- PRD 4.1: Group - Position Sizing & Core Hedging
input group "Position Sizing & Core Hedging"
input double   LotSize              = 0.10;      // Lot Size
input double   MaxLots              = 1.0;       // Max Lots per direction (Chart Level)
input double   HedgePips            = 30.0;      // Hedge Pips (Symmetrical Trigger)

//--- PRD 5.1: Group - Trade Management & Trimming
input group "Trade Management & Trimming"
input double   LockProfitPips       = 10.0;      // Lock Profit Pips (Activate Trailing SL - Relative to HedgePips)
input double   KeepProfitPercent    = 50.0;      // Keep Profit Percent (Trimming Fund portion)
input double   TrailingStopPips     = 5.0;       // Trailing Stop Pips

//--- PRD 5.4: Group - Pyramiding Positions
input group "Pyramiding Positions"
input bool     PyramidAllowed       = false;     // Pyramiding Allowed
input double   PyramidRiskPercent   = 10.0;      // Pyramid Risk Percent (of secured profit)
input double   PyramidPips          = 10.0;      // Pyramid Pips (Spacing between additional entries)

//--- PRD 2.3: Group - Market/Session Filters (Entry Only)
input group "Market Session Filters (Entry Only)"
input bool     SydneyActive         = true;      // Allow Sydney session
input bool     TokyoActive          = true;      // Allow Tokyo session
input bool     LondonActive         = true;      // Allow London session
input bool     NewYorkActive        = true;      // Allow New York session

input group "Market Day Filters (Entry Only)"
input bool     MondayActive         = true;      // Allow Monday
input bool     TuesdayActive        = true;      // Allow Tuesday
input bool     WednesdayActive      = true;      // Allow Wednesday
input bool     ThursdayActive       = true;      // Allow Thursday
input bool     FridayActive         = true;      // Allow Friday

//--- Strategy Configuration
input group "Strategy Priority & Random Mode"
input bool     EnableRandom         = false;     // Prioritize Random (For Testing)
input int      RandomSeed           = 12345;     // Random Seed
input ENUM_STRATEGY_PRIORITY PrioritizeStrategy = PRIORITY_S1_S2_S3; // Strategy Priority

//--- PRD 2.2: Group - Strategy 1 Indicator
input group "=============== Strategy 1 ==============="
input string          S1Name            = "Trend"; // Strategy Name
input bool            S1UseStrategy     = true;    // Use Strategy 1

input group "S1 RSI Rules"
input bool            S1UseRSI          = true;    // Use RSI
input ENUM_TF_OPTIONS S1RSITimeframe    = TF_M15;  // RSI Timeframe
input int             S1RSIPeriod       = 14;      // RSI Period
input double          S1RSISellLevel    = 70.0;    // Sell Level (Buy = 100 - SellLevel)
input ENUM_RSI_TREND_RULE S1RSITrendRule = RSI_AGAINST_TREND; // RSI Trend Rule

input group "S1 EMA Rules"
input bool            S1UseEMA          = true;    // Use EMA
input ENUM_TF_OPTIONS S1EMATimeframe    = TF_M15;  // EMA Timeframe
input ENUM_EMA_SETS   S1EMAPeriods      = EMA_P1;  // EMA Periods (Fast - Mid - Slow)
input ENUM_EMA_TREND_RULE S1EMATrendRule = EMA_WITH_TREND; // EMA Trend Rule

input group "S1 ADX Rules"
input bool            S1UseADX          = true;    // Use ADX
input ENUM_TF_OPTIONS S1ADXTimeframe    = TF_M15;  // ADX Timeframe
input int             S1ADXPeriod       = 14;      // ADX Period
input double          S1ADXTrendLevel   = 25.0;      // ADX Trend Level
input double          S1ADXExtremeLevel = 45.0;      // ADX Extreme Level
input double          S1ADXRangeLevel   = 20.0;      // ADX Range Level
input ENUM_ADX_TREND_RULE S1ADXTrendRule = ADX_WITH_TREND; // ADX Trend Rule

input group "S1 Bollinger Band Rules"
input bool            S1UseBB           = true;    // Use Bollinger Bands
input ENUM_TF_OPTIONS S1BBTimeframe     = TF_M15;  // BB Timeframe
input double          S1BBDeviations    = 2.0;     // BB Deviations
input ENUM_BB_TREND_RULE S1BBRule       = BB_AVOID_EXTREME_TREND; // BB Rule

//--- PRD 2.2: Group - Strategy 2 Indicators
input group "=============== Strategy 2 ==============="
input string          S2Name            = "Reversal"; // Strategy Name
input bool            S2UseStrategy     = true;    // Use Strategy 2

input group "S2 RSI Rules"
input bool            S2UseRSI          = true;    // Use RSI
input ENUM_TF_OPTIONS S2RSITimeframe    = TF_M5;   // RSI Timeframe
input int             S2RSIPeriod       = 14;      // RSI Period
input double          S2RSISellLevel    = 70.0;    // Sell Level (Buy = 100 - SellLevel)
input ENUM_RSI_TREND_RULE S2RSITrendRule = RSI_AGAINST_TREND; // RSI Trend Rule

input group "S2 EMA Rules"
input bool            S2UseEMA          = true;    // Use EMA
input ENUM_TF_OPTIONS S2EMATimeframe    = TF_M5;   // EMA Timeframe
input ENUM_EMA_SETS   S2EMAPeriods      = EMA_P3;  // EMA Periods (Fast - Mid - Slow)
input ENUM_EMA_TREND_RULE S2EMATrendRule = EMA_WITH_TREND; // EMA Trend Rule

input group "S2 ADX Rules"
input bool            S2UseADX          = true;    // Use ADX
input ENUM_TF_OPTIONS S2ADXTimeframe    = TF_M5;   // ADX Timeframe
input int             S2ADXPeriod       = 14;      // ADX Period
input double          S2ADXTrendLevel   = 25.0;      // ADX Trend Level
input double          S2ADXExtremeLevel = 45.0;      // ADX Extreme Level
input double          S2ADXRangeLevel   = 20.0;      // ADX Range Level
input ENUM_ADX_TREND_RULE S2ADXTrendRule = ADX_WITH_TREND; // ADX Trend Rule

input group "S2 Bollinger Band Rules"
input bool            S2UseBB           = true;    // Use Bollinger Bands
input ENUM_TF_OPTIONS S2BBTimeframe     = TF_M5;   // BB Timeframe
input double          S2BBDeviations    = 2.0;     // BB Deviations
input ENUM_BB_TREND_RULE S2BBRule       = BB_AGAINST_TREND; // BB Rule

//--- PRD 2.2: Group - Strategy 3 Indicators
input group "=============== Strategy 3 ==============="
input string          S3Name            = "Ranging"; // Strategy Name
input bool            S3UseStrategy     = true;    // Use Strategy 3

input group "S3 RSI Rules"
input bool            S3UseRSI          = true;    // Use RSI
input ENUM_TF_OPTIONS S3RSITimeframe    = TF_M5;   // RSI Timeframe
input int             S3RSIPeriod       = 14;      // RSI Period
input double          S3RSISellLevel    = 70.0;    // Sell Level (Buy = 100 - SellLevel)
input ENUM_RSI_TREND_RULE S3RSITrendRule = RSI_AGAINST_TREND; // RSI Trend Rule

input group "S3 EMA Rules"
input bool            S3UseEMA          = true;    // Use EMA
input ENUM_TF_OPTIONS S3EMATimeframe    = TF_M5;   // EMA Timeframe
input ENUM_EMA_SETS   S3EMAPeriods      = EMA_P3;  // EMA Periods (Fast - Mid - Slow)
input ENUM_EMA_TREND_RULE S3EMATrendRule = EMA_RANGING; // EMA Trend Rule

input group "S3 ADX Rules"
input bool            S3UseADX          = true;    // Use ADX
input ENUM_TF_OPTIONS S3ADXTimeframe    = TF_M5;   // ADX Timeframe
input int             S3ADXPeriod       = 14;      // ADX Period
input double          S3ADXTrendLevel   = 25.0;      // ADX Trend Level
input double          S3ADXExtremeLevel = 45.0;      // ADX Extreme Level
input double          S3ADXRangeLevel   = 20.0;      // ADX Range Level
input ENUM_ADX_TREND_RULE S3ADXTrendRule = ADX_RANGING; // ADX Trend Rule

input group "S3 Bollinger Band Rules"
input bool            S3UseBB           = true;    // Use Bollinger Bands
input ENUM_TF_OPTIONS S3BBTimeframe     = TF_M5;   // BB Timeframe
input double          S3BBDeviations    = 2.0;     // BB Deviations
input ENUM_BB_TREND_RULE S3BBRule       = BB_AVOID_EXTREME_TREND; // BB Rule


#endif // _INPUTS_MQH_
