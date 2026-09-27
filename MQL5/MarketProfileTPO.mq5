#property copyright "keiwan"
#property link      "https://t.me/keiwan_k99"
#property version   "1.00"
#property description "Market Profile (TPO) — session-based TPO chart with value area, POC,"
#property description "initial balance, single prints, and daily volatility context."
#property description "Row size adapts automatically to crypto, forex, indices,"
#property description "metals, and commodities."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

enum ENUM_PROFILE_PERIOD
{
   PROFILE_DAILY,
   PROFILE_WEEKLY,
   PROFILE_MONTHLY
};

enum ENUM_TPO_STYLE
{
   TPO_STYLE_BAR,
   TPO_STYLE_LETTERS
};

input group "1. Session"
input string            CustomSession          = "1700-1659";
input int               CustomUtcOffsetMinutes = 0;
input int               ServerUtcOffsetMinutes = 120;

input group "2. Profile Calculation"
input ENUM_PROFILE_PERIOD ProfilePeriodType    = PROFILE_DAILY;
input int                 TpoPeriodMinutes     = 30;
input double              RowPriceUnits        = 50.0;
input double              ValueAreaPercent     = 70.0;

input group "3. Row Ticks"
input int               ForexRowTicks          = 10;
input int               IndicesRowTicks        = 500;
input int               MetalsRowTicks         = 200;
input int               CommoditiesRowTicks    = 5;
input int               DefaultRowTicks        = 10;

input group "4. Profile Display"
input ENUM_TPO_STYLE    ProfileStyle           = TPO_STYLE_BAR;
input int               WidthPerTpo            = 1;
input double            SinglePrintWidthScale  = 0.68;
input bool              ShowPocVaLines         = false;
input bool              ShowInitialBalance     = true;
input bool              ShowIbLabels           = false;
input int               IbOffsetBars           = 0;
input bool              ShowOpenMarker         = false;
input int               OpenOffsetBars         = 0;
input bool              ShowCloseMarker        = false;
input int               CloseOffsetBars        = 0;

input group "5. History & Table"
input int               MaxDaysHistory         = 7;
input bool              ShowTable              = true;
input int               MaxProfilesDrawn       = 30;
input int               TableRightMargin       = 6;
input int               TableTopMargin         = 20;
input int               TableWidth             = 230;

input group "6. Daily Volatility Context"
input int               VolatilitySampleSize   = 20;

input group "7. Diagnostics"
input bool              Verbose                = false;

#define NA                EMPTY_VALUE
#define PFX_ROOT          "MPTPO_"
#define PFX_FINAL         "MPTPO_F_"
#define PFX_LIVE          "MPTPO_L_"
#define PFX_TABLE         "MPTPO_T_"
#define TR_PROFILE        70
#define TR_VALUE_AREA     45
#define TR_POC            0
#define TR_SINGLE         30
#define TR_LETTER_BG      10
#define MAX_ROW_SPAN      400
#define MAX_ROW_FILL      500
#define TBL_ROW_H         16
#define TBL_ROWS          16
#define TBL_PAD_X         8

#define COL_PROFILE       clrGray
#define COL_VALUE_AREA    clrDodgerBlue
#define COL_POC           clrRed
#define COL_SINGLE        clrYellow
#define COL_SINGLE_BORDER clrWhite
#define COL_IB            clrOrange
#define COL_OPEN          clrLime
#define COL_OPEN_TEXT     clrWhite
#define COL_CLOSE         clrFuchsia
#define COL_CLOSE_TEXT    clrWhite

#define COL_TABLE_BG      C'23,42,74'
#define COL_TABLE_HDR     C'41,88,150'
#define COL_TABLE_ROW     C'38,38,38'
#define COL_TABLE_BORDER  C'60,60,60'
#define COL_TABLE_TEXT    clrWhite
#define COL_TABLE_TITLE   clrWhite
#define COL_HDR_PREV      C'41,88,150'
#define COL_HDR_TODAY     C'24,87,60'
#define COL_HDR_SINGLE    C'140,78,32'

double   g_rowHeight     = 0.0;
int      g_sessStartMin  = 0;
int      g_sessEndMin    = 0;
bool     g_useNewYork    = false;
int      g_fixedOffsetSec= 0;
int      g_barSec        = 60;
int      g_baseNext      = 0;
long     g_drawnIds[];

struct STimeInfo
{
   bool inSession;
   int  phase;
   long sessionDay;
   long anchorDay;
};

struct SProfileGrid
{
   bool   valid;
   int    n;
   double prices[];
   int    counts[];
   string letters[];
   int    pocIdx;
   int    vaLow;
   int    vaHigh;
   double poc;
   double vah;
   double val;
   int    topRun;
   int    bottomRun;
};

struct STableRow
{
   string name;
   string value;
   int    kind;
};

class CEngine;

bool BuildGrid(CEngine *e, SProfileGrid &g);
void RenderFinal(CEngine *e, SProfileGrid &g, datetime endTime);
STimeInfo ResolveTime(datetime serverTime);

bool IsNA(double v)
{
   return v == EMPTY_VALUE;
}

template<typename T>
void CopyArray(T &dst[], const T &src[])
{
   int n = ArraySize(src);
   ArrayResize(dst, n);
   for(int i = 0; i < n; i++)
      dst[i] = src[i];
}

void PushCapped(double &arr[], double value, int cap)
{
   if(cap <= 0)
      return;
   int size = ArraySize(arr);
   ArrayResize(arr, size + 1);
   arr[size] = value;
   size++;
   int excess = size - cap;
   if(excess <= 0)
      return;
   for(int i = 0; i < size - excess; i++)
      arr[i] = arr[i + excess];
   ArrayResize(arr, size - excess);
}

double ArrayAverage(double &arr[])
{
   int n = ArraySize(arr);
   if(n == 0)
      return NA;
   double sum = 0.0;
   for(int i = 0; i < n; i++)
      sum += arr[i];
   return sum / n;
}

string FormatPrice(double v)
{
   return IsNA(v) ? "-" : DoubleToString(v, _Digits);
}

string LetterFor(int idx)
{
   string letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
   int m = idx % 52;
   return StringSubstr(letters, m, 1);
}

