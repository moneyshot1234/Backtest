//+------------------------------------------------------------------+
//|                              MA_Channel_RSI_EA_TrailingOptimized.mq5|
//|                     MA Channel RSI EA - Trailing Stop Optimized  |
//|                       Version 3.3 - DETAILED INIT LOGGING        |
//+------------------------------------------------------------------+
#property copyright "MA Channel RSI - INIT DIAGNOSTIC LOGGING"
#property link      "https://www.mql5.com"
#property version   "3.30"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Input paraméterek - FINOMHANGOLT ÉRTÉKEK
input group "═══ Általános Beállítások ═══"
input ulong    MagicNumber        = 202412;        // Magic Number
input bool     UseFixedLot        = true;          // Fix lot használata
input double   FixedLotSize       = 0.1;           // Fix pozíció méret (lot)
input double   RiskPerTrade       = 1.0;           // Kockázat/trade (%)
input int      MaxDailyTrades     = 5;             // Max napi trade szám
input int      MaxConcurrentTrades = 3;            // Max egyidejű pozíciók

input group "═══ Risk Management ═══"
input double   MaxDailyRisk       = 3.0;           // Max napi kockázat (%)
input double   MaxDrawdownLimit   = 15.0;          // Max drawdown limit (%)
input bool     UseEquityStop      = true;          // Equity stop használata
input double   EquityStopLevel    = 8.0;           // Equity stop szint (%)

input group "═══ Mozgóátlag Beállítások ═══"
input int      MA_Period          = 20;            // MA periódus
input ENUM_MA_METHOD MA_Method    = MODE_SMA;      // MA típus
input int      MA_Shift           = 0;             // MA eltolás

input group "═══ RSI Beállítások ═══"
input int      RSI_Period         = 14;            // RSI periódus
input ENUM_APPLIED_PRICE RSI_Applied = PRICE_CLOSE; // RSI alkalmazott ár
input double   RSI_LevelBuy       = 50.0;          // RSI Buy szint
input double   RSI_LevelSell      = 50.0;          // RSI Sell szint
input double   RSI_Overbought     = 70.0;          // RSI túlvett (trailing gyorsítás)
input double   RSI_Oversold       = 30.0;          // RSI túladott (trailing gyorsítás)

input group "═══ Belépési Beállítások ═══"
input int      EntryOffset        = 2;             // Belépési távolság (pip)
input bool     UseH1TrendFilter   = true;          // H1 trendszűrő használata

input group "═══ Stop Loss Beállítások ═══"
input bool     UseFixedSL         = true;          // Fix SL használata
input int      FixedSL_Pips       = 50;            // Stop Loss (pip) - OPTIMALIZÁLT!
input bool     UseATR_SL          = false;         // ATR alapú SL
input double   ATR_SL_Multiplier  = 2.0;           // ATR szorzó SL-hez

input group "═══ Take Profit Beállítások ═══"
input bool     UseFixedTP         = true;          // Fix TP használata - AJÁNLOTT!
input int      FixedTP_Pips       = 75;            // Take Profit (pip) - REÁLIS!
input bool     UseRiskReward      = false;         // Risk:Reward alapú TP
input double   RiskRewardRatio    = 1.5;           // Risk:Reward arány
input int      MaxTP_Pips         = 150;           // Maximum TP limit (pip)

input group "═══ Break-Even Beállítások ═══"
input bool     UseBreakEven       = true;          // Break-even használata
input int      BreakEvenTrigger   = 20;            // BE aktiválási szint (pip)
input int      BreakEvenProfit    = 3;             // BE profit biztosítás (pip)

//--- Enum a trailing módokhoz (INPUT ELŐTT kell lennie!)
//--- Enum a trailing módokhoz (INPUT ELŐTT kell lennie!)
enum ENUM_TRAILING_MODE
{
    TRAIL_NONE = 0,      // Nincs trailing
    TRAIL_BASIC = 1,     // Egyszerű trailing
    TRAIL_STEPPED = 2,   // Lépcsős trailing
    TRAIL_DYNAMIC = 3,   // Dinamikus trailing
    TRAIL_AGGRESSIVE = 4 // Agresszív trailing
};

input group "═══ ADVANCED Trailing Stop ═══"
input bool     UseTrailingStop    = true;          // Trailing stop használata
input ENUM_TRAILING_MODE TrailingMode = TRAIL_DYNAMIC; // Trailing mód

// Alap Trailing (TRAIL_BASIC)
input int      TrailingStart      = 15;            // Trailing kezdete (pip)
input int      TrailingStep       = 5;             // Trailing lépés (pip)
input int      TrailingDistance   = 15;            // Trailing távolság (pip)

// Lépcsős Trailing (TRAIL_STEPPED)
input int      Trail_Level1_Start = 15;            // 1. szint kezdete (pip)
input int      Trail_Level1_Distance = 15;         // 1. szint távolság (pip)
input int      Trail_Level2_Start = 30;            // 2. szint kezdete (pip)
input int      Trail_Level2_Distance = 12;         // 2. szint távolság (pip)
input int      Trail_Level3_Start = 50;            // 3. szint kezdete (pip)
input int      Trail_Level3_Distance = 10;         // 3. szint távolság (pip)
input int      Trail_Level4_Start = 75;            // 4. szint kezdete (pip)
input int      Trail_Level4_Distance = 8;          // 4. szint távolság (pip)

// Dinamikus Trailing (TRAIL_DYNAMIC)
input bool     UseRSI_Acceleration = true;         // RSI alapú gyorsítás
input bool     UseVolatility_Adjust = true;        // Volatilitás alapú állítás
input double   Trail_ATR_Multiplier = 1.5;         // ATR szorzó trail távolsághoz

// Profit Védelem
input int      SecureProfit_50    = 30;            // 50% profit védelem (pip)
input int      SecureProfit_75    = 50;            // 75% profit védelem (pip)
input int      SecureProfit_90    = 75;            // 90% profit védelem (pip)


input group "═══ Időzítés ═══"
input bool     UseTimeFilter      = true;          // Időszűrő használata
input int      StartHour          = 8;             // Kereskedés kezdete (óra GMT)
input int      EndHour            = 20;            // Kereskedés vége (óra GMT)

input group "═══ Monitoring ═══"
input bool     EnableLogging      = true;          // Részletes logolás
input bool     ShowDashboard      = true;          // Dashboard megjelenítése
input bool     AlertOnTP          = true;          // Értesítés TP elérésekor
input bool     AlertOnSL          = false;         // Értesítés SL elérésekor

//--- Globális változók
CTrade trade;
CPositionInfo position;
COrderInfo order;
CAccountInfo account;

// Indikátor handle-k
int handleMA_High, handleMA_Low, handleRSI;
int handleMA_High_H1, handleMA_Low_H1, handleRSI_H1;
int handleATR;

// Buffer tömbök
double ma_high_buffer[], ma_low_buffer[], rsi_buffer[];
double ma_high_h1_buffer[], ma_low_h1_buffer[], rsi_h1_buffer[];
double atr_buffer[];

// Trading változók
datetime lastTradeDate = 0;
int dailyTradeCount = 0;
double dailyProfit = 0;
double dailyLoss = 0;
double startingBalance = 0;
double maxEquity = 0;
string logFileName = "";

// Trailing változók minden pozícióhoz
struct TrailingInfo
{
    ulong ticket;
    double maxProfit;
    double lastTrailPrice;
    int currentLevel;
    datetime lastUpdate;
};
TrailingInfo trailingData[];

