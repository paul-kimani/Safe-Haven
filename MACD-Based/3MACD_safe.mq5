//+------------------------------------------------------------------+
//|                                                   3MACD_SAFE.mq5 |
//|                    Safer rewrite of 3MACD - anti-blowup version  |
//+------------------------------------------------------------------+
#property copyright "Rewrite based on original 3MACD"
#property version   "2.0"
#property strict

#include <EAUtils.mqh>

input group "Indicator Parameters"
input int M1Fast = 5;
input int M1Slow = 8;
input int M2Fast = 13;
input int M2Slow = 21;
input int M3Fast = 34;
input int M3Slow = 144;

input group "General"
input double TPCoef = 1.5;              // more realistic for scalping
input ENUM_SL SLType = SL_SWING;
input int SLLookback = 7;
input int SLDev = 60;
input int BuffSize = 32;
input bool Reverse = true;

input group "Risk Management"
input double Risk = 0.5;                // percent risk if RISK_DEFAULT
input ENUM_RISK RiskMode = RISK_DEFAULT;
input bool IgnoreSL = false;            // enforced
input bool IgnoreTP = false;            // enforced
input bool Trail = true;
input double TrailingStopLevel = 25;    // trail later, not too early
input double EquityDrawdownLimit = 10;  // hard kill switch

input group "Strategy Control"
input bool Grid = false;                // disabled to stop account wipeout
input double GridVolMult = 1.0;
input double GridTrailingStopLevel = 0;
input int GridMaxLvl = 1;

input group "News"
input bool News = false;
input ENUM_NEWS_IMPORTANCE NewsImportance = NEWS_IMPORTANCE_MEDIUM;
input int NewsMinsBefore = 60;
input int NewsMinsAfter = 60;
input int NewsStartYear = 0;

input group "Open Position Limit"
input bool OpenNewPos = true;
input bool MultipleOpenPos = false;
input double MarginLimit = 300;
input int SpreadLimit = 25;             // safer default than disabled

input group "Auxiliary"
input int Slippage = 30;
input int TimerInterval = 15;
input ulong MagicNumber = 5001;
input ENUM_FILLING Filling = FILLING_DEFAULT;

GerEA ea;
datetime lastCandle = 0;
datetime tc = 0;

int M1_handle = INVALID_HANDLE;
int M2_handle = INVALID_HANDLE;
int M3_handle = INVALID_HANDLE;

double M1[];
double M2[];
double M3[];

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
bool LoadBuffers()
{
   if (CopyBuffer(M1_handle, 0, 0, BuffSize, M1) <= 0) return false;
   if (CopyBuffer(M2_handle, 0, 0, BuffSize, M2) <= 0) return false;
   if (CopyBuffer(M3_handle, 0, 0, BuffSize, M3) <= 0) return false;

   ArraySetAsSeries(M1, true);
   ArraySetAsSeries(M2, true);
   ArraySetAsSeries(M3, true);

   return true;
}

//+------------------------------------------------------------------+
//| Validate stop distance                                           |
//+------------------------------------------------------------------+
bool ValidBuyLevels(double entry, double sl, double tp)
{
   if (sl <= 0 || tp <= 0) return false;
   if (sl >= entry) return false;
   if (tp <= entry) return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) return false;

   double stopDistPts = (entry - sl) / point;
   if (stopDistPts < 20) return false; // reject unrealistically tight stops

   return true;
}

bool ValidSellLevels(double entry, double sl, double tp)
{
   if (sl <= 0 || tp <= 0) return false;
   if (sl <= entry) return false;
   if (tp >= entry) return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point <= 0) return false;

   double stopDistPts = (sl - entry) / point;
   if (stopDistPts < 20) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Buy pattern only                                                 |