datetime NthSundayOfMonth(int year, int month, int nth)
{
   MqlDateTime d;
   d.year = year;
   d.mon  = month;
   d.day  = 1;
   d.hour = 0;
   d.min  = 0;
   d.sec  = 0;
   datetime first = StructToTime(d);
   TimeToStruct(first, d);
   int offset = (7 - d.day_of_week) % 7;
   return first + (datetime)((offset + (nth - 1) * 7) * 86400);
}

bool IsUsDst(datetime utc)
{
   MqlDateTime d;
   TimeToStruct(utc, d);
   datetime dstStart = NthSundayOfMonth(d.year, 3, 2) + 7 * 3600;
   datetime dstEnd   = NthSundayOfMonth(d.year, 11, 1) + 6 * 3600;
   return utc >= dstStart && utc < dstEnd;
}

int LocalOffsetSeconds(datetime utc)
{
   if(g_useNewYork)
      return IsUsDst(utc) ? -4 * 3600 : -5 * 3600;
   return g_fixedOffsetSec;
}

bool InSessionWindow(int localMin)
{
   if(g_sessStartMin < g_sessEndMin)
      return localMin >= g_sessStartMin && localMin < g_sessEndMin;
   if(g_sessStartMin > g_sessEndMin)
      return localMin >= g_sessStartMin || localMin < g_sessEndMin;
   return true;
}

long AnchorDay(long sessionDay)
{
   if(ProfilePeriodType == PROFILE_WEEKLY)
   {
      int dow = (int)((sessionDay + 4) % 7);
      int daysFromMonday = (dow + 6) % 7;
      return sessionDay - daysFromMonday;
   }
   if(ProfilePeriodType == PROFILE_MONTHLY)
   {
      MqlDateTime d;
      TimeToStruct((datetime)(sessionDay * 86400), d);
      d.day  = 1;
      d.hour = 0;
      d.min  = 0;
      d.sec  = 0;
      return (long)StructToTime(d) / 86400;
   }
   return sessionDay;
}

STimeInfo ResolveTime(datetime serverTime)
{
   STimeInfo info;
   datetime utc   = serverTime - ServerUtcOffsetMinutes * 60;
   datetime local = utc + LocalOffsetSeconds(utc);
   long dayIndex  = (long)local / 86400;
   int  localMin  = (int)(((long)local % 86400) / 60);
   info.inSession = InSessionWindow(localMin);
   info.phase     = (localMin - g_sessStartMin + 1440) % 1440;
   info.sessionDay = dayIndex - (localMin < g_sessStartMin ? 1 : 0);
   info.anchorDay  = AnchorDay(info.sessionDay);
   return info;
}

bool IsKnownCryptoTicker(const string code)
{
   string s = code;
   StringToUpper(s);
   StringTrimLeft(s);
   StringTrimRight(s);

   if(s == "BTC")  return true;
   if(s == "XBT")  return true;
   if(s == "ETH")  return true;
   if(s == "LTC")  return true;
   if(s == "XRP")  return true;
   if(s == "BCH")  return true;
   if(s == "ADA")  return true;
   if(s == "SOL")  return true;
   if(s == "DOT")  return true;
   if(s == "DOGE") return true;
   if(s == "BNB")  return true;
   if(s == "LINK") return true;
   if(s == "AVAX") return true;
   if(s == "MATIC")return true;
   if(s == "TRX")  return true;
   if(s == "XLM")  return true;
   if(s == "ATOM") return true;
   if(s == "ETC")  return true;
   if(s == "FIL")  return true;
   if(s == "NEAR") return true;
   if(s == "ALGO") return true;
   if(s == "USDT") return true;
   if(s == "USDC") return true;
   if(s == "BUSD") return true;
   if(s == "TUSD") return true;
   if(s == "DAI")  return true;
   if(s == "SHIB") return true;
   if(s == "UNI")  return true;
   if(s == "AAVE") return true;
   if(s == "MKR")  return true;
   if(s == "XTZ")  return true;
   if(s == "EOS")  return true;
   if(s == "XMR")  return true;
   if(s == "ZEC")  return true;
   if(s == "DASH") return true;
   if(s == "HBAR") return true;
   if(s == "VET")  return true;
   if(s == "ICP")  return true;
   if(s == "APT")  return true;
   if(s == "ARB")  return true;
   if(s == "OP")   return true;
   if(s == "SUI")  return true;
   if(s == "PEPE") return true;
   if(s == "TON")  return true;
   if(s == "RNDR") return true;
   if(s == "INJ")  return true;

   return false;
}

bool TextContainsCryptoWord(string text)
{
   string s = text;
   StringToUpper(s);

   if(StringFind(s, "CRYPTO")        >= 0) return true;
   if(StringFind(s, "CRYPTOCURRENC") >= 0) return true;
   if(StringFind(s, "DIGITAL")       >= 0) return true;
   if(StringFind(s, "BITCOIN")       >= 0) return true;
   if(StringFind(s, "ETHEREUM")      >= 0) return true;
   if(StringFind(s, "LITECOIN")      >= 0) return true;
   if(StringFind(s, "RIPPLE")        >= 0) return true;
   if(StringFind(s, "DOGECOIN")      >= 0) return true;
   if(StringFind(s, "SOLANA")        >= 0) return true;
   if(StringFind(s, "CARDANO")       >= 0) return true;
   if(StringFind(s, "POLKADOT")      >= 0) return true;
   if(StringFind(s, "TETHER")        >= 0) return true;
   if(StringFind(s, "BINANCE")       >= 0) return true;
   if(StringFind(s, "COIN")          >= 0) return true;

   return false;
}

string StripBrokerSuffix(string sym)
{
   string s = sym;
   StringToUpper(s);

   int cut = StringLen(s);
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c == '.' || c == '_' || c == '-' || c == '+' || c == ' ')
      {
         cut = i;
         break;
      }
   }
   return StringSubstr(s, 0, cut);
}

bool SymbolNameContainsCryptoTicker(const string sym)
{
   string base = StripBrokerSuffix(sym);
   int n = StringLen(base);
   if(n < 3)
      return false;

   for(int i = 0; i <= n - 3; i++)
   {
      for(int len = 3; len <= 4; len++)
      {
         if(i + len > n)
            continue;
         string token = StringSubstr(base, i, len);
         if(!IsKnownCryptoTicker(token))
            continue;

         bool leftOk  = (i == 0);
         bool rightOk = (i + len == n);
         if(!leftOk)
         {
            ushort lc = StringGetCharacter(base, i - 1);
            if(lc < 'A' || lc > 'Z')
               leftOk = true;
         }
         if(!rightOk)
         {
            ushort rc = StringGetCharacter(base, i + len);
            if(rc < 'A' || rc > 'Z')
               rightOk = true;
         }
         if(leftOk && rightOk)
            return true;
      }
   }
   return false;
}

