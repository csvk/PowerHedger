//+------------------------------------------------------------------+
//|                                                PowerHedger.mq5    |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Expert Advisor: PowerHedger v2
   Description: Symmetrical Sequence Isolation & Trimming.
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
   // Initialize symbol
   if(!m_symbol.Name(_Symbol)) return(INIT_FAILED);
   m_symbol.RefreshRates();
   
   // Setup persistence
   g_fileName = IntegerToString(BaseMagicNumber) + ".json";
   LoadState();
   
   // Sync deal tracker
   if(HistorySelect(0, TimeCurrent())) {
      int total = HistoryDealsTotal();
      if(total > 0) g_lastProcessedDeal = HistoryDealGetTicket(total - 1);
   }
   
   // Initial indicators
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
   // 1. Sync
   ReconcileRecentDeals();
   CalculateBalances();
   
   if(!m_symbol.RefreshRates()) return;
   
   // 2. Adopt Manual Trades
   AdoptManualTrades();
   
   // 3. Trimming (Risk Reduction)
   // PerformSymmetricalTrimming(); // Now event-triggered via ReconcileRecentDeals and ManageTrailingSL
   
   // 4. Entry & Hedging
   CheckNewEntries();
   ManageLockedSequences();
   ManagePyramiding();
   
   // 5. Active Trade Management
   ManageTrailingSL();
   
   // 6. Emergency
   CapitulationRule();
   
   // 7. Persist
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
//| Tester Metric                                                    |
//+------------------------------------------------------------------+
double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(dd <= 0) return profit;
   return profit / dd;
}
