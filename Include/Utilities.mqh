//+------------------------------------------------------------------+
//|                                                    Utilities.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Utilities
   Description: Mathematical helper functions and technical indicator signal generation.
   PRD Sections: 2.3 (Balance Monitoring), 3.1 (Session Filters), 4 (Indicator Logic).
*/

#include "Globals.mqh"
#include "Inputs.mqh"

//+------------------------------------------------------------------+
//| PRD 2.3: Calculate Volumetric Balances                           |
//| Scans open positions to sync directional volume.                 |
//+------------------------------------------------------------------+
void CalculateBalances()
{
   g_totalBuyLots = 0;
   g_totalSellLots = 0;
   
   //--- Iterate through all open positions for the current magic number and symbol
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol)
         {
            if(m_position.PositionType() == POSITION_TYPE_BUY) g_totalBuyLots += m_position.Volume();
            else if(m_position.PositionType() == POSITION_TYPE_SELL) g_totalSellLots += m_position.Volume();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Count active open positions in a specific direction      |
//| PRD 2.5: Used for dynamic <N> serial numbers                     |
//+------------------------------------------------------------------+
int CountOpenPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == type) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| PRD 2.1: Check if new signalled trade is allowed based on        |
//| Inside/Outside market conditions and distance rules.             |
//+------------------------------------------------------------------+
bool IsStrategicEntryAllowed(ENUM_POSITION_TYPE signalType, double minPipGap, ENUM_MARKET_CONTEXT &outContext)
{
   double lowestBuy = -1, highestBuy = -1;
   double lowestSell = -1, highestSell = -1;
   
   //--- Identify boundaries of existing positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol)
      {
         double openP = m_position.PriceOpen();
         if(m_position.PositionType() == POSITION_TYPE_BUY)
         {
            if(lowestBuy == -1 || openP < lowestBuy) lowestBuy = openP;
            if(highestBuy == -1 || openP > highestBuy) highestBuy = openP;
         }
         else
         {
            if(lowestSell == -1 || openP < lowestSell) lowestSell = openP;
            if(highestSell == -1 || openP > highestSell) highestSell = openP;
         }
      }
   }
   
   bool hasBuy = (lowestBuy != -1);
   bool hasSell = (lowestSell != -1);
   
   if(!hasBuy && !hasSell) {
      outContext = CONTEXT_NEW;
      return true; 
   }

   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double currentPrice = (signalType == POSITION_TYPE_BUY) ? ask : bid;
   
   //--- SCENARIO 1: Inside Entry (PRD 2.1.a)
   //--- Price is between Buy and Sell trades
   if(hasBuy && hasSell)
   {
      double innerBuy = lowestBuy;  
      double innerSell = highestSell; 
      
      // Correct for relative orientation
      if(highestBuy < lowestSell) { innerBuy = highestBuy; innerSell = lowestSell; }
      else if(highestSell < lowestBuy) { innerSell = highestSell; innerBuy = lowestBuy; }
      
      // Check if price is between the "inner" boundaries
      bool isInside = false;
      if(innerBuy < innerSell) isInside = (currentPrice > innerBuy && currentPrice < innerSell);
      else isInside = (currentPrice > innerSell && currentPrice < innerBuy);
      
      if(isInside) {
         // PRD 2.1: Distance must be checked against both Buy and Sell when open on both sides
         double distToBuy = MathAbs(currentPrice - innerBuy);
         double distToSell = MathAbs(currentPrice - innerSell);
         double minPipGapPoints = minPipGap * m_symbol.Point() * 10;
         
         if(distToBuy < minPipGapPoints || distToSell < minPipGapPoints) return false;
         
         outContext = CONTEXT_INSIDE;
         return true;
      }
   }
   
   //--- SCENARIO 2: Outside Entry (PRD 2.1.b)
   //--- Only Buy OR only Sell open. 
   if((hasBuy && !hasSell) || (!hasBuy && hasSell))
   {
      if(OutsideAllowed == OUTSIDE_NO) return false;
      
      // Find nearest position to current market price
      double nearestP = -1;
      double minDist = -1;
      ENUM_POSITION_TYPE nearestType = (ENUM_POSITION_TYPE)-1;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol)
         {
            double dist = MathAbs(currentPrice - m_position.PriceOpen());
            if(minDist == -1 || dist < minDist)
            {
               minDist = dist;
               nearestP = m_position.PriceOpen();
               nearestType = m_position.PositionType();
            }
         }
      }
      
      if(nearestP == -1) { outContext = CONTEXT_NEW; return true; } 
      
      // Condition 1: Nearest must be in loss
      bool nearestInLoss = (nearestType == POSITION_TYPE_BUY) ? (bid < nearestP) : (ask > nearestP);
      if(!nearestInLoss) return false;
      
      // Condition 2: MinPipGap away
      if(minDist < minPipGap * m_symbol.Point() * 10) return false;
      
      // Condition 3: OutsideAllowed enum filters
      bool isAllowed = false;
      if(OutsideAllowed == OUTSIDE_BOTH) isAllowed = true;
      else {
         bool isSameDir = (signalType == nearestType);
         if(OutsideAllowed == OUTSIDE_SAME_DIR && isSameDir) isAllowed = true;
         else if(OutsideAllowed == OUTSIDE_AGAINST_DIR && !isSameDir) isAllowed = true;
      }
      
      if(isAllowed) {
         outContext = CONTEXT_OUTSIDE;
         return true;
      }
      
      return false;
   }
   
   return false; 
}

