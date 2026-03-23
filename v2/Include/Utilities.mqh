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
   PRD Section 8: Detailed annotations provided to align with requirements.
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
   
   // Reset current volumes for all known sequences
   for(int i=0; i<ArraySize(g_sequences); i++) {
      g_sequences[i].volBuy = 0;
      g_sequences[i].volSell = 0;
      // We don't reset midPrice here because it might be reused if still active
   }
   
   // PRD 7.4.14: Static storage for mid-price calculation to prevent heap thrashing
   struct SeqCalc { double entryB, entryS; int countB, countS; };
   static SeqCalc calcs[100]; // Fixed capacity for max sequences
   for(int i=0; i<100; i++) ZeroMemory(calcs[i]);
   
   ArrayResize(g_activeTickets, 0); // Rebuild ticket cache
   g_hasActiveSequence = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol)
      {
         long magic = m_position.Magic();
         bool isManaged = (magic >= BaseMagicNumber && magic < BaseMagicNumber + 100000);
         
         // PRD 7.4.11: Pre-cache tickets for active (unhedged) sequences to bypass O(N) loops later
         // Optimization: Skip manual loop if magic is standard sequence magic
         if(!isManaged && !g_isOptimizing) {
            for(int j=0; j<ArraySize(g_manualMaps); j++) {
               if(m_position.Ticket() == g_manualMaps[j].ticket) { magic = g_manualMaps[j].assignedMagic; isManaged = true; break; }
            }
         }
         
         if(!isManaged) continue;

         double vol = m_position.Volume();
         double price = m_position.PriceOpen();
         if(m_position.PositionType() == POSITION_TYPE_BUY) g_totalBuyLots += vol;
         else g_totalSellLots += vol;
         
         int seqIdx = -1;
         for(int j=0; j<ArraySize(g_sequences); j++) { if(g_sequences[j].magic == magic) { seqIdx = j; break; } }
         if(seqIdx == -1) {
            seqIdx = ArraySize(g_sequences);
            ArrayResize(g_sequences, seqIdx + 1, 10);
            if(seqIdx < 100) ZeroMemory(calcs[seqIdx]);
            g_sequences[seqIdx].magic = magic;
            g_sequences[seqIdx].volBuy = 0; 
            g_sequences[seqIdx].volSell = 0; 
            g_sequences[seqIdx].midPrice = 0; 
            g_sequences[seqIdx].state = SEQ_ACTIVE;
            g_sequences[seqIdx].lastPyramidSL = 0;
         }
         
         if(m_position.PositionType() == POSITION_TYPE_BUY) {
            g_sequences[seqIdx].volBuy += vol;
            calcs[seqIdx].entryB += price;
            calcs[seqIdx].countB++;
         } else {
            g_sequences[seqIdx].volSell += vol;
            calcs[seqIdx].entryS += price;
            calcs[seqIdx].countS++;
         }
      }
   }
   
   // Finalize states and cleanup in one final loop
   for(int i = ArraySize(g_sequences) - 1; i >= 0; i--) {
      if(g_sequences[i].volBuy <= 0 && g_sequences[i].volSell <= 0) {
         for(int k=i; k<ArraySize(g_sequences)-1; k++) g_sequences[k] = g_sequences[k+1];
         ArrayResize(g_sequences, ArraySize(g_sequences) - 1);
         continue;
      }

      if(calcs[i].countB > 0 && calcs[i].countS > 0) {
         g_sequences[i].state = SEQ_LOCKED;
         g_sequences[i].midPrice = (calcs[i].entryB/calcs[i].countB + calcs[i].entryS/calcs[i].countS) / 2.0;
      } else {
         g_sequences[i].state = SEQ_ACTIVE;
         g_sequences[i].midPrice = (calcs[i].countB > 0) ? (calcs[i].entryB/calcs[i].countB) : (calcs[i].entryS/calcs[i].countS);
         g_hasActiveSequence = true; // Update PRD 7.4.13 flag
      }
   }
   
   // PRD 7.4.11: Finalize Ticket Cache based on state determined above
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol) {
         long magic = m_position.Magic(); ulong ticket = m_position.Ticket();
         if(magic < BaseMagicNumber || magic >= BaseMagicNumber + 100000) {
            for(int j=0; j<ArraySize(g_manualMaps); j++) if(ticket == g_manualMaps[j].ticket) { magic = g_manualMaps[j].assignedMagic; break; }
         }
         for(int j=0; j<ArraySize(g_sequences); j++) {
            if(g_sequences[j].magic == magic && g_sequences[j].state == SEQ_ACTIVE) {
               int sz = ArraySize(g_activeTickets);
               ArrayResize(g_activeTickets, sz + 1);
               g_activeTickets[sz].ticket = ticket;
               g_activeTickets[sz].magic = magic;
               break;
            }
         }
      }
   }
}