bool IsCryptoPair()
{
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   if(TextContainsCryptoWord(path))
      return true;

   string base   = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(IsKnownCryptoTicker(base))
      return true;
   if(IsKnownCryptoTicker(profit))
      return true;

   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   if(TextContainsCryptoWord(desc))
      return true;

   if(SymbolNameContainsCryptoTicker(_Symbol))
      return true;

   return false;
}

bool IsIndexSymbol()
{
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   string p = path;
   StringToUpper(p);

   if(StringFind(p, "INDEX")  >= 0) return true;
   if(StringFind(p, "INDICES")>= 0) return true;
   if(StringFind(p, "STOCK")  >= 0) return true;
   if(StringFind(p, "EQUITY") >= 0) return true;

   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   string d = desc;
   StringToUpper(d);

   if(StringFind(d, "INDEX")  >= 0) return true;
   if(StringFind(d, "INDICES")>= 0) return true;
   if(StringFind(d, "500")    >= 0) return true;
   if(StringFind(d, "100")    >= 0) return true;
   if(StringFind(d, "200")    >= 0) return true;
   if(StringFind(d, "DOW")    >= 0) return true;
   if(StringFind(d, "NASDAQ") >= 0) return true;
   if(StringFind(d, "DAX")    >= 0) return true;
   if(StringFind(d, "FTSE")   >= 0) return true;
   if(StringFind(d, "NIKKEI") >= 0) return true;

   string base = StripBrokerSuffix(_Symbol);
   if(StringFind(base, "US500") >= 0) return true;
   if(StringFind(base, "US100") >= 0) return true;
   if(StringFind(base, "US30")  >= 0) return true;
   if(StringFind(base, "NAS")   >= 0) return true;
   if(StringFind(base, "SPX")   >= 0) return true;
   if(StringFind(base, "NDX")   >= 0) return true;
   if(StringFind(base, "DJI")   >= 0) return true;
   if(StringFind(base, "DAX")   >= 0) return true;
   if(StringFind(base, "FTSE")  >= 0) return true;
   if(StringFind(base, "CAC")   >= 0) return true;
   if(StringFind(base, "NIK")   >= 0) return true;
   if(StringFind(base, "HK50")  >= 0) return true;
   if(StringFind(base, "GER40") >= 0) return true;
   if(StringFind(base, "UK100") >= 0) return true;
   if(StringFind(base, "JP225") >= 0) return true;

   return false;
}

bool IsMetalSymbol()
{
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   string p = path;
   StringToUpper(p);

   if(StringFind(p, "METAL") >= 0) return true;

   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   string d = desc;
   StringToUpper(d);

   if(StringFind(d, "GOLD")      >= 0) return true;
   if(StringFind(d, "SILVER")    >= 0) return true;
   if(StringFind(d, "PLATINUM")  >= 0) return true;
   if(StringFind(d, "PALLADIUM") >= 0) return true;
   if(StringFind(d, "METAL")     >= 0) return true;

   string base = StripBrokerSuffix(_Symbol);

   if(StringFind(base, "XAU")      >= 0) return true;
   if(StringFind(base, "XAG")      >= 0) return true;
   if(StringFind(base, "XPT")      >= 0) return true;
   if(StringFind(base, "XPD")      >= 0) return true;
   if(StringFind(base, "GOLD")     >= 0) return true;
   if(StringFind(base, "SILVER")   >= 0) return true;
   if(StringFind(base, "PLATINUM") >= 0) return true;
   if(StringFind(base, "PALLADIUM")>= 0) return true;

   return false;
}

bool IsCommoditySymbol()
{
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   string p = path;
   StringToUpper(p);

   if(StringFind(p, "COMMODIT") >= 0) return true;
   if(StringFind(p, "ENERGY")   >= 0) return true;
   if(StringFind(p, "OIL")      >= 0) return true;

   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   string d = desc;
   StringToUpper(d);

   if(StringFind(d, "OIL")         >= 0) return true;
   if(StringFind(d, "CRUDE")       >= 0) return true;
   if(StringFind(d, "BRENT")       >= 0) return true;
   if(StringFind(d, "WTI")         >= 0) return true;
   if(StringFind(d, "NATURAL GAS") >= 0) return true;
   if(StringFind(d, "GASOLINE")    >= 0) return true;
   if(StringFind(d, "COPPER")      >= 0) return true;
   if(StringFind(d, "COCOA")       >= 0) return true;
   if(StringFind(d, "COFFEE")      >= 0) return true;
   if(StringFind(d, "SUGAR")       >= 0) return true;
   if(StringFind(d, "WHEAT")       >= 0) return true;
   if(StringFind(d, "CORN")        >= 0) return true;
   if(StringFind(d, "SOYBEAN")     >= 0) return true;
   if(StringFind(d, "COMMODIT")    >= 0) return true;

   string base = StripBrokerSuffix(_Symbol);

   if(StringFind(base, "WTI")    >= 0) return true;
   if(StringFind(base, "BRENT")  >= 0) return true;
   if(StringFind(base, "USOIL")  >= 0) return true;
   if(StringFind(base, "UKOIL")  >= 0) return true;
   if(StringFind(base, "XTI")    >= 0) return true;
   if(StringFind(base, "XBR")    >= 0) return true;
   if(StringFind(base, "NGAS")   >= 0) return true;
   if(StringFind(base, "XNG")    >= 0) return true;
   if(StringFind(base, "COPPER") >= 0) return true;
   if(StringFind(base, "XCU")    >= 0) return true;
   if(StringFind(base, "COCOA")  >= 0) return true;
   if(StringFind(base, "COFFEE") >= 0) return true;
   if(StringFind(base, "SUGAR")  >= 0) return true;
   if(StringFind(base, "WHEAT")  >= 0) return true;
   if(StringFind(base, "CORN")   >= 0) return true;
   if(StringFind(base, "SOY")    >= 0) return true;

   return false;
}

