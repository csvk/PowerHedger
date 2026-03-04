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

//--- Indicator Trend Rules logic (PRD 1.8 Alignment)
enum ENUM_TREND_RULE
{
   RULE_CROSS_LEVEL, // Signal on level crossover (e.g., RSI 70/30, ADX 25)
   RULE_ALIGNMENT   // Signal on stacked moving average alignment
};

//--- Bollinger Band Interaction Rules
enum ENUM_BB_RULE
{
   BB_TOUCH_OUTSIDE, // Signal when price touches or crosses the outer band
   BB_REVERSAL       // Signal on price rejection towards the midline
};