// Performance tracking
struct PerformanceStats
{
    int totalTrades;
    int winningTrades;
    int losingTrades;
    int tradesClosedByTP;
    int tradesClosedByTrailing;
    int tradesClosedBySL;
    double totalProfit;
    double totalLoss;
    double maxDrawdown;
    double winRate;
    double profitFactor;
    double avgWinPips;
    double avgLossPips;
};
PerformanceStats stats;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║          EA INICIALIZÁLÁS MEGKEZDVE - v3.2                   ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    
    // 1. ALAPADATOK
    Print("📊 SZIMBÓLUM ÉS IDŐKERET:");
    Print("  ├─ Symbol: ", Symbol());
    Print("  ├─ Timeframe: ", EnumToString(Period()));
    Print("  ├─ Digits: ", (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
    Print("  ├─ Point: ", SymbolInfoDouble(Symbol(), SYMBOL_POINT));
    Print("  └─ Pip Value: ", GetPipValue());
    
    // 2. SZÁMLA INFORMÁCIÓK
    Print("💰 SZÁMLA ADATOK:");
    Print("  ├─ Account ID: ", AccountInfoInteger(ACCOUNT_LOGIN));
    Print("  ├─ Account Name: ", AccountInfoString(ACCOUNT_NAME));
    Print("  ├─ Broker: ", AccountInfoString(ACCOUNT_SERVER));
    Print("  ├─ Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("  ├─ Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("  ├─ Leverage: 1:", AccountInfoInteger(ACCOUNT_LEVERAGE));
    Print("  └─ Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
    
    //--- EA beállítások
    Print("⚙️ EA BEÁLLÍTÁSOK:");
    Print("  ├─ Magic Number: ", MagicNumber);
    Print("  ├─ Fixed Lot Size: ", FixedLotSize);
    Print("  ├─ Max Daily Trades: ", MaxDailyTrades);
    Print("  ├─ Max Concurrent: ", MaxConcurrentTrades);
    Print("  ├─ Fixed SL: ", FixedSL_Pips, " pips");
    Print("  ├─ Fixed TP: ", FixedTP_Pips, " pips");
    Print("  └─ Trading Hours: ", StringFormat("%02d:00-%02d:00 GMT", StartHour, EndHour));
    
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(Symbol());
    trade.SetDeviationInPoints(10);
    Print("✓ Trade engine inicializálva");
    
    //--- Starting balance mentése
    startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    maxEquity = startingBalance;
    Print("✓ Kezdő balance mentve: ", DoubleToString(startingBalance, 2));
    
    //--- Indikátor handle-k létrehozása
    Print("🔧 INDIKÁTOROK LÉTREHOZÁSA:");
    Print("  ├─ Létrehozás: MA High (", MA_Period, " periódus)...");
    handleMA_High = iMA(Symbol(), PERIOD_CURRENT, MA_Period, MA_Shift, MA_Method, PRICE_HIGH);
    if(handleMA_High == INVALID_HANDLE)
    {
        Print("  │  └─ ❌ HIBA! MA_High handle invalid!");
        return(INIT_FAILED);
    }
    Print("  │  └─ ✓ MA_High handle: ", handleMA_High);
    
    Print("  ├─ Létrehozás: MA Low (", MA_Period, " periódus)...");
    handleMA_Low = iMA(Symbol(), PERIOD_CURRENT, MA_Period, MA_Shift, MA_Method, PRICE_LOW);
    if(handleMA_Low == INVALID_HANDLE)
    {
        Print("  │  └─ ❌ HIBA! MA_Low handle invalid!");
        return(INIT_FAILED);
    }
    Print("  │  └─ ✓ MA_Low handle: ", handleMA_Low);
    
    Print("  ├─ Létrehozás: RSI (", RSI_Period, " periódus)...");
    handleRSI = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, RSI_Applied);
    if(handleRSI == INVALID_HANDLE)
    {
        Print("  │  └─ ❌ HIBA! RSI handle invalid!");
        return(INIT_FAILED);
    }
    Print("  │  └─ ✓ RSI handle: ", handleRSI);
    
    Print("  ├─ Létrehozás: ATR (14 periódus)...");
    handleATR = iATR(Symbol(), PERIOD_CURRENT, 14);
    if(handleATR == INVALID_HANDLE)
    {
        Print("  │  └─ ❌ HIBA! ATR handle invalid!");
        return(INIT_FAILED);
    }
    Print("  │  └─ ✓ ATR handle: ", handleATR);
    
    //--- H1 indikátorok
    if(UseH1TrendFilter)
    {
        Print("  ├─ H1 TREND FILTER ENABLED:");
        Print("  │  ├─ Létrehozás: H1 MA High...");
        handleMA_High_H1 = iMA(Symbol(), PERIOD_H1, MA_Period, MA_Shift, MA_Method, PRICE_HIGH);
        if(handleMA_High_H1 == INVALID_HANDLE)
        {
            Print("  │  │  └─ ❌ HIBA! H1 MA_High handle invalid!");
            return(INIT_FAILED);
        }
        Print("  │  │  └─ ✓ H1 MA_High handle: ", handleMA_High_H1);
        
        Print("  │  ├─ Létrehozás: H1 MA Low...");
        handleMA_Low_H1 = iMA(Symbol(), PERIOD_H1, MA_Period, MA_Shift, MA_Method, PRICE_LOW);
        if(handleMA_Low_H1 == INVALID_HANDLE)
        {
            Print("  │  │  └─ ❌ HIBA! H1 MA_Low handle invalid!");
            return(INIT_FAILED);
        }
        Print("  │  │  └─ ✓ H1 MA_Low handle: ", handleMA_Low_H1);
        
        Print("  │  └─ Létrehozás: H1 RSI...");
        handleRSI_H1 = iRSI(Symbol(), PERIOD_H1, RSI_Period, RSI_Applied);
        if(handleRSI_H1 == INVALID_HANDLE)
        {
            Print("  │     └─ ❌ HIBA! H1 RSI handle invalid!");
            return(INIT_FAILED);
        }
        Print("  │     └─ ✓ H1 RSI handle: ", handleRSI_H1);
    }
    else
    {
        Print("  └─ H1 Trend Filter: KIKAPCSOLVA");
    }
    
    Print("✓ Minden indikátor handle sikeresen létrehozva!");
    
    //--- Buffer beállítások
    Print("📋 BUFFER TÖMBÖK BEÁLLÍTÁSA:");
    ArraySetAsSeries(ma_high_buffer, true);
    ArraySetAsSeries(ma_low_buffer, true);
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(ma_high_h1_buffer, true);
    ArraySetAsSeries(ma_low_h1_buffer, true);
    ArraySetAsSeries(rsi_h1_buffer, true);
    ArraySetAsSeries(atr_buffer, true);
    Print("✓ Buffer tömbök time series módban");
    
    //--- Trailing array init
    ArrayResize(trailingData, 0);
    Print("✓ Trailing data array inicializálva");
    
    //--- Várakozás az indikátorok inicializálására
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║ ⏳ VÁRAKOZÁS AZ INDIKÁTOROK ADATAINAK BETÖLTÉSÉRE...         ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    
    int attempts = 0;
    int maxAttempts = 100; // 10 másodperc maximum várakozás
    
    while(attempts < maxAttempts)
    {
        int ma_high_bars = BarsCalculated(handleMA_High);
        int ma_low_bars = BarsCalculated(handleMA_Low);
        int rsi_bars = BarsCalculated(handleRSI);
        int atr_bars = BarsCalculated(handleATR);
        
        int h1_ma_high_bars = 0;
        int h1_ma_low_bars = 0;
        int h1_rsi_bars = 0;
        
        if(UseH1TrendFilter)
        {
            h1_ma_high_bars = BarsCalculated(handleMA_High_H1);
            h1_ma_low_bars = BarsCalculated(handleMA_Low_H1);
            h1_rsi_bars = BarsCalculated(handleRSI_H1);
        }
        
        bool mainIndicatorsReady = (ma_high_bars >= MA_Period && 
                                     ma_low_bars >= MA_Period && 
                                     rsi_bars >= RSI_Period &&
                                     atr_bars >= 14);
        
        bool h1IndicatorsReady = !UseH1TrendFilter || 
                                  (h1_ma_high_bars >= MA_Period && 
                                   h1_ma_low_bars >= MA_Period && 
                                   h1_rsi_bars >= RSI_Period);
        
        if(mainIndicatorsReady && h1IndicatorsReady)
        {
            Print("╔═══════════════════════════════════════════════════════════════╗");
            Print("║ ✅ INDIKÁTOROK KÉSZEN!                                        ║");
            Print("╠═══════════════════════════════════════════════════════════════╣");
            Print("║ Timeframe: ", EnumToString(Period()));
            Print("║   ├─ MA High: ", ma_high_bars, " bars");
            Print("║   ├─ MA Low: ", ma_low_bars, " bars");
            Print("║   ├─ RSI: ", rsi_bars, " bars");
            Print("║   └─ ATR: ", atr_bars, " bars");
            
            if(UseH1TrendFilter)
            {
                Print("║ H1 Timeframe:");
                Print("║   ├─ MA High: ", h1_ma_high_bars, " bars");
                Print("║   ├─ MA Low: ", h1_ma_low_bars, " bars");
                Print("║   └─ RSI: ", h1_rsi_bars, " bars");
            }
            Print("╚═══════════════════════════════════════════════════════════════╝");
            break;
        }
        
        if(attempts % 10 == 0) // Minden másodpercben log
        {
            Print("⏳ Töltés [", attempts/10, "s]:");
            Print("  Current TF: MA_High=", ma_high_bars, "/", MA_Period, 
                  ", MA_Low=", ma_low_bars, "/", MA_Period,
                  ", RSI=", rsi_bars, "/", RSI_Period,
                  ", ATR=", atr_bars, "/14");
            
            if(UseH1TrendFilter)
            {
                Print("  H1 TF: MA_High=", h1_ma_high_bars, "/", MA_Period,
                      ", MA_Low=", h1_ma_low_bars, "/", MA_Period,
                      ", RSI=", h1_rsi_bars, "/", RSI_Period);
            }
        }
        
        Sleep(100); // 100ms várakozás
        attempts++;
    }
    
    if(attempts >= maxAttempts)
    {
        Print("╔═══════════════════════════════════════════════════════════════╗");
        Print("║ ❌ TIMEOUT - INDIKÁTOROK NEM TÖLTŐDTEK BE!                   ║");
        Print("╠═══════════════════════════════════════════════════════════════╣");
        Print("║ Az indikátorok nem töltődtek be ", maxAttempts/10, " másodperc alatt!");
        Print("║ ");
        Print("║ MEGOLDÁS:");
        Print("║ 1. Nyisd meg az ", Symbol(), " ", EnumToString(Period()), " chart-ot");
        Print("║ 2. Várj 1-2 percet");
        Print("║ 3. Indítsd újra az EA-t");
        Print("╚═══════════════════════════════════════════════════════════════╝");
        return(INIT_FAILED);
    }
    
    //--- Log fájl
    if(EnableLogging)
    {
        MqlDateTime timeStruct;
        TimeToStruct(TimeCurrent(), timeStruct);
        logFileName = StringFormat("MA_RSI_Trailing_%s_%04d%02d%02d.log", 
                                   Symbol(), timeStruct.year, timeStruct.mon, timeStruct.day);
        
        Print("📁 LOG FÁJL:");
        Print("  ├─ Fájlnév: ", logFileName);
        Print("  └─ Útvonal: MQL5\\Files\\");
        
        WriteLog("╔═══════════════════════════════════════════════════════════════╗");
        WriteLog("║        EA ADVANCED TRAILING v3.2 ELINDÍTVA! 🚀               ║");
        WriteLog("╚═══════════════════════════════════════════════════════════════╝");
        WriteLog(StringFormat("Kezdő balance: %.2f", startingBalance));
        WriteLog("Trailing Mode: " + GetTrailingModeName());
        WriteLog(StringFormat("MA Period: %d | RSI Period: %d", MA_Period, RSI_Period));
        WriteLog(StringFormat("SL: %d pips | TP: %d pips", FixedSL_Pips, FixedTP_Pips));
        WriteLog(StringFormat("Max Daily Trades: %d | Max Concurrent: %d", MaxDailyTrades, MaxConcurrentTrades));
        WriteLog(StringFormat("Trading Hours: %02d:00-%02d:00 GMT", StartHour, EndHour));
    }
    
    //--- Timer beállítása (1 másodperc)
    EventSetTimer(1);
    Print("✓ Timer beállítva (1 másodperc)");
    
    // VÉGSŐ ÖSSZEGZÉS
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║ ✅ EA INICIALIZÁLÁS SIKERES! KERESKEDÉSRE KÉSZ! 🎉          ║");
    Print("╠═══════════════════════════════════════════════════════════════╣");
    Print("║ Symbol: ", Symbol(), " | TF: ", EnumToString(Period()));
    Print("║ Balance: ", DoubleToString(startingBalance, 2));
    Print("║ Max Daily: ", MaxDailyTrades, " | Lot: ", FixedLotSize);
    Print("║ SL: ", FixedSL_Pips, " pips | TP: ", FixedTP_Pips, " pips");
    Print("║ Trailing: ", GetTrailingModeName());
    Print("║ Trading: ", StringFormat("%02d:00-%02d:00 GMT", StartHour, EndHour));
    Print("║ ");
    Print("║ 🔥 A ROBOT MÁR MŰKÖDIK ÉS FIGYELI A PIACOT! 🔥              ║");
    Print("╚═══════════════════════════════════════════════════════════════╝");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    
    //--- Handle-k felszabadítása
    if(handleMA_High != INVALID_HANDLE) IndicatorRelease(handleMA_High);
    if(handleMA_Low != INVALID_HANDLE) IndicatorRelease(handleMA_Low);
    if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
    if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
    
    if(UseH1TrendFilter)
    {
        if(handleMA_High_H1 != INVALID_HANDLE) IndicatorRelease(handleMA_High_H1);
        if(handleMA_Low_H1 != INVALID_HANDLE) IndicatorRelease(handleMA_Low_H1);
        if(handleRSI_H1 != INVALID_HANDLE) IndicatorRelease(handleRSI_H1);
    }
    
    if(EnableLogging)
    {
        WriteLog("Final Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
        WriteLog("Total P/L: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) - startingBalance, 2));
        WriteLog("═══ EA Leállítva ═══");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    static int tickCount = 0;
    tickCount++;
    
    // Minden 100. tick-nél részletes státusz
    if(tickCount % 100 == 0)
    {
        WriteLog(StringFormat("📊 TICK STATUS #%d | Price=%.5f | Bal=%.2f | Eqty=%.2f | Pos=%d", 
                             tickCount, SymbolInfoDouble(Symbol(), SYMBOL_BID),
                             AccountInfoDouble(ACCOUNT_BALANCE),
                             AccountInfoDouble(ACCOUNT_EQUITY),
                             CountOpenPositions()));
    }
    
    //--- Risk management
    if(!CheckRiskManagement())
    {
        if(tickCount % 100 == 0)
            WriteLog("⚠️ Risk management blokkolja a kereskedést!");
        return;
    }
    
    //--- Új nap ellenőrzése
    CheckNewDay();
    
    //--- Időszűrő
    if(UseTimeFilter && !IsTimeToTrade())
    {
        static datetime lastTimeWarning = 0;
        if(TimeCurrent() - lastTimeWarning > 300) // 5 percenként
        {
            MqlDateTime tm;
            TimeToStruct(TimeCurrent(), tm);
            WriteLog(StringFormat("⏰ Időszűrő AKTÍV - Kereskedési időn kívül! Jelenlegi óra: %02d:%02d GMT (Kereskedés: %02d:00-%02d:00)", 
                                 tm.hour, tm.min, StartHour, EndHour));
            lastTimeWarning = TimeCurrent();
        }
        return;
    }
    
    //--- Indikátor értékek
    if(!GetIndicatorValues())
    {
        static datetime lastWarning = 0;
        if(TimeCurrent() - lastWarning > 60) // Csak 1 percenként
        {
            int ma_bars = BarsCalculated(handleMA_High);
            int rsi_bars = BarsCalculated(handleRSI);
            WriteLog(StringFormat("⏳ VÁRAKOZÁS INDIKÁTOR ADATOKRA... MA=%d/%d, RSI=%d/%d bars", 
                              ma_bars, MA_Period, rsi_bars, RSI_Period));
            lastWarning = TimeCurrent();
        }
        return;
    }
    
    //--- Pozíció management (minden tick-en fut!)
    ManageOpenPositions();
    
    //--- Új gyertya?
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(Symbol(), PERIOD_CURRENT, 0);
    
    if(lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        
        // Részletes log minden új gyertyánál
        WriteLog("╔═══════════════════════════════════════════════════════════════╗");
        WriteLog(StringFormat("║ ⭐ ÚJ H1 GYERTYA | %s", TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES)));
        WriteLog("╠═══════════════════════════════════════════════════════════════╣");
        WriteLog(StringFormat("║ 💰 Balance: %.2f | Equity: %.2f | P/L: %.2f", 
                             AccountInfoDouble(ACCOUNT_BALANCE),
                             AccountInfoDouble(ACCOUNT_EQUITY),
                             AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE)));
        WriteLog(StringFormat("║ 📊 Indikátorok: MA High=%.5f | MA Low=%.5f | RSI=%.2f", 
                             ma_high_buffer[0], ma_low_buffer[0], rsi_buffer[0]));
        WriteLog(StringFormat("║ 📈 Ár: Close=%.5f | Ask=%.5f | Bid=%.5f", 
                             iClose(Symbol(), PERIOD_CURRENT, 0),
                             SymbolInfoDouble(Symbol(), SYMBOL_ASK),
                             SymbolInfoDouble(Symbol(), SYMBOL_BID)));
        WriteLog(StringFormat("║ 🔢 Napi trade-ek: %d/%d | Pozíciók: %d/%d", 
                             dailyTradeCount, MaxDailyTrades,
                             CountOpenPositions(), MaxConcurrentTrades));
        
        //--- Trading feltételek csak új gyertyánál
        if(CountOpenPositions() < MaxConcurrentTrades && dailyTradeCount < MaxDailyTrades)
        {
            if(!HasPendingOrders())
            {
                WriteLog("║ 🔍 SIGNAL CHECK indítása...");
                CheckBuySignal();
                CheckSellSignal();
            }
            else
            {
                WriteLog("║ ⏸️ Pending order-ek várnak - új jel kihagyva");
            }
        }
        else
        {
            if(CountOpenPositions() >= MaxConcurrentTrades)
                WriteLog(StringFormat("║ 🛑 Max pozíciószám elérve (%d/%d)", CountOpenPositions(), MaxConcurrentTrades));
            if(dailyTradeCount >= MaxDailyTrades)
                WriteLog(StringFormat("║ 🛑 Max napi trade elérve (%d/%d)", dailyTradeCount, MaxDailyTrades));
        }
        WriteLog("╚═══════════════════════════════════════════════════════════════╝");
    }
    
    //--- Dashboard
    if(ShowDashboard)
        UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer event (másodpercenként)                                    |
//+------------------------------------------------------------------+

void OnTimer()
{
    //--- Trailing finomhangolás másodpercenként
    if(UseTrailingStop && TrailingMode != TRAIL_NONE)
    {
        ManageAdvancedTrailing();
    }
}


//+------------------------------------------------------------------+
//| Trade event                                                       |
//+------------------------------------------------------------------+
void OnTrade()
{
    WriteLog("╔═══════════════════════════════════════════════════════════════╗");
    WriteLog("║ 🔔 TRADE EVENT - Pozíció/Order változás történt!             ║");
    WriteLog("╚═══════════════════════════════════════════════════════════════╝");
    
    // Ellenőrizzük mi történt
    HistorySelect(TimeCurrent() - 60, TimeCurrent()); // Utolsó 1 perc
    int totalDeals = HistoryDealsTotal();
    
    if(totalDeals > 0)
    {
        ulong ticket = HistoryDealGetTicket(totalDeals - 1);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
        {
            long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
            double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double dealVolume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double dealPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
            string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            
            if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
            {
                string typeStr = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
                WriteLog(StringFormat("  ├─ Pozíció NYITVA: %s %.2f lot @ %.5f", typeStr, dealVolume, dealPrice));
                WriteLog(StringFormat("  └─ Symbol: %s | Ticket: %llu", dealSymbol, ticket));
            }
            else if(dealProfit != 0)
            {
                WriteLog(StringFormat("  ├─ Pozíció ZÁRVA: Profit=%.2f %s", 
                                     dealProfit, 
                                     dealProfit > 0 ? "✅" : "❌"));
                WriteLog(StringFormat("  ├─ Price: %.5f | Volume: %.2f", dealPrice, dealVolume));
                WriteLog(StringFormat("  └─ Ticket: %llu", ticket));
                
                // Frissítsd a napi statisztikát
                if(dealProfit > 0)
                    dailyProfit += dealProfit;
                else
                    dailyLoss += dealProfit;
            }
        }
    }
    
    UpdateTrailingData();
    UpdatePerformanceStats();
    
    // Jelenlegi pozíciók listája
    int openPos = CountOpenPositions();
    if(openPos > 0)
    {
        WriteLog(StringFormat("📊 Jelenleg %d pozíció nyitva:", openPos));
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(position.SelectByIndex(i))
            {
                if(position.Symbol() == Symbol() && position.Magic() == MagicNumber)
                {
                    double profit = position.Profit();
                    double profitPips = 0;
                    if(position.PositionType() == POSITION_TYPE_BUY)
                        profitPips = (position.PriceCurrent() - position.PriceOpen()) / GetPipValue();
                    else
                        profitPips = (position.PriceOpen() - position.PriceCurrent()) / GetPipValue();
                    
                    WriteLog(StringFormat("  #%d: %s | %.1f pips | P/L: %.2f", 
                                         i+1,
                                         position.PositionType() == POSITION_TYPE_BUY ? "BUY " : "SELL",
                                         profitPips,
                                         profit));
                }
            }
        }
    }
}


//+------------------------------------------------------------------+
//| ADVANCED Trailing Stop Management                                |
//+------------------------------------------------------------------+
void ManageAdvancedTrailing()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != Symbol() || position.Magic() != MagicNumber) continue;
        
        double currentPrice = position.PriceCurrent();
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentTP = position.TakeProfit();
        double pipValue = GetPipValue();
        
        //--- Profit számítás pip-ben
        double profitPips = 0;
        if(position.PositionType() == POSITION_TYPE_BUY)
            profitPips = (currentPrice - openPrice) / pipValue;
        else
            profitPips = (openPrice - currentPrice) / pipValue;
        
        //--- Ha nincs profit, nincs trailing
        if(profitPips <= 0) continue;
        
        //--- Trailing mód szerint
        switch(TrailingMode)
        {
            case TRAIL_BASIC:
                ApplyBasicTrailing(position.Ticket(), profitPips);
                break;
                
            case TRAIL_STEPPED:
                ApplySteppedTrailing(position.Ticket(), profitPips);
                break;
                
            case TRAIL_DYNAMIC:
                ApplyDynamicTrailing(position.Ticket(), profitPips);
                break;
                
            case TRAIL_AGGRESSIVE:
                ApplyAggressiveTrailing(position.Ticket(), profitPips);
                break;
        }
    }
}