string SymbolClassLabel()
{
   if(IsCryptoPair())        return "crypto";
   if(IsMetalSymbol())       return "metal";
   if(IsCommoditySymbol())   return "commodity";
   if(IsIndexSymbol())       return "index";

   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   string p = path;
   StringToUpper(p);
   if(StringFind(p, "FOREX") >= 0) return "forex";
   if(StringFind(p, "MAJOR") >= 0) return "forex";
   if(StringFind(p, "MINOR") >= 0) return "forex";

   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   string d = desc;
   StringToUpper(d);
   if(StringFind(d, "FOREX") >= 0) return "forex";

   return "default";
}

class CEngine
{
public:
   int      rowBase;
   int      rowCounts[];
   int      rowLastPeriod[];
   string   rowLetters[];
   datetime startTime;
   int      periodIndex;
   double   ibHigh;
   double   ibLow;
   double   sOpen;
   double   sClose;
   double   sHigh;
   double   sLow;
   double   prevIBHigh;
   double   prevIBLow;
   double   prevOpen;
   double   prevClose;
   double   prevHigh;
   double   prevLow;
   double   prevPOC;
   double   prevVAH;
   double   prevVAL;
   long     lastAnchor;
   bool     hasAnchor;
   double   dailyTR[];
   double   avgDailyTR;
   bool     hasVolDay;
   long     volDay;
   double   volHigh;
   double   volLow;
   double   volPrevClose;

            CEngine() { Reset(); }
   void     Reset();
   void     Assign(CEngine &src);
   void     ProcessBar(datetime t, double o, double h, double l, double c, double prevBarClose);

private:
   void     FinalizeProfile(datetime endTime);
   void     StartProfile(datetime t, double o);
   void     AccumulateSession(STimeInfo &ti, double h, double l, double c);
   void     TrackVolatility(bool inSess, STimeInfo &ti, double h, double l, double prevBarClose);
   void     EnsureRange(int lowRow, int highRow);
   void     AddRows(double l, double h);
};

void CEngine::Reset()
{
   rowBase = 0;
   ArrayResize(rowCounts, 0);
   ArrayResize(rowLastPeriod, 0);
   ArrayResize(rowLetters, 0);
   startTime   = 0;
   periodIndex = 0;
   ibHigh = NA;
   ibLow  = NA;
   sOpen  = NA;
   sClose = NA;
   sHigh  = NA;
   sLow   = NA;
   prevIBHigh = NA;
   prevIBLow  = NA;
   prevOpen   = NA;
   prevClose  = NA;
   prevHigh   = NA;
   prevLow    = NA;
   prevPOC    = NA;
   prevVAH    = NA;
   prevVAL    = NA;
   lastAnchor = 0;
   hasAnchor  = false;
   ArrayResize(dailyTR, 0);
   avgDailyTR   = NA;
   hasVolDay    = false;
   volDay       = 0;
   volHigh      = NA;
   volLow       = NA;
   volPrevClose = NA;
}

void CEngine::Assign(CEngine &src)
{
   rowBase = src.rowBase;
   CopyArray(rowCounts, src.rowCounts);
   CopyArray(rowLastPeriod, src.rowLastPeriod);
   CopyArray(rowLetters, src.rowLetters);
   startTime   = src.startTime;
   periodIndex = src.periodIndex;
   ibHigh = src.ibHigh;
   ibLow  = src.ibLow;
   sOpen  = src.sOpen;
   sClose = src.sClose;
   sHigh  = src.sHigh;
   sLow   = src.sLow;
   prevIBHigh = src.prevIBHigh;
   prevIBLow  = src.prevIBLow;
   prevOpen   = src.prevOpen;
   prevClose  = src.prevClose;
   prevHigh   = src.prevHigh;
   prevLow    = src.prevLow;
   prevPOC    = src.prevPOC;
   prevVAH    = src.prevVAH;
   prevVAL    = src.prevVAL;
   lastAnchor = src.lastAnchor;
   hasAnchor  = src.hasAnchor;
   CopyArray(dailyTR, src.dailyTR);
   avgDailyTR   = src.avgDailyTR;
   hasVolDay    = src.hasVolDay;
   volDay       = src.volDay;
   volHigh      = src.volHigh;
   volLow       = src.volLow;
   volPrevClose = src.volPrevClose;
}

void CEngine::ProcessBar(datetime t, double o, double h, double l, double c, double prevBarClose)
{
   STimeInfo ti = ResolveTime(t);
   bool inSess     = ti.inSession;
   bool newProfile = inSess && (!hasAnchor || ti.anchorDay != lastAnchor);
   bool endProfile = newProfile && hasAnchor;

   if(endProfile)
      FinalizeProfile(t);
   if(newProfile)
      StartProfile(t, o);
   if(inSess)
      AccumulateSession(ti, h, l, c);

   TrackVolatility(inSess, ti, h, l, prevBarClose);

   if(inSess)
      AddRows(l, h);

   if(inSess)
   {
      lastAnchor = ti.anchorDay;
      hasAnchor  = true;
   }
}

void CEngine::FinalizeProfile(datetime endTime)
{
   prevIBHigh = ibHigh;
   prevIBLow  = ibLow;
   prevOpen   = sOpen;
   prevClose  = sClose;
   prevHigh   = sHigh;
   prevLow    = sLow;

   if(ArraySize(rowCounts) == 0)
      return;

   SProfileGrid g;
   BuildGrid(GetPointer(this), g);
   prevPOC = g.valid ? g.poc : NA;
   prevVAH = g.valid ? g.vah : NA;
   prevVAL = g.valid ? g.val : NA;
   RenderFinal(GetPointer(this), g, endTime);
}

void CEngine::StartProfile(datetime t, double o)
{
   ArrayResize(rowCounts, 0);
   ArrayResize(rowLastPeriod, 0);
   ArrayResize(rowLetters, 0);
   rowBase     = 0;
   startTime   = t;
   periodIndex = 0;
   ibHigh = NA;
   ibLow  = NA;
   sOpen  = o;
   sHigh  = NA;
   sLow   = NA;
   sClose = NA;
}

void CEngine::AccumulateSession(STimeInfo &ti, double h, double l, double c)
{
   long daysFromStart = ti.sessionDay - ti.anchorDay;
   long profileMinute = daysFromStart * 1440 + ti.phase;
   periodIndex = (int)(profileMinute / TpoPeriodMinutes);

   sClose = c;
   sHigh  = IsNA(sHigh) ? h : MathMax(sHigh, h);
   sLow   = IsNA(sLow)  ? l : MathMin(sLow, l);

   if(periodIndex <= 1)
   {
      ibHigh = IsNA(ibHigh) ? h : MathMax(ibHigh, h);
      ibLow  = IsNA(ibLow)  ? l : MathMin(ibLow, l);
   }
}

