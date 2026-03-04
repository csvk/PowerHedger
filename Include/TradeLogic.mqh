//+------------------------------------------------------------------+
//|                                                   TradeLogic.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include "Globals.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "Persistence.mqh"

//+------------------------------------------------------------------+
//| Entry: Check New Entries                                         |
//+------------------------------------------------------------------+
void CheckNewEntries()
{
   bool isFlat = (g_totalBuyLots == 0 && g_totalSellLots == 0);
   bool isInside = (g_totalBuyLots > 0 && g_totalSellLots > 0);
   
   if(!isFlat && !isInside) return;
   
   if(isFlat && !IsSessionActive()) return;
   
   if(isInside) {
      double minGap = InsidePipMultiplier * HedgePips * m_symbol.Point() * 10;
      double nearestBuy = -1, nearestSell = -1;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol) {
            if(m_position.PositionType() == POSITION_TYPE_BUY) {
               if(nearestBuy == -1 || m_position.PriceOpen() > nearestBuy) nearestBuy = m_position.PriceOpen();
            } else {
               if(nearestSell == -1 || m_position.PriceOpen() < nearestSell) nearestSell = m_position.PriceOpen();
            }
         }
      }
      if(nearestBuy != -1 && nearestSell != -1) {
         if(MathAbs(m_symbol.Ask() - nearestBuy) < minGap || MathAbs(m_symbol.Bid() - nearestSell) < minGap) return;
      }
   }

   int signal = GetRandomSignal();
   string keyword = isFlat ? "New Sequence" : "Inside Trade";
   
   if(signal != 0) {
      double volume = LotSize;
      if(signal == 1 && (g_totalBuyLots + volume) <= MaxLots) {
         string comment = StringFormat("<%d> %s", g_buySequence++, keyword);
         m_trade.Buy(volume, _Symbol, m_symbol.Ask(), 0, 0, comment);
      } else if(signal == -1 && (g_totalSellLots + volume) <= MaxLots) {
         string comment = StringFormat("<%d> %s", g_sellSequence++, keyword);
         m_trade.Sell(volume, _Symbol, m_symbol.Bid(), 0, 0, comment);
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Trim Farthest First                                  |
//+------------------------------------------------------------------+
void TrimPositions(double amount)
{
   if(amount <= 0) return;
   double pool = amount + g_profitTally;
   g_profitTally = 0;
   
   ENUM_POSITION_TYPE targetType = (g_totalBuyLots > g_totalSellLots) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   
   while(pool > 0) {
      ulong ticket = 0;
      double maxDist = -1;
      double vol = 0;
      double farthestP = 0;
      
      double currentPrice = (targetType == POSITION_TYPE_BUY) ? m_symbol.Bid() : m_symbol.Ask();
      
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == targetType) {
            double dist = MathAbs(m_position.PriceOpen() - currentPrice);
            if(dist > maxDist) {
               maxDist = dist;
               ticket = m_position.Ticket();
               vol = m_position.Volume();
               farthestP = m_position.PriceOpen();
            }
         }
      }
      
      if(ticket == 0) break;
      double lossPerLot = MathAbs(currentPrice - farthestP) / m_symbol.Point() * m_symbol.TickValue();
      if(lossPerLot <= 0) break;
      double lotToClose = pool / lossPerLot;
      lotToClose = MathMin(lotToClose, vol);
      lotToClose = MathFloor(lotToClose / m_symbol.LotsStep()) * m_symbol.LotsStep();
      if(lotToClose >= m_symbol.LotsMin()) {
         if(m_trade.PositionClosePartial(ticket, lotToClose)) pool -= (lotToClose * lossPerLot);
         else break;
      } else { g_profitTally = pool; break; }
   }
   SaveState();
}

//+------------------------------------------------------------------+
//| Management: Trailing & Theoretical Trimming                      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol) {
         double pips = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - m_position.PriceOpen()) : (m_position.PriceOpen() - m_symbol.Ask());
         pips /= (m_symbol.Point() * 10);
         if(pips >= LockProfitPips) {
            double newSL = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - TrailingStopPips * m_symbol.Point() * 10) : (m_symbol.Ask() + TrailingStopPips * m_symbol.Point() * 10);
            
            double lockedPips = (m_position.PositionType() == POSITION_TYPE_BUY) ? (newSL - m_position.PriceOpen()) : (m_position.PriceOpen() - newSL);
            lockedPips /= (m_symbol.Point() * 10);
            
            if(lockedPips > 0) {
               double profit = lockedPips * m_position.Volume() * m_symbol.TickValue();
               TrimPositions(profit * (1.0 - KeepProfitPercent));
            }

            if(m_position.StopLoss() == 0 || (m_position.PositionType() == POSITION_TYPE_BUY && newSL > m_position.StopLoss()) || (m_position.PositionType() == POSITION_TYPE_SELL && newSL < m_position.StopLoss())) m_trade.PositionModify(m_position.Ticket(), newSL, 0);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Hedge Squeeze                                        |
//+------------------------------------------------------------------+
void ManageHedgeSqueeze()
{
   if(g_hedgePoint <= 0) return;
   double dist = MathAbs(m_symbol.Bid() - g_hedgePoint) / (m_symbol.Point() * 10);
   if(dist > SqueezePips) {
      g_hedgePoint = (g_totalBuyLots > g_totalSellLots) ? (m_symbol.Bid() + HedgePips * m_symbol.Point() * 10) : (m_symbol.Bid() - HedgePips * m_symbol.Point() * 10);
      SaveState();
   }
   if((g_totalBuyLots > g_totalSellLots && m_symbol.Bid() <= g_hedgePoint) || (g_totalSellLots > g_totalBuyLots && m_symbol.Ask() >= g_hedgePoint)) {
      double vol = MathAbs(g_totalBuyLots - g_totalSellLots);
      if(vol >= m_symbol.LotsMin()) {
         if(g_totalBuyLots > g_totalSellLots) m_trade.Sell(vol, _Symbol, m_symbol.Bid(), 0, 0, StringFormat("<%d> Hedge", g_sellSequence++));
         else m_trade.Buy(vol, _Symbol, m_symbol.Ask(), 0, 0, StringFormat("<%d> Hedge", g_buySequence++));
         g_hedgePoint = -1;
         SaveState();
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Hedging Triggers                                     |
//+------------------------------------------------------------------+
void CheckHedgeTriggers()
{
   if(g_hedgePoint > 0 || g_totalBuyLots == g_totalSellLots) return;
   double limit = -1;
   if(g_totalBuyLots > g_totalSellLots) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_BUY) if(limit == -1 || m_position.PriceOpen() < limit) limit = m_position.PriceOpen();
      if(limit != -1 && m_symbol.Bid() <= (limit - HedgePips * m_symbol.Point() * 10)) m_trade.Sell(g_totalBuyLots - g_totalSellLots, _Symbol, m_symbol.Bid(), 0, 0, StringFormat("<%d> Hedge", g_sellSequence++));
   } else {
      for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_SELL) if(limit == -1 || m_position.PriceOpen() > limit) limit = m_position.PriceOpen();
      if(limit != -1 && m_symbol.Ask() >= (limit + HedgePips * m_symbol.Point() * 10)) m_trade.Buy(g_totalSellLots - g_totalBuyLots, _Symbol, m_symbol.Ask(), 0, 0, StringFormat("<%d> Hedge", g_buySequence++));
   }
}