//+------------------------------------------------------------------+
//| Basic Trailing (Egyszerű)                                        |
//+------------------------------------------------------------------+
void ApplyBasicTrailing(ulong ticket, double profitPips)
{
    if(profitPips < TrailingStart) return;
    
    position.SelectByTicket(ticket);
    double currentPrice = position.PriceCurrent();
    double currentSL = position.StopLoss();
    double pipValue = GetPipValue();
    double newSL = 0;
    
    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        newSL = currentPrice - TrailingDistance * pipValue;
        if(newSL > currentSL + TrailingStep * pipValue)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("Basic Trail BUY: Profit=%.1f pips, New SL=%.5f", 
                        profitPips, newSL));
            }
        }
    }
    else // SELL
    {
        newSL = currentPrice + TrailingDistance * pipValue;
        if(newSL < currentSL - TrailingStep * pipValue || currentSL == 0)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("Basic Trail SELL: Profit=%.1f pips, New SL=%.5f", 
                        profitPips, newSL));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Stepped Trailing (Lépcsős)                                       |
//+------------------------------------------------------------------+
void ApplySteppedTrailing(ulong ticket, double profitPips)
{
    position.SelectByTicket(ticket);
    double currentPrice = position.PriceCurrent();
    double currentSL = position.StopLoss();
    double openPrice = position.PriceOpen();
    double pipValue = GetPipValue();
    double newSL = 0;
    int trailDistance = 0;
    
    //--- Szint meghatározása
    string level = "";
    if(profitPips >= Trail_Level4_Start)
    {
        trailDistance = Trail_Level4_Distance;
        level = "Level 4";
    }
    else if(profitPips >= Trail_Level3_Start)
    {
        trailDistance = Trail_Level3_Distance;
        level = "Level 3";
    }
    else if(profitPips >= Trail_Level2_Start)
    {
        trailDistance = Trail_Level2_Distance;
        level = "Level 2";
    }
    else if(profitPips >= Trail_Level1_Start)
    {
        trailDistance = Trail_Level1_Distance;
        level = "Level 1";
    }
    else
        return; // Még nincs elég profit
    
    //--- Profit védelem
    double protectPips = 0;
    if(profitPips >= SecureProfit_90)
        protectPips = profitPips * 0.9;
    else if(profitPips >= SecureProfit_75)
        protectPips = profitPips * 0.75;
    else if(profitPips >= SecureProfit_50)
        protectPips = profitPips * 0.5;
    
    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        newSL = currentPrice - trailDistance * pipValue;
        
        // Profit védelem ellenőrzése
        double protectSL = openPrice + protectPips * pipValue;
        if(protectSL > newSL) newSL = protectSL;
        
        if(newSL > currentSL + TrailingStep * pipValue)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("Stepped Trail BUY [%s]: Profit=%.1f pips, New SL=%.5f, Protected=%.1f pips", 
                        level, profitPips, newSL, (newSL-openPrice)/pipValue));
            }
        }
    }
    else // SELL
    {
        newSL = currentPrice + trailDistance * pipValue;
        
        // Profit védelem ellenőrzése
        double protectSL = openPrice - protectPips * pipValue;
        if(protectSL < newSL) newSL = protectSL;
        
        if(newSL < currentSL - TrailingStep * pipValue || currentSL == 0)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("Stepped Trail SELL [%s]: Profit=%.1f pips, New SL=%.5f, Protected=%.1f pips", 
                        level, profitPips, newSL, (openPrice-newSL)/pipValue));
            }
        }
    }
}


