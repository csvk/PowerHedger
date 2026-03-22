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
   PRD Section 8: Requirement for line-by-line / block-level annotations.
   Aligns with Sections: 2 (Core Logic), 3 (Sequence Management), 4 (Hedging), 5 (Trimming)
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
//| PRD 3.1 & 6: Manual Trade Adoption                               |
//| Scans for Magic 0 trades on the same symbol and assigns a unique |
//| Sequence ID to bring them under EA management (Trailing/Hedging).|
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
//| Multi-strategy evaluation with Priority and Session enforcement. |
//+------------------------------------------------------------------+
void CheckNewEntries()
{
   if(IsActiveTradePresent()) return; // One-active-trade per chart rule
   if(!IsSessionActive()) return;

   int signal = 0;
   string stratName = "";
   string explanation = "";
   
   if(EnableRandom) {
      signal = GetRandomSignal();
      stratName = "Random";
      explanation = "--------------------------------------------------\n- Mode: Random Signal (Testing)\n--------------------------------------------------";
   } else {
      int p[3];
      switch(PrioritizeStrategy) {
         case PRIORITY_S1_S2_S3: p[0]=1; p[1]=2; p[2]=3; break;
         case PRIORITY_S2_S1_S3: p[0]=2; p[1]=1; p[2]=3; break;
         case PRIORITY_S1_S3_S2: p[0]=1; p[1]=3; p[2]=2; break;
         case PRIORITY_S2_S3_S1: p[0]=2; p[1]=3; p[2]=1; break;
         case PRIORITY_S3_S1_S2: p[0]=3; p[1]=1; p[2]=2; break;
         case PRIORITY_S3_S2_S1: p[0]=3; p[1]=2; p[2]=1; break;
         default: p[0]=1; p[1]=2; p[2]=3; break;
      }
      
      for(int i=0; i<3; i++) {
         int stratIndex = p[i];
         bool useStrat = false;
         string stratN = "";
         if(stratIndex == 1) { useStrat = S1UseStrategy; stratN = S1Name; }
         else if(stratIndex == 2) { useStrat = S2UseStrategy; stratN = S2Name; }
         else if(stratIndex == 3) { useStrat = S3UseStrategy; stratN = S3Name; }
         
         if(useStrat) {
            string explanation = "";
            int s = GetStrategySignal(stratIndex, explanation);
            if(s != 0) { 
               if(!g_isOptimizing) {
                  PrintFormat("[SIGNAL] Strategy Evaluation: %s", stratN);
                  Print(explanation);
               }
               
               if(signal == 0) { // Select the first one found (Priority order)
                  signal = s; 
                  stratName = stratN;
               }
            }
         }
      }
   }
   
   if(signal == 0) return;

   // Execution
   if(!g_isOptimizing) PrintFormat("[SIGNAL] Strategy Selected: %s", stratName);
   
   long magic = GetNextMagic();
   double volume = LotSize;
   string side = (signal == 1) ? "[LONG]" : "[SHORT]";
   string comment = StringFormat("[%I64d] %s %s", magic, side, stratName);
   
   m_trade.SetExpertMagicNumber(magic);
   bool success = false;
   if(signal == 1) success = m_trade.Buy(volume, _Symbol, m_symbol.Ask(), 0, 0, comment);
   else success = m_trade.Sell(volume, _Symbol, m_symbol.Bid(), 0, 0, comment);
   
   if(success && !g_isOptimizing) PrintFormat("[SIGNAL] Entry Executed: %s", comment);
}

//+------------------------------------------------------------------+
//| PRD 4.1: Symmetrical Hedging                                     |
//| Monitors active sequences for the HedgePips breach to trigger    |
//| a perfectly balanced (net delta zero) protective hedge.          |
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
            
            if(success) {
               if(!g_isOptimizing) PrintFormat("[HEDGE] Sequence %I64d Locked Symmetrically (Vol: %.2f)", g_sequences[i].magic, reqVol);
               
               // PRD 4.1: Once locked, all trailing functionality is disabled and exposure must remain invariant.
               // Remove existing StopLoss and TakeProfit from ALL positions in this sequence to prevent accidental closures.
               for(int j=PositionsTotal()-1; j>=0; j--) {
                  if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol && m_position.Magic() == g_sequences[i].magic) {
                     if(m_position.StopLoss() != 0 || m_position.TakeProfit() != 0) {
                        m_trade.PositionModify(m_position.Ticket(), 0, 0);
                     }
                  }
               }
               
               // Update state immediately to prevent other logic in the same tick (e.g. ManageTrailingSL) from treating it as ACTIVE
               g_sequences[i].state = SEQ_LOCKED;
               g_sequences[i].volBuy = (g_sequences[i].volBuy > 0) ? g_sequences[i].volBuy : reqVol;
               g_sequences[i].volSell = (g_sequences[i].volSell > 0) ? g_sequences[i].volSell : reqVol;
               
               TriggerSave();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 5.4: Pyramiding Logic                                        |
