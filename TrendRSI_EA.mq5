//+------------------------------------------------------------------+
//|                    TrendRSI_EA.mq5                               |
//|         AI-Powered Trend + RSI Expert Advisor                    |
//|         Sends signals via WebRequest to your dashboard           |
//+------------------------------------------------------------------+
#property copyright "TrendRSI EA"
#property version   "2.00"
#property strict

//--- Input Parameters
input string   EA_Name          = "TrendRSI AI EA";
input int      RSI_Period       = 14;
input double   RSI_OversoldLevel= 30.0;      // Buy when RSI below this
input double   RSI_OverboughtLevel = 70.0;   // Sell when RSI above this
input int      MA_Fast_Period   = 20;         // Fast EMA for trend
input int      MA_Slow_Period   = 50;         // Slow EMA for trend
input int      ATR_Period       = 14;
input double   RiskPercent      = 1.5;        // Risk per trade (%)
input double   RR_Ratio         = 2.0;        // Risk:Reward ratio
input bool     EnableAlerts     = true;
input bool     EnableWebhook    = true;
input string   WebhookURL       = "https://your-dashboard.vercel.app/api/signal";
input string   WebhookSecret    = "YOUR_SECRET_KEY";
input bool     AutoTrade        = false;      // Set true to enable auto trading
input int      MagicNumber      = 20250503;

//--- Global Variables
int    rsiHandle, maFastHandle, maSlowHandle, atrHandle;
double rsiBuffer[], maFastBuffer[], maSlowBuffer[], atrBuffer[];
datetime lastSignalTime = 0;
string lastSignal = "";
int    signalCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   rsiHandle    = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   maFastHandle = iMA(_Symbol, PERIOD_CURRENT, MA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   maSlowHandle = iMA(_Symbol, PERIOD_CURRENT, MA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle    = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);

   if(rsiHandle==INVALID_HANDLE || maFastHandle==INVALID_HANDLE ||
      maSlowHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
   {
      Print("ERROR: Failed to initialize indicators!");
      return INIT_FAILED;
   }

   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(maFastBuffer, true);
   ArraySetAsSeries(maSlowBuffer, true);
   ArraySetAsSeries(atrBuffer, true);

   Print("=== ", EA_Name, " Initialized ===");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(Period()));
   Print("RSI Period: ", RSI_Period, " | Oversold: ", RSI_OversoldLevel);
   Print("Fast EMA: ", MA_Fast_Period, " | Slow EMA: ", MA_Slow_Period);
   Print("Auto Trade: ", AutoTrade ? "ENABLED" : "DISABLED (Signal Only Mode)");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(rsiHandle);
   IndicatorRelease(maFastHandle);
   IndicatorRelease(maSlowHandle);
   IndicatorRelease(atrHandle);
   Print(EA_Name, " deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Copy indicator data
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3) return;
   if(CopyBuffer(maFastHandle, 0, 0, 3, maFastBuffer) < 3) return;
   if(CopyBuffer(maSlowHandle, 0, 0, 3, maSlowBuffer) < 3) return;
   if(CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 3) return;

   double rsi     = rsiBuffer[1];    // Previous closed bar
   double maFast  = maFastBuffer[1];
   double maSlow  = maSlowBuffer[1];
   double atr     = atrBuffer[1];
   double price   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ---- Trend Detection ----
   bool bullishTrend = (maFast > maSlow) && (price > maFast);
   bool bearishTrend = (maFast < maSlow) && (price < maFast);

   // ---- Signal Logic ----
   string signal    = "HOLD";
   string reasoning = "";
   double strength  = 0;

   // BUY: Bullish trend + RSI oversold (dip buying)
   if(bullishTrend && rsi < RSI_OversoldLevel)
   {
      signal    = "BUY";
      reasoning = "Bullish trend (EMA" + MA_Fast_Period + " > EMA" + MA_Slow_Period + 
                  ") + RSI oversold (" + DoubleToString(rsi,1) + " < " + DoubleToString(RSI_OversoldLevel,0) + ")";
      strength  = NormalizeDouble((RSI_OversoldLevel - rsi) / RSI_OversoldLevel * 100, 1);
   }
   // SELL: Bearish trend + RSI overbought
   else if(bearishTrend && rsi > RSI_OverboughtLevel)
   {
      signal    = "SELL";
      reasoning = "Bearish trend (EMA" + MA_Fast_Period + " < EMA" + MA_Slow_Period + 
                  ") + RSI overbought (" + DoubleToString(rsi,1) + " > " + DoubleToString(RSI_OverboughtLevel,0) + ")";
      strength  = NormalizeDouble((rsi - RSI_OverboughtLevel) / (100 - RSI_OverboughtLevel) * 100, 1);
   }
   // EXIT LONG: RSI overbought while in bullish trend
   else if(bullishTrend && rsi > RSI_OverboughtLevel)
   {
      signal    = "EXIT_LONG";
      reasoning = "RSI reached overbought (" + DoubleToString(rsi,1) + ") — consider taking profit on longs";
      strength  = 50;
   }

   // Only process new signals (avoid repeating on every tick)
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(signal != "HOLD" && (signal != lastSignal || currentBar != lastSignalTime))
   {
      lastSignal     = signal;
      lastSignalTime = currentBar;
      signalCount++;

      // Calculate SL/TP
      double sl = 0, tp = 0, lots = 0;
      if(signal == "BUY")
      {
         sl   = price - (atr * 1.5);
         tp   = price + (atr * 1.5 * RR_Ratio);
         lots = CalculateLotSize(price - sl);
      }
      else if(signal == "SELL")
      {
         sl   = price + (atr * 1.5);
         tp   = price - (atr * 1.5 * RR_Ratio);
         lots = CalculateLotSize(sl - price);
      }

      // Log to console
      PrintSignal(signal, reasoning, rsi, maFast, maSlow, price, sl, tp, lots, strength);

      // Alert
      if(EnableAlerts)
         Alert(EA_Name, " | ", _Symbol, " | ", signal, " | RSI: ", DoubleToString(rsi,1), " | Price: ", DoubleToString(price,5));

      // Send to dashboard webhook
      if(EnableWebhook)
         SendWebhookSignal(signal, reasoning, rsi, maFast, maSlow, price, sl, tp, lots, strength);

      // Execute trade if AutoTrade enabled
      if(AutoTrade && (signal == "BUY" || signal == "SELL"))
         ExecuteTrade(signal, price, sl, tp, lots);
   }

   // Draw on-chart info panel
   DrawInfoPanel(rsi, maFast, maSlow, price, bullishTrend, bearishTrend, signal);
}

