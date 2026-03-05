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
   
   //--- Write Tally, HedgePoint, and Last Reconciled Deal to string
   if(file.Open(g_fileName, flags)) {
      file.WriteString(StringFormat("{\"Tally\":%.2f,\"HedgePoint\":%.5f,\"LastDeal\":%I64u}", 
                                     g_profitTally, g_hedgePoint, g_lastProcessedDeal));
      file.Close();
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
      int pHedge = StringFind(content, "\"HedgePoint\":");
      int pDeal = StringFind(content, "\"LastDeal\":");
      
      if(pTally >= 0) g_profitTally = StringToDouble(StringSubstr(content, pTally + 8));
      if(pHedge >= 0) g_hedgePoint = StringToDouble(StringSubstr(content, pHedge + 13));
      if(pDeal >= 0) g_lastProcessedDeal = (ulong)StringToInteger(StringSubstr(content, pDeal + 11));
   }
}
