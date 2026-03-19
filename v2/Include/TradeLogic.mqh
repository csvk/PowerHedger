#ifndef _TRADELOGIC_MQH_
#define _TRADELOGIC_MQH_

//+------------------------------------------------------------------+
//|                                                   TradeLogic.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Trade Logic (v2)
   Description: Symmetrical Sequence Isolation, Manual Adoption, and Trimming.
   PRD Sections: 2 (Core Logic), 3 (Sequence Management), 4 (Hedging), 5 (Trimming)
*/

#include "Globals.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "Persistence.mqh"

//+------------------------------------------------------------------+
//| Helper: Close position or partial with a custom comment          |
//+------------------------------------------------------------------+
bool CloseWithComment(ulong ticket, double volume, string comment, long magic)
{
   if(!m_position.SelectByTicket(ticket)) return false;
   
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action       = TRADE_ACTION_DEAL;
   request.position     = ticket;
   request.symbol       = m_position.Symbol();
   request.volume       = (volume > m_position.Volume()) ? m_position.Volume() : volume;
   request.magic        = magic;
   request.comment      = comment;
   request.type         = (m_position.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price        = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(request.symbol, SYMBOL_BID) : SymbolInfoDouble(request.symbol, SYMBOL_ASK);
   request.deviation    = 10;
   
   uint filling = (uint)SymbolInfoInteger(request.symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) request.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0) request.type_filling = ORDER_FILLING_IOC;
   else request.type_filling = ORDER_FILLING_RETURN;
   
   if(!OrderSend(request, result)) {
      PrintFormat("[ERROR] CloseWithComment failed (Ticket: %I64u, Error: %d)", ticket, GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| PRD 3.1: Manual Trade Adoption                                   |
//| Scans for Magic 0 trades and assigns them a Sequence ID.         |
//+------------------------------------------------------------------+
void AdoptManualTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i) && m_position.Magic() == 0 && m_position.Symbol() == _Symbol)
      {
         ulong ticket = m_position.Ticket();
         bool alreadyMapped = false;
         for(int j=0; j<ArraySize(g_manualMaps); j++) {
            if(g_manualMaps[j].ticket == ticket) { alreadyMapped = true; break; }
         }
         
         if(!alreadyMapped) {
            long newMagic = GetNextMagic();
            int size = ArraySize(g_manualMaps);
            ArrayResize(g_manualMaps, size + 1);
            g_manualMaps[size].ticket = ticket;
            g_manualMaps[size].assignedMagic = newMagic;
            
            PrintFormat("[MANUAL] Adopted Manual Trade: Ticket %I64u assigned Sequence Magic %I64d", ticket, newMagic);
            TriggerSave();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 2.1: Entry Logic - One-Active-Trade Rule                     |
//+------------------------------------------------------------------+
void CheckNewEntries()
{
   if(IsActiveTradePresent()) return; // One-active-trade per chart rule
   if(!IsSessionActive()) return;

   int signal = 0;
   string stratName = "";
   
   if(EnableRandom) {
      signal = GetRandomSignal();
      stratName = "Random";
   } else {
      // Prioritize S1, then S2
      int s1 = GetStrategySignal(1);
      if(s1 != 0) { signal = s1; stratName = S1Name; }
      else {
         int s2 = GetStrategySignal(2);
         if(s2 != 0) { signal = s2; stratName = S2Name; }
      }
   }
   
   if(signal == 0) return;

   // Execution
   long magic = GetNextMagic();
   double volume = LotSize;
   string side = (signal == 1) ? "[LONG]" : "[SHORT]";
   string comment = StringFormat("[%I64d] %s %s", magic, side, stratName);
   
   m_trade.SetExpertMagicNumber(magic); // Set magic for THIS specific trade
   bool success = false;
   if(signal == 1) success = m_trade.Buy(volume, _Symbol, m_symbol.Ask(), 0, 0, comment);
   else success = m_trade.Sell(volume, _Symbol, m_symbol.Bid(), 0, 0, comment);
   
   if(success) PrintFormat("[SIGNAL] Entry Executed: %s", comment);
}

//+------------------------------------------------------------------+
//| PRD 4.1: Symmetrical Hedging                                     |
//| Locks an active sequence if price moves against it by HedgePips. |
//+------------------------------------------------------------------+
void ManageLockedSequences()
{
   for(int i=0; i<ArraySize(g_sequences); i++) {
      if(g_sequences[i].state == SEQ_ACTIVE) {
         double currentPrice = (g_sequences[i].volBuy > 0) ? m_symbol.Bid() : m_symbol.Ask();
         double dist = MathAbs(g_sequences[i].midPrice - currentPrice);
         
         if(dist >= HedgePips * m_symbol.Point() * 10) {
            double reqVol = (g_sequences[i].volBuy > 0) ? g_sequences[i].volBuy : g_sequences[i].volSell;
            
            if(reqVol > MaxLots) {
               PrintFormat("[WARNING] Hedge for Magic %I64d blocked by MaxLots (%.2f).", g_sequences[i].magic, MaxLots);
               continue;
            }
            
            m_trade.SetExpertMagicNumber(g_sequences[i].magic);
            bool success = false;
            string comment = StringFormat("[%I64d] [HEDGE] Locked", g_sequences[i].magic);
            if(g_sequences[i].volBuy > 0) success = m_trade.Sell(reqVol, _Symbol, m_symbol.Bid(), 0, 0, comment);
            else success = m_trade.Buy(reqVol, _Symbol, m_symbol.Ask(), 0, 0, comment);
            
            if(success) PrintFormat("[HEDGE] Sequence %I64d Locked Symmetrically (Vol: %.2f)", g_sequences[i].magic, reqVol);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 5.1: Symmetrical Trimming Logic                              |
//| Uses ProfitTally to close equal volumes of Buy/Sell legs.        |
//+------------------------------------------------------------------+
void PerformSymmetricalTrimming()
{
   if(TimeCurrent() == g_lastTrimTime) return; // Guard against double-trimming in same tick
   
   ulong originalTicket = m_position.Ticket();
   
   double usableProfit = g_profitTally;
   if(usableProfit <= 0) return;
   
   int farthestIdx = -1;
   double maxDist = -1;
   double currentPrice = (m_symbol.Ask() + m_symbol.Bid()) / 2.0;

   for(int i=0; i<ArraySize(g_sequences); i++) {
      if(g_sequences[i].state == SEQ_LOCKED) {
         double dist = MathAbs(g_sequences[i].midPrice - currentPrice);
         if(dist > maxDist) { maxDist = dist; farthestIdx = i; }
      }
   }
   
   if(farthestIdx == -1) return;
   
   SequenceInfo seq = g_sequences[farthestIdx];
   double entryB = 0, entryS = 0;
   double volB = 0, volS = 0;
   
   for(int j=PositionsTotal()-1; j>=0; j--) {
      if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol) {
         long magic = m_position.Magic();
         if(magic == 0) {
            for(int k=0; k<ArraySize(g_manualMaps); k++) {
               if(m_position.Ticket() == g_manualMaps[k].ticket) { magic = g_manualMaps[k].assignedMagic; break; }
            }
         }
         if(magic == seq.magic) {
            if(m_position.PositionType() == POSITION_TYPE_BUY) { entryB += m_position.PriceOpen() * m_position.Volume(); volB += m_position.Volume(); }
            else { entryS += m_position.PriceOpen() * m_position.Volume(); volS += m_position.Volume(); }
         }
      }
   }
   
   if(volB == 0 || volS == 0) return;
   double avgB = entryB / volB;
   double avgS = entryS / volS;
   
   // PRD 5.2: Cost calculation considering combined net PnL (distance-neutral)
   double buyPnLPerLot = (m_symbol.Bid() - avgB) / m_symbol.Point() * m_symbol.TickValue();
   double sellPnLPerLot = (avgS - m_symbol.Ask()) / m_symbol.Point() * m_symbol.TickValue();
   double combinedPnLPerLot = buyPnLPerLot + sellPnLPerLot;

   double costPerLot = (combinedPnLPerLot < 0) ? MathAbs(combinedPnLPerLot) : 0;
   if(costPerLot <= 0) costPerLot = 0.000001; // Fallback to avoid division by zero
   
   double lotsToClose = usableProfit / costPerLot;
   lotsToClose = MathMin(lotsToClose, MathMin(volB, volS));
   lotsToClose = MathFloor(lotsToClose / m_symbol.LotsStep()) * m_symbol.LotsStep();
   
   if(lotsToClose >= m_symbol.LotsMin()) {
      double cost = lotsToClose * costPerLot;
      PrintFormat("[TRIM] Symmetrical Trim: Magic %I64d, Lots: %.2f, Cost: %.2f", seq.magic, lotsToClose, cost);
      
      string commentBuy = StringFormat("[%I64d] [TRIM] P:%.2f", seq.magic, -(buyPnLPerLot * lotsToClose));
      string commentSell = StringFormat("[%I64d] [TRIM] P:%.2f", seq.magic, -(sellPnLPerLot * lotsToClose));
      
      // Close Buy Leg
      for(int j=PositionsTotal()-1; j>=0; j--) {
         if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol) {
             long magic = m_position.Magic();
             if(magic == 0) { for(int k=0; k<ArraySize(g_manualMaps); k++) if(m_position.Ticket()==g_manualMaps[k].ticket) { magic=g_manualMaps[k].assignedMagic; break; } }
             if(magic == seq.magic && m_position.PositionType() == POSITION_TYPE_BUY) {
                 CloseWithComment(m_position.Ticket(), lotsToClose, commentBuy, magic);
                 break;
             }
         }
      }
      // Close Sell Leg
      for(int j=PositionsTotal()-1; j>=0; j--) {
         if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol) {
             long magic = m_position.Magic();
             if(magic == 0) { for(int k=0; k<ArraySize(g_manualMaps); k++) if(m_position.Ticket()==g_manualMaps[k].ticket) { magic=g_manualMaps[k].assignedMagic; break; } }
             if(magic == seq.magic && m_position.PositionType() == POSITION_TYPE_SELL) {
                 CloseWithComment(m_position.Ticket(), lotsToClose, commentSell, magic);
                 break;
             }
         }
      }
      
      PrintFormat("[TRIM] Order Sent: Magic %I64d, Lots: %.2f (Estimated Cost: %.2f)", seq.magic, lotsToClose, cost);
      g_lastTrimTime = TimeCurrent();
      TriggerSave();
   }
   
   if(originalTicket > 0) m_position.SelectByTicket(originalTicket);
}

//+------------------------------------------------------------------+
//| PRD 4.2: Capitulation Rule                                       |
//+------------------------------------------------------------------+
void CapitulationRule()
{
   if(g_totalBuyLots > MaxLots * 2.0 || g_totalSellLots > MaxLots * 2.0) {
      int farthestIdx = -1;
      double maxDist = -1;
      double currentPrice = (m_symbol.Ask() + m_symbol.Bid()) / 2.0;
      for(int i=0; i<ArraySize(g_sequences); i++) {
         if(g_sequences[i].state == SEQ_LOCKED) {
            double dist = MathAbs(g_sequences[i].midPrice - currentPrice);
            if(dist > maxDist) { maxDist = dist; farthestIdx = i; }
         }
      }
      if(farthestIdx != -1) {
         long magic = g_sequences[farthestIdx].magic;
         PrintFormat("[CAPITULATION] Risk Alert! Closing Sequence %I64d.", magic);
         string comment = StringFormat("[%I64d] [LOSS] Capitulation", magic);
         for(int j=PositionsTotal()-1; j>=0; j--) {
            if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol) {
               long m = m_position.Magic();
               if(m == 0) { for(int k=0; k<ArraySize(g_manualMaps); k++) if(m_position.Ticket()==g_manualMaps[k].ticket) { m=g_manualMaps[k].assignedMagic; break; } }
               if(m == magic) CloseWithComment(m_position.Ticket(), m_position.Volume(), comment, m);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 5.1: Trailing Stop for Active Trades                         |
//+------------------------------------------------------------------+
void ManageTrailingSL()
{
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol) {
         long magic = m_position.Magic();
         bool isActive = false;
         for(int j=0; j<ArraySize(g_sequences); j++) {
            if(g_sequences[j].magic == magic && g_sequences[j].state == SEQ_ACTIVE) { isActive = true; break; }
         }
         if(!isActive) continue;
         
         double pips = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - m_position.PriceOpen()) : (m_position.PriceOpen() - m_symbol.Ask());
         pips /= (m_symbol.Point() * 10);
         
         if(pips >= LockProfitPips) {
            double newSL = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - TrailingStopPips * m_symbol.Point() * 10) : (m_symbol.Ask() + TrailingStopPips * m_symbol.Point() * 10);
            double currentSL = m_position.StopLoss();
            
            // Re-check betterment before processing harvest
            bool better = (m_position.PositionType() == POSITION_TYPE_BUY) ? (newSL > currentSL || currentSL == 0) : (newSL < currentSL || currentSL == 0);
            if(!better) continue;

            ulong ticket = m_position.Ticket();
            if(m_trade.PositionModify(ticket, newSL, 0)) {
               if(currentSL == 0) {
                  PrintFormat("[TRADE] Profit Locked: Ticket %I64u SL set at %.5f (Pips: %.1f, TrailPips: %.1f)", 
                              ticket, newSL, pips, TrailingStopPips);
               } else {
                  PrintFormat("[TRADE] Trailing Stop updated: %.5f -> %.5f (Ticket %I64u, Pips: %.1f, TrailPips: %.1f)", 
                              currentSL, newSL, ticket, pips, TrailingStopPips);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 5.1: Real-time Profit Recon                                  |
//+------------------------------------------------------------------+
void ReconcileRecentDeals()
{
   if(HistorySelect(0, TimeCurrent())) {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++) {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket > g_lastProcessedDeal) {
            long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) {
               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               double comm = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
               double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
               double net = profit + comm + swap;
               
               string dealComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
               long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
               double amountToAdd = 0;
               // Booked Profit (At Close)
               if(StringFind(dealComment, "[TRIM]") < 0 && HasLockedSequences()) {
                  if(net > 0) {
                     amountToAdd = net * (KeepProfitPercent / 100.0);
                     double unharvestedAmount = net - amountToAdd;
                     g_unharvestedProfit += unharvestedAmount;
                     PrintFormat("[TRIM] Target Profit Harvested: Magic %I64d, Net: %.2f, Amount (%.0f%%): +%.2f, Unharvested Added: %.2f, Total Unharvested: %.2f", 
                                 dealMagic, net, KeepProfitPercent, amountToAdd, unharvestedAmount, g_unharvestedProfit);
                  }
               } else if (StringFind(dealComment, "[TRIM]") >= 0) {
                  // Deal generated by Symmetrical Trimming
                  g_profitTally += net;
                  PrintFormat("[TRIM] Realized PnL applied to Tally: Magic %I64d, DealNet: %.2f, New Tally: %.2f", dealMagic, net, g_profitTally);
                  TriggerSave();
               }
               
               if(amountToAdd > 0) {
                  g_profitTally += amountToAdd;
                  TriggerSave();
                  SaveStateIfNeeded();
                  PerformSymmetricalTrimming();
               }
            }
            g_lastProcessedDeal = dealTicket;
            TriggerSave();
         }
      }
   }
}

#endif // _TRADELOGIC_MQH_
