#ifndef _UTILITIES_MQH_
#define _UTILITIES_MQH_

//+------------------------------------------------------------------+
//|                                                    Utilities.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Utilities (v2)
   Description: Mathematical helpers, indicator management, and signal logic.
*/

#include "Globals.mqh"
#include "Inputs.mqh"

//+------------------------------------------------------------------+
//| PRD 3.1: Get Next Unique Magic Number                            |
//+------------------------------------------------------------------+
long GetNextMagic()
{
   long magic = BaseMagicNumber + g_nextSequenceID;
   g_nextSequenceID++;
   TriggerSave();
   return magic;
}

//+------------------------------------------------------------------+
//| PRD 2.3: Calculate Balances & Sequence States                    |
//+------------------------------------------------------------------+
void CalculateBalances()
{
   g_totalBuyLots = 0;
   g_totalSellLots = 0;
   
   // Reset volumes but keep the sequence objects to preserve harvestedProfit
   for(int i=0; i<ArraySize(g_sequences); i++) {
      g_sequences[i].volBuy = 0;
      g_sequences[i].volSell = 0;
   }
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol)
      {
         long magic = m_position.Magic();
         bool isManaged = false;
         
         if(magic >= BaseMagicNumber && magic < BaseMagicNumber + 100000) isManaged = true;
         else {
            for(int j=0; j<ArraySize(g_manualMaps); j++) {
               if(m_position.Ticket() == g_manualMaps[j].ticket) { magic = g_manualMaps[j].assignedMagic; isManaged = true; break; }
            }
         }
         
         if(!isManaged) continue;

         double vol = m_position.Volume();
         if(m_position.PositionType() == POSITION_TYPE_BUY) g_totalBuyLots += vol;
         else g_totalSellLots += vol;
         
         int seqIdx = -1;
         for(int j=0; j<ArraySize(g_sequences); j++) { if(g_sequences[j].magic == magic) { seqIdx = j; break; } }
         if(seqIdx == -1) {
            seqIdx = ArraySize(g_sequences);
            ArrayResize(g_sequences, seqIdx + 1);
            g_sequences[seqIdx].magic = magic;
            g_sequences[seqIdx].volBuy = 0; 
            g_sequences[seqIdx].volSell = 0; 
            g_sequences[seqIdx].midPrice = 0; 
            g_sequences[seqIdx].state = SEQ_ACTIVE;
            g_sequences[seqIdx].harvestedProfit = 0;
         }
         if(m_position.PositionType() == POSITION_TYPE_BUY) g_sequences[seqIdx].volBuy += vol;
         else g_sequences[seqIdx].volSell += vol;
      }
   }
   
   // Cleanup empty sequences (where both legs are 0) and update states
   for(int i = ArraySize(g_sequences) - 1; i >= 0; i--) {
      if(g_sequences[i].volBuy <= 0 && g_sequences[i].volSell <= 0) {
         // Sequence closed, remove it
         for(int k=i; k<ArraySize(g_sequences)-1; k++) g_sequences[k] = g_sequences[k+1];
         ArrayResize(g_sequences, ArraySize(g_sequences) - 1);
         continue;
      }

      double entryB = 0, entryS = 0;
      int countB = 0, countS = 0;
      for(int j=PositionsTotal()-1; j>=0; j--) {
         if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol) {
            long magic = m_position.Magic();
            if(magic == 0) { for(int k=0; k<ArraySize(g_manualMaps); k++) if(m_position.Ticket()==g_manualMaps[k].ticket) { magic=g_manualMaps[k].assignedMagic; break; } }
            if(magic == g_sequences[i].magic) {
               if(m_position.PositionType() == POSITION_TYPE_BUY) { entryB += m_position.PriceOpen(); countB++; }
               else { entryS += m_position.PriceOpen(); countS++; }
            }
         }
      }
      if(countB > 0 && countS > 0) { g_sequences[i].state = SEQ_LOCKED; g_sequences[i].midPrice = (entryB/countB + entryS/countS) / 2.0; }
      else { g_sequences[i].state = SEQ_ACTIVE; g_sequences[i].midPrice = (countB > 0) ? (entryB/countB) : (entryS/countS); }
   }
}

