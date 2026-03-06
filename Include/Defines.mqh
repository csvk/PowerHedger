//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Defines
   Description: Core enumerations and constant definitions for the PowerHedger EA.
   PRD Sections: 4.1 (Timeframes), 4.2 (EMA Sets).
*/

//--- PRD 4.1: Supported Timeframe Enumeration for indicator calculations
enum ENUM_TF_OPTIONS
{
   TF_M1  = PERIOD_M1,  // 1 Minute
   TF_M5  = PERIOD_M5,  // 5 Minutes
   TF_M15 = PERIOD_M15, // 15 Minutes
   TF_M30 = PERIOD_M30, // 30 Minutes
   TF_H1  = PERIOD_H1,  // 1 Hour
   TF_H4  = PERIOD_H4,  // 4 Hours
   TF_H12 = PERIOD_H12, // 12 Hours
   TF_D1  = PERIOD_D1   // 1 Day
};

//--- PRD 4.2: Predefined EMA Period Sets (Fast - Medium - Slow)
enum ENUM_EMA_SETS
{
   EMA_P1,  // 5 - 10 - 20 (Standard Scalping)
   EMA_P2,  // 4 - 8 - 60
   EMA_P3,  // 8 - 13 - 21 (Fibonacci Sequence)
   EMA_P4,  // 5 - 20 - 50
   EMA_P5,  // 7 - 21 - 50
   EMA_P6,  // 9 - 21 - 55
   EMA_P7,  // 10 - 21 - 50
   EMA_P8,  // 10 - 50 - 100
   EMA_P9,  // 10 - 50 - 200
   EMA_P10, // 20 - 50 - 200
   EMA_P11  // 50 - 100 - 200 (Long-term Trend)
};

//--- PRD 5.6: Internal Indicator Signal States for Matrix Evaluation
enum ENUM_IND_SIGNAL
{
   IND_BUY,      // Logic confirms Buy
   IND_SELL,     // Logic confirms Sell
   IND_PASS,     // Ranging condition met (Allows trade if direction provided by others)
   IND_NEUTRAL   // Condition not met (Blocks trade entry)
};

//--- EMA Trend Rules (PRD 5.6)
enum ENUM_EMA_TREND_RULE
{
   EMA_WITH_TREND,    // Trade with Trend
   EMA_AGAINST_TREND, // Trade against Trend
   EMA_RANGING        // Trade when Ranging
};

//--- ADX Trend Rules (PRD 5.6)
enum ENUM_ADX_TREND_RULE
{
   ADX_WITH_TREND,               // Trade with Trend
   ADX_WITH_TREND_AVOID_EXTREME, // Trade with Trend but avoid Extreme
   ADX_AGAINST_TREND,            // Trade against Trend
   ADX_RANGING                   // Trade when Ranging
};

//--- BB Trend Rules (PRD 5.6)
enum ENUM_BB_TREND_RULE
{
   BB_AVOID_EXTREME_TREND, // Avoid Extreme Trend
   BB_AGAINST_TREND        // Trade against Trend
};

//--- Strategy Prioritization (PRD 2.1)
enum ENUM_STRATEGY_PRIORITY
{
   STRAT_1, // Strategy 1 prioritized
   STRAT_2  // Strategy 2 prioritized
};

//--- Outside Entry Permission Rules (PRD 2.1)
enum ENUM_OUTSIDE_ALLOWED
{
   OUTSIDE_NO,              // Outside trade not allowed
   OUTSIDE_BOTH,            // Both sides allowed
   OUTSIDE_SAME_DIR,        // Only same direction as existing trades
   OUTSIDE_AGAINST_DIR      // Only opposite direction to existing trades
};

//--- Market Context for Trade Comments (PRD 2.5)
enum ENUM_MARKET_CONTEXT
{
   CONTEXT_NEW,     // Flat market
   CONTEXT_INSIDE,  // Between trades
   CONTEXT_OUTSIDE  // One-sided or outside corridor
};
