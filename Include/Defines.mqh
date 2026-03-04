//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

// Timeframe Enumeration (PRD 4.1)
enum ENUM_TF_OPTIONS
{
   TF_M1  = PERIOD_M1,  // M1
   TF_M5  = PERIOD_M5,  // M5
   TF_M15 = PERIOD_M15, // M15
   TF_M30 = PERIOD_M30, // M30
   TF_H1  = PERIOD_H1,  // H1
   TF_H4  = PERIOD_H4,  // H4
   TF_H12 = PERIOD_H12, // H12
   TF_D1  = PERIOD_D1   // D1
};

// EMA Periods Sets (PRD 4.2)
enum ENUM_EMA_SETS
{
   EMA_P1,  // 5 - 10 - 20
   EMA_P2,  // 4 - 8 - 60
   EMA_P3,  // 8 - 13 - 21
   EMA_P4,  // 5 - 20 - 50
   EMA_P5,  // 7 - 21 - 50
   EMA_P6,  // 9 - 21 - 55
   EMA_P7,  // 10 - 21 - 50
   EMA_P8,  // 10 - 50 - 100
   EMA_P9,  // 10 - 50 - 200
   EMA_P10, // 20 - 50 - 200
   EMA_P11  // 50 - 100 - 200
};

// Indicator Trend Rules (Assumptions 1)
enum ENUM_TREND_RULE
{
   RULE_CROSS_LEVEL, // Cross Level (RSI/ADX)
   RULE_ALIGNMENT   // Stacked Alignment (EMA)
};

// Bollinger Band Rules
enum ENUM_BB_RULE
{
   BB_TOUCH_OUTSIDE, // Touch/Cross Outside Band
   BB_REVERSAL       // Reversal inside Band
};