//+------------------------------------------------------------------+
//| Dynamic Trailing (Dinamikus - ATR & RSI alapú)                   |
//+------------------------------------------------------------------+
void ApplyDynamicTrailing(ulong ticket, double profitPips)
{
    if(profitPips < TrailingStart) return;
    
    position.SelectByTicket(ticket);
    double currentPrice = position.PriceCurrent();
    double currentSL = position.StopLoss();
    double openPrice = position.PriceOpen();
    double pipValue = GetPipValue();
    
    //--- ATR érték
    if(CopyBuffer(handleATR, 0, 0, 1, atr_buffer) <= 0) return;
    double atr = atr_buffer[0];
    
    //--- RSI érték
    if(CopyBuffer(handleRSI, 0, 0, 1, rsi_buffer) <= 0) return;
    double rsi = rsi_buffer[0];
    
    //--- Dinamikus távolság számítása
    double baseDistance = TrailingDistance;
    double dynamicDistance = baseDistance;
    
    // ATR alapú módosítás
    if(UseVolatility_Adjust)
    {
        dynamicDistance = atr * Trail_ATR_Multiplier / pipValue;
        dynamicDistance = MathMax(10, MathMin(50, dynamicDistance)); // 10-50 pip között
    }
    
    // RSI alapú gyorsítás
    if(UseRSI_Acceleration)
    {
        if(position.PositionType() == POSITION_TYPE_BUY)
        {
            if(rsi > RSI_Overbought)
                dynamicDistance *= 0.7; // Szorosabb trailing ha túlvett
            else if(rsi < 50)
                dynamicDistance *= 1.3; // Lazább trailing ha gyengül
        }
        else // SELL
        {
            if(rsi < RSI_Oversold)
                dynamicDistance *= 0.7; // Szorosabb trailing ha túladott
            else if(rsi > 50)
                dynamicDistance *= 1.3; // Lazább trailing ha gyengül
        }
    }
    
    // Profit alapú szorzó
    double profitMultiplier = 1.0;
    if(profitPips > 100)
        profitMultiplier = 0.5; // Nagyon szoros 100 pip felett
    else if(profitPips > 50)
        profitMultiplier = 0.7; // Szoros 50 pip felett
    else if(profitPips > 30)
        profitMultiplier = 0.85; // Közepes 30 pip felett
    
    dynamicDistance *= profitMultiplier;
    dynamicDistance = MathMax(8, dynamicDistance); // Minimum 8 pip
    
    //--- SL módosítás
    double newSL = 0;
    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        newSL = currentPrice - dynamicDistance * pipValue;
        
        // Minimum profit védelem
        double minProtect = openPrice + MathMax(3, profitPips * 0.3) * pipValue;
        if(newSL < minProtect) newSL = minProtect;
        
        if(newSL > currentSL + TrailingStep * pipValue)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("Dynamic Trail BUY: Profit=%.1f pips, Distance=%.1f pips, RSI=%.1f, ATR=%.5f", 
                        profitPips, dynamicDistance, rsi, atr));
            }
        }
    }
    else // SELL
    {
        newSL = currentPrice + dynamicDistance * pipValue;
        
        // Minimum profit védelem
        double minProtect = openPrice - MathMax(3, profitPips * 0.3) * pipValue;
        if(newSL > minProtect) newSL = minProtect;
        
        if(newSL < currentSL - TrailingStep * pipValue || currentSL == 0)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("Dynamic Trail SELL: Profit=%.1f pips, Distance=%.1f pips, RSI=%.1f, ATR=%.5f", 
                        profitPips, dynamicDistance, rsi, atr));
            }
        }
    }
}


