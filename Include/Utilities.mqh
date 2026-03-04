//+------------------------------------------------------------------+
//|                                                    Utilities.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include "Globals.mqh"
#include "Inputs.mqh"

//+------------------------------------------------------------------+
//| Helper: Calculate Volumetric Balances                            |
//+------------------------------------------------------------------+
void CalculateBalances()
{
   g_totalBuyLots = 0;
   g_totalSellLots = 0;
   
   bool hasBuy = false;
   bool hasSell = false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol)
         {
            if(m_position.PositionType() == POSITION_TYPE_BUY)
            {
               g_totalBuyLots += m_position.Volume();
               hasBuy = true;
            }
            else if(m_position.PositionType() == POSITION_TYPE_SELL)
            {
               g_totalSellLots += m_position.Volume();
               hasSell = true;
            }
         }
      }
   }
   
   if(!hasBuy) g_buySequence = 1;
   if(!hasSell) g_sellSequence = 1;
}

//+------------------------------------------------------------------+
//| Helper: Get EMA Periods from Enum                                |
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
//| Helper: Check Session Filters (UTC)                              |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   datetime now = (MQLInfoInteger(MQL_TESTER)) ? TimeTradeServer() : TimeGMT();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   if(dt.day_of_week == 1 && !MondayActive) return false;
   if(dt.day_of_week == 2 && !TuesdayActive) return false;
   if(dt.day_of_week == 3 && !WednesdayActive) return false;
   if(dt.day_of_week == 4 && !ThursdayActive) return false;
   if(dt.day_of_week == 5 && !FridayActive) return false;
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false; 
   
   int hour = dt.hour;
   
   if(SydneyActive && (hour >= 22 || hour < 7)) return true;
   if(TokyoActive && (hour >= 0 && hour < 9)) return true;
   if(LondonActive && (hour >= 8 && hour < 17)) return true;
   if(NewYorkActive && (hour >= 13 && hour < 22)) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Calculate Signal for a Strategy                          |
//+------------------------------------------------------------------+
int GetStrategySignal(int strategyNum)
{
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

   if(useRSI) {
      anyActive = true;
      int h = (strategyNum == 1) ? g_hRSI1 : g_hRSI2;
      if(h == INVALID_HANDLE) {
         h = iRSI(_Symbol, (ENUM_TIMEFRAMES)tfRSI, rsiPeriod, PRICE_CLOSE);
         if(strategyNum == 1) g_hRSI1 = h; else g_hRSI2 = h;
      }
      double rsi[];
      if(CopyBuffer(h, 0, 0, 2, rsi) == 2) {
         if(!(rsi[0] < (100 - rsiSellLevel) && rsi[1] >= (100 - rsiSellLevel))) buySignal = false;
         if(!(rsi[0] > rsiSellLevel && rsi[1] <= rsiSellLevel)) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

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
         if(!(emaF[0] > emaM[0] && emaM[0] > emaS[0])) buySignal = false;
         if(!(emaF[0] < emaM[0] && emaM[0] < emaS[0])) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

   if(useADX) {
      anyActive = true;
      int h = (strategyNum == 1) ? g_hADX1 : g_hADX2;
      if(h == INVALID_HANDLE) {
         h = iADX(_Symbol, (ENUM_TIMEFRAMES)tfADX, adxPeriod);
         if(strategyNum == 1) g_hADX1 = h; else g_hADX2 = h;
      }
      double adx[], diPlus[], diMinus[];
      if(CopyBuffer(h, 0, 0, 1, adx) == 1 && CopyBuffer(h, 1, 0, 1, diPlus) == 1 && CopyBuffer(h, 2, 0, 1, diMinus) == 1) {
         if(!(adx[0] > adxThreshold && diPlus[0] > diMinus[0])) buySignal = false;
         if(!(adx[0] > adxThreshold && diMinus[0] > diPlus[0])) sellSignal = false;
      } else { buySignal = false; sellSignal = false; }
   }

   if(useBB) {
      anyActive = true;
      int h = (strategyNum == 1) ? g_hBB1 : g_hBB2;
      if(h == INVALID_HANDLE) {
         h = iBands(_Symbol, (ENUM_TIMEFRAMES)tfBB, 20, 0, bbDev, PRICE_CLOSE);
         if(strategyNum == 1) g_hBB1 = h; else g_hBB2 = h;
      }
      double upper[], lower[];
      if(CopyBuffer(h, 1, 0, 1, upper) == 1 && CopyBuffer(h, 2, 0, 1, lower) == 1) {
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
//| Helper: Get Random Signal for Testing                            |
//+------------------------------------------------------------------+
int GetRandomSignal()
{
   return (MathRand() % 2 == 0) ? 1 : -1;
}
