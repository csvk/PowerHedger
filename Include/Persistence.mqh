//+------------------------------------------------------------------+
//|                                                  Persistence.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include <Files\FileTxt.mqh>
#include "Globals.mqh"
#include "Inputs.mqh"

//+------------------------------------------------------------------+
//| Persistence: Save State                                          |
//+------------------------------------------------------------------+
void SaveState()
{
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return; 
   
   CFileTxt file;
   int flags = FILE_WRITE;
   
   if(!MQLInfoInteger(MQL_TESTER)) flags |= FILE_COMMON; 
   
   if(file.Open(g_fileName, flags)) {
      file.WriteString(StringFormat("{\"Tally\":%.2f,\"HedgePoint\":%.5f,\"BuySeq\":%d,\"SellSeq\":%d}", 
                                     g_profitTally, g_hedgePoint, g_buySequence, g_sellSequence));
      file.Close();
   }
}

//+------------------------------------------------------------------+
//| Persistence: Load State                                          |
//+------------------------------------------------------------------+
void LoadState()
{
   CFileTxt file;
   int flags = FILE_READ;
   if(!MQLInfoInteger(MQL_TESTER)) flags |= FILE_COMMON;
   
   if(file.Open(g_fileName, flags)) {
      string content = file.ReadString();
      file.Close();
      
      int pTally = StringFind(content, "\"Tally\":");
      int pHedge = StringFind(content, "\"HedgePoint\":");
      int pBuy = StringFind(content, "\"BuySeq\":");
      int pSell = StringFind(content, "\"SellSeq\":");
      
      if(pTally >= 0) g_profitTally = StringToDouble(StringSubstr(content, pTally + 8));
      if(pHedge >= 0) g_hedgePoint = StringToDouble(StringSubstr(content, pHedge + 13));
      if(pBuy >= 0) g_buySequence = (int)StringToInteger(StringSubstr(content, pBuy + 9));
      if(pSell >= 0) g_sellSequence = (int)StringToInteger(StringSubstr(content, pSell + 10));
   }
}