//+------------------------------------------------------------------+
//| Aggressive Trailing (Agresszív - maximális profit védelem)       |
//+------------------------------------------------------------------+
void ApplyAggressiveTrailing(ulong ticket, double profitPips)
{
    if(profitPips < 10) return; // 10 pip-től indul
    
    position.SelectByTicket(ticket);
    double currentPrice = position.PriceCurrent();
    double currentSL = position.StopLoss();
    double openPrice = position.PriceOpen();
    double pipValue = GetPipValue();
    
    //--- Agresszív távolság: minél nagyobb a profit, annál szorosabb
    double trailDistance = MathMax(5, 20 - profitPips/10); // 5-20 pip között
    
    //--- Garantált profit
    double guaranteedProfit = profitPips * 0.8; // 80% profit védelem
    
    double newSL = 0;
    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        newSL = currentPrice - trailDistance * pipValue;
        
        // Garantált profit SL
        double guaranteedSL = openPrice + guaranteedProfit * pipValue;
        if(guaranteedSL > newSL) newSL = guaranteedSL;
        
        if(newSL > currentSL + 2 * pipValue) // Agresszív: 2 pip lépés
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("AGGRESSIVE Trail BUY: Profit=%.1f pips, Distance=%.1f, Guaranteed=%.1f pips", 
                        profitPips, trailDistance, guaranteedProfit));
            }
        }
    }
    else // SELL
    {
        newSL = currentPrice + trailDistance * pipValue;
        
        // Garantált profit SL
        double guaranteedSL = openPrice - guaranteedProfit * pipValue;
        if(guaranteedSL < newSL) newSL = guaranteedSL;
        
        if(newSL < currentSL - 2 * pipValue || currentSL == 0)
        {
            if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("AGGRESSIVE Trail SELL: Profit=%.1f pips, Distance=%.1f, Guaranteed=%.1f pips", 
                        profitPips, trailDistance, guaranteedProfit));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Pozíció management                                               |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    //--- Break-even kezelés
    if(UseBreakEven)
        ManageBreakEven();
}

