#ifndef _GLOBALS_MQH_
#define _GLOBALS_MQH_

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
double   g_profitTally   = 0;    // Persistent bucket for fractional profit left after trimming (PRD 5.2)
double   g_unharvestedProfit = 0;// Persistent bucket for profit not used for trim
int      g_nextSequenceID = 1;   // Persistent ID for new sequences (PRD 3.1)
bool     g_isStateDirty  = false; // Dirty flag to consolidate redundant SaveState calls
datetime g_lastTrimTime  = 0;     // Timestamp of last trim to prevent double-triggering

//--- SEQUENCE INFO: Tracks individual trade cycles (PRD 3.1, 5.2)
struct SequenceInfo {
   long   magic;              // Full UniqueMagic
   double midPrice;           // (Entry_Buy + Entry_Sell) / 2
   ENUM_SEQUENCE_STATE state; // ACTIVE or LOCKED
   double volBuy;             // Current open buy volume
   double volSell;            // Current open sell volume
};
SequenceInfo g_sequences[];   // Dynamic array of all managed sequences

//--- MANUAL ADOPTION: Maps manual tickets to sequence IDs (PRD 3.2)
struct ManualMap {
   ulong ticket;
   long  assignedMagic;
};
ManualMap g_manualMaps[];     // Persistent mapping of Adopted trades

string   g_fileName      = "";   // Filename for JSON state persistence (<BaseMagicNumber>.json)

//--- SYNC TRACKING: Variables to detect closures synchronously in OnTick
ulong    g_lastProcessedDeal  = 0;   // Ticket of the last reconciled deal

//--- INDICATOR HANDLE CACHE: Handles stored once per init to maximize performance
int g_hRSI1 = INVALID_HANDLE, g_hEMA1_F = INVALID_HANDLE, g_hEMA1_M = INVALID_HANDLE, g_hEMA1_S = INVALID_HANDLE;
int g_hADX1 = INVALID_HANDLE, g_hBB1 = INVALID_HANDLE;
int g_hRSI2 = INVALID_HANDLE, g_hEMA2_F = INVALID_HANDLE, g_hEMA2_M = INVALID_HANDLE, g_hEMA2_S = INVALID_HANDLE;
int g_hADX2 = INVALID_HANDLE, g_hBB2 = INVALID_HANDLE;

#endif // _GLOBALS_MQH_