//+------------------------------------------------------------------+
//| PRD 4.2: Derive individual EMA Periods from defined set enum     |
//+------------------------------------------------------------------+
void GetEMAPeriods(ENUM_EMA_SETS set, int &fast, int &medium, int &slow)
{
   switch(set)
   {
      case EMA_P1:  fast = 5;  medium = 10; slow = 20;  break;
      case EMA_P2:  fast = 4;  medium = 8;  slow = 60;  break;
      case EMA_P3:  fast = 8;  medium = 13; slow = 21;  break;
      case EMA_P4:  fast = 5;  medium = 20; slow = 50;  break;
      case EMA_P5:  fast = 7;  medium = 21; slow = 50;  break;
      case EMA_P6:  fast = 9;  medium = 21; slow = 55;  break;
      case EMA_P7:  fast = 10; medium = 21; slow = 50;  break;
      case EMA_P8:  fast = 10; medium = 50; slow = 100; break;
      case EMA_P9:  fast = 10; medium = 50; slow = 200; break;
      case EMA_P10: fast = 20; medium = 50; slow = 200; break;
      case EMA_P11: fast = 50; medium = 100; slow = 200; break;
      default:      fast = 5;  medium = 10; slow = 20;  break;
   }
}

//+------------------------------------------------------------------+
//| PRD 1.1/5.3: Verify if current server time matches active sessions|
//| Note: Sydney, Tokyo, London, and New York overlap handled.       |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   //--- PRD 7.2: Use TimeTradeServer in Strategy Tester for synchronization
   datetime now = (MQLInfoInteger(MQL_TESTER)) ? TimeTradeServer() : TimeGMT();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   //--- Individual weekday exclusion toggles (PRD 5.3)
   if(dt.day_of_week == 1 && !MondayActive) return false;
   if(dt.day_of_week == 2 && !TuesdayActive) return false;
   if(dt.day_of_week == 3 && !WednesdayActive) return false;
   if(dt.day_of_week == 4 && !ThursdayActive) return false;
   if(dt.day_of_week == 5 && !FridayActive) return false;
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false; // Weekend block
   
   int hour = dt.hour;
   
   //--- Session active checks (inclusive hourly ranges per PRD 5.3)
   if(SydneyActive && (hour >= 22 || hour < 7)) return true;
   if(TokyoActive && (hour >= 0 && hour < 9)) return true;
   if(LondonActive && (hour >= 8 && hour < 17)) return true;
   if(NewYorkActive && (hour >= 13 && hour < 22)) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| PRD 4, 5.6: Core Strategy Logic - Generates trade signals        |
