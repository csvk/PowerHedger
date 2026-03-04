//+------------------------------------------------------------------+
//|                                                PowerHedger.mq5    |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Souvik Chanda"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict

// Include modular files
#include "Include\Defines.mqh"
#include "Include\Inputs.mqh"
#include "Include\Globals.mqh"
#include "Include\Utilities.mqh"
#include "Include\Persistence.mqh"
#include "Include\TradeLogic.mqh"

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set magic number
   m_trade.SetExpertMagicNumber(MagicNumber);
   
   // Initialize symbol info
   if(!m_symbol.Name(_Symbol)) return(INIT_FAILED);
   m_symbol.RefreshRates();
   
   // Setup persistence filename
   g_fileName = IntegerToString(MagicNumber) + ".json";
   
   // Load state from file
   LoadState();
   
   // Initial volume calculation
   CalculateBalances();
   
   // Seed random generator for testing
   MathSrand((uint)GetTickCount());
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveState();
   
   IndicatorRelease(g_hRSI1); IndicatorRelease(g_hEMA1_F); IndicatorRelease(g_hEMA1_M); IndicatorRelease(g_hEMA1_S);
   IndicatorRelease(g_hADX1); IndicatorRelease(g_hBB1);
   IndicatorRelease(g_hRSI2); IndicatorRelease(g_hEMA2_F); IndicatorRelease(g_hEMA2_M); IndicatorRelease(g_hEMA2_S);
   IndicatorRelease(g_hADX2); IndicatorRelease(g_hBB2);
}

//+------------------------------------------------------------------+
//| Tick event handler                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Refresh symbol data
   if(!m_symbol.RefreshRates()) return;
   
   // 2. Trailing Stops and Theoretical Trimming
   ManageOpenPositions();
   
   // 3. Post-Trim Squeezing Logic
   ManageHedgeSqueeze();
   
   // 4. Hedging Logic (Per Tick Monitoring)
   CheckHedgeTriggers();
   
   // 5. Indicator Entry Logic (Conditional Invocation)
   CheckNewEntries();
}

//+------------------------------------------------------------------+
//| Trade Event Calculation                                          |
//+------------------------------------------------------------------+
void OnTrade()
{
   CalculateBalances();
   SaveState();
}

//+------------------------------------------------------------------+
//| Tester: Custom Optimization Metric                               |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(dd <= 0) return profit;
   return profit / dd;
}