void CEngine::TrackVolatility(bool inSess, STimeInfo &ti, double h, double l, double prevBarClose)
{
   if(!inSess)
      return;

   if(!hasVolDay)
   {
      hasVolDay = true;
      volDay    = ti.sessionDay;
      volHigh   = h;
      volLow    = l;
      return;
   }

   if(ti.sessionDay != volDay)
   {
      if(!IsNA(volHigh) && !IsNA(volLow))
      {
         double tr1 = volHigh - volLow;
         double tr2 = IsNA(volPrevClose) ? tr1 : MathAbs(volHigh - volPrevClose);
         double tr3 = IsNA(volPrevClose) ? tr1 : MathAbs(volLow - volPrevClose);
         double trueRange = MathMax(tr1, MathMax(tr2, tr3));
         PushCapped(dailyTR, trueRange, VolatilitySampleSize);
         avgDailyTR = ArrayAverage(dailyTR);
      }
      volPrevClose = prevBarClose;
      volDay  = ti.sessionDay;
      volHigh = h;
      volLow  = l;
      return;
   }

   volHigh = MathMax(volHigh, h);
   volLow  = MathMin(volLow, l);
}

void CEngine::EnsureRange(int lowRow, int highRow)
{
   int size = ArraySize(rowCounts);
   if(size == 0)
   {
      int newSize = highRow - lowRow + 1;
      rowBase = lowRow;
      ArrayResize(rowCounts, newSize);
      ArrayResize(rowLastPeriod, newSize);
      ArrayResize(rowLetters, newSize);
      for(int i = 0; i < newSize; i++)
      {
         rowCounts[i]     = 0;
         rowLastPeriod[i] = -1;
         rowLetters[i]    = "";
      }
      return;
   }

   if(lowRow < rowBase)
   {
      int add = rowBase - lowRow;
      ArrayResize(rowCounts, size + add);
      ArrayResize(rowLastPeriod, size + add);
      ArrayResize(rowLetters, size + add);
      for(int i = size - 1; i >= 0; i--)
      {
         rowCounts[i + add]     = rowCounts[i];
         rowLastPeriod[i + add] = rowLastPeriod[i];
         rowLetters[i + add]    = rowLetters[i];
      }
      for(int i = 0; i < add; i++)
      {
         rowCounts[i]     = 0;
         rowLastPeriod[i] = -1;
         rowLetters[i]    = "";
      }
      rowBase = lowRow;
      size += add;
   }

   int curHigh = rowBase + size - 1;
   if(highRow > curHigh)
   {
      int add = highRow - curHigh;
      ArrayResize(rowCounts, size + add);
      ArrayResize(rowLastPeriod, size + add);
      ArrayResize(rowLetters, size + add);
      for(int i = size; i < size + add; i++)
      {
         rowCounts[i]     = 0;
         rowLastPeriod[i] = -1;
         rowLetters[i]    = "";
      }
   }
}

void CEngine::AddRows(double l, double h)
{
   int lowRow  = (int)MathFloor(l / g_rowHeight);
   int highRow = (int)MathFloor(h / g_rowHeight);
   if(highRow - lowRow > MAX_ROW_FILL)
      highRow = lowRow + MAX_ROW_FILL;

   EnsureRange(lowRow, highRow);
   string letter = LetterFor(periodIndex);

   for(int r = lowRow; r <= highRow; r++)
   {
      int i = r - rowBase;
      if(rowLastPeriod[i] != periodIndex)
      {
         rowCounts[i]++;
         rowLastPeriod[i] = periodIndex;
         rowLetters[i]   += letter;
      }
   }
}

bool BuildGrid(CEngine *e, SProfileGrid &g)
{
   g.valid = false;
   g.n     = ArraySize(e.rowCounts);
   int n   = g.n;
   if(n == 0 || n > MAX_ROW_SPAN)
      return false;

   ArrayResize(g.prices, n);
   ArrayResize(g.counts, n);
   ArrayResize(g.letters, n);

   int maxCount = 0;
   int total    = 0;
   g.pocIdx     = 0;
   for(int i = 0; i < n; i++)
   {
      g.prices[i]  = (e.rowBase + i) * g_rowHeight;
      g.counts[i]  = e.rowCounts[i];
      g.letters[i] = e.rowLetters[i];
      total += g.counts[i];
      if(g.counts[i] > maxCount)
      {
         maxCount = g.counts[i];
         g.pocIdx = i;
      }
   }

   double vaTarget = total * ValueAreaPercent / 100.0;
   int vaLow  = g.pocIdx;
   int vaHigh = g.pocIdx;
   int vaSum  = g.counts[g.pocIdx];

   while(vaSum < vaTarget && (vaLow > 0 || vaHigh < n - 1))
   {
      int upCount   = vaHigh < n - 1 ? g.counts[vaHigh + 1] : -1;
      int downCount = vaLow > 0      ? g.counts[vaLow - 1]  : -1;
      if(upCount == -1 && downCount == -1)
         break;
      if(upCount >= downCount)
      {
         vaHigh++;
         vaSum += upCount;
      }
      else
      {
         vaLow--;
         vaSum += downCount;
      }
   }

   g.vaLow  = vaLow;
   g.vaHigh = vaHigh;
   g.poc    = g.prices[g.pocIdx] + g_rowHeight / 2.0;
   g.vah    = g.prices[vaHigh] + g_rowHeight;
   g.val    = g.prices[vaLow];

   int topRun = 0;
   int ti = n - 1;
   while(ti >= 0 && g.counts[ti] == 1)
   {
      topRun++;
      ti--;
   }

   int bottomRun = 0;
   int bi = 0;
   while(bi < n && g.counts[bi] == 1)
   {
      bottomRun++;
      bi++;
   }

   g.topRun    = topRun;
   g.bottomRun = bottomRun;
   g.valid     = true;
   return true;
}

void StyleObject(string name, bool back)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
}

void MakeRect(string name, datetime t1, double p1, datetime t2, double p2, color clr, bool fill, int width)
{
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   StyleObject(name, true);
}