// PRD 2.1: One-Active-Trade Rule - Replaced by g_hasActiveSequence O(1) flag

//+------------------------------------------------------------------+
//| Helper: Check if ANY sequence is in LOCKED state                 |
//+------------------------------------------------------------------+
bool HasLockedSequences()
{
   for(int i=0; i<ArraySize(g_sequences); i++) { if(g_sequences[i].state == SEQ_LOCKED) return true; }
   return false;
}

//+------------------------------------------------------------------+
//| PRD 1.1 & 7.2: Session Filters                                   |
//| Multi-session UTC-based activation logic.                        |
//| Requirement 7.2: Uses TimeTradeServer() in Strategy Tester to    |
//| align with tester's internal clock for accurate backtesting.     |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   static int lastCalculatedHour = -1;
   static int lastCalculatedDay = -1;
   static bool lastResult = false;
   
   // PRD 7.2: Time Synchronization
   datetime now = g_isTester ? TimeTradeServer() : TimeCurrent();
   MqlDateTime dt; TimeToStruct(now, dt);
   
   if(dt.hour == lastCalculatedHour && dt.day_of_year == lastCalculatedDay) {
      return lastResult;
   }
   
   lastCalculatedHour = dt.hour;
   lastCalculatedDay = dt.day_of_year;
   
   if(dt.day_of_week == 0 || dt.day_of_week == 6) { lastResult = false; return false; }
   if(dt.day_of_week == 1 && !MondayActive) { lastResult = false; return false; }
   if(dt.day_of_week == 5 && !FridayActive) { lastResult = false; return false; }
   
   int hour = dt.hour;
   if(SydneyActive && (hour >= 22 || hour < 7)) { lastResult = true; return true; }
   if(TokyoActive && (hour >= 0 && hour < 9)) { lastResult = true; return true; }
   if(LondonActive && (hour >= 8 && hour < 17)) { lastResult = true; return true; }
   if(NewYorkActive && (hour >= 13 && hour < 22)) { lastResult = true; return true; }
   
   lastResult = false;
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Enum Decoder for EMA Periods                             |
//| PRD Section 4: Derives individual EMA values from a single Enum.  |
//+------------------------------------------------------------------+
void GetEMAPeriods(ENUM_EMA_SETS set, int &fast, int &mid, int &slow) {
   switch(set) {
      case EMA_P1: fast=5; mid=13; slow=21; break;
      case EMA_P2: fast=8; mid=21; slow=34; break;
      case EMA_P3: fast=13; mid=34; slow=55; break;
      default: fast=5; mid=13; slow=21; break;
   }
}

