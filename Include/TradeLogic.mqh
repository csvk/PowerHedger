//+------------------------------------------------------------------+
//|                                                   TradeLogic.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Trade Logic
   Description: Manages entry signals, position tracking, trimming, and hedging.
   PRD Sections: 2 (Core Logic), 3 (Trade Management)
*/

#include "Globals.mqh"
#include "Inputs.mqh"
#include "Utilities.mqh"
#include "Persistence.mqh"

//--- Helper: PRD 2.5/3.2: Partial closure with custom comment (not supported by CTrade directly)
bool ClosePartialWithComment(ulong ticket, double volume, string comment)
{
   if(!m_position.SelectByTicket(ticket)) return false;
   
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action       = TRADE_ACTION_DEAL;
   request.position     = ticket;
   request.symbol       = _Symbol;
   request.volume       = volume;
   request.magic        = MagicNumber;
   request.comment      = comment;
   request.type         = (m_position.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price        = (request.type == ORDER_TYPE_SELL) ? m_symbol.Bid() : m_symbol.Ask();
   request.deviation    = 10;
   
   //--- Determine allowed filling mode (PRD 7.2 Strategy Tester compatibility)
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) request.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0) request.type_filling = ORDER_FILLING_IOC;
   else request.type_filling = ORDER_FILLING_RETURN;
   
   if(!OrderSend(request, result)) {
      PrintFormat("[ERROR] ClosePartialWithComment failed (Ticket: %d, Vol: %.2f, Error: %d)", ticket, volume, GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Entry: Check and Execute New Indicator-Based Entries             |
//| PRD 2.1, 2.4: Condition Check and Strategy Invocation            |
//+------------------------------------------------------------------+
void CheckNewEntries()
{
   //--- 0. Debounce: Only one attempt per tick
   static datetime lastTickTime = 0;
   if(TimeCurrent() == lastTickTime) return;
   lastTickTime = TimeCurrent();

   //--- Determine current market state: Flat market has Session/Weekday filters (PRD 1.1)
   bool isFlat = (g_totalBuyLots == 0 && g_totalSellLots == 0);
   if(isFlat && !IsSessionActive()) return; 

   //--- PRD 2.1: MinPipGap calculation
   double minPipGap = MinPipGapMultiplier * HedgePips;

   //--- Consolidate trade permission checks and capture reasons
   string buyReason = "", sellReason = "";
   ENUM_MARKET_CONTEXT buyContext = CONTEXT_NEW, sellContext = CONTEXT_NEW;
   
   bool buyLimitOk = (g_totalBuyLots + LotSize <= MaxLots);
   if(!buyLimitOk) buyReason = StringFormat("MaxLots (%.2f) reached", MaxLots);
   bool buyAllowed = buyLimitOk && IsStrategicEntryAllowed(POSITION_TYPE_BUY, minPipGap, buyContext, buyReason);
   
   bool sellLimitOk = (g_totalSellLots + LotSize <= MaxLots);
   if(!sellLimitOk) sellReason = StringFormat("MaxLots (%.2f) reached", MaxLots);
   bool sellAllowed = sellLimitOk && IsStrategicEntryAllowed(POSITION_TYPE_SELL, minPipGap, sellContext, sellReason);

   //--- [CORE FIX]: Suppress signal generation if neither side is allowed (PRD Refinement)
   if(!buyAllowed && !sellAllowed) return; 

   //--- PRD 2.1: Prioritized strategy invocation (Mutual Exclusion)
   int signal = 0;
   string strategyName = "";
   ENUM_MARKET_CONTEXT context = CONTEXT_NEW;
   
   if(EnableRandom) {
      int randSig = GetRandomSignal();
      if(randSig == 1) {
         if(buyAllowed) { signal = 1; strategyName = "Random"; context = buyContext; }
         else PrintFormat("[DECISION] Random BUY blocked: %s", buyReason);
      }
      else if(randSig == -1) {
         if(sellAllowed) { signal = -1; strategyName = "Random"; context = sellContext; }
         else PrintFormat("[DECISION] Random SELL blocked: %s", sellReason);
      }
   } else {
      int s1_signal = GetStrategySignal(1);
      int s2_signal = GetStrategySignal(2);
      
      if(PrioritizeStrategy == STRAT_1) {
         if(s1_signal == 1) {
            if(buyAllowed) { signal = 1; strategyName = S1Name; context = buyContext; }
            else PrintFormat("[DECISION] %s BUY blocked: %s", S1Name, buyReason);
         }
         else if(s1_signal == -1) {
            if(sellAllowed) { signal = -1; strategyName = S1Name; context = sellContext; }
            else PrintFormat("[DECISION] %s SELL blocked: %s", S1Name, sellReason);
         }
         else if(s2_signal == 1) {
            if(buyAllowed) { signal = 1; strategyName = S2Name; context = buyContext; }
            else PrintFormat("[DECISION] %s BUY blocked: %s", S2Name, buyReason);
         }
         else if(s2_signal == -1) {
            if(sellAllowed) { signal = -1; strategyName = S2Name; context = sellContext; }
            else PrintFormat("[DECISION] %s SELL blocked: %s", S2Name, sellReason);
         }
      } else {
         if(s2_signal == 1) {
            if(buyAllowed) { signal = 1; strategyName = S2Name; context = buyContext; }
            else PrintFormat("[DECISION] %s BUY blocked: %s", S2Name, buyReason);
         }
         else if(s2_signal == -1) {
            if(sellAllowed) { signal = -1; strategyName = S2Name; context = sellContext; }
            else PrintFormat("[DECISION] %s SELL blocked: %s", S2Name, sellReason);
         }
         else if(s1_signal == 1) {
            if(buyAllowed) { signal = 1; strategyName = S1Name; context = buyContext; }
            else PrintFormat("[DECISION] %s BUY blocked: %s", S1Name, buyReason);
         }
         else if(s1_signal == -1) {
            if(sellAllowed) { signal = -1; strategyName = S1Name; context = sellContext; }
            else PrintFormat("[DECISION] %s SELL blocked: %s", S1Name, sellReason);
         }
      }
   }
   
   if(signal == 0) return;

   ENUM_POSITION_TYPE type = (signal == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   //--- Execute entry
   double volume = LotSize;
   
   //--- PRD 2.5: Dynamic sequence number <N> (Total open positions including new one)
   //--- Include New/Inside/Outside context in comment
   int n = CountOpenPositions(type) + 1;
   string contextStr = "New";
   if(context == CONTEXT_INSIDE) contextStr = "Inside";
   else if(context == CONTEXT_OUTSIDE) contextStr = "Outside";
   
   string sideTag = (type == POSITION_TYPE_BUY) ? "[LONG]" : "[SHORT]";
   string comment = StringFormat("<%d> %s %s [%s]", n, sideTag, strategyName, contextStr);
   
   bool success = false;
   if(type == POSITION_TYPE_BUY) success = m_trade.Buy(volume, _Symbol, m_symbol.Ask(), 0, 0, comment);
   else success = m_trade.Sell(volume, _Symbol, m_symbol.Bid(), 0, 0, comment);
   
   if(success) {
      double entryPrice = (type == POSITION_TYPE_BUY) ? m_symbol.Ask() : m_symbol.Bid();
      PrintFormat("[TRADE] Entry Executed: %s at %.5f (Nearest Opp.: %.5f, MinPipGap: %.1f, HedgePips: %.1f)", 
                  comment, entryPrice, (type == POSITION_TYPE_BUY) ? 0 : 0, minPipGap, HedgePips); // FIXME: Add actual nearest oppositte entry if needed, but minPipGap is key
      
      //--- PRD 3.5: Handover from squeezing to standard hedging immediately upon successful strategic entry
      if(g_trailingHedgePrice > 0) {
         PrintFormat("[HEDGE] Squeezing Handover: Strategic entry detected. Resetting Trailing Hedge Price (%.5f) for standard handover.", g_trailingHedgePrice);
         g_trailingHedgePrice = -1;
         TriggerSave();
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Ticket Trim Tracking Helpers                         |
//| These helpers manage g_ticketTracks to ensure theoretical trim   |
//| is only reconciled once upon completion.                         |
//+------------------------------------------------------------------+
double GetTrimmedAmount(ulong ticket) {
   for(int i = ArraySize(g_ticketTracks) - 1; i >= 0; i--) if(g_ticketTracks[i].ticket == ticket) return g_ticketTracks[i].trimmedAmount;
   return 0;
}

double GetLastTrimPips(ulong ticket) {
   for(int i = ArraySize(g_ticketTracks) - 1; i >= 0; i--) if(g_ticketTracks[i].ticket == ticket) return g_ticketTracks[i].lastTrimPips;
   return 0;
}

void SetTrimData(ulong ticket, double amount, double lastPips) {
   for(int i = ArraySize(g_ticketTracks) - 1; i >= 0; i--) {
      if(g_ticketTracks[i].ticket == ticket) {
         g_ticketTracks[i].trimmedAmount = amount;
         g_ticketTracks[i].lastTrimPips = lastPips;
         return;
      }
   }
   int size = ArraySize(g_ticketTracks);
   ArrayResize(g_ticketTracks, size + 1);
   g_ticketTracks[size].ticket = ticket;
   g_ticketTracks[size].trimmedAmount = amount;
   g_ticketTracks[size].lastTrimPips = lastPips;
}

void RemoveTicketTrack(ulong ticket) {
   int size = ArraySize(g_ticketTracks);
   for(int i = 0; i < size; i++) {
      if(g_ticketTracks[i].ticket == ticket) {
         for(int j = i; j < size - 1; j++) g_ticketTracks[j] = g_ticketTracks[j + 1];
         ArrayResize(g_ticketTracks, size - 1);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Trim Farthest First (Losing Trades Only)             |
//| PRD 3.2: Systematically use internal profits to reduce risk.     |
//+------------------------------------------------------------------+
void TrimPositions(double amount, string comment = "Trim")
{
   if(amount <= 0) return;
   
   //--- Combine current available profit with persistent "leftover" tally (PRD 3.4)
   double pool = amount + g_profitTally;
   g_profitTally = 0;
   
   //--- Continuously trim until the profit pool is exhausted or no losing trades remain
   while(pool > 0) {
      ulong ticket = 0;
      double maxDist = -1;
      double vol = 0;
      double farthestP = 0;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)0;
      
      //--- Scan for the position farthest from current price (PRD 3.2: Farthest First)
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol) {
            //--- Only trim losing trades (Net profit < 0)
            double netProfit = m_position.Profit() + m_position.Commission() + m_position.Swap();
            if(netProfit >= 0) continue; 

            //--- PRD 3.2 Refinement: Only trim if distance >= HedgePips
            double currentPrice = (m_position.PositionType() == POSITION_TYPE_BUY) ? m_symbol.Bid() : m_symbol.Ask();
            double dist = MathAbs(m_position.PriceOpen() - currentPrice);
            if(dist < HedgePips * m_symbol.Point() * 10) continue;
            
            //--- Select the position with maximum pip distance from market
            if(dist > maxDist) {
               maxDist = dist;
               ticket = m_position.Ticket();
               vol = m_position.Volume();
               farthestP = m_position.PriceOpen();
               type = m_position.PositionType();
            }
         }
      }
      
      //--- Terminate if no qualifying losing positions are found
      if(ticket == 0) {
         if(pool > 0) PrintFormat("[INFO] Trimming stopped: No qualifying losing positions found at distance >= HedgePips (%.1f) (Remaining Pool: %.2f)", HedgePips, pool);
         break;
      }
      
      PrintFormat("[DECISION] Trimming decision: Selected Ticket %d (Dist: %.1f pips) for risk reduction using profit pool (Available: %.2f)", 
                  ticket, maxDist / (m_symbol.Point() * 10), pool);
      
      //--- Calculate the dollar value of loss for 1 full lot at current price
      double currentPrice = (type == POSITION_TYPE_BUY) ? m_symbol.Bid() : m_symbol.Ask();
      double lossPerLot = MathAbs(currentPrice - farthestP) / m_symbol.Point() * m_symbol.TickValue();
      if(lossPerLot <= 0) break;
      
      //--- Determine maximum volume that can be trimmed with remaining pool
      double lotToClose = pool / lossPerLot;
      lotToClose = MathMin(lotToClose, vol); // Cannot trim more than available volume
      
      //--- Normalize to broker requirements (Step size and Min lot size)
      lotToClose = MathFloor(lotToClose / m_symbol.LotsStep()) * m_symbol.LotsStep();
      
      if(lotToClose >= m_symbol.LotsMin()) {
         //--- PRD 3.2: Execute partial closure with [LONG]/[SHORT] tag
         string sideTag = (type == POSITION_TYPE_BUY) ? "[LONG]" : "[SHORT]";
         if(ClosePartialWithComment(ticket, lotToClose, sideTag + " " + comment)) {
            pool -= (lotToClose * lossPerLot); // Reduce available pool
            vol -= lotToClose; // Update volume for pending tick reconciliation
         } else break; // Terminate loop if execution fails
      } else { 
         //--- PRD 3.4: Store unspent fractional profit for future use
         g_profitTally = pool; 
         break; 
      }
   }
   //--- Ensure state is saved after risk reduction
   TriggerSave();
}

//+------------------------------------------------------------------+
//| Management: Trailing Stops and Theoretical Risk Reduction       |
//| PRD 3.1/3.3: Proactive Risk Reduction before position closure.  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Management: Reduce Position Volume (Farthest First)              |
//| Used when MaxLots limit is reached during hedging triggers.      |
//+------------------------------------------------------------------+
void ReducePositionSide(ENUM_POSITION_TYPE type, double volumeToReduce)
{
   if(volumeToReduce <= 0) return;
   double remaining = volumeToReduce;

   //--- Continuously reduce volume from farthest positions
   while(remaining > 0) {
      ulong ticket = 0;
      double maxDist = -1;
      double vol = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == type) {
            double currentPrice = (type == POSITION_TYPE_BUY) ? m_symbol.Bid() : m_symbol.Ask();
            double dist = MathAbs(m_position.PriceOpen() - currentPrice);
            if(dist > maxDist) {
               maxDist = dist;
               ticket = m_position.Ticket();
               vol = m_position.Volume();
            }
         }
      }

      if(ticket == 0) break;

      double lotToClose = MathMin(remaining, vol);
      lotToClose = MathFloor(lotToClose / m_symbol.LotsStep()) * m_symbol.LotsStep();
      
      if(lotToClose >= m_symbol.LotsMin()) {
         string sideTag = (type == POSITION_TYPE_BUY) ? "[LONG]" : "[SHORT]";
         if(ClosePartialWithComment(ticket, lotToClose, sideTag + " Reduction")) {
            remaining -= lotToClose;
         } else break;
      } else break;
   }
   
   CalculateBalances();
   TriggerSave();
}

//| Management: Execute Hedge or Reduction based on MaxLots          |
//| PRD 2.2: Enforces MaxLots limit even for hedging.                |
//| PRD 2.5: Supports custom keywords like "Trailing Hedge".         |
//+------------------------------------------------------------------+
void ExecuteHedgeOrReduce(ENUM_POSITION_TYPE hedgeType, double requiredVolume, string keyword = "Hedge")
{
   double hedgeSideVol = (hedgeType == POSITION_TYPE_BUY) ? g_totalBuyLots : g_totalSellLots;
   double unbalancedSideVol = (hedgeType == POSITION_TYPE_BUY) ? g_totalSellLots : g_totalBuyLots;
   ENUM_POSITION_TYPE unbalancedType = (hedgeType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

   //--- PRD 2.2: Check if MaxLots reached in either direction or hedge breaches limit
   if(hedgeSideVol + requiredVolume > MaxLots || unbalancedSideVol >= MaxLots) {
      PrintFormat("[WARNING] Hedge Sidelined -> Executing Reduction: Side %s reached MaxLots limit. Reducing %s by LotSize (%.2f) to stay within safety limits (PRD 2.2).", 
                  EnumToString(hedgeType), EnumToString(unbalancedType), LotSize);
      ReducePositionSide(unbalancedType, LotSize);
   } else {
      //--- Execute standard or trailing hedge
      if(hedgeType == POSITION_TYPE_BUY) {
         int n = CountOpenPositions(POSITION_TYPE_BUY) + 1;
         string comment = StringFormat("<%d> [LONG] %s", n, keyword);
         if(m_trade.Buy(requiredVolume, _Symbol, m_symbol.Ask(), 0, 0, comment)) {
            PrintFormat("[TRADE] Hedge Executed: %s (Vol: %.2f) at %.5f", comment, requiredVolume, m_symbol.Ask());
         }
      } else {
         int n = CountOpenPositions(POSITION_TYPE_SELL) + 1;
         string comment = StringFormat("<%d> [SHORT] %s", n, keyword);
         if(m_trade.Sell(requiredVolume, _Symbol, m_symbol.Bid(), 0, 0, comment)) {
            PrintFormat("[TRADE] Hedge Executed: %s (Vol: %.2f) at %.5f", comment, requiredVolume, m_symbol.Bid());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Trailing Stops and Theoretical Risk Reduction       |
//| PRD 3.1/3.3: Proactive Risk Reduction before position closure.  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol) {
         //--- Calculate floating profit in pips
         double pips = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - m_position.PriceOpen()) : (m_position.PriceOpen() - m_symbol.Ask());
         pips /= (m_symbol.Point() * 10);
         
         //--- PRD 1.7/3.1: Activation check for trailing stop and trimming
         if(pips >= LockProfitPips) {
            double newSL = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - TrailingStopPips * m_symbol.Point() * 10) : (m_symbol.Ask() + TrailingStopPips * m_symbol.Point() * 10);
            
            ulong winTicket = m_position.Ticket();
            
            //--- PRD 3.3: Intermediate (Theoretical) Profit Trimming
            //--- Execute trim calculation based on currently locked profit (Price vs SL)
            double actLockedPips = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_position.StopLoss() - m_position.PriceOpen()) : (m_position.PriceOpen() - m_position.StopLoss());
            actLockedPips /= (m_symbol.Point() * 10);
            
            double lastTrimPips = GetLastTrimPips(winTicket);
            bool isFirstTrim = (GetTrimmedAmount(winTicket) == 0);
            bool isIncremental = (actLockedPips >= lastTrimPips + IntermediateTrimPips);

            if(m_position.StopLoss() != 0 && (isFirstTrim || isIncremental)) {
               if(actLockedPips > 0) {
                  //--- Calculate profit in currency using points (consistent with Section 3.2)
                  double actLockedPoints = actLockedPips * 10; 
                  double profit = actLockedPoints * m_position.Volume() * m_symbol.TickValue();
                  double totalTrimGoal = profit * (1.0 - KeepProfitPercent);
                  double incrementalTrim = totalTrimGoal - GetTrimmedAmount(winTicket);

                  if(incrementalTrim > 0) {
                     PrintFormat("[DECISION] Intermediate Trim triggered: Ticket %d has locked %.1f pips (Profit: %.2f, MinTrim: %.1f). Applying risk reduction (Goal: %.2f, KeepProfitPct: %.1f%%).", 
                                 winTicket, actLockedPips, profit, IntermediateTrimPips, incrementalTrim, KeepProfitPercent * 100);
                     TrimPositions(incrementalTrim, "Intermediate Trim");
                     SetTrimData(winTicket, totalTrimGoal, actLockedPips);
                  }
               }
            }

            //--- PRD 3.1: Update physical Trailing Stop
            m_position.SelectByTicket(winTicket);
            double currentSL = m_position.StopLoss();
            double stopLevel = m_symbol.StopsLevel() * m_symbol.Point();
            double minChangePips = 1.0; // Minimal change to avoid spamming "Invalid stops" (1 pip)

            bool isSignificantMove = (MathAbs(newSL - currentSL) > minChangePips * m_symbol.Point() * 10);
            bool isAboveStopLevel = (m_position.PositionType() == POSITION_TYPE_BUY) ? (m_symbol.Bid() - newSL > stopLevel) : (newSL - m_symbol.Ask() > stopLevel);

            if(isSignificantMove && isAboveStopLevel) {
               if(currentSL == 0 || (m_position.PositionType() == POSITION_TYPE_BUY && newSL > currentSL) || (m_position.PositionType() == POSITION_TYPE_SELL && newSL < currentSL)) {
                  if(m_trade.PositionModify(winTicket, newSL, 0)) {
                     PrintFormat("[TRADE] Trailing Stop updated: Ticket %d SL moved from %.5f to %.5f (Reason: Price advancement, Pips: %.1f, TrailPips: %.1f)", 
                                 winTicket, currentSL, newSL, pips, TrailingStopPips);
                  }
               }
            }
         }
      }
   }
   
   //--- PRD 3.4: ProfitTally Reset logic
   //--- Reset if no positions are further than HedgePips from current price
   bool hasDistantTrade = false;
   double currentBid = m_symbol.Bid();
   double currentAsk = m_symbol.Ask();
   double gapPoints = HedgePips * m_symbol.Point() * 10;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol) {
         double openP = m_position.PriceOpen();
         double dist = MathAbs(openP - ((m_position.PositionType() == POSITION_TYPE_BUY) ? currentBid : currentAsk));
         if(dist >= gapPoints) {
            hasDistantTrade = true;
            break;
         }
      }
   }
   
   if(!hasDistantTrade && g_profitTally > 0) {
      PrintFormat("[INFO] ProfitTally Reset: No positions remain >= HedgePips (%.1f) away from market. Tally %.2f cleared.", HedgePips, g_profitTally);
      g_profitTally = 0;
      TriggerSave();
   }
}

//+------------------------------------------------------------------+
//| Management: Synchronous Deal Reconciliation                      |
//| PRD 3.5: Ensures profit closures are handled BEFORE hedging.     |
//+------------------------------------------------------------------+
void ReconcileRecentDeals()
{
   //--- PRD 3.2, 3.5: Scan history for new deals since the last reconciled one
   if(HistorySelect(0, TimeCurrent())) {
      int total = HistoryDealsTotal();
      
      //--- To avoid duplicate iteration on every tick, we start from the last known deal
      //--- But since tickets aren't always strictly sequential, we search backward or iterate all.
      //--- For robustness, iterate through all history in the current period and filter.
      for(int i = 0; i < total; i++) {
         ulong dealTicket = HistoryDealGetTicket(i);
         
         //--- Process only deals newer than or equal to the last processed deal to ensure sync
         if(dealTicket > g_lastProcessedDeal) {
            long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(magic == MagicNumber) {
               long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
               
               //--- We only process closure deals (OUT) for trimming and hedge points
               //--- We only process closure deals (OUT) for trimming and hedge points
               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) {
                  ulong positionTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
                  double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                  
                  //--- Determine the type of the closing position for reconciliation
                  ENUM_POSITION_TYPE closedPosType = (type == DEAL_TYPE_SELL) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
                  
                  //--- Synchronously trigger the trimming logic and hedge adjustment sequence
                  ProcessFinalClosure(positionTicket, profit, closedPosType, price);
               }
            }
            //--- Update the last processed deal to the latest encountered ticket
            if(dealTicket > g_lastProcessedDeal) {
               g_lastProcessedDeal = dealTicket;
               TriggerSave();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Final Closure Reconciliation and Hedge Delay         |
//| PRD 3.2, 3.5: Trimming sequence and Post-Trim Hedge Point setup. |
//+------------------------------------------------------------------+
void ProcessFinalClosure(ulong ticket, double finalProfit, ENUM_POSITION_TYPE posType, double exitPrice)
{
   //--- 0. SYNC: Refresh cached volumes immediately after a position is closed
   CalculateBalances();
   
   //--- 1. FILTER: Losing trades (Trims, S/L, Manual loss) do not trigger new trims or hedge points
   if(finalProfit <= 0) {
      //--- PRD 3.5 Safeguard: If we already have a delayed hedge point active, do not reset it
      if (g_trailingHedgePrice <= 0 && g_totalBuyLots != g_totalSellLots) g_trailingHedgePrice = -1;
      RemoveTicketTrack(ticket);
      TriggerSave();
      return;
   }
   
   //--- 2. CALCULATE: Determine remaining profit to be used for trimming (PRD 3.3 excess reconciliation)
   double previouslyTrimmed = GetTrimmedAmount(ticket);
   double totalTrimAmount = finalProfit * (1.0 - KeepProfitPercent);
   double incrementalTrim = totalTrimAmount - previouslyTrimmed;
   
   //--- 2. EXECUTE TRIM: Apply residual profit to losing trades BEFORE establishing new hedge point
   if(incrementalTrim > 0) {
      TrimPositions(incrementalTrim);
   }
   
   //--- 3. PRD 3.5: Post-Trim Hedge Point Establishment
   //--- Only set a delayed hedge point if we are still unbalanced after the closure and trimming
   if(g_totalBuyLots != g_totalSellLots) {
      //--- Logic: Only delay the hedge if we actually booked profit (available for trimming)
      //--- If no profit was available, standard hedging (CheckHedgeTriggers) will handle it.
      if(incrementalTrim > 0 || previouslyTrimmed > 0 || g_profitTally > 0) {
         //--- Find nearest entry of the unbalanced side
         double nearestEntry = -1;
         if(g_totalBuyLots > g_totalSellLots) {
             for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_BUY) if(nearestEntry == -1 || m_position.PriceOpen() < nearestEntry) nearestEntry = m_position.PriceOpen();
         } else {
             for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_SELL) if(nearestEntry == -1 || m_position.PriceOpen() > nearestEntry) nearestEntry = m_position.PriceOpen();
         }

         //--- Set g_trailingHedgePrice at exactly HedgePips from the exit price of the profitable trade
         g_trailingHedgePrice = (g_totalBuyLots > g_totalSellLots) ? (exitPrice - HedgePips * m_symbol.Point() * 10) : (exitPrice + HedgePips * m_symbol.Point() * 10);
         double unbalancedVol = MathAbs(g_totalBuyLots - g_totalSellLots);
         string hedgeDir = (g_totalBuyLots > g_totalSellLots) ? "SHORT" : "LONG";
         PrintFormat("[HEDGE] Trailing Hedge Price established: %.5f (%s, Vol: %.2f) (Nearest Entry: %.5f, ExitPrice: %.5f, HedgePips: %.1f). Squeezing active.", 
                     g_trailingHedgePrice, hedgeDir, unbalancedVol, nearestEntry, exitPrice, HedgePips);
      } else {
         //--- PRD 3.5 Safeguard: If we already have a delayed hedge point active, do not reset it
         //--- intermediate loss closures in the same tick should not wipe out the delayed point.
         if (g_trailingHedgePrice <= 0) g_trailingHedgePrice = -1; // Reset to allow immediate standard hedge
      }
   } else {
      g_trailingHedgePrice = -1; // Reset if perfectly balanced
   }
   
   //--- 4. CLEANUP: Remove ticket tracking data and finalize volume state
   RemoveTicketTrack(ticket);
   CalculateBalances(); // Final sync of volumes after potential trims
   g_lastHedgeTickTime = 0; // Reset hedge guard to allow immediately required hedges after a closure if needed (but ManageHedgeSqueeze usually takes over)
}

//+------------------------------------------------------------------+
//| Management: Hedge Squeeze (Post-Trim Delayed Hedge)              |
//| PRD 3.5: Dynamic adjustment of the post-trim price point.        |
void ManageHedgeSqueeze()
{
   //--- 0. SYNC: Always ensure we have latest volumes for distance calculation
   CalculateBalances();

   //--- 1. PRD 3.5: Active check for delayed hedge
   if(g_trailingHedgePrice <= 0) return;

   //--- 2. GUARD: Per-tick throttle (PRD 2.3/3.5 transition safety)
   if(g_lastHedgeTickTime == TimeCurrent()) return;
   
   //--- 3. Calculate current distance to the delayed hedge point
   double currentPrice = (g_totalBuyLots > g_totalSellLots) ? m_symbol.Bid() : m_symbol.Ask();
   double dist = MathAbs(currentPrice - g_trailingHedgePrice) / (m_symbol.Point() * 10);
   
   //--- 4. PRD 3.5: Trailing Adjustment (Squeezing)
   //--- Logic: If price moves further away than HedgePips + SqueezePips, trail the hedge point.
   //--- PRD Fix: Use SqueezePips as a "trailing step" to ensure discrete updates and avoid sub-pip jitter.
   if(dist > HedgePips + SqueezePips) {
      double oldPoint = g_trailingHedgePrice;
      g_trailingHedgePrice = (g_totalBuyLots > g_totalSellLots) ? (currentPrice - HedgePips * m_symbol.Point() * 10) : (currentPrice + HedgePips * m_symbol.Point() * 10);
      
      //--- Find nearest entry of the unbalanced side
      double nearestEntry = -1;
      if(g_totalBuyLots > g_totalSellLots) {
          for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_BUY) if(nearestEntry == -1 || m_position.PriceOpen() < nearestEntry) nearestEntry = m_position.PriceOpen();
      } else {
          for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_SELL) if(nearestEntry == -1 || m_position.PriceOpen() > nearestEntry) nearestEntry = m_position.PriceOpen();
      }

       double unbalancedVol = MathAbs(g_totalBuyLots - g_totalSellLots);
       string hedgeDir = (g_totalBuyLots > g_totalSellLots) ? "SHORT" : "LONG";
       PrintFormat("[HEDGE] Trailing Hedge Price Trailed: %.5f -> %.5f (%s, Vol: %.2f) (Nearest Entry: %.5f, HedgePips: %.1f, SqueezePips: %.1f)", 
                   oldPoint, g_trailingHedgePrice, hedgeDir, unbalancedVol, nearestEntry, HedgePips, SqueezePips);
      TriggerSave();
   }
   
   //--- 5. EXECUTION: Monitor if the delayed hedge point has been reached (per tick)
   if((g_totalBuyLots > g_totalSellLots && m_symbol.Bid() <= g_trailingHedgePrice) || (g_totalSellLots > g_totalBuyLots && m_symbol.Ask() >= g_trailingHedgePrice)) {
      double vol = MathAbs(g_totalBuyLots - g_totalSellLots);
      if(vol >= m_symbol.LotsMin()) {
         //--- PRD 2.5 Logic: Determine if this is a "Trailing Hedge" or standard "Hedge"
         string keyword = "Hedge";
         double stdPoint = -1;
         
         if(g_totalBuyLots > g_totalSellLots) {
            // Standard trigger is based on LOWEST Buy
            for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_BUY) if(stdPoint == -1 || m_position.PriceOpen() < stdPoint) stdPoint = m_position.PriceOpen();
            if(stdPoint != -1) stdPoint -= HedgePips * m_symbol.Point() * 10;
            //--- PRD 2.5: Trailing Hedge is at a WORSE (lower for Sell hedge) price than standard
            if(g_trailingHedgePrice < stdPoint - 0.000001) keyword = "Trailing Hedge"; 
         } else {
            // Standard trigger is based on HIGHEST Sell
            for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_SELL) if(stdPoint == -1 || m_position.PriceOpen() > stdPoint) stdPoint = m_position.PriceOpen();
            if(stdPoint != -1) stdPoint += HedgePips * m_symbol.Point() * 10;
            //--- PRD 2.5: Trailing Hedge is at a WORSE (higher for Buy hedge) price than standard
            if(g_trailingHedgePrice > stdPoint + 0.000001) keyword = "Trailing Hedge";
         }

          double unbalancedVol = MathAbs(g_totalBuyLots - g_totalSellLots);
          string hedgeDir = (g_totalBuyLots > g_totalSellLots) ? "SHORT" : "LONG";
          PrintFormat("[HEDGE] Squeeze Trigger Reached: Price at %.5f (Trigger: %.5f, %s, Vol: %.2f). Keyword: %s (Standard Point: %.5f)", 
                      currentPrice, g_trailingHedgePrice, hedgeDir, unbalancedVol, keyword, stdPoint);
                     
         ExecuteHedgeOrReduce((g_totalBuyLots > g_totalSellLots) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY, vol, keyword);
         
         g_lastHedgeTickTime = TimeCurrent(); 
         g_trailingHedgePrice = -1; 
         TriggerSave();
      }
   }
}

