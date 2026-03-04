//+------------------------------------------------------------------+
//|                                                      Globals.mqh |
//|                                  Copyright 2026, Souvik Chanda  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- GLOBAL OBJECTS ---
CTrade         m_trade;          // Trading class
CPositionInfo  m_position;       // Position info class
CSymbolInfo    m_symbol;         // Symbol info class

//--- GLOBAL STATE VARIABLES ---
double   g_totalBuyLots  = 0;    // Cached total Buy volume
double   g_totalSellLots = 0;    // Cached total Sell volume
int      g_buySequence   = 1;    // Sequence counter for BUY
int      g_sellSequence  = 1;    // Sequence counter for SELL
double   g_profitTally   = 0;    // Persistent profit tally for trimming
double   g_hedgePoint    = -1;   // Persistent Post-Trim Hedge Price Point

string   g_fileName      = "";   // JSON persistence filename

// Handle Cache
int g_hRSI1 = INVALID_HANDLE, g_hEMA1_F = INVALID_HANDLE, g_hEMA1_M = INVALID_HANDLE, g_hEMA1_S = INVALID_HANDLE;
int g_hADX1 = INVALID_HANDLE, g_hBB1 = INVALID_HANDLE;
int g_hRSI2 = INVALID_HANDLE, g_hEMA2_F = INVALID_HANDLE, g_hEMA2_M = INVALID_HANDLE, g_hEMA2_S = INVALID_HANDLE;
int g_hADX2 = INVALID_HANDLE, g_hBB2 = INVALID_HANDLE;
