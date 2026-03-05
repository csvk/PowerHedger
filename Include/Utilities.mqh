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
//| PRD 4: Core Strategy Logic - Generates trade signals             |
//| Processes RSI, EMA alignment, ADX trend, and Bollinger Bands.    |
//+------------------------------------------------------------------+
int GetStrategySignal(int strategyNum)
{
   //--- Local mappings for the requested strategy index (1 or 2)
   bool useRSI, useEMA, useADX, useBB;
   ENUM_TF_OPTIONS tfRSI, tfEMA, tfADX, tfBB;
   int rsiPeriod, adxPeriod;
   double rsiSellLevel, adxThreshold, bbDev;
   ENUM_EMA_SETS emaSet;
   ENUM_TREND_RULE emaRule, adxRule;
   ENUM_BB_RULE bbRule;
   
   if(strategyNum == 1) {
      useRSI = S1UseRSI; tfRSI = S1RSITimeframe; rsiPeriod = S1RSIPeriod; rsiSellLevel = S1RSISellLevel;
      useEMA = S1UseEMA; tfEMA = S1EMATimeframe; emaSet = S1EMAPeriods; emaRule = S1EMATrendRule;
      useADX = S1UseADX; tfADX = S1ADXTimeframe; adxPeriod = S1ADXPeriod; adxThreshold = S1ADXThreshold; adxRule = S1ADXTrendRule;
      useBB = S1UseBB; tfBB = S1BBTimeframe; bbDev = S1BBDeviations; bbRule = S1BBRule;
   } else {
      useRSI = S2UseRSI; tfRSI = S2RSITimeframe; rsiPeriod = S2RSIPeriod; rsiSellLevel = S2RSISellLevel;
      useEMA = S2UseEMA; tfEMA = S2EMATimeframe; emaSet = S2EMAPeriods; emaRule = S2EMATrendRule;
      useADX = S2UseADX; tfADX = S2ADXTimeframe; adxPeriod = S2ADXPeriod; adxThreshold = S2ADXThreshold; adxRule = S2ADXTrendRule;
      useBB = S2UseBB; tfBB = S2BBTimeframe; bbDev = S2BBDeviations; bbRule = S2BBRule;
   }

   bool buySignal = true;
   bool sellSignal = true;
   bool anyActive = false;

   //--- PRD 4: RSI Component
   if(useRSI) {
      anyActive = true;
      int h = (strategyNum == 1) ? g_hRSI1 : g_hRSI2;
      if(h == INVALID_HANDLE) {
         h = iRSI(_Symbol, (ENUM_TIMEFRAMES)tfRSI, rsiPeriod, PRICE_CLOSE);
         if(strategyNum == 1) g_hRSI1 = h; else g_hRSI2 = h;
      }
      double rsi[];
      if(CopyBuffer(h, 0, 0, 2, rsi) == 2) {
         //--- Level crossover logic
         if(!(rsi[0] < (100 - rsiSellLevel) && rsi[1] >= (100 - rsiSellLevel))) buySignal = false;
         if(!(rsi[0] > rsiSellLevel && rsi[1] <= rsiSellLevel)) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

   //--- PRD 4: EMA Component (Stacked Alignment)
   if(useEMA) {
      anyActive = true;
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
         //--- Buy: Fast > Medium > Slow | Sell: Fast < Medium < Slow
         if(!(emaF[0] > emaM[0] && emaM[0] > emaS[0])) buySignal = false;
         if(!(emaF[0] < emaM[0] && emaM[0] < emaS[0])) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

   //--- PRD 4: ADX Component
   if(useADX) {
      anyActive = true;
      int h = (strategyNum == 1) ? g_hADX1 : g_hADX2;
      if(h == INVALID_HANDLE) {
         h = iADX(_Symbol, (ENUM_TIMEFRAMES)tfADX, adxPeriod);
         if(strategyNum == 1) g_hADX1 = h; else g_hADX2 = h;
      }
      double adx[], diPlus[], diMinus[];
      if(CopyBuffer(h, 0, 0, 1, adx) == 1 && CopyBuffer(h, 1, 0, 1, diPlus) == 1 && CopyBuffer(h, 2, 0, 1, diMinus) == 1) {
         //--- Strong trend (ADX > Threshold) and Directional Alignment
         if(!(adx[0] > adxThreshold && diPlus[0] > diMinus[0])) buySignal = false;
         if(!(adx[0] > adxThreshold && diMinus[0] > diPlus[0])) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

   //--- PRD 4: Bollinger Band Component
   if(useBB) {
      anyActive = true;
      int h = (strategyNum == 1) ? g_hBB1 : g_hBB2;
      if(h == INVALID_HANDLE) {
         h = iBands(_Symbol, (ENUM_TIMEFRAMES)tfBB, 20, 0, bbDev, PRICE_CLOSE);
         if(strategyNum == 1) g_hBB1 = h; else g_hBB2 = h;
      }
      double upper[], lower[];
      if(CopyBuffer(h, 1, 0, 1, upper) == 1 && CopyBuffer(h, 2, 0, 1, lower) == 1) {
         //--- Buy on Lower Band | Sell on Upper Band
         if(!(m_symbol.Ask() <= lower[0])) buySignal = false;
         if(!(m_symbol.Bid() >= upper[0])) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

   if(!anyActive) return 0;
   if(buySignal) return 1;
   if(sellSignal) return -1;
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