//+------------------------------------------------------------------+
//| PRD 2.1: One-Active-Trade Rule                                   |
//+------------------------------------------------------------------+
bool IsActiveTradePresent()
{
   for(int i=0; i<ArraySize(g_sequences); i++) { if(g_sequences[i].state == SEQ_ACTIVE) return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Check if ANY sequence is in LOCKED state                 |
//+------------------------------------------------------------------+
bool HasLockedSequences()
{
   for(int i=0; i<ArraySize(g_sequences); i++) { if(g_sequences[i].state == SEQ_LOCKED) return true; }
   return false;
}

//+------------------------------------------------------------------+
//| PRD 1.1: Session Filters                                         |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   datetime now = (MQLInfoInteger(MQL_TESTER)) ? TimeTradeServer() : TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.day_of_week == 1 && !MondayActive) return false;
   if(dt.day_of_week == 5 && !FridayActive) return false;
   int hour = dt.hour;
   if(SydneyActive && (hour >= 22 || hour < 7)) return true;
   if(TokyoActive && (hour >= 0 && hour < 9)) return true;
   if(LondonActive && (hour >= 8 && hour < 17)) return true;
   if(NewYorkActive && (hour >= 13 && hour < 22)) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Indicator Management                                             |
//+------------------------------------------------------------------+
void GetEMAPeriods(ENUM_EMA_SETS set, int &fast, int &mid, int &slow) {
   switch(set) {
      case EMA_P1: fast=5; mid=13; slow=21; break;
      case EMA_P2: fast=8; mid=21; slow=34; break;
      case EMA_P3: fast=13; mid=34; slow=55; break;
      default: fast=5; mid=13; slow=21; break;
   }
}

bool InitIndicators() {
   if(S1UseRSI) g_hRSI1 = iRSI(_Symbol, (ENUM_TIMEFRAMES)S1RSITimeframe, S1RSIPeriod, PRICE_CLOSE);
   if(S1UseEMA) { int f,m,s; GetEMAPeriods(S1EMAPeriods, f,m,s); g_hEMA1_F = iMA(_Symbol, (ENUM_TIMEFRAMES)S1EMATimeframe, f, 0, MODE_EMA, PRICE_CLOSE); g_hEMA1_M = iMA(_Symbol, (ENUM_TIMEFRAMES)S1EMATimeframe, m, 0, MODE_EMA, PRICE_CLOSE); g_hEMA1_S = iMA(_Symbol, (ENUM_TIMEFRAMES)S1EMATimeframe, s, 0, MODE_EMA, PRICE_CLOSE); }
   if(S1UseADX) g_hADX1 = iADX(_Symbol, (ENUM_TIMEFRAMES)S1ADXTimeframe, S1ADXPeriod);
   if(S1UseBB) g_hBB1 = iBands(_Symbol, (ENUM_TIMEFRAMES)S1BBTimeframe, 20, 0, S1BBDeviations, PRICE_CLOSE);
   
   if(S2UseRSI) g_hRSI2 = iRSI(_Symbol, (ENUM_TIMEFRAMES)S2RSITimeframe, S2RSIPeriod, PRICE_CLOSE);
   if(S2UseEMA) { int f,m,s; GetEMAPeriods(S2EMAPeriods, f,m,s); g_hEMA2_F = iMA(_Symbol, (ENUM_TIMEFRAMES)S2EMATimeframe, f, 0, MODE_EMA, PRICE_CLOSE); g_hEMA2_M = iMA(_Symbol, (ENUM_TIMEFRAMES)S2EMATimeframe, m, 0, MODE_EMA, PRICE_CLOSE); g_hEMA2_S = iMA(_Symbol, (ENUM_TIMEFRAMES)S2EMATimeframe, s, 0, MODE_EMA, PRICE_CLOSE); }
   if(S2UseADX) g_hADX2 = iADX(_Symbol, (ENUM_TIMEFRAMES)S2ADXTimeframe, S2ADXPeriod);
   if(S2UseBB) g_hBB2 = iBands(_Symbol, (ENUM_TIMEFRAMES)S2BBTimeframe, 20, 0, S2BBDeviations, PRICE_CLOSE);
   return true;
}

void ReleaseIndicators() {
   IndicatorRelease(g_hRSI1); IndicatorRelease(g_hEMA1_F); IndicatorRelease(g_hEMA1_M); IndicatorRelease(g_hEMA1_S); IndicatorRelease(g_hADX1); IndicatorRelease(g_hBB1);
   IndicatorRelease(g_hRSI2); IndicatorRelease(g_hEMA2_F); IndicatorRelease(g_hEMA2_M); IndicatorRelease(g_hEMA2_S); IndicatorRelease(g_hADX2); IndicatorRelease(g_hBB2);
}

//+------------------------------------------------------------------+
//| PRD 2.2: Universal Alignment Matrix                              |
//+------------------------------------------------------------------+
int GetStrategySignal(int sNum) {
   bool useRSI = (sNum==1)?S1UseRSI:S2UseRSI;
   bool useEMA = (sNum==1)?S1UseEMA:S2UseEMA;
   bool useADX = (sNum==1)?S1UseADX:S2UseADX;
   bool useBB = (sNum==1)?S1UseBB:S2UseBB;
   
   ENUM_EMA_TREND_RULE emaRule = (sNum==1)?S1EMATrendRule:S2EMATrendRule;
   ENUM_ADX_TREND_RULE adxRule = (sNum==1)?S1ADXTrendRule:S2ADXTrendRule;
   ENUM_BB_TREND_RULE bbRule = (sNum==1)?S1BBRule:S2BBRule;
   double rsiSell = (sNum==1)?S1RSISellLevel:S2RSISellLevel;
   double rsiBuy = 100.0 - rsiSell;
   
   int buyVotes = 0, sellVotes = 0, activeInds = 0;
   
   if(useRSI) {
      activeInds++; double r[]; int h = (sNum==1)?g_hRSI1:g_hRSI2;
      if(CopyBuffer(h,0,0,2,r)==2) { if(r[0]<rsiBuy && r[1]>=rsiBuy) buyVotes++; else if(r[0]>rsiSell && r[1]<=rsiSell) sellVotes++; }
   }
   if(useEMA) {
      activeInds++; double f[],m[],s[]; int hf=(sNum==1)?g_hEMA1_F:g_hEMA2_F, hm=(sNum==1)?g_hEMA1_M:g_hEMA2_M, hs=(sNum==1)?g_hEMA1_S:g_hEMA2_S;
      if(CopyBuffer(hf,0,0,1,f)==1 && CopyBuffer(hm,0,0,1,m)==1 && CopyBuffer(hs,0,0,1,s)==1) {
         bool bull = (f[0]>m[0] && m[0]>s[0]); bool bear = (f[0]<m[0] && m[0]<s[0]);
         if(emaRule==EMA_WITH_TREND) { if(bull) buyVotes++; else if(bear) sellVotes++; }
         else { if(bull) sellVotes++; else if(bear) buyVotes++; }
      }
   }
   if(useADX) {
      activeInds++; double a[],p[],mn[]; int h=(sNum==1)?g_hADX1:g_hADX2;
      if(CopyBuffer(h,0,0,1,a)==1 && CopyBuffer(h,1,0,1,p)==1 && CopyBuffer(h,2,0,1,mn)==1) {
         double lvl = (sNum==1)?S1ADXTrendLevel:S2ADXTrendLevel;
         if(a[0]>lvl) { if(p[0]>mn[0]) buyVotes++; else sellVotes++; }
      }
   }
   if(useBB) {
      activeInds++; double u[],l[]; int h=(sNum==1)?g_hBB1:g_hBB2;
      if(CopyBuffer(h,1,0,1,u)==1 && CopyBuffer(h,2,0,1,l)==1) {
         if(m_symbol.Ask()<=l[0]) buyVotes++; else if(m_symbol.Bid()>=u[0]) sellVotes++;
      }
   }
   
   if(activeInds > 0 && buyVotes == activeInds) return 1;
   if(activeInds > 0 && sellVotes == activeInds) return -1;
   return 0;
}

int GetRandomSignal() { return (MathRand()%2==0)?1:-1; }

#endif // _UTILITIES_MQH_
