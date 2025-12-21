//+------------------------------------------------------------------+
//|                                       MA_Channel_RSI_EA_v5.1.mq5 |
//|                              + Dynamic Position Sizing ONLY      |
//|                                        Version 5.1 - MINIMAL     |
//+------------------------------------------------------------------+
#property copyright "MA Channel RSI EA v5.1"
#property version   "5.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== GENERAL ===
input ulong    MagicNumber        = 202412;
input int      MaxDailyTrades     = 5;
input int      MaxPositions       = 3;

//=== RISK MANAGEMENT (NEW - only addition) ===
input bool     UseDynamicLots     = true;      // Use dynamic position sizing
input double   RiskPercent        = 1.5;       // Risk % per trade (1-2% recommended)
input double   FixedLotSize       = 0.1;       // Fixed lot size (if dynamic disabled)

//=== INDICATORS ===
input int      MA_Period          = 20;
input ENUM_MA_METHOD MA_Method    = MODE_SMA;
input int      RSI_Period         = 14;
input double   RSI_BuyLevel       = 50.0;
input double   RSI_SellLevel      = 50.0;
input bool     UseH1Filter        = true;

//=== ENTRY ===
input int      EntryOffset        = 2;

//=== STOP LOSS ===
input int      StopLoss_Pips      = 50;

//=== BREAK EVEN ===
input bool     UseBreakEven       = true;
input int      BE_TriggerPips     = 30;
input int      BE_LockPips        = 5;

//=== TRAILING STOP ===
input bool     UseTrailing        = true;
input int      TrailStartPips     = 60;
input int      TrailDistancePips  = 50;
input int      TrailStepPips      = 10;

//=== TIME FILTER ===
input bool     UseTimeFilter      = true;
input int      StartHour          = 8;
input int      EndHour            = 20;

//=== LOGGING ===
input bool     EnableLog          = false;

//--- Global objects
CTrade trade;
CPositionInfo position;
COrderInfo order;

//--- Indicator handles
int hMA_High, hMA_Low, hRSI;
int hMA_High_H1, hMA_Low_H1;
int hATR;

//--- Buffers
double maHigh[], maLow[], rsi[];
double maHighH1[], maLowH1[];
double atr[];

//--- State
datetime lastBarTime = 0;
int dailyTrades = 0;
datetime lastTradeDate = 0;
double startBalance = 0;

