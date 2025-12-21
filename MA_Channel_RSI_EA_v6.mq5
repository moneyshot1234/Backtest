//+------------------------------------------------------------------+
//|                                         MA_Channel_RSI_EA_v6.mq5 |
//|                              Enhanced Risk Management Version    |
//|                                        Version 6.0 - IMPROVED    |
//+------------------------------------------------------------------+
#property copyright "MA Channel RSI EA v6"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== GENERAL ===
input group "=== GENERAL SETTINGS ==="
input ulong    MagicNumber        = 202412;
input int      MaxDailyTrades     = 5;
input int      MaxPositions       = 3;

//=== RISK MANAGEMENT (NEW) ===
input group "=== RISK MANAGEMENT ==="
input double   RiskPercent        = 1.0;      // Risk % per trade (1-2% recommended)
input double   MaxDailyLossPercent = 3.0;     // Max daily loss % to stop trading
input bool     UseDynamicLotSize  = true;     // Use dynamic position sizing
input double   FixedLotSize       = 0.1;      // Fixed lot size (if dynamic disabled)

//=== INDICATORS ===
input group "=== INDICATORS ==="
input int      MA_Period          = 20;
input ENUM_MA_METHOD MA_Method    = MODE_SMA;
input int      RSI_Period         = 14;
input double   RSI_BuyLevel       = 50.0;
input double   RSI_SellLevel      = 50.0;
input bool     UseH1Filter        = true;

//=== ADX TREND FILTER (NEW) ===
input group "=== ADX TREND FILTER ==="
input bool     UseADXFilter       = true;     // Enable ADX trend filter
input int      ADX_Period         = 14;
input double   ADX_Threshold      = 20.0;     // Min ADX for trading (trend strength)

//=== SPREAD FILTER (NEW) ===
input group "=== SPREAD FILTER ==="
input bool     UseSpreadFilter    = true;     // Enable spread filter
input double   MaxSpreadPips      = 4.0;      // Max allowed spread in pips

//=== ENTRY ===
input group "=== ENTRY SETTINGS ==="
input int      EntryOffset        = 2;

//=== STOP LOSS & TAKE PROFIT ===
input group "=== SL/TP SETTINGS ==="
input bool     UseATR_SL          = true;     // Use ATR-based SL (recommended)
input double   ATR_SL_Multiplier  = 2.0;      // ATR multiplier for SL
input int      FixedStopLoss_Pips = 50;       // Fixed SL (if ATR disabled)
input int      MinStopLoss_Pips   = 30;       // Minimum SL in pips
input int      MaxStopLoss_Pips   = 100;      // Maximum SL in pips

//=== TAKE PROFIT (NEW) ===
input group "=== TAKE PROFIT ==="
input bool     UseTakeProfit      = true;     // Enable Take Profit
input bool     UseATR_TP          = true;     // Use ATR-based TP
input double   ATR_TP_Multiplier  = 3.0;      // ATR multiplier for TP
input int      FixedTakeProfit_Pips = 150;    // Fixed TP (if ATR disabled)

//=== BREAK EVEN ===
input group "=== BREAK EVEN ==="
input bool     UseBreakEven       = true;
input int      BE_TriggerPips     = 30;
input int      BE_LockPips        = 5;

//=== TRAILING STOP ===
input group "=== TRAILING STOP ==="
input bool     UseTrailing        = true;
input bool     UseATR_Trail       = true;     // Use ATR-based trailing (NEW)
input double   ATR_Trail_Multiplier = 1.5;    // ATR multiplier for trail distance
input int      TrailStartPips     = 60;       // Fixed trail start (if ATR disabled)
input int      TrailDistancePips  = 50;       // Fixed trail distance
input int      TrailStepPips      = 10;

//=== TIME FILTER ===
input group "=== TIME FILTER ==="
input bool     UseTimeFilter      = true;
input int      StartHour          = 10;       // Optimized: 10 instead of 8
input int      EndHour            = 17;       // Optimized: 17 instead of 20
input bool     SkipMonday         = true;     // Skip Monday trading (NEW)
input bool     SkipFridayAfternoon = true;    // Skip Friday after 14:00 (NEW)