//| Enforces Universal Alignment Matrix across enabled indicators.   |
//+------------------------------------------------------------------+
int GetStrategySignal(int strategyNum)
{
   //--- Local mappings for the requested strategy index (1 or 2)
   bool useRSI, useEMA, useADX, useBB;
   ENUM_TF_OPTIONS tfRSI, tfEMA, tfADX, tfBB;
   int rsiPeriod, adxPeriod, bbPeriod = 20; // Standard BB Period
   double rsiSellLevel, bbDev;
   ENUM_EMA_SETS emaSet;
   ENUM_EMA_TREND_RULE emaRule;
   ENUM_ADX_TREND_RULE adxRule;
   ENUM_BB_TREND_RULE bbRule;
   
   //--- Strategy-specific thresholds
   double adxTrendLevel, adxExtremeLevel, adxRangeLevel, bbBufferPips;
   
   if(strategyNum == 1) {
      useRSI = S1UseRSI; tfRSI = S1RSITimeframe; rsiPeriod = S1RSIPeriod; rsiSellLevel = S1RSISellLevel;
      useEMA = S1UseEMA; tfEMA = S1EMATimeframe; emaSet = S1EMAPeriods; emaRule = S1EMATrendRule;
      useADX = S1UseADX; tfADX = S1ADXTimeframe; adxPeriod = S1ADXPeriod; adxRule = S1ADXTrendRule;
      useBB = S1UseBB; tfBB = S1BBTimeframe; bbDev = S1BBDeviations; bbRule = S1BBRule;
      
      adxTrendLevel   = S1ADXTrendLevel;
      adxExtremeLevel = S1ADXExtremeLevel;
      adxRangeLevel   = S1ADXRangeLevel;
      bbBufferPips    = S1BBBufferPips;
   } else {
      useRSI = S2UseRSI; tfRSI = S2RSITimeframe; rsiPeriod = S2RSIPeriod; rsiSellLevel = S2RSISellLevel;
      useEMA = S2UseEMA; tfEMA = S2EMATimeframe; emaSet = S2EMAPeriods; emaRule = S2EMATrendRule;
      useADX = S2UseADX; tfADX = S2ADXTimeframe; adxPeriod = S2ADXPeriod; adxRule = S2ADXTrendRule;
      useBB = S2UseBB; tfBB = S2BBTimeframe; bbDev = S2BBDeviations; bbRule = S2BBRule;
      
      adxTrendLevel   = S2ADXTrendLevel;
      adxExtremeLevel = S2ADXExtremeLevel;
      adxRangeLevel   = S2ADXRangeLevel;
      bbBufferPips    = S2BBBufferPips;
   }

   //--- Signal tracking for matrix evaluation
   ENUM_IND_SIGNAL rsiSig = IND_PASS, emaSig = IND_PASS, adxSig = IND_PASS, bbSig = IND_PASS;
   bool anyActive = false;

   //--- PRD 4: RSI Component (Directional Only)
   if(useRSI) {
      anyActive = true;
      rsiSig = IND_NEUTRAL; // Default to neutral/block
      int h = (strategyNum == 1) ? g_hRSI1 : g_hRSI2;
      if(h == INVALID_HANDLE) {
         h = iRSI(_Symbol, (ENUM_TIMEFRAMES)tfRSI, rsiPeriod, PRICE_CLOSE);
         if(strategyNum == 1) g_hRSI1 = h; else g_hRSI2 = h;
      }
      double rsi[];
      if(CopyBuffer(h, 0, 0, 2, rsi) == 2) {
         if(rsi[0] < (100 - rsiSellLevel) && rsi[1] >= (100 - rsiSellLevel)) rsiSig = IND_BUY;
         else if(rsi[0] > rsiSellLevel && rsi[1] <= rsiSellLevel) rsiSig = IND_SELL;
      }
   }

   //--- PRD 4, 5.6: EMA Component (Trend or Ranging)
   if(useEMA) {
      anyActive = true;
      emaSig = IND_NEUTRAL;
      int f, m, s;
      GetEMAPeriods(emaSet, f, m, s);
      int hf = (strategyNum == 1) ? g_hEMA1_F : g_hEMA2_F;
      int hm = (strategyNum == 1) ? g_hEMA1_M : g_hEMA2_M;
      int hs = (strategyNum == 1) ? g_hEMA1_S : g_hEMA2_S;
      
      if(hf == INVALID_HANDLE) {
         hf = iMA(_Symbol, (ENUM_TIMEFRAMES)tfEMA, f, 0, MODE_EMA, PRICE_CLOSE);
         if(strategyNum == 1) g_hEMA1_F = hf; else g_hEMA2_F = hf;
      }
      if(hm == INVALID_HANDLE) {
         hm = iMA(_Symbol, (ENUM_TIMEFRAMES)tfEMA, m, 0, MODE_EMA, PRICE_CLOSE);
         if(strategyNum == 1) g_hEMA1_M = hm; else g_hEMA2_M = hm;
      }
      if(hs == INVALID_HANDLE) {
         hs = iMA(_Symbol, (ENUM_TIMEFRAMES)tfEMA, s, 0, MODE_EMA, PRICE_CLOSE);
         if(strategyNum == 1) g_hEMA1_S = hs; else g_hEMA2_S = hs;
      }
      
      double emaF[], emaM[], emaS[];
      if(CopyBuffer(hf, 0, 0, 1, emaF) == 1 && CopyBuffer(hm, 0, 0, 1, emaM) == 1 && CopyBuffer(hs, 0, 0, 1, emaS) == 1) {
         bool isBullTrend = (emaF[0] > emaM[0] && emaM[0] > emaS[0]);
         bool isBearTrend = (emaF[0] < emaM[0] && emaM[0] < emaS[0]);
         
         if(emaRule == EMA_WITH_TREND) {
            if(isBullTrend) emaSig = IND_BUY;
            else if(isBearTrend) emaSig = IND_SELL;
         }
         else if(emaRule == EMA_AGAINST_TREND) {
            if(isBullTrend) emaSig = IND_SELL;
            else if(isBearTrend) emaSig = IND_BUY;
         }
         else if(emaRule == EMA_RANGING) {
            if(!isBullTrend && !isBearTrend) emaSig = IND_PASS;
         }
      }
   }

   //--- PRD 4, 5.6: ADX Component (Trend, Extreme, or Ranging)
   if(useADX) {
      anyActive = true;
      adxSig = IND_NEUTRAL;
      int h = (strategyNum == 1) ? g_hADX1 : g_hADX2;
      if(h == INVALID_HANDLE) {
         h = iADX(_Symbol, (ENUM_TIMEFRAMES)tfADX, adxPeriod);
         if(strategyNum == 1) g_hADX1 = h; else g_hADX2 = h;
      }
      double adx[], diPlus[], diMinus[];
      if(CopyBuffer(h, 0, 0, 1, adx) == 1 && CopyBuffer(h, 1, 0, 1, diPlus) == 1 && CopyBuffer(h, 2, 0, 1, diMinus) == 1) {
         double val = adx[0];
         bool buyDI = (diPlus[0] > diMinus[0]);
         bool sellDI = (diMinus[0] > diPlus[0]);
         
         if(adxRule == ADX_WITH_TREND) {
            if(val > adxTrendLevel) {
               if(buyDI) adxSig = IND_BUY;
               else if(sellDI) adxSig = IND_SELL;
            }
         }
         else if(adxRule == ADX_WITH_TREND_AVOID_EXTREME) {
            if(val > adxTrendLevel && val < adxExtremeLevel) {
               if(buyDI) adxSig = IND_BUY;
               else if(sellDI) adxSig = IND_SELL;
            }
         }
         else if(adxRule == ADX_AGAINST_TREND) {
            if(val > adxExtremeLevel) {
               if(buyDI) adxSig = IND_SELL; // Trade AGAINST dominant DI
               else if(sellDI) adxSig = IND_BUY;
            }
         }
         else if(adxRule == ADX_RANGING) {
            if(val < adxRangeLevel) adxSig = IND_PASS;
         }
      }
   }

   //--- PRD 4, 5.6: Bollinger Band Component (Extreme Avoidance or Mean Reversion)
   if(useBB) {
      anyActive = true;
      bbSig = IND_NEUTRAL;
      int h = (strategyNum == 1) ? g_hBB1 : g_hBB2;
      if(h == INVALID_HANDLE) {
         h = iBands(_Symbol, (ENUM_TIMEFRAMES)tfBB, bbPeriod, 0, bbDev, PRICE_CLOSE);
         if(strategyNum == 1) g_hBB1 = h; else g_hBB2 = h;
      }
      double upper[], lower[];
      if(CopyBuffer(h, 1, 0, 1, upper) == 1 && CopyBuffer(h, 2, 0, 1, lower) == 1) {
         double ask = m_symbol.Ask();
         double bid = m_symbol.Bid();
         double buffer = bbBufferPips * m_symbol.Point() * 10;
         
         if(bbRule == BB_AVOID_EXTREME_TREND) {
            //--- Allow trade only if NOT pushing the outer boundaries (with buffer)
            bool buyAllowed = (ask < upper[0] - buffer);
            bool sellAllowed = (bid > lower[0] + buffer);
            
            if(buyAllowed && sellAllowed) {
               // This rule is essentially a directionless filter/pass when inside the channel
               if(buyAllowed && sellAllowed) bbSig = IND_PASS; 
               else if(buyAllowed) bbSig = IND_BUY;
               else if(sellAllowed) bbSig = IND_SELL;
            }
         }
         else if(bbRule == BB_AGAINST_TREND) {
            //--- Reversal: Buy at Lower, Sell at Upper
            if(ask <= lower[0]) bbSig = IND_BUY;
            else if(bid >= upper[0]) bbSig = IND_SELL;
         }
      }
   }

   if(!anyActive) return 0;

   //--- 5.6 Universal Alignment Matrix Evaluation
   //--- 1. Check for Blockers (NEUTRAL)
   if(rsiSig == IND_NEUTRAL || emaSig == IND_NEUTRAL || adxSig == IND_NEUTRAL || bbSig == IND_NEUTRAL) return 0;
   
   //--- 2. Check for Conflict (Buy and Sell existing together)
   bool hasBuy = (rsiSig == IND_BUY || emaSig == IND_BUY || adxSig == IND_BUY || bbSig == IND_BUY);
   bool hasSell = (rsiSig == IND_SELL || emaSig == IND_SELL || adxSig == IND_SELL || bbSig == IND_SELL);
   if(hasBuy && hasSell) return 0;
   
   //--- 3. Directional Execution
   if(hasBuy) return 1;
   if(hasSell) return -1;
   
   //--- 4. All PASS or No Signals (Directionless)
   return 0;
}

//+------------------------------------------------------------------+
//| Placeholder: Get Random Signal for Optimization Tests            |
//| Note: Should be replaced by PRD 2 requirements in production.    |
//+------------------------------------------------------------------+
int GetRandomSignal()
{
   return (MathRand() % 2 == 0) ? 1 : -1;
}