//| Adds positions to an active sequence when profit is secured.     |
//+------------------------------------------------------------------+
void ManagePyramiding()
{
   if(!PyramidAllowed) return;

   for(int i=0; i<ArraySize(g_sequences); i++) {
      if(g_sequences[i].state == SEQ_ACTIVE) {
         long magic = g_sequences[i].magic;
         
         double totalSecuredProfit = 0;
         double currentSL = 0;
         int posCount = 0;
         ENUM_POSITION_TYPE type = POSITION_TYPE_BUY;
         
         double tickSize = m_symbol.TickSize();
         double tickValue = m_symbol.TickValue();
         if(tickSize <= 0) tickSize = _Point;
         
         for(int j=PositionsTotal()-1; j>=0; j--) {
            if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol && m_position.Magic() == magic) {
               double sl = m_position.StopLoss();
               double entry = m_position.PriceOpen();
               double vol = m_position.Volume();
               type = m_position.PositionType();
               
               if(sl > 0) {
                  double profitDist = (type == POSITION_TYPE_BUY) ? (sl - entry) : (entry - sl);
                  if(profitDist > 0) {
                     double posSecured = (profitDist / tickSize) * tickValue * vol;
                     totalSecuredProfit += posSecured;
                     if(currentSL == 0) currentSL = sl;
                  }
               }
               posCount++;
            }
         }
         
         if(posCount == 0 || currentSL == 0) continue; 
         
         double slChange = MathAbs(currentSL - g_sequences[i].lastPyramidSL);
         double reqChange = PyramidPips * m_symbol.Point() * 10;
         if(g_sequences[i].lastPyramidSL > 0 && slChange < reqChange - 0.0000001) continue;
         
         double availableProfit = totalSecuredProfit;
         bool isHedged = HasLockedSequences();
         if(isHedged) {
            availableProfit *= (1.0 - HarvestsProfitPercent / 100.0);
         }
         
         double riskAmount = availableProfit * (PyramidRiskPercent / 100.0);
         double currentPrice = (type == POSITION_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
         double distToSL = MathAbs(currentPrice - currentSL);
         
         if(distToSL <= tickSize) continue;
         
         double pyramidLots = riskAmount / ((distToSL / tickSize) * tickValue);
         double flooredLots = MathFloor(pyramidLots / m_symbol.LotsStep()) * m_symbol.LotsStep();
         
         if(flooredLots < m_symbol.LotsMin()) continue;
         
         double totalLots = (type == POSITION_TYPE_BUY) ? g_totalBuyLots : g_totalSellLots;
         if(totalLots + flooredLots > MaxLots) {
            PrintFormat("[WARNING] Pyramid for Magic %I64d blocked by MaxLots (%.2f). Proposed: %.2f", magic, MaxLots, totalLots + flooredLots);
            continue;
         }
         
         m_trade.SetExpertMagicNumber(magic);
         string side = (type == POSITION_TYPE_BUY) ? "[LONG]" : "[SHORT]";
         string comment = StringFormat("[%I64d] [PYRAMID] %s", magic, side);
         
         bool success = false;
         if(type == POSITION_TYPE_BUY) success = m_trade.Buy(flooredLots, _Symbol, m_symbol.Ask(), currentSL, 0, comment);
         else success = m_trade.Sell(flooredLots, _Symbol, m_symbol.Bid(), currentSL, 0, comment);

         if(success) {
            if(!g_isOptimizing) PrintFormat("[PYRAMID] Triggered for Magic %I64d: TotalSecured: %.2f, Risk: %.2f, LotSize: %.2f, SL: %.5f", 
                        magic, totalSecuredProfit, riskAmount, flooredLots, currentSL);
            g_sequences[i].lastPyramidSL = currentSL;
            TriggerSave();
         } else {
            if(!g_isOptimizing) PrintFormat("[ERROR] Pyramid Magic %I64d execution failed: %d", magic, GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| PRD 5.2: Symmetrical Trimming Algorithm                           |
//| Closes equal volumes from the Buy and Sell legs of the farthest  |
//| Mid-Price Locked Sequence using funds from the ProfitTally.      |
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
      if(!g_isOptimizing) PrintFormat("[TRIM] Symmetrical Trim: Magic %I64d, Lots: %.2f, Cost: %.2f, ExitB: %.5f, ExitS: %.5f", seq.magic, lotsToClose, cost, m_symbol.Bid(), m_symbol.Ask());
      
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
      
         if(!g_isOptimizing) PrintFormat("[TRIM] Order Sent: Magic %I64d, Lots: %.2f (Estimated Cost: %.2f)", seq.magic, lotsToClose, cost);
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
         if(!g_isOptimizing) PrintFormat("[CAPITULATION] Risk Alert! Closing Sequence %I64d.", magic);
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
         
         double effectiveLockProfit = HedgePips + LockProfitPips;
         if(pips >= effectiveLockProfit) {
            double newSL = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - TrailingStopPips * m_symbol.Point() * 10) : (m_symbol.Ask() + TrailingStopPips * m_symbol.Point() * 10);
            double currentSL = m_position.StopLoss();
            
            // Re-check betterment before processing harvest
            bool better = false;
            double diff = (m_position.PositionType() == POSITION_TYPE_BUY) ? (newSL - currentSL) : (currentSL - newSL);
            if(currentSL == 0 || diff > 0.5 * m_symbol.Point()) better = true;

            if(!better) continue;

            ulong ticket = m_position.Ticket();
            
            // Sync SL to all UNHEDGED positions of the same magic that match the active direction
            bool anyFailed = false;
            for(int j=PositionsTotal()-1; j>=0; j--) {
               if(m_position.SelectByIndex(j) && m_position.Symbol() == _Symbol && m_position.Magic() == magic) {
                  // Only modify if it's the correct direction for this active sequence to avoid race conditions with opening hedges
                  if(m_position.PositionType() == ((pips > 0 && m_position.PositionType() == POSITION_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL)) {
                     if(!m_trade.PositionModify(m_position.Ticket(), newSL, 0)) anyFailed = true;
                  }
               }
            }

            if(!anyFailed) {
               if(!g_isOptimizing) {
                  if(currentSL == 0) {
                     PrintFormat("[TRADE] Profit Locked: Sequence %I64d SL set at %.5f (Pips: %.1f, TrailPips: %.1f)", 
                                 magic, newSL, pips, TrailingStopPips);
                  } else {
                     PrintFormat("[TRADE] Trailing Stop updated: %.5f -> %.5f (Sequence %I64d, Pips: %.1f, TrailPips: %.1f)", 
                                 currentSL, newSL, magic, pips, TrailingStopPips);
                  }
               }
            }
            break; // Processed this sequence, move to next position in outer loop
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PRD 5.2: Real-time Profit Reconciliation                         |
//| Scans history deals to harvest profit for the Tally fund or      |
//| reconcile actual net realized loss from trimming operations.     |
//+------------------------------------------------------------------+
void ReconcileRecentDeals()
{
   datetime now = TimeCurrent();
   datetime start = (now > 86400 * 7) ? now - 86400 * 7 : 0;
   
   if(HistorySelect(start, now)) {
      int total = HistoryDealsTotal();
      int startIndex = 0;
      if(g_lastProcessedDeal > 0) {
         for(int i = total - 1; i >= 0; i--) {
            if(HistoryDealGetTicket(i) == g_lastProcessedDeal) {
               startIndex = i + 1;
               break;
            }
         }
      }
      for(int i = startIndex; i < total; i++) {
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
               if(StringFind(dealComment, "[TRIM]") < 0 && StringFind(dealComment, "Capitulation") < 0 && HasLockedSequences()) {
                  if(net > 0) {
                     amountToAdd = net * (HarvestsProfitPercent / 100.0);
                     double unharvestedAmount = net - amountToAdd;
                     g_unharvestedProfit += unharvestedAmount;
                     if(!g_isOptimizing) PrintFormat("[TRIM] Target Profit Harvested: Magic %I64d, Net: %.2f, Amount (%.0f%%): +%.2f, Unharvested Added: %.2f, Total Unharvested: %.2f", 
                                 dealMagic, net, HarvestsProfitPercent, amountToAdd, unharvestedAmount, g_unharvestedProfit);
                  }
               } else if (StringFind(dealComment, "[TRIM]") >= 0) {
                  // Deal generated by Symmetrical Trimming
                  g_profitTally += net;
                  double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  if(!g_isOptimizing) PrintFormat("[TRIM] Realized PnL applied to Tally: Magic %I64d, DealNet: %.2f, New Tally: %.2f, ExitPrice: %.5f", dealMagic, net, g_profitTally, dealPrice);
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
