//+------------------------------------------------------------------+
//|                                                      Globals.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
/*
   Component: Globals
   Description: Shared object instances and persistent global state variables.
   PRD Section: 3.4 (Persistence), 2.1 (Sequence Tracking).
*/

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- GLOBAL OBJECTS: Standard MQL5 library wrappers for trading and market data
CTrade         m_trade;          // Order execution class
CPositionInfo  m_position;       // Active position inspection class
CSymbolInfo    m_symbol;         // Symbol properties (Bid, Ask, TickValue) class

//--- GLOBAL STATE VARIABLES: Persistent values tracked across ticks and sessions
double   g_totalBuyLots  = 0;    // Sum of volume for all open Buy positions
double   g_totalSellLots = 0;    // Sum of volume for all open Sell positions
double   g_profitTally   = 0;    // Persistent bucket for fractional profit left after trimming (PRD 3.4)
double   g_hedgePoint    = -1;   // Tick-monitored Post-Trim Hedge Price Point (PRD 3.5)

//--- TICKET TRACKING: Structure to mirror theoretical vs actual trim (PRD 3.3)
struct TicketProfit {
   ulong ticket;              // ID of the profitable position
   double trimmedAmount;      // Cumulative profit already used for trimming during theoretical phase
   double lastTrimPips;       // The locked pip level at which the last intermediate trim occurred (PRD 3.3)
};
TicketProfit g_ticketTracks[];   // Dynamic array to track trimming status per position

string   g_fileName      = "";   // Filename for JSON state persistence (<MagicNumber>.json)

//--- SYNC TRACKING: Variables to detect closures synchronously in OnTick
int      g_lastPositionsCount = 0;   // PositionsTotal() from the previous tick
ulong    g_lastProcessedDeal  = 0;   // Ticket of the last reconciled deal
datetime g_lastHedgeTickTime  = 0;   // Guard: Prevents multiple hedges/reductions in a single tick

//--- INDICATOR HANDLE CACHE: Handles stored once per init to maximize performance (PRD 7.1)
int g_hRSI1 = INVALID_HANDLE, g_hEMA1_F = INVALID_HANDLE, g_hEMA1_M = INVALID_HANDLE, g_hEMA1_S = INVALID_HANDLE;
int g_hADX1 = INVALID_HANDLE, g_hBB1 = INVALID_HANDLE;
int g_hRSI2 = INVALID_HANDLE, g_hEMA2_F = INVALID_HANDLE, g_hEMA2_M = INVALID_HANDLE, g_hEMA2_S = INVALID_HANDLE;
int g_hADX2 = INVALID_HANDLE, g_hBB2 = INVALID_HANDLE;
