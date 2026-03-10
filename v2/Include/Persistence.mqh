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
//+------------------------------------------------------------------+
//| PRD 6: Save State to JSON File                                   |
//| Stores critical values to enable recovery after terminal restart.|
//+------------------------------------------------------------------+
void SaveState()
{
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return; 
   
   CFileTxt file;
   int flags = FILE_WRITE;
   
   if(!MQLInfoInteger(MQL_TESTER)) flags |= FILE_COMMON; 
   
   if(file.Open(g_fileName, flags)) {
      string content = "{";
      content += StringFormat("\"Tally\":%.2f,", g_profitTally);
      content += StringFormat("\"NextID\":%d,", g_nextSequenceID);
      content += StringFormat("\"LastDeal\":%I64u,", g_lastProcessedDeal);
      
      content += "\"ManualMaps\":[";
      for(int i=0; i<ArraySize(g_manualMaps); i++) {
         content += StringFormat("{\"t\":%I64u,\"m\":%I64d}", g_manualMaps[i].ticket, g_manualMaps[i].assignedMagic);
         if(i < ArraySize(g_manualMaps)-1) content += ",";
      }
      content += "]}";
      
      file.WriteString(content);
      file.Close();
   }
   
   g_isStateDirty = false;
}

//+------------------------------------------------------------------+
//| TriggerSave: Marks the state as dirty to be saved later          |
//+------------------------------------------------------------------+
void TriggerSave() { g_isStateDirty = true; }

//+------------------------------------------------------------------+
//| SaveStateIfNeeded: Executes SaveState if dirty flag is set       |
//+------------------------------------------------------------------+
void SaveStateIfNeeded()
{
   if(g_isStateDirty) {
      SaveState();
      PrintFormat("[INFO] State saved to %s (Tally: %.2f, NextID: %d)", g_fileName, g_profitTally, g_nextSequenceID);
   }
}

//+------------------------------------------------------------------+
//| PRD 6: Load State from JSON File                                 |
//| Invoked on EA initialization to restore previous session state. |
//+------------------------------------------------------------------+
void LoadState()
{
   CFileTxt file;
   int flags = FILE_READ;
   if(!MQLInfoInteger(MQL_TESTER)) flags |= FILE_COMMON;
   
   if(file.Open(g_fileName, flags)) {
      string content = file.ReadString();
      file.Close();
      
      //--- Parse primitive keys
      int pTally = StringFind(content, "\"Tally\":");
      int pNext  = StringFind(content, "\"NextID\":");
      int pDeal  = StringFind(content, "\"LastDeal\":");
      
      if(pTally >= 0) g_profitTally = StringToDouble(StringSubstr(content, pTally + 8));
      if(pNext  >= 0) g_nextSequenceID = (int)StringToInteger(StringSubstr(content, pNext + 9));
      if(pDeal  >= 0) g_lastProcessedDeal = (ulong)StringToInteger(StringSubstr(content, pDeal + 11));
      
      //--- Parse ManualMaps Array: "ManualMaps":[{"t":123,"m":456},...]
      int pMapArr = StringFind(content, "\"ManualMaps\":[");
      if(pMapArr >= 0) {
         ArrayResize(g_manualMaps, 0);
         int pEnd = StringFind(content, "]", pMapArr);
         if(pEnd > pMapArr + 14) {
            string sub = StringSubstr(content, pMapArr + 14, pEnd - (pMapArr + 14));
            string items[];
            int count = StringSplit(sub, '}', items);
            for(int i=0; i<count; i++) {
               int pt = StringFind(items[i], "\"t\":");
               int pm = StringFind(items[i], "\"m\":");
               if(pt >= 0 && pm >= 0) {
                  int size = ArraySize(g_manualMaps);
                  ArrayResize(g_manualMaps, size + 1);
                  string tVal = StringSubstr(items[i], pt + 4);
                  string mVal = StringSubstr(items[i], pm + 4);
                  // Find end of numeric value (comma or quote)
                  int tEnd = StringFind(tVal, ","); if(tEnd < 0) tEnd = StringFind(tVal, "\"");
                  int mEnd = StringFind(mVal, ","); if(mEnd < 0) mEnd = StringFind(mVal, "\"");
                  if(tEnd > 0) tVal = StringSubstr(tVal, 0, tEnd);
                  if(mEnd > 0) mVal = StringSubstr(mVal, 0, mEnd);
                  
                  g_manualMaps[size].ticket = (ulong)StringToInteger(tVal);
                  g_manualMaps[size].assignedMagic = StringToInteger(mVal);
               }
            }
         }
      }
      
      PrintFormat("[INFO] State loaded from %s (Tally: %.2f, NextID: %d, Maps: %d)", 
                  g_fileName, g_profitTally, g_nextSequenceID, ArraySize(g_manualMaps));
   }
}