void MakeTrend(string name, datetime t1, double p1, datetime t2, double p2, color clr, int width, ENUM_LINE_STYLE style)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   StyleObject(name, true);
}

void MakeText(string name, datetime t, double p, string text, color clr, ENUM_ANCHOR_POINT anchor, int fontSize)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   StyleObject(name, false);
}

color RowColor(bool single, bool isPoc, bool inVA)
{
   if(single)
      return COL_SINGLE;
   if(isPoc)
      return COL_POC;
   if(inVA)
      return COL_VALUE_AREA;
   return COL_PROFILE;
}

void DrawRows(string prefix, SProfileGrid &g, datetime leftTime, int &seq)
{
   bool useLetters = ProfileStyle == TPO_STYLE_LETTERS;

   for(int i = 0; i < g.n; i++)
   {
      int c = g.counts[i];
      if(c <= 0)
         continue;

      double top    = g.prices[i] + g_rowHeight;
      double bottom = g.prices[i];
      bool inVA     = i >= g.vaLow && i <= g.vaHigh;
      bool single   = c == 1;
      bool edgeSingle = single && (i >= g.n - g.topRun || i < g.bottomRun);
      bool isPoc    = i == g.pocIdx;
      color clr     = RowColor(single, isPoc, inVA);

      if(useLetters)
      {
         int lineWidth = isPoc ? 4 : 2;
         MakeTrend(prefix + IntegerToString(seq++), leftTime, bottom, leftTime, top, clr, lineWidth, STYLE_SOLID);
         MakeText(prefix + IntegerToString(seq++), leftTime, (top + bottom) / 2.0, g.letters[i], clrWhite, ANCHOR_LEFT, 7);
         continue;
      }

      int widthBars = edgeSingle ? (int)MathMax(1, MathRound(WidthPerTpo * SinglePrintWidthScale)) : c * WidthPerTpo;
      datetime rightTime = leftTime + widthBars * g_barSec;
      MakeRect(prefix + IntegerToString(seq++), leftTime, top, rightTime, bottom, clr, true, 1);
      if(edgeSingle)
         MakeRect(prefix + IntegerToString(seq++), leftTime, top, rightTime, bottom, COL_SINGLE_BORDER, false, 1);
   }
}

void DrawLevels(string prefix, SProfileGrid &g, datetime leftTime, datetime rightTime, int &seq)
{
   if(!ShowPocVaLines)
      return;

   MakeTrend(prefix + IntegerToString(seq++), leftTime, g.poc, rightTime, g.poc, COL_POC, 2, STYLE_SOLID);
   MakeTrend(prefix + IntegerToString(seq++), leftTime, g.vah, rightTime, g.vah, COL_VALUE_AREA, 1, STYLE_DASH);
   MakeTrend(prefix + IntegerToString(seq++), leftTime, g.val, rightTime, g.val, COL_VALUE_AREA, 1, STYLE_DASH);
}

void DrawMarkers(string prefix, CEngine *e, datetime leftTime, datetime rightTime, bool live, int &seq)
{
   double halfHeight = g_rowHeight * 0.4 * 0.65;

   if(ShowOpenMarker && !IsNA(e.sOpen))
   {
      datetime openX = leftTime + OpenOffsetBars * g_barSec;
      MakeRect(prefix + IntegerToString(seq++), openX - g_barSec, e.sOpen + halfHeight, openX + g_barSec, e.sOpen - halfHeight, COL_OPEN, true, 1);
   }

   if(ShowCloseMarker && !live && !IsNA(e.sClose))
   {
      datetime closeX = rightTime + CloseOffsetBars * g_barSec;
      MakeRect(prefix + IntegerToString(seq++), closeX - g_barSec, e.sClose + halfHeight, closeX + g_barSec, e.sClose - halfHeight, COL_CLOSE, true, 1);
   }
}

void DrawInitialBalance(string prefix, CEngine *e, datetime leftTime, int &seq)
{
   if(!ShowInitialBalance || IsNA(e.ibHigh) || IsNA(e.ibLow))
      return;

   datetime ibX = leftTime - IbOffsetBars * g_barSec;

   MakeTrend(prefix + IntegerToString(seq++), ibX, e.ibLow, ibX, e.ibHigh, COL_IB, 3, STYLE_SOLID);
   MakeTrend(prefix + IntegerToString(seq++), ibX - g_barSec, e.ibHigh, ibX + g_barSec, e.ibHigh, COL_IB, 2, STYLE_SOLID);
   MakeTrend(prefix + IntegerToString(seq++), ibX - g_barSec, e.ibLow, ibX + g_barSec, e.ibLow, COL_IB, 2, STYLE_SOLID);

   if(ShowIbLabels)
   {
      MakeText(prefix + IntegerToString(seq++), ibX, e.ibHigh, "IBH", COL_IB, ANCHOR_UPPER, 7);
      MakeText(prefix + IntegerToString(seq++), ibX, e.ibLow, "IBL", COL_IB, ANCHOR_LOWER, 7);
   }
}

void DrawProfile(string prefix, CEngine *e, SProfileGrid &g, datetime rightTime, bool live)
{
   int seq = 0;
   datetime leftTime = e.startTime;

   if(!g.valid)
   {
      string warning = "Market Profile: row height too small (" + IntegerToString(g.n) + " rows). Increase Row Height input.";
      MakeText(prefix + "warn", rightTime, e.sHigh, warning, clrRed, ANCHOR_LOWER, 8);
      return;
   }

   DrawRows(prefix, g, leftTime, seq);
   DrawLevels(prefix, g, leftTime, rightTime, seq);
   DrawMarkers(prefix, e, leftTime, rightTime, live, seq);
   DrawInitialBalance(prefix, e, leftTime, seq);
}

bool IsDrawn(long id)
{
   for(int i = 0; i < ArraySize(g_drawnIds); i++)
      if(g_drawnIds[i] == id)
         return true;
   return false;
}

void TrimDrawn()
{
   while(ArraySize(g_drawnIds) > MaxProfilesDrawn)
   {
      ObjectsDeleteAll(0, PFX_FINAL + IntegerToString(g_drawnIds[0]) + "_");
      int size = ArraySize(g_drawnIds);
      for(int i = 1; i < size; i++)
         g_drawnIds[i - 1] = g_drawnIds[i];
      ArrayResize(g_drawnIds, size - 1);
   }
}