//=== LOGGING ===
input group "=== LOGGING ==="
input bool     EnableLog          = false;

//--- Global objects
CTrade trade;
CPositionInfo position;
COrderInfo order;

//--- Indicator handles
int hMA_High, hMA_Low, hRSI;
int hMA_High_H1, hMA_Low_H1;
int hATR, hATR_H1;
int hADX;

//--- Buffers
double maHigh[], maLow[], rsi[];
double maHighH1[], maLowH1[];
double atr[], atrH1[];
double adxMain[], adxPlus[], adxMinus[];

//--- State
datetime lastBarTime = 0;
int dailyTrades = 0;
datetime lastTradeDate = 0;
double startBalance = 0;
double dailyStartBalance = 0;

//--- Log & Stats
int logFileHandle = INVALID_HANDLE;
int totalTrades = 0;
int winTrades = 0;
double totalProfitPips = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);

    startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    dailyStartBalance = startBalance;

    // Open log file
    if(EnableLog)
    {
        string fname = "EA_Log_v6_" + Symbol() + "_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
        StringReplace(fname, ".", "_");
        StringReplace(fname, ":", "");
        fname = StringSubstr(fname, 0, StringLen(fname)-4) + ".csv";
        logFileHandle = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_COMMON, ";");
        if(logFileHandle != INVALID_HANDLE)
        {
            FileWrite(logFileHandle, "Time", "Type", "Price", "SL", "TP", "Lots", "ATR", "Spread", "Profit", "Balance");
        }
    }

    // Create indicators
    hMA_High = iMA(Symbol(), PERIOD_CURRENT, MA_Period, 0, MA_Method, PRICE_HIGH);
    hMA_Low = iMA(Symbol(), PERIOD_CURRENT, MA_Period, 0, MA_Method, PRICE_LOW);
    hRSI = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    hATR = iATR(Symbol(), PERIOD_CURRENT, 14);

    if(hMA_High == INVALID_HANDLE || hMA_Low == INVALID_HANDLE ||
       hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators");
        return INIT_FAILED;
    }

    // ADX indicator
    if(UseADXFilter)
    {
        hADX = iADX(Symbol(), PERIOD_CURRENT, ADX_Period);
        if(hADX == INVALID_HANDLE)
        {
            Print("ERROR: Failed to create ADX indicator");
            return INIT_FAILED;
        }
    }

    if(UseH1Filter)
    {
        hMA_High_H1 = iMA(Symbol(), PERIOD_H1, MA_Period, 0, MA_Method, PRICE_HIGH);
        hMA_Low_H1 = iMA(Symbol(), PERIOD_H1, MA_Period, 0, MA_Method, PRICE_LOW);
        hATR_H1 = iATR(Symbol(), PERIOD_H1, 14);

        if(hMA_High_H1 == INVALID_HANDLE || hMA_Low_H1 == INVALID_HANDLE || hATR_H1 == INVALID_HANDLE)
        {
            Print("ERROR: Failed to create H1 indicators");
            return INIT_FAILED;
        }
    }

    ArraySetAsSeries(maHigh, true);
    ArraySetAsSeries(maLow, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(maHighH1, true);
    ArraySetAsSeries(maLowH1, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(atrH1, true);
    ArraySetAsSeries(adxMain, true);
    ArraySetAsSeries(adxPlus, true);
    ArraySetAsSeries(adxMinus, true);

    Print("EA v6 initialized | Risk:", RiskPercent, "% | ATR_SL:", UseATR_SL,
          " | ADX Filter:", UseADXFilter, " | Spread Filter:", UseSpreadFilter);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Write summary and close log
    if(EnableLog && logFileHandle != INVALID_HANDLE)
    {
        double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double winRate = totalTrades > 0 ? (double)winTrades / totalTrades * 100.0 : 0;
        FileWrite(logFileHandle, "---SUMMARY---");
        FileWrite(logFileHandle, "Trades", totalTrades, "Wins", winTrades, "WinRate%", DoubleToString(winRate,1));
        FileWrite(logFileHandle, "TotalPips", DoubleToString(totalProfitPips,1), "P/L$", DoubleToString(finalBalance - startBalance, 2));
        FileClose(logFileHandle);
    }

    if(hMA_High != INVALID_HANDLE) IndicatorRelease(hMA_High);
    if(hMA_Low != INVALID_HANDLE) IndicatorRelease(hMA_Low);
    if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
    if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
    if(UseADXFilter && hADX != INVALID_HANDLE) IndicatorRelease(hADX);

    if(UseH1Filter)
    {
        if(hMA_High_H1 != INVALID_HANDLE) IndicatorRelease(hMA_High_H1);
        if(hMA_Low_H1 != INVALID_HANDLE) IndicatorRelease(hMA_Low_H1);
        if(hATR_H1 != INVALID_HANDLE) IndicatorRelease(hATR_H1);
    }

    double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("EA v6 stopped | P/L: ", DoubleToString(finalBalance - startBalance, 2));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check new day
    CheckNewDay();

    // Time filter (enhanced)
    if(!IsValidTradeTime())
        return;

    // Daily loss limit check
    if(!CheckDailyLossLimit())
        return;

    // Spread filter
    if(UseSpreadFilter && !IsSpreadAcceptable())
        return;

    // Get indicator values
    if(!GetIndicators())
        return;

    // Manage positions (trailing, break-even)
    ManagePositions();

    // Check for new bar
    datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
    if(lastBarTime == currentBar)
        return;
    lastBarTime = currentBar;

    // ADX filter check
    if(UseADXFilter && !IsADXValid())
        return;

    // Check signals on new bar
    if(CountPositions() < MaxPositions && dailyTrades < MaxDailyTrades && !HasPendingOrders())
    {
        CheckBuySignal();
        CheckSellSignal();
    }
}

//+------------------------------------------------------------------+
//| Get indicator values                                              |
//+------------------------------------------------------------------+
bool GetIndicators()
{
    if(CopyBuffer(hMA_High, 0, 0, 3, maHigh) <= 0) return false;
    if(CopyBuffer(hMA_Low, 0, 0, 3, maLow) <= 0) return false;
    if(CopyBuffer(hRSI, 0, 0, 3, rsi) <= 0) return false;
    if(CopyBuffer(hATR, 0, 0, 3, atr) <= 0) return false;

    if(UseADXFilter)
    {
        if(CopyBuffer(hADX, 0, 0, 3, adxMain) <= 0) return false;
        if(CopyBuffer(hADX, 1, 0, 3, adxPlus) <= 0) return false;
        if(CopyBuffer(hADX, 2, 0, 3, adxMinus) <= 0) return false;
    }

    if(UseH1Filter)
    {
        if(CopyBuffer(hMA_High_H1, 0, 0, 2, maHighH1) <= 0) return false;
        if(CopyBuffer(hMA_Low_H1, 0, 0, 2, maLowH1) <= 0) return false;
        if(CopyBuffer(hATR_H1, 0, 0, 2, atrH1) <= 0) return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on risk                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
    if(!UseDynamicLotSize)
        return FixedLotSize;

    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;

    // Get tick value
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double pip = GetPipValue();

    // Calculate pip value per lot
    double pipValuePerLot = tickValue * (pip / tickSize);

    // Calculate lot size
    double lotSize = riskAmount / (slPips * pipValuePerLot);

    // Apply lot size limits
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

    // Round to lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;

    // Clamp to min/max
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss in pips (ATR-based or fixed)                  |
//+------------------------------------------------------------------+
double CalculateStopLossPips()
{
    double slPips;

    if(UseATR_SL && atr[0] > 0)
    {
        double pip = GetPipValue();
        slPips = (atr[0] * ATR_SL_Multiplier) / pip;
    }
    else
    {
        slPips = FixedStopLoss_Pips;
    }

    // Apply min/max limits
    slPips = MathMax(MinStopLoss_Pips, MathMin(MaxStopLoss_Pips, slPips));

    return slPips;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit in pips (ATR-based or fixed)                |
//+------------------------------------------------------------------+
double CalculateTakeProfitPips()
{
    if(!UseTakeProfit)
        return 0;

    double tpPips;

    if(UseATR_TP && atr[0] > 0)
    {
        double pip = GetPipValue();
        tpPips = (atr[0] * ATR_TP_Multiplier) / pip;
    }
    else
    {
        tpPips = FixedTakeProfit_Pips;
    }

    return tpPips;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                     |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
    double spreadPoints = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    double pip = GetPipValue();
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double spreadPips = spreadPoints * point / pip;

    return (spreadPips <= MaxSpreadPips);
}

//+------------------------------------------------------------------+
//| Check ADX filter validity                                         |
//+------------------------------------------------------------------+
bool IsADXValid()
{
    if(!UseADXFilter)
        return true;

    // ADX must be above threshold (indicating trending market)
    return (adxMain[0] >= ADX_Threshold);
}

//+------------------------------------------------------------------+
//| Check daily loss limit                                            |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit()
{
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyPL = currentBalance - dailyStartBalance;
    double maxLoss = dailyStartBalance * MaxDailyLossPercent / 100.0;

    if(dailyPL < -maxLoss)
    {
        // Daily loss limit reached
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Enhanced time filter                                              |
//+------------------------------------------------------------------+
bool IsValidTradeTime()
{
    if(!UseTimeFilter)
        return true;

    MqlDateTime tm;
    TimeToStruct(TimeCurrent(), tm);

    // Skip Monday if enabled
    if(SkipMonday && tm.day_of_week == 1)
        return false;

    // Skip Friday afternoon if enabled (after 14:00)
    if(SkipFridayAfternoon && tm.day_of_week == 5 && tm.hour >= 14)
        return false;

    // Skip weekend
    if(tm.day_of_week == 0 || tm.day_of_week == 6)
        return false;

    // Check trading hours
    return (tm.hour >= StartHour && tm.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Check buy signal                                                  |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
    double close1 = iClose(Symbol(), PERIOD_CURRENT, 1);
    double low1 = iLow(Symbol(), PERIOD_CURRENT, 1);
    double high1 = iHigh(Symbol(), PERIOD_CURRENT, 1);

    // MA breakout: close above MA_High, low above MA_Low
    bool maBreakout = (close1 > maHigh[1] && low1 > maLow[1]);

    // RSI condition
    bool rsiOK = (rsi[1] > RSI_BuyLevel);

    // H1 filter
    bool h1OK = true;
    if(UseH1Filter)
    {
        double h1Close = iClose(Symbol(), PERIOD_H1, 0);
        h1OK = (h1Close > maHighH1[0]);
    }

    // ADX directional filter (optional: DI+ > DI- for buy)
    bool adxDirectionOK = true;
    if(UseADXFilter)
    {
        adxDirectionOK = (adxPlus[0] > adxMinus[0]);
    }

    if(maBreakout && rsiOK && h1OK && adxDirectionOK)
    {
        double pip = GetPipValue();
        double entry = high1 + EntryOffset * pip;

        // Calculate dynamic SL and TP
        double slPips = CalculateStopLossPips();
        double tpPips = CalculateTakeProfitPips();

        double sl = entry - slPips * pip;
        double tp = (tpPips > 0) ? entry + tpPips * pip : 0;

        // Calculate dynamic lot size
        double lots = CalculateLotSize(slPips);

        if(trade.BuyStop(lots, entry, Symbol(), sl, tp, ORDER_TIME_DAY, 0, "MA_Buy_v6"))
        {
            dailyTrades++;
            Log("BUY STOP @ " + DoubleToString(entry, _Digits) +
                " | SL:" + DoubleToString(slPips, 1) + " pips" +
                " | TP:" + DoubleToString(tpPips, 1) + " pips" +
                " | Lots:" + DoubleToString(lots, 2) +
                " | ATR:" + DoubleToString(atr[0], _Digits));
        }
    }
}

//+------------------------------------------------------------------+
//| Check sell signal                                                 |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
    double close1 = iClose(Symbol(), PERIOD_CURRENT, 1);
    double high1 = iHigh(Symbol(), PERIOD_CURRENT, 1);
    double low1 = iLow(Symbol(), PERIOD_CURRENT, 1);

    // MA breakout: close below MA_Low, high below MA_High
    bool maBreakout = (close1 < maLow[1] && high1 < maHigh[1]);

    // RSI condition
    bool rsiOK = (rsi[1] < RSI_SellLevel);

    // H1 filter
    bool h1OK = true;
    if(UseH1Filter)
    {
        double h1Close = iClose(Symbol(), PERIOD_H1, 0);
        h1OK = (h1Close < maLowH1[0]);
    }

    // ADX directional filter (optional: DI- > DI+ for sell)
    bool adxDirectionOK = true;
    if(UseADXFilter)
    {
        adxDirectionOK = (adxMinus[0] > adxPlus[0]);
    }

    if(maBreakout && rsiOK && h1OK && adxDirectionOK)
    {
        double pip = GetPipValue();
        double entry = low1 - EntryOffset * pip;

        // Calculate dynamic SL and TP
        double slPips = CalculateStopLossPips();
        double tpPips = CalculateTakeProfitPips();

        double sl = entry + slPips * pip;
        double tp = (tpPips > 0) ? entry - tpPips * pip : 0;

        // Calculate dynamic lot size
        double lots = CalculateLotSize(slPips);

        if(trade.SellStop(lots, entry, Symbol(), sl, tp, ORDER_TIME_DAY, 0, "MA_Sell_v6"))
        {
            dailyTrades++;
            Log("SELL STOP @ " + DoubleToString(entry, _Digits) +
                " | SL:" + DoubleToString(slPips, 1) + " pips" +
                " | TP:" + DoubleToString(tpPips, 1) + " pips" +
                " | Lots:" + DoubleToString(lots, 2) +
                " | ATR:" + DoubleToString(atr[0], _Digits));
        }
    }
}

//+------------------------------------------------------------------+
//| Manage open positions (enhanced trailing)                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
    double pip = GetPipValue();

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != Symbol() || position.Magic() != MagicNumber) continue;

        double openPrice = position.PriceOpen();
        double currentPrice = position.PriceCurrent();
        double currentSL = position.StopLoss();
        double currentTP = position.TakeProfit();
        ulong ticket = position.Ticket();

        // Calculate profit in pips
        double profitPips = 0;
        if(position.PositionType() == POSITION_TYPE_BUY)
            profitPips = (currentPrice - openPrice) / pip;
        else
            profitPips = (openPrice - currentPrice) / pip;

        // Skip if no profit
        if(profitPips <= 0) continue;

        double newSL = currentSL;
        bool modify = false;

        // Get trailing parameters (ATR-based or fixed)
        double trailStartPips = TrailStartPips;
        double trailDistPips = TrailDistancePips;

        if(UseATR_Trail && atr[0] > 0)
        {
            trailDistPips = (atr[0] * ATR_Trail_Multiplier) / pip;
            trailStartPips = trailDistPips * 1.2; // Start trailing at 1.2x trail distance
        }

        // BREAK EVEN
        if(UseBreakEven && profitPips >= BE_TriggerPips)
        {
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
                double beSL = openPrice + BE_LockPips * pip;
                if(currentSL < beSL)
                {
                    newSL = beSL;
                    modify = true;
                }
            }
            else
            {
                double beSL = openPrice - BE_LockPips * pip;
                if(currentSL > beSL || currentSL == 0)
                {
                    newSL = beSL;
                    modify = true;
                }
            }
        }

        // TRAILING STOP (enhanced with ATR)
        if(UseTrailing && profitPips >= trailStartPips)
        {
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
                double trailSL = currentPrice - trailDistPips * pip;
                if(trailSL > newSL + TrailStepPips * pip)
                {
                    newSL = trailSL;
                    modify = true;
                }
            }
            else
            {
                double trailSL = currentPrice + trailDistPips * pip;
                if(trailSL < newSL - TrailStepPips * pip || newSL == 0)
                {
                    newSL = trailSL;
                    modify = true;
                }
            }
        }

        // Apply modification
        if(modify)
        {
            newSL = NormalizeDouble(newSL, _Digits);
            if(trade.PositionModify(ticket, newSL, currentTP))
            {
                Log("SL modified: " + DoubleToString(newSL, _Digits) + " (+" + DoubleToString(profitPips, 1) + " pips)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Get pip value                                             |
//+------------------------------------------------------------------+
double GetPipValue()
{
    string sym = Symbol();
    int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(sym, SYMBOL_POINT);

    // Gold (XAUUSD)
    if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
        return 0.10;

    // Silver
    if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
        return 0.01;

    // Standard forex (5 or 3 digits)
    if(digits == 5 || digits == 3)
        return point * 10.0;

    return point;
}

//+------------------------------------------------------------------+
//| Helper: Count open positions                                      |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == Symbol() && position.Magic() == MagicNumber)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Helper: Check pending orders                                      |
//+------------------------------------------------------------------+
bool HasPendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(order.SelectByIndex(i))
        {
            if(order.Symbol() == Symbol() && order.Magic() == MagicNumber)
                return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper: Check new day                                             |
//+------------------------------------------------------------------+
void CheckNewDay()
{
    MqlDateTime current, last;
    TimeToStruct(TimeCurrent(), current);
    TimeToStruct(lastTradeDate, last);

    if(current.day != last.day || current.mon != last.mon || current.year != last.year)
    {
        dailyTrades = 0;
        lastTradeDate = TimeCurrent();
        dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    }
}

//+------------------------------------------------------------------+
//| Helper: Log message                                               |
//+------------------------------------------------------------------+
void Log(string msg)
{
    if(!EnableLog) return;
    Print(TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", msg);
}

//+------------------------------------------------------------------+
//| Log trade to file                                                 |
//+------------------------------------------------------------------+
void LogTrade(string type, double price, double sl, double tp, double lots, double pips, double profit)
{
    if(!EnableLog || logFileHandle == INVALID_HANDLE) return;

    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    double spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * SymbolInfoDouble(Symbol(), SYMBOL_POINT) / GetPipValue();

    FileWrite(logFileHandle,
              TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
              type,
              DoubleToString(price, _Digits),
              DoubleToString(sl, _Digits),
              DoubleToString(tp, _Digits),
              DoubleToString(lots, 2),
              DoubleToString(atr[0], _Digits),
              DoubleToString(spread, 1),
              DoubleToString(profit, 2),
              DoubleToString(bal, 2));
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    if(!EnableLog) return;
    if(trans.symbol != Symbol()) return;

    // Deal executed (position opened or closed)
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong dealTicket = trans.deal;
        if(dealTicket == 0) return;

        if(HistoryDealSelect(dealTicket))
        {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

            if(magic != MagicNumber) return;

            double pip = GetPipValue();

            if(entry == DEAL_ENTRY_IN)
            {
                // Position opened
                string dir = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
                LogTrade(dir + "_OPEN", price, 0, 0, volume, 0, 0);
            }
            else if(entry == DEAL_ENTRY_OUT)
            {
                // Position closed
                string dir = (dealType == DEAL_TYPE_BUY) ? "SELL" : "BUY"; // reverse for close
                double pips = 0;

                // Get original position price from history
                ulong posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
                if(HistorySelectByPosition(posId))
                {
                    for(int i = 0; i < HistoryDealsTotal(); i++)
                    {
                        ulong hTicket = HistoryDealGetTicket(i);
                        if(HistoryDealGetInteger(hTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
                        {
                            double openPrice = HistoryDealGetDouble(hTicket, DEAL_PRICE);
                            if(dealType == DEAL_TYPE_SELL) // closed a BUY
                                pips = (price - openPrice) / pip;
                            else // closed a SELL
                                pips = (openPrice - price) / pip;
                            break;
                        }
                    }
                }

                totalTrades++;
                totalProfitPips += pips;
                if(profit > 0) winTrades++;

                LogTrade("CLOSE", price, 0, 0, volume, pips, profit);
            }
        }
    }
}
//+------------------------------------------------------------------+