//+------------------------------------------------------------------+
//| Break-Even management                                            |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != Symbol() || position.Magic() != MagicNumber) continue;
        
        double currentPrice = position.PriceCurrent();
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double pipValue = GetPipValue();
        
        // Már break-even-ben van?
        bool alreadyBE = false;
        if(position.PositionType() == POSITION_TYPE_BUY)
            alreadyBE = (currentSL >= openPrice);
        else
            alreadyBE = (currentSL <= openPrice && currentSL != 0);
        
        if(alreadyBE) continue;
        
        // Profit ellenőrzés
        double profitPips = 0;
        if(position.PositionType() == POSITION_TYPE_BUY)
            profitPips = (currentPrice - openPrice) / pipValue;
        else
            profitPips = (openPrice - currentPrice) / pipValue;
        
        if(profitPips >= BreakEvenTrigger)
        {
            double newSL = 0;
            if(position.PositionType() == POSITION_TYPE_BUY)
                newSL = openPrice + BreakEvenProfit * pipValue;
            else
                newSL = openPrice - BreakEvenProfit * pipValue;
            
            if(trade.PositionModify(position.Ticket(), newSL, position.TakeProfit()))
            {
                WriteLog(StringFormat("BREAK-EVEN aktiválva: Ticket=%d, New SL=%.5f", 
                        position.Ticket(), newSL));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Buy signal check                                                 |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
    WriteLog("  ├─ 🔍 BUY signal ellenőrzés...");
    
    double close1 = iClose(Symbol(), PERIOD_CURRENT, 1);
    double high1 = iHigh(Symbol(), PERIOD_CURRENT, 1);
    double low1 = iLow(Symbol(), PERIOD_CURRENT, 1);
    
    WriteLog(StringFormat("  │  ├─ Előző gyertya: Close=%.5f, High=%.5f, Low=%.5f", close1, high1, low1));
    WriteLog(StringFormat("  │  ├─ MA csatorna[1]: High=%.5f, Low=%.5f", ma_high_buffer[1], ma_low_buffer[1]));
    WriteLog(StringFormat("  │  ├─ RSI[1]: %.2f (limit: >%.1f)", rsi_buffer[1], RSI_LevelBuy));
    
    //--- MA breakout
    bool maBreakout = (close1 > ma_high_buffer[1] && low1 > ma_low_buffer[1]);
    WriteLog(StringFormat("  │  ├─ MA Breakout: %s (Close > MA_High: %s, Low > MA_Low: %s)", 
                         maBreakout ? "✓ IGEN" : "✗ NEM",
                         close1 > ma_high_buffer[1] ? "✓" : "✗",
                         low1 > ma_low_buffer[1] ? "✓" : "✗"));
    
    //--- RSI condition
    bool rsiCondition = (rsi_buffer[1] > RSI_LevelBuy);
    WriteLog(StringFormat("  │  ├─ RSI feltétel: %s (%.2f > %.1f)", 
                         rsiCondition ? "✓ IGEN" : "✗ NEM", rsi_buffer[1], RSI_LevelBuy));
    
    //--- H1 trend
    bool h1TrendOK = true;
    if(UseH1TrendFilter)
    {
        double h1_close = iClose(Symbol(), PERIOD_H1, 0);
        h1TrendOK = (h1_close > ma_high_h1_buffer[0]);
        WriteLog(StringFormat("  │  ├─ H1 Trend szűrő: %s (H1 Close=%.5f > H1 MA_High=%.5f: %s)", 
                             h1TrendOK ? "✓ IGEN" : "✗ NEM", 
                             h1_close, ma_high_h1_buffer[0],
                             h1_close > ma_high_h1_buffer[0] ? "✓" : "✗"));
    }
    else
    {
        WriteLog("  │  ├─ H1 Trend szűrő: KIKAPCSOLVA");
    }
    
    if(maBreakout && rsiCondition && h1TrendOK)
    {
        WriteLog("  │  └─ ✅ MINDEN FELTÉTEL TELJESÜL! BUY jel generálása...");
        
        double entryPrice = high1 + EntryOffset * GetPipValue();
        double sl = CalculateStopLoss(ORDER_TYPE_BUY, low1);
        double tp = CalculateTakeProfit(ORDER_TYPE_BUY, entryPrice, sl);
        double lotSize = CalculateLotSize(sl, entryPrice);
        
        // DEBUG info
        double tpPips = (tp - entryPrice) / GetPipValue();
        double slPips = (entryPrice - sl) / GetPipValue();
        
        WriteLog("  │");
        WriteLog("  │  ┌─ 📊 BUY ORDER RÉSZLETEI:");
        WriteLog(StringFormat("  │  ├─ Entry Price: %.5f (High[1] + %d pip offset)", entryPrice, EntryOffset));
        WriteLog(StringFormat("  │  ├─ Stop Loss: %.5f (%.1f pip)", sl, slPips));
        WriteLog(StringFormat("  │  ├─ Take Profit: %.5f (%.1f pip)", tp, tpPips));
        WriteLog(StringFormat("  │  ├─ Lot Size: %.2f", lotSize));
        WriteLog(StringFormat("  │  └─ Risk:Reward = 1:%.2f", tpPips/slPips));
        
        if(trade.BuyStop(lotSize, entryPrice, Symbol(), sl, tp, ORDER_TIME_DAY, 0, "MA Channel Buy"))
        {
            dailyTradeCount++;
            WriteLog("  └─ ✅ BUY STOP ORDER SIKERESEN ELHELYEZVE! 🎉");
            if(AlertOnTP)
                Alert("✅ BUY STOP order placed @ ", entryPrice);
        }
        else
        {
            WriteLog(StringFormat("  └─ ❌ BUY STOP ORDER HIBA! ResultRetcode=%d, Comment=%s", 
                                 trade.ResultRetcode(), trade.ResultComment()));
        }
    }
    else
    {
        WriteLog(StringFormat("  └─ ❌ BUY jel NINCS (MA:%s, RSI:%s, H1:%s)", 
                             maBreakout ? "✓" : "✗",
                             rsiCondition ? "✓" : "✗",
                             h1TrendOK ? "✓" : "✗"));
    }
}

//+------------------------------------------------------------------+
//| Sell signal check                                                |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
    WriteLog("  ├─ 🔍 SELL signal ellenőrzés...");
    
    double close1 = iClose(Symbol(), PERIOD_CURRENT, 1);
    double high1 = iHigh(Symbol(), PERIOD_CURRENT, 1);
    double low1 = iLow(Symbol(), PERIOD_CURRENT, 1);
    
    WriteLog(StringFormat("  │  ├─ Előző gyertya: Close=%.5f, High=%.5f, Low=%.5f", close1, high1, low1));
    WriteLog(StringFormat("  │  ├─ MA csatorna[1]: High=%.5f, Low=%.5f", ma_high_buffer[1], ma_low_buffer[1]));
    WriteLog(StringFormat("  │  ├─ RSI[1]: %.2f (limit: <%.1f)", rsi_buffer[1], RSI_LevelSell));
    
    //--- MA breakout
    bool maBreakout = (close1 < ma_low_buffer[1] && high1 < ma_high_buffer[1]);
    WriteLog(StringFormat("  │  ├─ MA Breakout: %s (Close < MA_Low: %s, High < MA_High: %s)", 
                         maBreakout ? "✓ IGEN" : "✗ NEM",
                         close1 < ma_low_buffer[1] ? "✓" : "✗",
                         high1 < ma_high_buffer[1] ? "✓" : "✗"));
    
    //--- RSI condition
    bool rsiCondition = (rsi_buffer[1] < RSI_LevelSell);
    WriteLog(StringFormat("  │  ├─ RSI feltétel: %s (%.2f < %.1f)", 
                         rsiCondition ? "✓ IGEN" : "✗ NEM", rsi_buffer[1], RSI_LevelSell));
    
    //--- H1 trend
    bool h1TrendOK = true;
    if(UseH1TrendFilter)
    {
        double h1_close = iClose(Symbol(), PERIOD_H1, 0);
        h1TrendOK = (h1_close < ma_low_h1_buffer[0]);
        WriteLog(StringFormat("  │  ├─ H1 Trend szűrő: %s (H1 Close=%.5f < H1 MA_Low=%.5f: %s)", 
                             h1TrendOK ? "✓ IGEN" : "✗ NEM",
                             h1_close, ma_low_h1_buffer[0],
                             h1_close < ma_low_h1_buffer[0] ? "✓" : "✗"));
    }
    else
    {
        WriteLog("  │  ├─ H1 Trend szűrő: KIKAPCSOLVA");
    }
    
    if(maBreakout && rsiCondition && h1TrendOK)
    {
        WriteLog("  │  └─ ✅ MINDEN FELTÉTEL TELJESÜL! SELL jel generálása...");
        
        double entryPrice = low1 - EntryOffset * GetPipValue();
        double sl = CalculateStopLoss(ORDER_TYPE_SELL, high1);
        double tp = CalculateTakeProfit(ORDER_TYPE_SELL, entryPrice, sl);
        double lotSize = CalculateLotSize(entryPrice, sl);
        
        // DEBUG info
        double tpPips = (entryPrice - tp) / GetPipValue();
        double slPips = (sl - entryPrice) / GetPipValue();
        
        WriteLog("  │");
        WriteLog("  │  ┌─ 📊 SELL ORDER RÉSZLETEI:");
        WriteLog(StringFormat("  │  ├─ Entry Price: %.5f (Low[1] - %d pip offset)", entryPrice, EntryOffset));
        WriteLog(StringFormat("  │  ├─ Stop Loss: %.5f (%.1f pip)", sl, slPips));
        WriteLog(StringFormat("  │  ├─ Take Profit: %.5f (%.1f pip)", tp, tpPips));
        WriteLog(StringFormat("  │  ├─ Lot Size: %.2f", lotSize));
        WriteLog(StringFormat("  │  └─ Risk:Reward = 1:%.2f", tpPips/slPips));
        
        if(trade.SellStop(lotSize, entryPrice, Symbol(), sl, tp, ORDER_TIME_DAY, 0, "MA Channel Sell"))
        {
            dailyTradeCount++;
            WriteLog("  └─ ✅ SELL STOP ORDER SIKERESEN ELHELYEZVE! 🎉");
            if(AlertOnTP)
                Alert("✅ SELL STOP order placed @ ", entryPrice);
        }
        else
        {
            WriteLog(StringFormat("  └─ ❌ SELL STOP ORDER HIBA! ResultRetcode=%d, Comment=%s", 
                                 trade.ResultRetcode(), trade.ResultComment()));
        }
    }
    else
    {
        WriteLog(StringFormat("  └─ ❌ SELL jel NINCS (MA:%s, RSI:%s, H1:%s)", 
                             maBreakout ? "✓" : "✗",
                             rsiCondition ? "✓" : "✗",
                             h1TrendOK ? "✓" : "✗"));
    }
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double swingLevel)
{
    double sl = 0;
    double pipValue = GetPipValue();
    double currentPrice = (orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_STOP) ? 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    if(UseATR_SL)
    {
        // ATR alapú SL
        if(CopyBuffer(handleATR, 0, 0, 1, atr_buffer) > 0)
        {
            double atrDistance = atr_buffer[0] * ATR_SL_Multiplier;
            
            if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_STOP)
                sl = currentPrice - atrDistance;
            else
                sl = currentPrice + atrDistance;
        }
    }
    else if(UseFixedSL)
    {
        // Fix SL
        if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_STOP)
            sl = currentPrice - FixedSL_Pips * pipValue;
        else
            sl = currentPrice + FixedSL_Pips * pipValue;
    }
    
    return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit - OPTIMALIZÁLT!                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss)
{
    double tp = 0;
    double pipValue = GetPipValue();
    
    // ELSŐDLEGES: Fix TP használata (AJÁNLOTT!)
    if(UseFixedTP)
    {
        if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_STOP)
            tp = entryPrice + FixedTP_Pips * pipValue;
        else
            tp = entryPrice - FixedTP_Pips * pipValue;
    }
    // MÁSODLAGOS: Risk:Reward alapú TP
    else if(UseRiskReward)
    {
        double riskDistance = MathAbs(entryPrice - stopLoss);
        double tpDistance = riskDistance * RiskRewardRatio;
        
        // LIMIT: Maximum TP távolság
        double maxTPDistance = MaxTP_Pips * pipValue;
        if(tpDistance > maxTPDistance)
        {
            tpDistance = maxTPDistance;
            WriteLog(StringFormat("TP limited to %d pips", MaxTP_Pips));
        }
        
        if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_BUY_STOP)
            tp = entryPrice + tpDistance;
        else
            tp = entryPrice - tpDistance;
    }
    
    return NormalizeDouble(tp, _Digits);
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
    if(UseFixedLot)
        return FixedLotSize;
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPerTrade / 100.0);
    double slDistance = MathAbs(entryPrice - stopLoss);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    
    if(tickValue == 0 || slDistance == 0)
        return SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    
    double lotSize = riskAmount / (slDistance / _Point * tickValue);
    
    // Normalizálás
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = NormalizeDouble(lotSize, 2);
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Risk Management Check                                            |
//+------------------------------------------------------------------+
bool CheckRiskManagement()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Max equity frissítése
    if(currentEquity > maxEquity)
    {
        maxEquity = currentEquity;
        WriteLog(StringFormat("💎 ÚJ MAX EQUITY: %.2f", maxEquity));
    }
    
    // Drawdown számítások
    double ddFromStart = (startingBalance - currentEquity) / startingBalance * 100;
    double ddFromPeak = (maxEquity - currentEquity) / maxEquity * 100;
    