void RenderFinal(CEngine *e, SProfileGrid &g, datetime endTime)
{
   long id = (long)e.startTime;
   if(IsDrawn(id))
      return;

   string prefix = PFX_FINAL + IntegerToString(id) + "_";
   DrawProfile(prefix, e, g, endTime, false);

   int size = ArraySize(g_drawnIds);
   ArrayResize(g_drawnIds, size + 1);
   g_drawnIds[size] = id;
}

color TableRowBg(int kind)
{
   switch(kind)
   {
      case 0: return COL_TABLE_BG;
      case 1: return COL_HDR_PREV;
      case 3: return COL_HDR_TODAY;
      case 5: return COL_HDR_SINGLE;
      default: return COL_TABLE_ROW;
   }
}

color TableRowText(int kind)
{
   return (kind == 0) ? COL_TABLE_TITLE : COL_TABLE_TEXT;
}

int TableXLeft()
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int x = chartW - TableWidth - TableRightMargin;
   if(x < 0)
      x = 0;
   return x;
}

void PutTablePanel()
{
   int xLeft = TableXLeft();

   string name = PFX_TABLE + "panel";
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xLeft);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, TableTopMargin);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, TableWidth);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, TBL_ROWS * TBL_ROW_H);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, COL_TABLE_BG);
   ObjectSetInteger(0, name, OBJPROP_COLOR, COL_TABLE_BORDER);
}

