# user_data/strategies/ProBTCStrategy.py
from freqtrade.strategy.interface import IStrategy
from freqtrade.strategy import IntParameter, DecimalParameter, CategoricalParameter
from pandas import DataFrame
import pandas as pd
import talib.abstract as ta
import numpy as np
from typing import Dict, Any


class ProBTCStrategy(IStrategy):
    """
    ProBTCStrategy
    - Designed for BTC/USDT on 5m timeframe (but can be tested on other pairs/timeframes)
    - Uses EMA, SMA, RSI, MACD, Bollinger Bands, ATR, Stochastic and a simple Fibonacci retracement
    - Contains hyperopt-able parameters (rsi thresholds, ema lengths, fib tolerance, atr stoploss, etc.)
    """

    # Basic config
    timeframe = "5m"
    startup_candle_count: int = 240

    # --- Risk management ---
    minimal_roi = {"0": 0.02, "30": 0.01, "120": 0.0}  # example ROI ladder (minutes)
    stoploss = -0.03
    trailing_stop = True
    trailing_stop_positive = 0.004
    trailing_stop_positive_offset = 0.01
    trailing_only_offset_is_reached = True

    # --- Hyperopt parameters ---
    ema_short = IntParameter(8, 21, default=12, space="buy")
    ema_long = IntParameter(34, 200, default=50, space="buy")

    rsi_buy = IntParameter(14, 45, default=32, space="buy")
    rsi_sell = IntParameter(50, 85, default=70, space="sell")

    bb_window = IntParameter(14, 30, default=20, space="buy")
    bb_dev = DecimalParameter(1.5, 3.5, default=2.0, space="buy")

    macd_fast = IntParameter(8, 16, default=12, space="buy")
    macd_slow = IntParameter(20, 40, default=26, space="buy")
    macd_signal = IntParameter(6, 12, default=9, space="buy")

    atr_stop_mult = DecimalParameter(1.0, 4.0, default=2.0, space="sell")
    fib_tol = DecimalParameter(0.002, 0.02, default=0.008, space="buy")  # tolerance relative to level

    stochastic_k = IntParameter(5, 21, default=14, space="buy")
    stochastic_d = IntParameter(3, 7, default=3, space="buy")

    use_fib = CategoricalParameter([True, False], default=True, space="buy")

    # Informative: max lookback to compute swing high/low for fib (in candles)
    fib_lookback = 120  # 120 * 5m = 10 hours

    def informative_pairs(self):
        # no external informative pairs needed for this strategy
        return []

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # --- Moving averages ---
        dataframe["ema_short"] = ta.EMA(dataframe, timeperiod=int(self.ema_short.value))
        dataframe["ema_long"] = ta.EMA(dataframe, timeperiod=int(self.ema_long.value))
        dataframe["sma200"] = ta.SMA(dataframe, timeperiod=200)

        # --- RSI ---
        dataframe["rsi"] = ta.RSI(dataframe, timeperiod=14)

        # --- MACD ---
        macd = ta.MACD(
            dataframe,
            fastperiod=int(self.macd_fast.value),
            slowperiod=int(self.macd_slow.value),
            signalperiod=int(self.macd_signal.value),
        )
        dataframe["macd"] = macd["macd"]
        dataframe["macd_signal"] = macd["macdsignal"]
        dataframe["macd_hist"] = macd["macdhist"]

        # --- Bollinger Bands ---
        bb_mid = ta.SMA(dataframe, timeperiod=int(self.bb_window.value))
        bb_std = dataframe["close"].rolling(int(self.bb_window.value)).std()
        dataframe["bb_upper"] = bb_mid + (bb_std * float(self.bb_dev.value))
        dataframe["bb_lower"] = bb_mid - (bb_std * float(self.bb_dev.value))
        dataframe["bb_mid"] = bb_mid

        # --- ATR for volatility-based sizing / stops ---
        dataframe["atr"] = ta.ATR(dataframe, timeperiod=14)

        # --- Stochastic ---
        stoch = ta.STOCH(
            dataframe,
            fastk_period=int(self.stochastic_k.value),
            slowk_period=3,
            slowk_matype=0,
            slowd_period=int(self.stochastic_d.value),
            slowd_matype=0,
        )
        dataframe["stoch_k"] = stoch["slowk"]
        dataframe["stoch_d"] = stoch["slowd"]

        # --- Fibonacci levels (simple swing high/low) ---
        # compute rolling high/low over lookback window to find recent swing high/low
        lb = int(self.fib_lookback)
        if len(dataframe) >= lb:
            # use rolling max/min on highs/lows
            dataframe["swing_high"] = dataframe["high"].rolling(window=lb, min_periods=1).max()
            dataframe["swing_low"] = dataframe["low"].rolling(window=lb, min_periods=1).min()
            # compute fib levels
            range_ = dataframe["swing_high"] - dataframe["swing_low"]
            dataframe["fib_382"] = dataframe["swing_high"] - range_ * 0.382
            dataframe["fib_50"] = dataframe["swing_high"] - range_ * 0.5
            dataframe["fib_618"] = dataframe["swing_high"] - range_ * 0.618
        else:
            dataframe["swing_high"] = np.nan
            dataframe["swing_low"] = np.nan
            dataframe["fib_382"] = np.nan
            dataframe["fib_50"] = np.nan
            dataframe["fib_618"] = np.nan

        # Fill NA safely
        dataframe.fillna(method="ffill", inplace=True)
        dataframe.fillna(method="bfill", inplace=True)
        dataframe.fillna(0, inplace=True)

        return dataframe

    def _price_near_level(self, price: float, level: float, tol: float) -> bool:
        if level is None or level == 0 or np.isnan(level):
            return False
        return abs(price - level) / level <= tol

    def populate_buy_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        """
        Buy conditions (conservative multi-confirmation):
        1) Trend confirmation: EMA short above EMA long (golden cross or recent crossover)
        2) Momentum: RSI below rsi_buy (oversold on pullback) and stochastic K < D
        3) Volatility/confirmation: price above bb_mid and volume positive (implicit)
        4) MACD hist turning positive (momentum shift)
        5) Optional: price near Fibonacci retracement levels (if use_fib=True)
        """
        df = dataframe.copy()
        tol = float(self.fib_tol.value)
        use_fib_flag = bool(self.use_fib.value)

        buy_cond = (
            (df["ema_short"] > df["ema_long"])  # trend
            & (df["rsi"] < int(self.rsi_buy.value))  # RSI oversold threshold for buys (pullback)
            & (df["stoch_k"] < df["stoch_d"])  # stochastic momentum
            & (df["macd_hist"] > 0)  # MACD histogram positive
            & (df["close"] > df["bb_mid"])  # price above middle BB (confirming trend)
        )

        # Fibonacci proximity check (any of 3 levels)
        if use_fib_flag:
            fib_check = (
                df.apply(
                    lambda row: (
                        self._price_near_level(row["close"], row["fib_382"], tol)
                        or self._price_near_level(row["close"], row["fib_50"], tol)
                        or self._price_near_level(row["close"], row["fib_618"], tol)
                    ),
                    axis=1,
                )
            )
            buy_cond = buy_cond & fib_check

        dataframe.loc[buy_cond, "buy"] = 1
        return dataframe

    def populate_sell_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        """
        Sell conditions:
        1) RSI above rsi_sell (overbought)
        2) EMA short crosses below EMA long (trend weakening)
        3) Price hits upper Bollinger Band (possible exhaustion)
        4) ATR-based stoploss handled separately by stoploss config / trailing stop
        """
        df = dataframe.copy()

        sell_cond = (
            (df["rsi"] > int(self.rsi_sell.value))
            | (df["ema_short"] < df["ema_long"])
            | (df["close"] >= df["bb_upper"])
        )

        dataframe.loc[sell_cond, "sell"] = 1
        return dataframe

    # Optional: custom stoploss based on ATR (uncomment if you want dynamic stoploss)
    # def custom_stoploss(self, pair: str, trade: "Trade", current_time: datetime, current_rate: float,
    #                     current_profit: float, **kwargs) -> float:
    #     # If in profit, use default stoploss behavior (handled by trailing). Otherwise use ATR-based SL.
    #     try:
    #         atr = trade.open_rate  # placeholder: get ATR from dataframe if needed
    #     except Exception:
    #         return self.stoploss
    #     return self.stoploss

    ####################################################################
    # Notes:
    # - This strategy is opinionated and conservative: it tries to confirm trend + momentum + fib pullback
    # - Tweak parameters using hyperopt (ema lengths, rsi thresholds, fib_tol, use_fib)
    # - Keep an eye on position sizing, exchange fees and slippage. Run long backtests and walk-forward tests before real money.
    ####################################################################