//--- Log & Stats
int logFileHandle = INVALID_HANDLE;
int totalTrades = 0;
int winTrades = 0;
double totalProfitPips = 0;

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage (NEW FUNCTION)       |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
    if(!UseDynamicLots)
        return FixedLotSize;

    // Account balance and risk amount
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * RiskPercent / 100.0;

    // Get contract specifications
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double pip = GetPipValue();

    // Pip value per 1 lot
    double pipValue = tickValue * (pip / tickSize);

    // Lot size calculation
    double lots = riskAmount / (slPips * pipValue);

    // Apply broker limits
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

    // Round down to lot step
    lots = MathFloor(lots / lotStep) * lotStep;

    // Clamp to min/max
    lots = MathMax(minLot, MathMin(maxLot, lots));

    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);

    startBalance = AccountInfoDouble(ACCOUNT_BALANCE);

    // Open log file
    if(EnableLog)
    {
        string fname = "EA_Log_" + Symbol() + "_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
        StringReplace(fname, ".", "_");
        StringReplace(fname, ":", "");
        fname = StringSubstr(fname, 0, StringLen(fname)-4) + ".csv";
        logFileHandle = FileOpen(fname, FILE_WRITE|FILE_CSV|FILE_COMMON, ";");
        if(logFileHandle != INVALID_HANDLE)
        {
            FileWrite(logFileHandle, "Time", "Type", "Price", "SL", "Lots", "Pips", "Profit", "Balance");
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

    if(UseH1Filter)
    {
        hMA_High_H1 = iMA(Symbol(), PERIOD_H1, MA_Period, 0, MA_Method, PRICE_HIGH);
        hMA_Low_H1 = iMA(Symbol(), PERIOD_H1, MA_Period, 0, MA_Method, PRICE_LOW);

        if(hMA_High_H1 == INVALID_HANDLE || hMA_Low_H1 == INVALID_HANDLE)
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

    Print("EA v5.1 initialized | Risk:", RiskPercent, "% | SL:", StopLoss_Pips,
          " | Trail:", TrailStartPips, "/", TrailDistancePips);

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

    if(UseH1Filter)
    {
        if(hMA_High_H1 != INVALID_HANDLE) IndicatorRelease(hMA_High_H1);
        if(hMA_Low_H1 != INVALID_HANDLE) IndicatorRelease(hMA_Low_H1);
    }

    double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("EA v5.1 stopped | P/L: ", DoubleToString(finalBalance - startBalance, 2));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check new day
    CheckNewDay();

    // Time filter
    if(UseTimeFilter && !IsTradeTime())
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
    if(CopyBuffer(hATR, 0, 0, 1, atr) <= 0) return false;

    if(UseH1Filter)
    {
        if(CopyBuffer(hMA_High_H1, 0, 0, 2, maHighH1) <= 0) return false;
        if(CopyBuffer(hMA_Low_H1, 0, 0, 2, maLowH1) <= 0) return false;
    }

    return true;
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

    if(maBreakout && rsiOK && h1OK)
    {
        double pip = GetPipValue();
        double entry = high1 + EntryOffset * pip;
        double sl = entry - StopLoss_Pips * pip;

        // CHANGED: Dynamic lot size calculation
        double lots = CalculateLotSize(StopLoss_Pips);

        if(trade.BuyStop(lots, entry, Symbol(), sl, 0, ORDER_TIME_DAY, 0, "MA_Buy"))
        {
            dailyTrades++;
            Log("BUY STOP @ " + DoubleToString(entry, _Digits) + " | Lots: " + DoubleToString(lots, 2));
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

    if(maBreakout && rsiOK && h1OK)
    {
        double pip = GetPipValue();
        double entry = low1 - EntryOffset * pip;
        double sl = entry + StopLoss_Pips * pip;

        // CHANGED: Dynamic lot size calculation
        double lots = CalculateLotSize(StopLoss_Pips);

        if(trade.SellStop(lots, entry, Symbol(), sl, 0, ORDER_TIME_DAY, 0, "MA_Sell"))
        {
            dailyTrades++;
            Log("SELL STOP @ " + DoubleToString(entry, _Digits) + " | Lots: " + DoubleToString(lots, 2));
        }
    }
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
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

        // TRAILING STOP
        if(UseTrailing && profitPips >= TrailStartPips)
        {
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
                double trailSL = currentPrice - TrailDistancePips * pip;
                if(trailSL > newSL + TrailStepPips * pip)
                {
                    newSL = trailSL;
                    modify = true;
                }
            }
            else
            {
                double trailSL = currentPrice + TrailDistancePips * pip;
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
//| Helper: Check trade time                                          |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
    MqlDateTime tm;
    TimeToStruct(TimeCurrent(), tm);
    return (tm.hour >= StartHour && tm.hour < EndHour);
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
void LogTrade(string type, double price, double sl, double lots, double pips, double profit)
{
    if(!EnableLog || logFileHandle == INVALID_HANDLE) return;

    double bal = AccountInfoDouble(ACCOUNT_BALANCE);
    FileWrite(logFileHandle,
              TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
              type,
              DoubleToString(price, _Digits),
              DoubleToString(sl, _Digits),
              DoubleToString(lots, 2),
              DoubleToString(pips, 1),
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
                LogTrade(dir + "_OPEN", price, 0, volume, 0, 0);
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

                LogTrade("CLOSE", price, 0, volume, pips, profit);
            }
        }
    }
}
//+------------------------------------------------------------------+
