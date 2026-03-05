//+------------------------------------------------------------------+
//|                                                PowerHedger.mq5    |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Expert Advisor: PowerHedger
   Description: Advanced MT5 Hedging & Recovery EA based on the POW Banker strategy.
   Logic: Combines indicator-based entries with a mathematical hedging and trimming system.
   PRD Alignment: Strictly follows the Product Requirements Document (PRD) for version 1.01.
*/

#property copyright "Copyright 2026, Souvik Chanda"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict

//--- Include modular components for better maintainability and organization
#include "Include\Defines.mqh"      // Key enumerations and definitions
#include "Include\Inputs.mqh"       // User-configurable input parameters
#include "Include\Globals.mqh"      // Global variables and class instances
#include "Include\Utilities.mqh"    // Helper functions and session filters
#include "Include\Persistence.mqh"  // JSON-based state saving and loading
#include "Include\TradeLogic.mqh"   // Core entry, hedging, and trimming logic

//+------------------------------------------------------------------+
//| Initialization: Sets up the EA on startup                        |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- PRD 5.1: Set magic number for this EA instance to track its own trades
   m_trade.SetExpertMagicNumber(MagicNumber);
   
   //--- Initialize symbol information and refresh market rates
   if(!m_symbol.Name(_Symbol)) return(INIT_FAILED);
   m_symbol.RefreshRates();
   
   //--- PRD 3.4: Setup persistence filename based on Magic Number
   g_fileName = IntegerToString(MagicNumber) + ".json";
   
   //--- PRD 3.4: Load previously saved state (ProfitTally, HedgePoint, etc.) from JSON
   LoadState();
   
   //--- SYNC: Initialize deal tracker to the latest transaction in history
   if(HistorySelect(0, TimeCurrent())) {
      int total = HistoryDealsTotal();
      if(total > 0) g_lastProcessedDeal = HistoryDealGetTicket(total - 1);
   }
   
   //--- Initial calculation of open volumes to synchronize global state
   CalculateBalances();
   
   //--- Seed random generator for testing purposes (Note: PRD 2.1 requires indicators, random is for dev)
   MathSrand(RandomSeed);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization: Cleans up resources on shutdown                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- PRD 3.4: Save current state to JSON file before the EA is removed
   SaveState();
   
   //--- Release all indicator handles to free up memory (PRD 7.1)
   IndicatorRelease(g_hRSI1); IndicatorRelease(g_hEMA1_F); IndicatorRelease(g_hEMA1_M); IndicatorRelease(g_hEMA1_S);
   IndicatorRelease(g_hADX1); IndicatorRelease(g_hBB1);
   IndicatorRelease(g_hRSI2); IndicatorRelease(g_hEMA2_F); IndicatorRelease(g_hEMA2_M); IndicatorRelease(g_hEMA2_S);
   IndicatorRelease(g_hADX2); IndicatorRelease(g_hBB2);
}

//+------------------------------------------------------------------+
//| Tick event handler: Core real-time processing loop               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 0. SYNC: Reconcile any recent closures (Profit/Loss) before proceeding with management
   ReconcileRecentDeals();
   
   //--- 1. Event-Driven Volume Refresh: Ensure g_totalBuyLots/g_totalSellLots are accurate
   CalculateBalances();
   
   //--- 1. Refresh market data (Bid, Ask, Spread) for the current symbol
   if(!m_symbol.RefreshRates()) return;
   
   //--- 2. PRD 3.1/3.3: Manage Trailing Stops and Theoretical Risk Reduction (Trimming)
   ManageOpenPositions();
   
   //--- 3. PRD 3.5: Post-Trim Hedge Adjustment (Squeezing the hedge gap)
   ManageHedgeSqueeze();
   
   //--- 4. PRD 2.3: Standard Hedging Logic (Monitors trigger distance per tick)
   CheckHedgeTriggers();
   
   //--- 5. PRD 2.1/2.4: Indicator-based Entry Logic (Conditional on market state)
   CheckNewEntries();
}

//+------------------------------------------------------------------+
//| Trade Event Calculation: Triggered on position/order changes     |
//+------------------------------------------------------------------+
void OnTrade()
{
   //--- SYNC: Reconcile any recent closures (Profit/Loss) on trade events
   ReconcileRecentDeals();
   
   //--- Recalculate balances whenever a trade event (open/close/modify) occurs
   CalculateBalances();
   
   //--- Persist the new state immediately to prevent data loss on crash (PRD 3.4)
   SaveState();
}

//+------------------------------------------------------------------+
//| Trade Transaction Event: Critical for profit reconciliation      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   //--- PRD 3.5/8: Use unified reconciliation for all transaction types
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      ReconcileRecentDeals();
      CalculateBalances(); // Re-sync volumes in case history processing modified open positions
   }
}

//+------------------------------------------------------------------+
//| Tester: Custom Optimization Metric (PRD 7.3)                     |
//+------------------------------------------------------------------+
double OnTester()
{
   //--- Returns Profit/RelativeDrawdown ratio for robust genetic optimization
   double profit = TesterStatistics(STAT_PROFIT);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(dd <= 0) return profit;
   return profit / dd;
}