//+------------------------------------------------------------------+
//| Management: Standard Hedging Triggers (Per Tick)                 |
//| PRD 2.3: Monitors trigger distance from nearest entries.         |
//+------------------------------------------------------------------+
void CheckHedgeTriggers()
{
   //--- 0. GUARD: Per-tick throttle
   if(g_lastHedgeTickTime == TimeCurrent()) return;

   //--- 1. CRITICAL GUARD: Do not execute standard hedge if a Post-Trim delayed point is active
   if(g_trailingHedgePrice > 0 || g_totalBuyLots == g_totalSellLots) return;
   
   double limit = -1;
   
   //--- Logic: Hedge trigger is calculated from the NEAREST entry of the unbalanced side (PRD 2.3)
   if(g_totalBuyLots > g_totalSellLots) {
      //--- Find the LOWEST Buy (nearest to current price in downtrend)
      for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_BUY) if(limit == -1 || m_position.PriceOpen() < limit) limit = m_position.PriceOpen();
      
      //--- Trigger SELL hedge if price drops by HedgePips from lowest Buy
      double trigger = limit - HedgePips * m_symbol.Point() * 10;
      if(limit != -1 && m_symbol.Bid() <= trigger) {
          PrintFormat("[HEDGE] Standard Hedge Triggered (SELL, Vol: %.2f): Price %.5f reached trigger %.5f (Lowest Buy: %.5f, HedgePips: %.1f)", 
                      g_totalBuyLots - g_totalSellLots, m_symbol.Bid(), trigger, limit, HedgePips);
         ExecuteHedgeOrReduce(POSITION_TYPE_SELL, g_totalBuyLots - g_totalSellLots);
      }
   } else {
      //--- Find the HIGHEST Sell (nearest to current price in uptrend)
      for(int i = PositionsTotal() - 1; i >= 0; i--) if(m_position.SelectByIndex(i) && m_position.Magic() == MagicNumber && m_position.Symbol() == _Symbol && m_position.PositionType() == POSITION_TYPE_SELL) if(limit == -1 || m_position.PriceOpen() > limit) limit = m_position.PriceOpen();
      
      //--- Trigger BUY hedge if price rises by HedgePips from highest Sell
      double trigger = limit + HedgePips * m_symbol.Point() * 10;
      if(limit != -1 && m_symbol.Ask() >= trigger) {
          PrintFormat("[HEDGE] Standard Hedge Triggered (BUY, Vol: %.2f): Price %.5f reached trigger %.5f (Highest Sell: %.5f, HedgePips: %.1f)", 
                      g_totalSellLots - g_totalBuyLots, m_symbol.Ask(), trigger, limit, HedgePips);
         ExecuteHedgeOrReduce(POSITION_TYPE_BUY, g_totalSellLots - g_totalBuyLots);
      }
   }
}