void PutTableRow(int index, string name, string value, int kind)
{
   color bg     = TableRowBg(kind);
   color fg     = TableRowText(kind);
   bool  header = (kind == 0 || kind == 1 || kind == 3 || kind == 5);

   int xLeft  = TableXLeft();
   int xRight = xLeft + TableWidth;
   int y      = TableTopMargin + index * TBL_ROW_H;

   string bgName = PFX_TABLE + "bg_" + IntegerToString(index);
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, xLeft);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, TableWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, TBL_ROW_H);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, COL_TABLE_BORDER);

   string nmName = PFX_TABLE + "nm_" + IntegerToString(index);
   if(ObjectFind(0, nmName) < 0)
   {
      ObjectCreate(0, nmName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nmName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, nmName, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nmName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nmName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nmName, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, nmName, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, nmName, OBJPROP_YDISTANCE, y + 2);
   ObjectSetString(0, nmName, OBJPROP_TEXT, name);

   if(header)
   {
      ObjectSetInteger(0, nmName, OBJPROP_ANCHOR, ANCHOR_UPPER);
      ObjectSetInteger(0, nmName, OBJPROP_XDISTANCE, xLeft + TableWidth / 2);
   }
   else
   {
      ObjectSetInteger(0, nmName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nmName, OBJPROP_XDISTANCE, xLeft + TBL_PAD_X);
   }

   string vlName = PFX_TABLE + "vl_" + IntegerToString(index);
   if(ObjectFind(0, vlName) < 0)
   {
      ObjectCreate(0, vlName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, vlName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, vlName, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, vlName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, vlName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, vlName, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, vlName, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, vlName, OBJPROP_YDISTANCE, y + 2);
   ObjectSetInteger(0, vlName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, vlName, OBJPROP_XDISTANCE, xRight - TBL_PAD_X);
   ObjectSetString(0, vlName, OBJPROP_TEXT, value);
}

void SetTableRow(STableRow &rows[], int i, string name, string value, int kind)
{
   rows[i].name  = name;
   rows[i].value = value;
   rows[i].kind  = kind;
}

void DrawTable(CEngine *e, int topRun, int bottomRun)
{
   STableRow rows[];
   ArrayResize(rows, TBL_ROWS);

   string profileLabel = ProfilePeriodType == PROFILE_DAILY ? "TODAY" : (ProfilePeriodType == PROFILE_WEEKLY ? "CURRENT WEEK" : "CURRENT MONTH");

   SetTableRow(rows, 0,  "TPO Profile Stats", "", 0);
   SetTableRow(rows, 1,  "PREVIOUS PROFILE", "", 1);
   SetTableRow(rows, 2,  "IB High", FormatPrice(e.prevIBHigh), 2);
   SetTableRow(rows, 3,  "IB Low",  FormatPrice(e.prevIBLow), 2);
   SetTableRow(rows, 4,  "Open",    FormatPrice(e.prevOpen), 2);
   SetTableRow(rows, 5,  "Close",   FormatPrice(e.prevClose), 2);
   SetTableRow(rows, 6,  "High",    FormatPrice(e.prevHigh), 2);
   SetTableRow(rows, 7,  "Low",     FormatPrice(e.prevLow), 2);
   SetTableRow(rows, 8,  profileLabel, "", 3);
   SetTableRow(rows, 9,  "IB High", FormatPrice(e.ibHigh), 4);
   SetTableRow(rows, 10, "IB Low",  FormatPrice(e.ibLow), 4);
   SetTableRow(rows, 11, "Open",    FormatPrice(e.sOpen), 4);
   SetTableRow(rows, 12, "SINGLE PRINTS (ACTIVE)", "", 5);
   SetTableRow(rows, 13, "Top of Range", IntegerToString(topRun), 6);
   SetTableRow(rows, 14, "Bottom of Range", IntegerToString(bottomRun), 6);
   SetTableRow(rows, 15, "Daily Volatility (avg TR)", FormatPrice(e.avgDailyTR) + " (n=" + IntegerToString(ArraySize(e.dailyTR)) + ")", 7);

   PutTablePanel();
   for(int i = 0; i < TBL_ROWS; i++)
      PutTableRow(i, rows[i].name, rows[i].value, rows[i].kind);
}

void RenderLive(CEngine *e, datetime lastTime)
{
   static datetime lastStart = 0;
   static int      lastRows  = -1;
   static int      lastTrN   = -1;

   int rows  = ArraySize(e.rowCounts);
   int trN   = ArraySize(e.dailyTR);

   if(e.startTime != lastStart || rows != lastRows || trN != lastTrN)
   {
      ObjectsDeleteAll(0, PFX_LIVE);
      lastStart = e.startTime;
      lastRows  = rows;
      lastTrN   = trN;
   }

   int topRun = 0;
   int bottomRun = 0;

   if(rows > 0)
   {
      SProfileGrid g;
      BuildGrid(e, g);
      DrawProfile(PFX_LIVE, e, g, lastTime, true);
      if(g.valid)
      {
         topRun    = g.topRun;
         bottomRun = g.bottomRun;
      }
   }

   if(ShowTable)
      DrawTable(e, topRun, bottomRun);

   ChartRedraw();
}

bool ParseSession(string session, int &startMin, int &endMin)
{
   if(StringLen(session) < 9)
      return false;
   int sh = (int)StringToInteger(StringSubstr(session, 0, 2));
   int sm = (int)StringToInteger(StringSubstr(session, 2, 2));
   int eh = (int)StringToInteger(StringSubstr(session, 5, 2));
   int em = (int)StringToInteger(StringSubstr(session, 7, 2));
   startMin = sh * 60 + sm;
   endMin   = eh * 60 + em;
   return true;
}

void ResetAll()
{
   ArrayResize(g_drawnIds, 0);
   g_base.Reset();
   g_work.Reset();
   g_baseNext = 0;
   ObjectsDeleteAll(0, PFX_ROOT);
}

int ResolveRowTicks()
{
   if(IsMetalSymbol())
      return MetalsRowTicks;

   if(IsCommoditySymbol())
      return CommoditiesRowTicks;

   if(IsIndexSymbol())
      return IndicesRowTicks;

   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   string p = path;
   StringToUpper(p);

   if(StringFind(p, "FOREX") >= 0)
      return ForexRowTicks;
   if(StringFind(p, "MAJOR") >= 0)
      return ForexRowTicks;
   if(StringFind(p, "MINOR") >= 0)
      return ForexRowTicks;

   string desc = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   string d = desc;
   StringToUpper(d);
   if(StringFind(d, "FOREX") >= 0)
      return ForexRowTicks;

   return DefaultRowTicks;
}

bool ValidateInputs()
{
   int startMin = 0;
   int endMin   = 0;
   if(!ParseSession(CustomSession, startMin, endMin))
   {
      Print("Market Profile (TPO): invalid CustomSession format — expected 'HHMM-HHMM'.");
      return false;
   }

   if(startMin < 0 || startMin > 1439 || endMin < 0 || endMin > 1439)
   {
      Print("Market Profile (TPO): CustomSession hours/minutes out of range.");
      return false;
   }

   if(TpoPeriodMinutes < 1 || TpoPeriodMinutes > 1440)
   {
      Print("Market Profile (TPO): TpoPeriodMinutes must be between 1 and 1440.");
      return false;
   }

   if(RowPriceUnits <= 0.0)
   {
      Print("Market Profile (TPO): RowPriceUnits must be > 0.");
      return false;
   }

   if(ForexRowTicks <= 0)
   {
      Print("Market Profile (TPO): ForexRowTicks must be > 0.");
      return false;
   }

   if(IndicesRowTicks <= 0)
   {
      Print("Market Profile (TPO): IndicesRowTicks must be > 0.");
      return false;
   }

   if(MetalsRowTicks <= 0)
   {
      Print("Market Profile (TPO): MetalsRowTicks must be > 0.");
      return false;
   }

   if(CommoditiesRowTicks <= 0)
   {
      Print("Market Profile (TPO): CommoditiesRowTicks must be > 0.");
      return false;
   }

   if(DefaultRowTicks <= 0)
   {
      Print("Market Profile (TPO): DefaultRowTicks must be > 0.");
      return false;
   }

   if(ValueAreaPercent < 1.0 || ValueAreaPercent > 100.0)
   {
      Print("Market Profile (TPO): ValueAreaPercent must be between 1 and 100.");
      return false;
   }

   if(MaxDaysHistory <= 0)
   {
      Print("Market Profile (TPO): MaxDaysHistory must be > 0.");
      return false;
   }

   if(MaxProfilesDrawn <= 0)
   {
      Print("Market Profile (TPO): MaxProfilesDrawn must be > 0.");
      return false;
   }

   if(VolatilitySampleSize <= 0)
   {
      Print("Market Profile (TPO): VolatilitySampleSize must be > 0.");
      return false;
   }

   if(TableWidth <= 0)
   {
      Print("Market Profile (TPO): TableWidth must be > 0.");
      return false;
   }

   return true;
}

int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   bool isCrypto = IsCryptoPair();
   int  rowTicks = ResolveRowTicks();
   string symClass = SymbolClassLabel();

   g_useNewYork     = false;
   g_fixedOffsetSec = CustomUtcOffsetMinutes * 60;

   if(!ParseSession(CustomSession, g_sessStartMin, g_sessEndMin))
      return INIT_PARAMETERS_INCORRECT;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = _Point;

   g_rowHeight = isCrypto ? RowPriceUnits : (rowTicks * tickSize);
   if(g_rowHeight <= 0.0)
   {
      Print("Market Profile (TPO): computed row height is invalid.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_barSec = PeriodSeconds();
   IndicatorSetString(INDICATOR_SHORTNAME, "Market Profile (TPO) v1.00");
   ObjectsDeleteAll(0, PFX_ROOT);
   ResetAll();

   if(Verbose)
   {
      Print("Market Profile (TPO) v1.00 loaded — symbol=", _Symbol,
            " class=", symClass,
            " crypto=", (isCrypto ? "yes" : "no"),
            " rowTicks=", (isCrypto ? 0 : rowTicks),
            " rowHeight=", DoubleToString(g_rowHeight, _Digits));
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX_ROOT);
   ArrayResize(g_drawnIds, 0);
   ChartRedraw();

   if(Verbose)
      Print("Market Profile (TPO) v1.00 removed from chart — symbol=", _Symbol, " reason=", reason);
}

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
   if(rates_total < 2)
      return 0;

   if(prev_calculated == 0)
      ResetAll();

   int lastClosed = rates_total - 2;
   int startIndex = g_baseNext;
   if(startIndex < 1)
      startIndex = 1;

   for(int i = startIndex; i <= lastClosed; i++)
      g_base.ProcessBar(time[i], open[i], high[i], low[i], close[i], close[i - 1]);
   g_baseNext = MathMax(g_baseNext, lastClosed + 1);

   int cur = rates_total - 1;
   g_work.Assign(g_base);
   g_work.ProcessBar(time[cur], open[cur], high[cur], low[cur], close[cur], close[cur - 1]);

   RenderLive(GetPointer(g_work), time[cur]);
   TrimDrawn();
   return rates_total;
}

CEngine g_base;
CEngine g_work;