//+------------------------------------------------------------------+
//| PRD 2.4 & 7.1: Indicator Initialization                          |
//| Requirement 7.1: Handles are created once and cached to avoid    |
//| per-tick overhead during genetic optimization.                   |
//+------------------------------------------------------------------+
bool InitIndicators() {
   if(S1UseRSI) g_hRSI1 = iRSI(_Symbol, (ENUM_TIMEFRAMES)S1RSITimeframe, S1RSIPeriod, PRICE_CLOSE);
   if(S1UseEMA) { int f,m,s; GetEMAPeriods(S1EMAPeriods, f,m,s); g_hEMA1_F = iMA(_Symbol, (ENUM_TIMEFRAMES)S1EMATimeframe, f, 0, MODE_EMA, PRICE_CLOSE); g_hEMA1_M = iMA(_Symbol, (ENUM_TIMEFRAMES)S1EMATimeframe, m, 0, MODE_EMA, PRICE_CLOSE); g_hEMA1_S = iMA(_Symbol, (ENUM_TIMEFRAMES)S1EMATimeframe, s, 0, MODE_EMA, PRICE_CLOSE); }
   if(S1UseADX) g_hADX1 = iADX(_Symbol, (ENUM_TIMEFRAMES)S1ADXTimeframe, S1ADXPeriod);
   if(S1UseBB) g_hBB1 = iBands(_Symbol, (ENUM_TIMEFRAMES)S1BBTimeframe, 20, 0, S1BBDeviations, PRICE_CLOSE);
   
   if(S2UseRSI) g_hRSI2 = iRSI(_Symbol, (ENUM_TIMEFRAMES)S2RSITimeframe, S2RSIPeriod, PRICE_CLOSE);
   if(S2UseEMA) { int f,m,s; GetEMAPeriods(S2EMAPeriods, f,m,s); g_hEMA2_F = iMA(_Symbol, (ENUM_TIMEFRAMES)S2EMATimeframe, f, 0, MODE_EMA, PRICE_CLOSE); g_hEMA2_M = iMA(_Symbol, (ENUM_TIMEFRAMES)S2EMATimeframe, m, 0, MODE_EMA, PRICE_CLOSE); g_hEMA2_S = iMA(_Symbol, (ENUM_TIMEFRAMES)S2EMATimeframe, s, 0, MODE_EMA, PRICE_CLOSE); }
   if(S2UseADX) g_hADX2 = iADX(_Symbol, (ENUM_TIMEFRAMES)S2ADXTimeframe, S2ADXPeriod);
   if(S2UseBB) g_hBB2 = iBands(_Symbol, (ENUM_TIMEFRAMES)S2BBTimeframe, 20, 0, S2BBDeviations, PRICE_CLOSE);
   
   if(S3UseRSI) g_hRSI3 = iRSI(_Symbol, (ENUM_TIMEFRAMES)S3RSITimeframe, S3RSIPeriod, PRICE_CLOSE);
   if(S3UseEMA) { int f,m,s; GetEMAPeriods(S3EMAPeriods, f,m,s); g_hEMA3_F = iMA(_Symbol, (ENUM_TIMEFRAMES)S3EMATimeframe, f, 0, MODE_EMA, PRICE_CLOSE); g_hEMA3_M = iMA(_Symbol, (ENUM_TIMEFRAMES)S3EMATimeframe, m, 0, MODE_EMA, PRICE_CLOSE); g_hEMA3_S = iMA(_Symbol, (ENUM_TIMEFRAMES)S3EMATimeframe, s, 0, MODE_EMA, PRICE_CLOSE); }
   if(S3UseADX) g_hADX3 = iADX(_Symbol, (ENUM_TIMEFRAMES)S3ADXTimeframe, S3ADXPeriod);
   if(S3UseBB) g_hBB3 = iBands(_Symbol, (ENUM_TIMEFRAMES)S3BBTimeframe, 20, 0, S3BBDeviations, PRICE_CLOSE);
   return true;
}

void ReleaseIndicators() {
   IndicatorRelease(g_hRSI1); IndicatorRelease(g_hEMA1_F); IndicatorRelease(g_hEMA1_M); IndicatorRelease(g_hEMA1_S); IndicatorRelease(g_hADX1); IndicatorRelease(g_hBB1);
   IndicatorRelease(g_hRSI2); IndicatorRelease(g_hEMA2_F); IndicatorRelease(g_hEMA2_M); IndicatorRelease(g_hEMA2_S); IndicatorRelease(g_hADX2); IndicatorRelease(g_hBB2);
   IndicatorRelease(g_hRSI3); IndicatorRelease(g_hEMA3_F); IndicatorRelease(g_hEMA3_M); IndicatorRelease(g_hEMA3_S); IndicatorRelease(g_hADX3); IndicatorRelease(g_hBB3);
}

//+------------------------------------------------------------------+
//| PRD 2.2: Universal Alignment Matrix                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Helpers: Convert Enums to Strings for Display                    |
//+------------------------------------------------------------------+
string GetRSIRuleName(ENUM_RSI_TREND_RULE rule) { return (rule == RSI_WITH_TREND) ? "Trade with Trend" : "Trade against Trend"; }
string GetEMARuleName(ENUM_EMA_TREND_RULE rule) { if(rule == EMA_WITH_TREND) return "Trade with Trend"; else if(rule == EMA_AGAINST_TREND) return "Trade against Trend"; return "Trade when Ranging"; }
string GetADXRuleName(ENUM_ADX_TREND_RULE rule) { if(rule == ADX_WITH_TREND) return "Trade with Trend"; else if(rule == ADX_WITH_TREND_AVOID_EXTREME) return "Trade with Trend but avoid Extreme"; else if(rule == ADX_AGAINST_TREND) return "Trade against Trend"; else if(rule == ADX_RANGING) return "Trade when Ranging"; return "Trade only at Extreme Trend levels"; }
string GetBBRuleName(ENUM_BB_TREND_RULE rule) { if(rule == BB_AVOID_EXTREME_TREND) return "Avoid Extreme Trend"; else if(rule == BB_AGAINST_TREND) return "Trade against Trend"; return "Trade only at Extreme Trend (Breakout)"; }
string GetSignalName(ENUM_IND_SIGNAL sig) { if(sig == IND_BUY) return "BUY"; else if (sig == IND_SELL) return "SELL"; else if (sig == IND_PASS) return "PASS"; return "NEUTRAL"; }