// Equity stop
if(UseEquityStop && ddFromStart > EquityStopLevel)
{
    WriteLog("╔═══════════════════════════════════════════════════════════════╗");
    WriteLog("║ 🚨 EQUITY STOP AKTIVÁLVA! 🚨                                  ║");
    WriteLog("╠═══════════════════════════════════════════════════════════════╣");
    WriteLog(StringFormat("║ Kezdő balance: %.2f", startingBalance));
    WriteLog(StringFormat("║ Jelenlegi equity: %.2f", currentEquity));
    WriteLog(StringFormat("║ Drawdown: %.2f%% (limit: %.2f%%)", ddFromStart, EquityStopLevel));
    WriteLog("╚═══════════════════════════════════════════════════════════════╝");
    CloseAllPositions("EQUITY STOP TRIGGERED!");
    return false;
}

// Max drawdown
if(ddFromPeak > MaxDrawdownLimit)
{
    WriteLog("╔═══════════════════════════════════════════════════════════════╗");
    WriteLog("║ 🚨 MAX DRAWDOWN LIMIT ELÉRVE! 🚨                              ║");
    WriteLog("╠═══════════════════════════════════════════════════════════════╣");
    WriteLog(StringFormat("║ Max equity: %.2f", maxEquity));
    WriteLog(StringFormat("║ Jelenlegi equity: %.2f", currentEquity));
    WriteLog(StringFormat("║ Drawdown from peak: %.2f%% (limit: %.2f%%)", ddFromPeak, MaxDrawdownLimit));
    WriteLog("╚═══════════════════════════════════════════════════════════════╝");
    CloseAllPositions("MAX DRAWDOWN TRIGGERED!");
    return false;
}


    
    // Daily risk
    double dailyLossPercent = MathAbs(dailyLoss) / startingBalance * 100;
    if(dailyLossPercent > MaxDailyRisk)
    {
        WriteLog("╔═══════════════════════════════════════════════════════════════╗");
        WriteLog("║ 🚨 NAPI RISK LIMIT ELÉRVE! 🚨                                 ║");
        WriteLog("╠═══════════════════════════════════════════════════════════════╣");
        WriteLog(StringFormat("║ Napi veszteség: %.2f (%.2f%%)", dailyLoss, dailyLossPercent));
        WriteLog(StringFormat("║ Max napi risk: %.2f%%", MaxDailyRisk));
        WriteLog("║ Ma nem nyitunk több pozíciót!                                 ║");
        WriteLog("╚═══════════════════════════════════════════════════════════════╝");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Minden pozíció és pending order zárása adott indokkal            |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason = "")
{
    WriteLog("╔═══════════════════════════════════════════════════════════════╗");
    WriteLog("║ 🔻 CloseAllPositions hívva: " + reason + "                    ║");
    WriteLog("╚═══════════════════════════════════════════════════════════════╝");
    
    // Először a nyitott pozíciók zárása
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!position.SelectByIndex(i)) 
            continue;
        
        if(position.Symbol() != Symbol() || position.Magic() != MagicNumber)
            continue;
        
        ulong ticket = position.Ticket();
        double volume = position.Volume();
        long type = position.PositionType();
        
        bool result = false;
        if(type == POSITION_TYPE_BUY)
            result = trade.PositionClose(ticket);
        else if(type == POSITION_TYPE_SELL)
            result = trade.PositionClose(ticket);
        
        if(result)
        {
            WriteLog(StringFormat("✔ Pozíció zárva | Ticket=%llu | Volume=%.2f | Reason=%s", 
                                  ticket, volume, reason));
        }
        else
        {
            WriteLog(StringFormat("❌ Pozíció zárási HIBA | Ticket=%llu | Reason=%s | Retcode=%d (%s)", 
                                  ticket, reason, 
                                  trade.ResultRetcode(), 
                                  trade.ResultComment()));
        }
    }
    
    // Pending order-ek törlése
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(!order.SelectByIndex(i))
            continue;
        
        if(order.Symbol() != Symbol() || order.Magic() != MagicNumber)
            continue;
        
        ulong orderTicket = order.Ticket();
        if(trade.OrderDelete(orderTicket))
        {
            WriteLog(StringFormat("✔ Pending order törölve | Ticket=%llu | Reason=%s", 
                                  orderTicket, reason));
        }
        else
        {
            WriteLog(StringFormat("❌ Pending törlési HIBA | Ticket=%llu | Reason=%s | Retcode=%d (%s)", 
                                  orderTicket, reason, 
                                  trade.ResultRetcode(), 
                                  trade.ResultComment()));
        }
    }
}




//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
    if(CopyBuffer(handleMA_High, 0, 0, 3, ma_high_buffer) <= 0) return false;
    if(CopyBuffer(handleMA_Low, 0, 0, 3, ma_low_buffer) <= 0) return false;
    if(CopyBuffer(handleRSI, 0, 0, 3, rsi_buffer) <= 0) return false;
    
    if(UseH1TrendFilter)
    {
        if(CopyBuffer(handleMA_High_H1, 0, 0, 2, ma_high_h1_buffer) <= 0) return false;
        if(CopyBuffer(handleMA_Low_H1, 0, 0, 2, ma_low_h1_buffer) <= 0) return false;
        if(CopyBuffer(handleRSI_H1, 0, 0, 2, rsi_h1_buffer) <= 0) return false;
    }
    
    return true;
}