//+------------------------------------------------------------------+
void PrintSignal(string sig, string reason, double rsi, double maFast, double maSlow,
                 double price, double sl, double tp, double lots, double strength)
{
   Print("════════════════════════════════════════");
   Print("  🤖 ", EA_Name, " SIGNAL #", signalCount);
   Print("  Symbol  : ", _Symbol);
   Print("  Time    : ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   Print("  Signal  : *** ", sig, " ***");
   Print("  Reason  : ", reason);
   Print("  Strength: ", strength, "%");
   Print("  Price   : ", DoubleToString(price,5));
   Print("  RSI     : ", DoubleToString(rsi,2));
   Print("  EMA",MA_Fast_Period,"   : ", DoubleToString(maFast,5));
   Print("  EMA",MA_Slow_Period,"   : ", DoubleToString(maSlow,5));
   if(sig=="BUY" || sig=="SELL") {
      Print("  Lots    : ", DoubleToString(lots,2));
      Print("  SL      : ", DoubleToString(sl,5));
      Print("  TP      : ", DoubleToString(tp,5));
   }
   Print("════════════════════════════════════════");
}

//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount     = accountBalance * RiskPercent / 100.0;
   double tickValue      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep        = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue == 0 || tickSize == 0 || slPoints == 0) return minLot;

   double slTicks = slPoints / tickSize;
   double lots    = riskAmount / (slTicks * tickValue);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