//+------------------------------------------------------------------+
//| PRD 2.2: Universal Alignment Matrix                              |
//| Returns: 1 (Buy), -1 (Sell), 0 (No Signal)                       |
//+------------------------------------------------------------------+
int GetStrategySignal(int sNum, string &explanation) {
   explanation = "";
   
   bool useRSI = (sNum==1)?S1UseRSI:(sNum==2)?S2UseRSI:S3UseRSI;
   bool useEMA = (sNum==1)?S1UseEMA:(sNum==2)?S2UseEMA:S3UseEMA;
   bool useADX = (sNum==1)?S1UseADX:(sNum==2)?S2UseADX:S3UseADX;
   bool useBB = (sNum==1)?S1UseBB:(sNum==2)?S2UseBB:S3UseBB;
   
   ENUM_EMA_TREND_RULE emaRule = (sNum==1)?S1EMATrendRule:(sNum==2)?S2EMATrendRule:S3EMATrendRule;
   ENUM_ADX_TREND_RULE adxRule = (sNum==1)?S1ADXTrendRule:(sNum==2)?S2ADXTrendRule:S3ADXTrendRule;
   ENUM_BB_TREND_RULE bbRule = (sNum==1)?S1BBRule:(sNum==2)?S2BBRule:S3BBRule;
   
   double rsiSell = (sNum==1)?S1RSISellLevel:(sNum==2)?S2RSISellLevel:S3RSISellLevel;
   double rsiBuy = 100.0 - rsiSell;
   
   ENUM_IND_SIGNAL rsiRes=IND_PASS, emaRes=IND_PASS, adxRes=IND_PASS, bbRes=IND_PASS;
   string rsiStr="", emaStr="", adxStr="", bbStr="";
   
    // 1. RSI
    if(useRSI) {
       double r[2]; // PRD 7.4.12: Stack-based allocation
       int h = (sNum==1)?g_hRSI1:(sNum==2)?g_hRSI2:g_hRSI3;
       ENUM_RSI_TREND_RULE rsiRule = (sNum==1)?S1RSITrendRule:(sNum==2)?S2RSITrendRule:S3RSITrendRule;
       
       if(CopyBuffer(h,0,0,2,r)==2) {
          if(rsiRule == RSI_AGAINST_TREND) {
             if(r[0]>=rsiBuy && r[1]<rsiBuy) rsiRes=IND_BUY;
             else if(r[0]<=rsiSell && r[1]>rsiSell) rsiRes=IND_SELL;
             else rsiRes=IND_NEUTRAL;
          } else { // RSI_WITH_TREND
             if(r[0]<=rsiSell && r[1]>rsiSell) rsiRes=IND_BUY;
             else if(r[0]>=rsiBuy && r[1]<rsiBuy) rsiRes=IND_SELL;
             else rsiRes=IND_NEUTRAL;
          }
          
          if(!g_isOptimizing) {
             double th = (rsiRes == IND_BUY) ? ((rsiRule == RSI_AGAINST_TREND) ? rsiBuy : rsiSell) :
                         (rsiRes == IND_SELL) ? ((rsiRule == RSI_AGAINST_TREND) ? rsiSell : rsiBuy) :
                         ((r[1] > 50) ? rsiSell : rsiBuy);
             rsiStr = StringFormat("- RSI (%s) : %.1f %s %.1f : %s", GetRSIRuleName(rsiRule), r[1], (r[1]>th?">":"<"), th, GetSignalName(rsiRes));
          }
       } else { rsiRes=IND_NEUTRAL; if(!g_isOptimizing) rsiStr="- RSI: Error copying buffer"; }
       if(rsiRes == IND_NEUTRAL && g_isOptimizing) return 0; // Short-circuit
    }
   
   // 2. EMA
   if(useEMA) {
      double f[1], m[1], s[1]; // PRD 7.4.12: Stack-based allocation
      int hf=(sNum==1)?g_hEMA1_F:(sNum==2)?g_hEMA2_F:g_hEMA3_F, hm=(sNum==1)?g_hEMA1_M:(sNum==2)?g_hEMA2_M:g_hEMA3_M, hs=(sNum==1)?g_hEMA1_S:(sNum==2)?g_hEMA2_S:g_hEMA3_S;
      if(CopyBuffer(hf,0,0,1,f)==1 && CopyBuffer(hm,0,0,1,m)==1 && CopyBuffer(hs,0,0,1,s)==1) {
         bool bull = (f[0]>m[0] && m[0]>s[0]); bool bear = (f[0]<m[0] && m[0]<s[0]);
         
         if(emaRule == EMA_WITH_TREND) {
            if(bull) emaRes=IND_BUY; else if(bear) emaRes=IND_SELL; else emaRes=IND_NEUTRAL;
         } else if(emaRule == EMA_AGAINST_TREND) {
            if(bull) emaRes=IND_SELL; else if(bear) emaRes=IND_BUY; else emaRes=IND_NEUTRAL;
         } else if(emaRule == EMA_RANGING) {
            if(!bull && !bear) emaRes=IND_PASS; else emaRes=IND_NEUTRAL;
         }
         
         if(!g_isOptimizing) {
            string rf = (f[0]>m[0])?">":(f[0]<m[0])?"<":"=";
            string rm = (m[0]>s[0])?">":(m[0]<s[0])?"<":"=";
            string vals = StringFormat("F(%.5f) %s M(%.5f) %s S(%.5f)", f[0], rf, m[0], rm, s[0]);
            emaStr = StringFormat("- EMA (%s) : %s : %s", GetEMARuleName(emaRule), vals, GetSignalName(emaRes));
         }
      } else { emaRes=IND_NEUTRAL; if(!g_isOptimizing) emaStr="- EMA: Error copying buffer"; }
      if(emaRes == IND_NEUTRAL && g_isOptimizing) return 0; // Short-circuit
   }
   
   // 3. ADX
   if(useADX) {
      double a[1], p[1], mn[1]; // PRD 7.4.12: Stack-based allocation
      int h=(sNum==1)?g_hADX1:(sNum==2)?g_hADX2:g_hADX3;
      if(CopyBuffer(h,0,0,1,a)==1 && CopyBuffer(h,1,0,1,p)==1 && CopyBuffer(h,2,0,1,mn)==1) {
         double trendLvl = (sNum==1)?S1ADXTrendLevel:(sNum==2)?S2ADXTrendLevel:S3ADXTrendLevel;
         double extremeLvl = (sNum==1)?S1ADXExtremeLevel:(sNum==2)?S2ADXExtremeLevel:S3ADXExtremeLevel;
         double rangeLvl = (sNum==1)?S1ADXRangeLevel:(sNum==2)?S2ADXRangeLevel:S3ADXRangeLevel;
         
         if(adxRule == ADX_WITH_TREND) {
            if(a[0]>trendLvl) { if(p[0]>mn[0]) adxRes=IND_BUY; else adxRes=IND_SELL; } else adxRes=IND_NEUTRAL;
         } else if(adxRule == ADX_WITH_TREND_AVOID_EXTREME) {
            if(a[0]>trendLvl && a[0]<extremeLvl) { if(p[0]>mn[0]) adxRes=IND_BUY; else adxRes=IND_SELL; } else adxRes=IND_NEUTRAL;
         } else if(adxRule == ADX_AGAINST_TREND) {
            if(a[0]>extremeLvl) { if(p[0]>mn[0]) adxRes=IND_SELL; else adxRes=IND_BUY; } else adxRes=IND_NEUTRAL;
         } else if(adxRule == ADX_RANGING) {
            if(a[0]<rangeLvl) adxRes=IND_PASS; else adxRes=IND_NEUTRAL;
         } else if(adxRule == ADX_EXTREME_ONLY) {
            if(a[0]>=extremeLvl) { if(p[0]>mn[0]) adxRes=IND_BUY; else adxRes=IND_SELL; } else adxRes=IND_NEUTRAL;
         }
         
         if(!g_isOptimizing) {
            double thVal = 0; string thType = "";
            if(adxRule==ADX_WITH_TREND || adxRule==ADX_WITH_TREND_AVOID_EXTREME) { thVal = trendLvl; thType = "Trend"; }
            else if(adxRule==ADX_AGAINST_TREND || adxRule==ADX_EXTREME_ONLY) { thVal = extremeLvl; thType = "Extreme"; }
            else if(adxRule==ADX_RANGING) { thVal = rangeLvl; thType = "Range"; }
            string rADX = (a[0]>thVal)?">":(a[0]<thVal)?"<":"=";
            string rDI = (p[0]>mn[0])?">":(p[0]<mn[0])?"<":"=";
            string vals = StringFormat("%.1f %s %.1f (%s) (DI+ %.1f %s DI- %.1f)", a[0], rADX, thVal, thType, p[0], rDI, mn[0]);
            adxStr = StringFormat("- ADX (%s) : %s : %s", GetADXRuleName(adxRule), vals, GetSignalName(adxRes));
         }
      } else { adxRes=IND_NEUTRAL; if(!g_isOptimizing) adxStr="- ADX: Error copying buffer"; }
      if(adxRes == IND_NEUTRAL && g_isOptimizing) return 0; // Short-circuit
   }
   
   // 4. BB
   if(useBB) {
      double u[1], l[1]; // PRD 7.4.12: Stack-based allocation
      int h=(sNum==1)?g_hBB1:(sNum==2)?g_hBB2:g_hBB3;
      if(CopyBuffer(h,1,0,1,u)==1 && CopyBuffer(h,2,0,1,l)==1) {
         double ask = m_symbol.Ask(); double bid = m_symbol.Bid(); double mid = (ask+bid)/2.0;
         
         if(bbRule == BB_AVOID_EXTREME_TREND) {
            if(bid > l[0] && ask < u[0]) bbRes=IND_PASS; else bbRes=IND_NEUTRAL;
         } else if(bbRule == BB_AGAINST_TREND) {
            if(ask <= l[0]) bbRes=IND_BUY; else if(bid >= u[0]) bbRes=IND_SELL; else bbRes=IND_NEUTRAL;
         } else if(bbRule == BB_EXTREME_ONLY) {
            if(ask >= u[0]) bbRes=IND_BUY; else if(bid <= l[0]) bbRes=IND_SELL; else bbRes=IND_NEUTRAL;
         }
         
         if(!g_isOptimizing) {
            string rL = (mid > l[0])?">":(mid < l[0])?"<":"=";
            string rU = (mid < u[0])?"<":(mid > u[0])?">":"=";
            string prce = StringFormat("L(%.5f) %s Price(%.5f) %s U(%.5f)", l[0], rL, mid, rU, u[0]);
            bbStr = StringFormat("- BB (%s) : %s : %s", GetBBRuleName(bbRule), prce, GetSignalName(bbRes));
         }
      } else { bbRes=IND_NEUTRAL; if(!g_isOptimizing) bbStr="- BB: Error copying buffer"; }
      if(bbRes == IND_NEUTRAL && g_isOptimizing) return 0; // Short-circuit
   }
   
   // 5. Universal Alignment Policy
   bool buyS=false, sellS=false, neutralP=false;
   int buyCount=0, sellCount=0, passCount=0;
   
   // Collect results
   if(!g_isOptimizing) {
      explanation = "--------------------------------------------------\n";
      if(useRSI) explanation += rsiStr + "\n";
      if(useEMA) explanation += emaStr + "\n";
      if(useADX) explanation += adxStr + "\n";
      if(useBB)  explanation += bbStr  + "\n";
      explanation += "--------------------------------------------------";
   }

   if(useRSI) { if(rsiRes==IND_NEUTRAL) neutralP=true; else if(rsiRes==IND_BUY) buyCount++; else if(rsiRes==IND_SELL) sellCount++; else passCount++; }
   if(useEMA) { if(emaRes==IND_NEUTRAL) neutralP=true; else if(emaRes==IND_BUY) buyCount++; else if(emaRes==IND_SELL) sellCount++; else passCount++; }
   if(useADX) { if(adxRes==IND_NEUTRAL) neutralP=true; else if(adxRes==IND_BUY) buyCount++; else if(adxRes==IND_SELL) sellCount++; else passCount++; }
   if(useBB)  { if(bbRes==IND_NEUTRAL)  neutralP=true; else if(bbRes==IND_BUY)  buyCount++; else if(bbRes==IND_SELL)  sellCount++; else passCount++; }
   
   if(neutralP) return 0; // Blocked
   if(buyCount > 0 && sellCount > 0) return 0; // Conflict
   if(buyCount == 0 && sellCount == 0) return 0; // All Pass (No Direction)
   
   if(buyCount > 0) return 1;
   if(sellCount > 0) return -1;
   
   return 0;
}

int GetRandomSignal() { return (MathRand()%2==0)?1:-1; }

#endif // _UTILITIES_MQH_
