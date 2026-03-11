//+------------------------------------------------------------------+
//|                                                    BiasLayer.mq5 |
//|                     Initial bias-layer visualizer for M1 / M5    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 2
#property indicator_buffers 2

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_label1  "Hybrid Bull"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_label2  "Hybrid Bear"

input int FastEMAPeriod = 20;
input int SlowEMAPeriod = 50;

input int LookbackBars = 12;
input int UpThreshold = 8;     // bullish if up-count >= this
input int DownThreshold = 4;   // bearish if up-count <= this

input bool ShowEMABias = true;
input bool ShowBinomialBias = true;
input bool ShowHybridArrows = true;

input int BullArrowOffsetPoints = 80;
input int BearArrowOffsetPoints = 80;

double BullBuffer[];
double BearBuffer[];

int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;

double fastEMA[];
double slowEMA[];

string labelName = "BIAS_LAYER_STATUS";

// Bias states
enum ENUM_BIAS_STATE
{
   BIAS_NEUTRAL = 0,
   BIAS_BULL    = 1,
   BIAS_BEAR    = -1
};

//+------------------------------------------------------------------+
//| Count directional dominance                                      |
//+------------------------------------------------------------------+
int GetUpCount(const double &closeArray[], const int shift, const int lookback)
{
   int upCount = 0;

   for(int j = shift; j < shift + lookback; j++)
   {
      // series arrays: lower index = more recent bar
      // compare current bar close to previous older bar close
      if(closeArray[j] > closeArray[j + 1])
         upCount++;
   }

   return upCount;
}

//+------------------------------------------------------------------+
//| EMA bias                                                         |
//+------------------------------------------------------------------+
int GetEMABias(const int i, const double &fast[], const double &slow[])
{
   if(i + 1 >= ArraySize(fast) || i + 1 >= ArraySize(slow))
      return BIAS_NEUTRAL;

   bool bull = (fast[i] > slow[i] && fast[i] > fast[i + 1]);
   bool bear = (fast[i] < slow[i] && fast[i] < fast[i + 1]);

   if(bull) return BIAS_BULL;
   if(bear) return BIAS_BEAR;
   return BIAS_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Binomial-style bias                                              |
//+------------------------------------------------------------------+
int GetBinomialBias(const int i, const double &closeArray[])
{
   if(i + LookbackBars + 1 >= ArraySize(closeArray))
      return BIAS_NEUTRAL;

   int upCount = GetUpCount(closeArray, i, LookbackBars);

   if(upCount >= UpThreshold)
      return BIAS_BULL;

   if(upCount <= DownThreshold)
      return BIAS_BEAR;

   return BIAS_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Hybrid bias                                                      |
//+------------------------------------------------------------------+
int GetHybridBias(const int emaBias, const int binBias)
{
   if(emaBias == BIAS_BULL && binBias == BIAS_BULL)
      return BIAS_BULL;

   if(emaBias == BIAS_BEAR && binBias == BIAS_BEAR)
      return BIAS_BEAR;

   return BIAS_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Build label text                                                 |
//+------------------------------------------------------------------+
string BiasToText(const int bias)
{
   if(bias == BIAS_BULL) return "BULLISH";
   if(bias == BIAS_BEAR) return "BEARISH";
   return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Label update                                                     |
//+------------------------------------------------------------------+
void UpdateStatusLabel(const int emaBias, const int binBias, const int hybridBias)
{
   string txt =
      "EMA Bias: " + BiasToText(emaBias) + "\n" +
      "Binomial Bias: " + BiasToText(binBias) + "\n" +
      "Hybrid Bias: " + BiasToText(hybridBias);

   if(ObjectFind(0, labelName) < 0)
   {
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 11);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
   }

   color c = clrSilver;
   if(hybridBias == BIAS_BULL) c = clrLime;
   if(hybridBias == BIAS_BEAR) c = clrTomato;

   ObjectSetString(0, labelName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, c);
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BullBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BearBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // down arrow

   ArraySetAsSeries(BullBuffer, true);
   ArraySetAsSeries(BearBuffer, true);
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);

   fastHandle = iMA(_Symbol, PERIOD_CURRENT, FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, SlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA handles. Error: ", GetLastError());
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "BiasLayer EMA+Binomial+Hybrid");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);

   ObjectDelete(0, labelName);
}

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < SlowEMAPeriod + LookbackBars + 5)
      return 0;

   if(CopyBuffer(fastHandle, 0, 0, rates_total, fastEMA) <= 0)
      return 0;

   if(CopyBuffer(slowHandle, 0, 0, rates_total, slowEMA) <= 0)
      return 0;

   int start = rates_total - prev_calculated;
   if(prev_calculated > 0)
      start += 2;

   if(start > rates_total - 2)
      start = rates_total - 2;

   for(int i = start; i >= 0; i--)
   {
      BullBuffer[i] = EMPTY_VALUE;
      BearBuffer[i] = EMPTY_VALUE;

      int emaBias = GetEMABias(i, fastEMA, slowEMA);
      int binBias = GetBinomialBias(i, close);
      int hybridBias = GetHybridBias(emaBias, binBias);

      if(ShowHybridArrows)
      {
         if(hybridBias == BIAS_BULL)
            BullBuffer[i] = low[i] - BullArrowOffsetPoints * _Point;
         else if(hybridBias == BIAS_BEAR)
            BearBuffer[i] = high[i] + BearArrowOffsetPoints * _Point;
      }
   }

   // current bar status
   int currEmaBias = GetEMABias(0, fastEMA, slowEMA);
   int currBinBias = GetBinomialBias(0, close);
   int currHybridBias = GetHybridBias(currEmaBias, currBinBias);

   UpdateStatusLabel(currEmaBias, currBinBias, currHybridBias);

   return rates_total;
}
