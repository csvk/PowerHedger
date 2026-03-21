//+------------------------------------------------------------------+
//|                                                PowerHedger.mq5    |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Expert Advisor: PowerHedger v2
   Description: Symmetrical Sequence Isolation & Trimming.
   PRD Section 8: Detailed annotations and alignment with product requirements.
*/

#property copyright "Copyright 2026, Souvik Chanda"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

//--- Include modular components
#include "Include/Defines.mqh"
#include "Include/Inputs.mqh"
#include "Include/Globals.mqh"
#include "Include/Utilities.mqh"
#include "Include/Persistence.mqh"
#include "Include/TradeLogic.mqh"

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // PRD Section 1: Symbol initialization
   if(!m_symbol.Name(_Symbol)) return(INIT_FAILED);
   m_symbol.RefreshRates();
   
   // PRD Section 6: Setup persistence (BaseMagicNumber used as file root)
   g_fileName = IntegerToString(BaseMagicNumber) + ".json";
   
   g_isOptimizing = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);
   
   LoadState();
   
   // Sync deal tracker
   if(HistorySelect(0, TimeCurrent())) {
      int total = HistoryDealsTotal();
      if(total > 0) g_lastProcessedDeal = HistoryDealGetTicket(total - 1);
   }
   
   // PRD Section 7.1: Handle Caching
   // Indicators are initialized once during EA startup to maximize genetic optimization speed.
   if(!InitIndicators()) return(INIT_FAILED);
   
   CalculateBalances();
   MathSrand((int)TimeCurrent());
   
   PrintFormat("[INFO] PowerHedger v2 initialized. BaseMagic: %I64d", BaseMagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveState();
   ReleaseIndicators();
   PrintFormat("[INFO] PowerHedger v2 deinitialized. Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Tick event handler                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Check if processing is needed (Optimization Tip: Skip if no active trade and no entry possible)
   if(!m_symbol.RefreshRates()) return;

   // 2. Sync State (Only if necessary or periodic)
   ReconcileRecentDeals();
   CalculateBalances();
   
   // 3. Adopt Manual Trades (Skip during optimization if not required)
   if(!g_isOptimizing) AdoptManualTrades();
   
   // 4. Entry Logic (Quick exit if active trade present)
   if(!IsActiveTradePresent() && IsSessionActive()) {
      CheckNewEntries();
   }

   // 5. Sequence & Hedge Management (Always run for active/locked sequences)
   if(ArraySize(g_sequences) > 0) {
      ManageLockedSequences();
      ManagePyramiding();
      ManageTrailingSL();
      CapitulationRule();
   }
   
   // 6. Persistence
   SaveStateIfNeeded();
}

//+------------------------------------------------------------------+
//| Trade Event                                                      |
//+------------------------------------------------------------------+
void OnTrade()
{
   ReconcileRecentDeals();
   CalculateBalances();
}

//+------------------------------------------------------------------+
//| Trade Transaction                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      ReconcileRecentDeals();
      CalculateBalances();
      SaveStateIfNeeded();
   }
}

//+------------------------------------------------------------------+
//| PRD 7.3: Custom Optimization Metric                              |
//| Returns the ratio of Total Profit to Relative Equity Drawdown.   |
//| Higher values indicate better risk-adjusted performance.         |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double dd_percent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   
   if(profit <= 0) return 0;
   
   // Custom Fitness Metric: Drawdown-Weighted Profit
   // Score = Profit * (1 - DD%)^OptRiskAversion
   double dd_factor = 1.0 - (dd_percent / 100.0);
   if (dd_factor <= 0) return 0;
   
   double score = profit * MathPow(dd_factor, OptRiskAversion);
   
   // Applying penalty for insufficient trade count (statistical insignificance)
   if(trades < OptMinTrades) score *= 0.1; 

   return score;
}