bool IsTimeToTrade()
{
    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);
    return (time.hour >= StartHour && time.hour < EndHour);
}

int CountOpenPositions()
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

void CheckNewDay()
{
    datetime currentDate = TimeCurrent();
    MqlDateTime currentDateStruct, lastDateStruct;
    TimeToStruct(currentDate, currentDateStruct);
    TimeToStruct(lastTradeDate, lastDateStruct);
    
    if(currentDateStruct.day != lastDateStruct.day)
    {
        // Előző nap összegzése
        if(lastTradeDate > 0)
        {
            WriteLog("╔═══════════════════════════════════════════════════════════════╗");
            WriteLog("║ 📅 NAP VÉGE ÖSSZEGZŐ - " + TimeToString(lastTradeDate, TIME_DATE) + "           ║");
            WriteLog("╠═══════════════════════════════════════════════════════════════╣");
            WriteLog(StringFormat("║ Trade-ek száma: %d/%d", dailyTradeCount, MaxDailyTrades));
            WriteLog(StringFormat("║ Napi profit: %.2f", dailyProfit));
            WriteLog(StringFormat("║ Napi loss: %.2f", dailyLoss));
            WriteLog(StringFormat("║ Nettó P/L: %.2f %s", 
                                 dailyProfit + dailyLoss,
                                 (dailyProfit + dailyLoss) > 0 ? "✅" : "❌"));
            WriteLog("╚═══════════════════════════════════════════════════════════════╝");
        }
        
        // Reset
        dailyTradeCount = 0;
        dailyProfit = 0;
        dailyLoss = 0;
        lastTradeDate = currentDate;
        
        // Új nap kezdete
        WriteLog("╔═══════════════════════════════════════════════════════════════╗");
        WriteLog("║ 🌅 ÚJ KERESKEDÉSI NAP - " + TimeToString(currentDate, TIME_DATE) + "       ║");
        WriteLog("╠═══════════════════════════════════════════════════════════════╣");
        WriteLog(StringFormat("║ Kezdő balance: %.2f", AccountInfoDouble(ACCOUNT_BALANCE)));
        WriteLog(StringFormat("║ Kezdő equity: %.2f", AccountInfoDouble(ACCOUNT_EQUITY)));
        WriteLog(StringFormat("║ Max trade-ek ma: %d", MaxDailyTrades));
        WriteLog(StringFormat("║ Max napi risk: %.2f%%", MaxDailyRisk));
        WriteLog(StringFormat("║ Kereskedési órák: %02d:00-%02d:00 GMT", StartHour, EndHour));
        WriteLog("╚═══════════════════════════════════════════════════════════════╝");
    }
}

double GetPipValue()
{
   string sym   = _Symbol;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   // Arany (XAUUSD, GOLD…): 1 pip = 0.1 USD
   if(StringFind(sym, "XAU", 0) == 0 || StringFind(sym, "GOLD", 0) == 0)
      return 0.10;

   // Ezüst (XAG…): 1 pip = 0.01 USD
   if(StringFind(sym, "XAG", 0) == 0 || StringFind(sym, "SILVER", 0) == 0)
      return 0.01;

   // Klasszikus forex párok – 5 és 3 digites jegyzés
   if(digits == 5 || digits == 3)
      return point * 10.0;

   // Egyéb szimbólumok (index, crypto stb.)
   return point;
}


void UpdateTrailingData()
{
    // Trailing data frissítése új pozíciókhoz
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == Symbol() && position.Magic() == MagicNumber)
            {
                bool found = false;
                for(int j = 0; j < ArraySize(trailingData); j++)
                {
                    if(trailingData[j].ticket == position.Ticket())
                    {
                        found = true;
                        break;
                    }
                }
                
                if(!found)
                {
                    int size = ArraySize(trailingData);
                    ArrayResize(trailingData, size + 1);
                    trailingData[size].ticket = position.Ticket();
                    trailingData[size].maxProfit = 0;
                    trailingData[size].lastTrailPrice = 0;
                    trailingData[size].currentLevel = 0;
                    trailingData[size].lastUpdate = TimeCurrent();
                }
            }
        }
    }
}

void UpdatePerformanceStats()
{
    // Performance statisztikák frissítése
    HistorySelect(0, TimeCurrent());
    int deals = HistoryDealsTotal();
    
    stats.totalTrades = 0;
    stats.winningTrades = 0;
    stats.losingTrades = 0;
    stats.totalProfit = 0;
    stats.totalLoss = 0;
    
    for(int i = 0; i < deals; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0)
        {
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            if(magic != MagicNumber) continue;
            
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
            
            if(dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
            {
                if(profit > 0)
                {
                    stats.winningTrades++;
                    stats.totalProfit += profit;
                }
                else if(profit < 0)
                {
                    stats.losingTrades++;
                    stats.totalLoss += MathAbs(profit);
                }
                stats.totalTrades++;
            }
        }
    }
    
    if(stats.totalTrades > 0)
        stats.winRate = (double)stats.winningTrades / stats.totalTrades * 100;
    
    if(stats.totalLoss > 0)
        stats.profitFactor = stats.totalProfit / stats.totalLoss;
}

void UpdateDashboard()
{
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double floatingPL = currentEquity - currentBalance;
    double totalPL = currentBalance - startingBalance;
    
    string dashboard = "\n╔═══════════ ADVANCED TRAILING EA v3.0 ═══════════╗\n";
    dashboard += StringFormat("║ Balance: %.2f | Equity: %.2f\n", currentBalance, currentEquity);
    dashboard += StringFormat("║ Floating P/L: %.2f | Total P/L: %.2f\n", floatingPL, totalPL);
    dashboard += StringFormat("║ Trailing Mode: %s\n", GetTrailingModeName());
    
    dashboard += "╠══════════════ POSITIONS ═════════════════════╣\n";
    
    // Pozíció információk
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == Symbol() && position.Magic() == MagicNumber)
            {
                double profitPips = 0;
                if(position.PositionType() == POSITION_TYPE_BUY)
                    profitPips = (position.PriceCurrent() - position.PriceOpen()) / GetPipValue();
                else
                    profitPips = (position.PriceOpen() - position.PriceCurrent()) / GetPipValue();
                
                string posType = (position.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                dashboard += StringFormat("║ %s: %.1f pips | P/L: %.2f\n", 
                                         posType, profitPips, position.Profit());
            }
        }
    }
    
    dashboard += "╠══════════════ STATISTICS ═══════════════════╣\n";
    dashboard += StringFormat("║ Total Trades: %d | Win Rate: %.1f%%\n", 
                              stats.totalTrades, stats.winRate);
    dashboard += StringFormat("║ Profit Factor: %.2f\n", stats.profitFactor);
    dashboard += StringFormat("║ Today's Trades: %d/%d\n", dailyTradeCount, MaxDailyTrades);
    
    dashboard += "╠══════════════ INDICATORS ═══════════════════╣\n";
    if(GetIndicatorValues())
    {
        dashboard += StringFormat("║ RSI: %.1f | MA Channel: %.5f-%.5f\n", 
                                 rsi_buffer[0], ma_low_buffer[0], ma_high_buffer[0]);
    }
    
    dashboard += "╚═══════════════════════════════════════════════╝\n";
    dashboard += "F1: Status | F2: Performance | F3: Close All\n";
    
    Comment(dashboard);
}

string GetTrailingModeName()
{
    switch(TrailingMode)
    {
        case TRAIL_NONE: return "None";
        case TRAIL_BASIC: return "Basic";
        case TRAIL_STEPPED: return "Stepped (4 Levels)";
        case TRAIL_DYNAMIC: return "Dynamic (ATR+RSI)";
        case TRAIL_AGGRESSIVE: return "Aggressive";
        default: return "Unknown";
    }
}

void WriteLog(string text)
{
   if(!EnableLogging)   // ha ki van kapcsolva a logolás, lépjünk ki
      return;

   string fileName = "EA_Log.txt";   // MQL5\\Files\\EA_Log.txt
   int handle = FileOpen(fileName, FILE_WRITE | FILE_READ | FILE_TXT);

   if(handle == INVALID_HANDLE)
   {
      Print("HIBA: Nem tudom megnyitni a log fájlt! Error: ", GetLastError());
      return;
   }

   // append mód: ugrás a fájl végére
   FileSeek(handle, 0, SEEK_END);

   string timeStr = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   FileWrite(handle, timeStr + " - " + text);
   FileClose(handle);
}


//+------------------------------------------------------------------+