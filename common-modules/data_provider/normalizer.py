from __future__ import annotations

import pandas as pd

CANDLE_COLUMNS = ["datetime", "open", "high", "low", "close", "volume"]


def normalize_candles(frame: pd.DataFrame) -> pd.DataFrame:
    """Normalize provider output to UTC timestamps and numeric OHLCV."""
    if frame is None or frame.empty:
        return pd.DataFrame(columns=CANDLE_COLUMNS)
    data = frame.copy()
    if "datetime" not in data.columns:
        data = data.reset_index()
        if "datetime" not in data.columns:
            data = data.rename(columns={data.columns[0]: "datetime"})
    data.columns = [str(column).lower() for column in data.columns]
    missing = {"datetime", "open", "high", "low", "close"} - set(data.columns)
    if missing:
        raise ValueError(f"Missing candle columns: {', '.join(sorted(missing))}")
    if "volume" not in data.columns:
        data["volume"] = 0.0
    data["datetime"] = pd.to_datetime(data["datetime"], utc=True, errors="coerce")
    for column in ("open", "high", "low", "close", "volume"):
        data[column] = pd.to_numeric(data[column], errors="coerce")
    return data[CANDLE_COLUMNS].sort_values("datetime").reset_index(drop=True)
