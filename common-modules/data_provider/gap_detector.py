from __future__ import annotations

import pandas as pd


_TIMEFRAME_SECONDS = {
    "1min": 60, "5min": 300, "15min": 900, "30min": 1800,
    "1h": 3600, "2h": 7200, "4h": 14400, "1day": 86400,
    "1week": 604800,
}


def detect_missing_candles(frame: pd.DataFrame, timeframe: str) -> list[pd.Timestamp]:
    """Return expected UTC candle openings absent between observed candles."""
    seconds = _TIMEFRAME_SECONDS.get(timeframe)
    if not seconds or frame.empty or len(frame) < 2:
        return []
    timestamps = pd.DatetimeIndex(frame["datetime"].sort_values().drop_duplicates())
    expected = pd.date_range(timestamps[0], timestamps[-1], freq=pd.Timedelta(seconds=seconds), tz="UTC")
    observed = set(timestamps)
    return [stamp for stamp in expected if stamp not in observed]