//+------------------------------------------------------------------+
bool BuyPattern()
{
   if (BuffSize < 8) return false;

   if (M3[1] > 0 && M2[1] > 0 && M2[2] > 0 && M2[3] > 0 &&
       M2[1] > M2[2] && M2[2] < M2[3])
   {
      int j = 0, k = 0;

      for (int i = 2; i < BuffSize - 1; i++)
      {
         if (M3[i] <= 0 || M3[i + 1] <= 0) break;
         if (M2[i] <= 0 || M2[i + 1] <= 0) break;

         if (M1[i] < 0 && M1[i + 1] > 0)
         {
            j = i + 1;
            break;
         }
      }

      if (j == 0) return false;

      for (int i = j; i < BuffSize - 2; i++)
      {
         if (M3[i] <= 0 || M3[i + 1] <= 0 || M3[i + 2] <= 0) break;
         if (M2[i] <= 0 || M2[i + 1] <= 0 || M2[i + 2] <= 0) break;

         if (M2[i] < M2[i + 1] && M2[i + 1] > M2[i + 2])
         {
            k = i + 1;
            break;
         }
      }

      return (k != 0);
   }

   if (M3[1] > 0 && M3[2] > 0 && M3[3] > 0 &&
       M3[1] > M3[2] && M3[2] < M3[3])
   {
      int j = 0, k = 0, m = 0;

      for (int i = 2; i < BuffSize - 1; i++)
      {
         if (M3[i] <= 0 || M3[i + 1] <= 0) break;

         if (M2[i] < 0 && M2[i + 1] > 0)
         {
            j = i + 1;
            break;
         }
      }

      if (j == 0) return false;

      for (int i = j; i < BuffSize - 1; i++)
      {
         if (M3[i] <= 0 || M3[i + 1] <= 0) break;
         if (M2[i] <= 0 || M2[i + 1] <= 0) break;

         if (M1[i] < 0 && M1[i + 1] > 0)
         {
            k = i + 1;
            break;
         }
      }

      if (k == 0) return false;

      for (int i = k; i < BuffSize - 2; i++)
      {
         if (M3[i] <= 0 || M3[i + 1] <= 0 || M3[i + 2] <= 0) break;
         if (M2[i] <= 0 || M2[i + 1] <= 0 || M2[i + 2] <= 0) break;

         if (M2[i] < M2[i + 1] && M2[i + 1] > M2[i + 2])
         {
            m = i + 1;
            break;
         }
      }

      return (m != 0);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Sell pattern only                                                |
//+------------------------------------------------------------------+
bool SellPattern()
{
   if (BuffSize < 8) return false;

   if (M3[1] < 0 && M2[1] < 0 && M2[2] < 0 && M2[3] < 0 &&
       M2[1] < M2[2] && M2[2] > M2[3])
   {
      int j = 0, k = 0;

      for (int i = 2; i < BuffSize - 1; i++)
      {
         if (M3[i] >= 0 || M3[i + 1] >= 0) break;
         if (M2[i] >= 0 || M2[i + 1] >= 0) break;

         if (M1[i] > 0 && M1[i + 1] < 0)
         {
            j = i + 1;
            break;
         }
      }

      if (j == 0) return false;

      for (int i = j; i < BuffSize - 2; i++)
      {
         if (M3[i] >= 0 || M3[i + 1] >= 0 || M3[i + 2] >= 0) break;
         if (M2[i] >= 0 || M2[i + 1] >= 0 || M2[i + 2] >= 0) break;

         if (M2[i] > M2[i + 1] && M2[i + 1] < M2[i + 2])
         {
            k = i + 1;
            break;
         }
      }

      return (k != 0);
   }

   if (M3[1] < 0 && M3[2] < 0 && M3[3] < 0 &&
       M3[1] < M3[2] && M3[2] > M3[3])
   {
      int j = 0, k = 0, m = 0;

      for (int i = 2; i < BuffSize - 1; i++)
      {
         if (M3[i] >= 0 || M3[i + 1] >= 0) break;

         if (M2[i] > 0 && M2[i + 1] < 0)
         {
            j = i + 1;
            break;
         }
      }

      if (j == 0) return false;

      for (int i = j; i < BuffSize - 1; i++)
      {
         if (M3[i] >= 0 || M3[i + 1] >= 0) break;
         if (M2[i] >= 0 || M2[i + 1] >= 0) break;

         if (M1[i] > 0 && M1[i + 1] < 0)
         {
            k = i + 1;
            break;
         }
      }

      if (k == 0) return false;

      for (int i = k; i < BuffSize - 2; i++)
      {
         if (M3[i] >= 0 || M3[i + 1] >= 0 || M3[i + 2] >= 0) break;
         if (M2[i] >= 0 || M2[i + 1] >= 0 || M2[i + 2] >= 0) break;

         if (M2[i] > M2[i + 1] && M2[i + 1] < M2[i + 2])
         {
            m = i + 1;
            break;
         }
      }

      return (m != 0);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
bool OpenBuy()
{
   double entry = Ask();
   double sl = BuySL(SLType, SLLookback, entry, SLDev, 1);
   double tp = entry + TPCoef * MathAbs(entry - sl);

   if (!ValidBuyLevels(entry, sl, tp))
      return false;

   ea.BuyOpen(entry, sl, tp, false, false);
   return true;
}

bool OpenSell()
{
   double entry = Bid();
   double sl = SellSL(SLType, SLLookback, entry, SLDev, 1);
   double tp = entry - TPCoef * MathAbs(entry - sl);

   if (!ValidSellLevels(entry, sl, tp))
      return false;

   ea.SellOpen(entry, sl, tp, false, false);
   return true;
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   ea.Init();
   ea.SetMagic(MagicNumber);
   ea.risk = Risk * 0.01;
   ea.reverse = Reverse;
   ea.trailingStopLevel = TrailingStopLevel * 0.01;

   ea.grid = false;
   ea.gridVolMult = 1.0;
   ea.gridTrailingStopLevel = 0.0;
   ea.gridMaxLvl = 1;

   ea.equityDrawdownLimit = EquityDrawdownLimit * 0.01;
   ea.slippage = Slippage;
   ea.news = News;
   ea.newsImportance = NewsImportance;
   ea.newsMinsBefore = NewsMinsBefore;
   ea.newsMinsAfter = NewsMinsAfter;
   ea.filling = Filling;
   ea.riskMode = RiskMode;

   if (RiskMode == RISK_FIXED_VOL || RiskMode == RISK_MIN_AMOUNT)
      ea.risk = Risk;

   if (News)
      fetchCalendarFromYear(NewsStartYear);

   M1_handle = iMACD(NULL, 0, M1Fast, M1Slow, 1, PRICE_CLOSE);
   M2_handle = iMACD(NULL, 0, M2Fast, M2Slow, 1, PRICE_CLOSE);
   M3_handle = iMACD(NULL, 0, M3Fast, M3Slow, 1, PRICE_CLOSE);

   if (M1_handle == INVALID_HANDLE || M2_handle == INVALID_HANDLE || M3_handle == INVALID_HANDLE)
   {
      Print("MACD handle creation failed. Error = ", GetLastError());
      return INIT_FAILED;
   }

   EventSetTimer(TimerInterval);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if (M1_handle != INVALID_HANDLE) IndicatorRelease(M1_handle);
   if (M2_handle != INVALID_HANDLE) IndicatorRelease(M2_handle);
   if (M3_handle != INVALID_HANDLE) IndicatorRelease(M3_handle);
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime oldTc = tc;
   tc = TimeCurrent();
   if (tc == oldTc) return;

   if (Trail) ea.CheckForTrail();
   if (EquityDrawdownLimit > 0) ea.CheckForEquity();
}

//+------------------------------------------------------------------+
//| Tick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = Time(0);
   if (lastCandle == currentBar)
      return;

   lastCandle = currentBar;

   if (!OpenNewPos) return;
   if (!LoadBuffers()) return;

   if (SpreadLimit != -1 && Spread() > SpreadLimit) return;
   if (MarginLimit > 0 && PositionsTotal() > 0 &&
       AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < MarginLimit) return;

   if (!MultipleOpenPos && ea.OPTotal() > 0) return;

   if (BuyPattern())
   {
      if (OpenBuy()) return;
   }

   if (SellPattern())
   {
      OpenSell();
   }
}
