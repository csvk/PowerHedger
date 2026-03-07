//+------------------------------------------------------------------+
//|                                                  Persistence.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Persistence
   Description: Manages JSON-based data serialization for EA state recovery.
   PRD Section: 3.4 (Persistence & Profit Tally).
*/

#include <Files\FileTxt.mqh>
#include "Globals.mqh"
#include "Inputs.mqh"

//+------------------------------------------------------------------+
//| PRD 3.4: Save State to JSON File                                 |
//| Stores critical values to enable recovery after terminal restart.|
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| PRD 3.4: Save State to JSON File                                 |
//| Stores critical values to enable recovery after terminal restart.|
//+------------------------------------------------------------------+
void SaveState()
{
   //--- PRD 7.1: optimization safety (Do not write during genetic optimization)
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return; 
   
   CFileTxt file;
   int flags = FILE_WRITE;
   
   //--- PRD 7.2: Use agent-local folder for Strategy Tester agents
   if(!MQLInfoInteger(MQL_TESTER)) flags |= FILE_COMMON; 
   
   //--- Write Tally, TrailingHedgePrice, and Last Reconciled Deal to string
   if(file.Open(g_fileName, flags)) {
      file.WriteString(StringFormat("{\"Tally\":%.2f,\"TrailingHedgePrice\":%.5f,\"LastDeal\":%I64u}", 
                                     g_profitTally, g_trailingHedgePrice, g_lastProcessedDeal));
      file.Close();
      // PrintFormat("[INFO] State saved to %s (Tally: %.2f, TrailingHedgePrice: %.5f)", g_fileName, g_profitTally, g_trailingHedgePrice);
   }
   
   g_isStateDirty = false;
}

//+------------------------------------------------------------------+
//| TriggerSave: Mars the state as dirty to be saved later           |
//+------------------------------------------------------------------+
void TriggerSave() { g_isStateDirty = true; }

//+------------------------------------------------------------------+
//| SaveStateIfNeeded: Executes SaveState if dirty flag is set       |
//+------------------------------------------------------------------+
void SaveStateIfNeeded()
{
   if(g_isStateDirty) {
      //--- Double Check: Only save if the data has actually changed compared to last write
      //--- This suppresses redundant logs when overlapping triggers (OnTick/OnTrade) occur
      bool hasChanged = (MathAbs(g_profitTally - g_lastSavedTally) > 0.000001 || 
                         MathAbs(g_trailingHedgePrice - g_lastSavedTrailingPrice) > 0.000001 || 
                         g_lastProcessedDeal != g_lastSavedDeal);
                         
      if(hasChanged) {
         SaveState();
         g_lastSavedTally = g_profitTally;
         g_lastSavedTrailingPrice = g_trailingHedgePrice;
         g_lastSavedDeal  = g_lastProcessedDeal;
         PrintFormat("[INFO] State saved to %s (Tally: %.2f, TrailingHedgePrice: %.5f)", g_fileName, g_profitTally, g_trailingHedgePrice);
      } else {
         // Reset flag even if check fails to prevent infinite retries of the same data
         g_isStateDirty = false;
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 3.4: Load State from JSON File                               |
//| Invoked on EA initialization to restore previous session state. |
//+------------------------------------------------------------------+
void LoadState()
{
   CFileTxt file;
   int flags = FILE_READ;
   if(!MQLInfoInteger(MQL_TESTER)) flags |= FILE_COMMON;
   
   //--- Read raw string and parse primitive key-value pairs
   if(file.Open(g_fileName, flags)) {
      string content = file.ReadString();
      file.Close();
      
      //--- Simple manual parsing of the JSON structure
      int pTally = StringFind(content, "\"Tally\":");
      int pHedge = StringFind(content, "\"TrailingHedgePrice\":");
      int pDeal = StringFind(content, "\"LastDeal\":");
      
      if(pTally >= 0) g_profitTally = StringToDouble(StringSubstr(content, pTally + 8));
      if(pHedge >= 0) g_trailingHedgePrice = StringToDouble(StringSubstr(content, pHedge + 21));
      if(pDeal >= 0) g_lastProcessedDeal = (ulong)StringToInteger(StringSubstr(content, pDeal + 11));
      
      PrintFormat("[INFO] State loaded from %s (Tally: %.2f, TrailingHedgePrice: %.5f, LastDeal: %I64u)", g_fileName, g_profitTally, g_trailingHedgePrice, g_lastProcessedDeal);
   }
   
   //--- Initialize trackers to match current state
   g_lastSavedTally = g_profitTally;
   g_lastSavedTrailingPrice = g_trailingHedgePrice;
   g_lastSavedDeal  = g_lastProcessedDeal;
}