//+------------------------------------------------------------------+
void ExecuteTrade(string sig, double price, double sl, double tp, double lots)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lots;
   req.magic     = MagicNumber;
   req.sl        = NormalizeDouble(sl, _Digits);
   req.tp        = NormalizeDouble(tp, _Digits);
   req.deviation = 10;
   req.comment   = EA_Name + " | " + sig;

   if(sig == "BUY") {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   } else {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }

   if(!OrderSend(req, res))
      Print("Trade FAILED: ", GetLastError(), " | Retcode: ", res.retcode);
   else
      Print("Trade EXECUTED: ", sig, " | Ticket: ", res.order, " | Lots: ", lots);
}

//+------------------------------------------------------------------+
void SendWebhookSignal(string sig, string reason, double rsi, double maFast, double maSlow,
                       double price, double sl, double tp, double lots, double strength)
{
   string json = "{";
   json += "\"secret\":\"" + WebhookSecret + "\",";
   json += "\"signal\":\"" + sig + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"timeframe\":\"" + EnumToString(Period()) + "\",";
   json += "\"price\":" + DoubleToString(price, 5) + ",";
   json += "\"rsi\":" + DoubleToString(rsi, 2) + ",";
   json += "\"ema_fast\":" + DoubleToString(maFast, 5) + ",";
   json += "\"ema_slow\":" + DoubleToString(maSlow, 5) + ",";
   json += "\"sl\":" + DoubleToString(sl, 5) + ",";
   json += "\"tp\":" + DoubleToString(tp, 5) + ",";
   json += "\"lots\":" + DoubleToString(lots, 2) + ",";
   json += "\"strength\":" + DoubleToString(strength, 1) + ",";
   json += "\"reason\":\"" + reason + "\",";
   json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\"";
   json += "}";

   char post[], result[];
   string resultHeaders;
   StringToCharArray(json, post, 0, StringLen(json));

   string headers = "Content-Type: application/json\r\nX-EA-Secret: " + WebhookSecret;
   int res = WebRequest("POST", WebhookURL, headers, 5000, post, result, resultHeaders);
   if(res == -1)
      Print("Webhook failed. Error: ", GetLastError(), ". Add URL to Tools > Options > Expert Advisors > Allowed URLs");
   else
      Print("Webhook sent: ", sig, " | HTTP: ", res);
}

//+------------------------------------------------------------------+
void DrawInfoPanel(double rsi, double maFast, double maSlow, double price,
                   bool bullish, bool bearish, string signal)
{
   string prefix = "TRSI_";
   color bgColor   = C'15,20,35';
   color textColor = clrWhite;
   color sigColor  = signal=="BUY" ? clrLime : (signal=="SELL" ? clrRed : clrGold);

   CreateLabel(prefix+"bg",    "▐█████████████████████████████████▌", 10, 30, bgColor, 10);
   CreateLabel(prefix+"title", "🤖 TrendRSI AI EA",                   15, 35, clrCyan, 9);
   CreateLabel(prefix+"sym",   "Symbol : " + _Symbol,                  15, 50, textColor, 8);
   CreateLabel(prefix+"tf",    "TF     : " + EnumToString(Period()),   15, 65, textColor, 8);
   CreateLabel(prefix+"price", "Price  : " + DoubleToString(price,5), 15, 80, textColor, 8);
   CreateLabel(prefix+"rsi",   "RSI    : " + DoubleToString(rsi,2),   15, 95, rsi<30?clrLime:(rsi>70?clrRed:textColor), 8);
   CreateLabel(prefix+"emaf",  "EMA"+MA_Fast_Period+"  : " + DoubleToString(maFast,5), 15, 110, textColor, 8);
   CreateLabel(prefix+"emas",  "EMA"+MA_Slow_Period+"  : " + DoubleToString(maSlow,5), 15, 125, textColor, 8);
   CreateLabel(prefix+"trend", "Trend  : " + (bullish?"▲ BULLISH":(bearish?"▼ BEARISH":"◆ NEUTRAL")), 15, 140,
               bullish?clrLime:(bearish?clrRed:clrGold), 8);
   CreateLabel(prefix+"sig",   "Signal : ► " + signal,                 15, 158, sigColor, 9);
   CreateLabel(prefix+"cnt",   "Signals: " + signalCount,              15, 175, clrSilver, 7);

   ChartRedraw();
}

//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
}
//+------------------------------------------------------------------+
