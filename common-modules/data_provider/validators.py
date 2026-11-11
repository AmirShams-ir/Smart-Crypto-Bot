from __future__ import annotations

import pandas as pd

from .exceptions import CandleValidationError


def validate_candles(frame: pd.DataFrame) -> pd.DataFrame:
    """Drop malformed rows and reject impossible OHLC relationships."""
    if frame.empty:
        return frame
    data = frame.copy()
    required = ["datetime", "open", "high", "low", "close", "volume"]
    data = data.dropna(subset=required)
    if data.empty:
        return data
    positive = (data[["open", "high", "low", "close"]] > 0).all(axis=1)
    volume_ok = data["volume"] >= 0
    bounds_ok = (
        (data["high"] >= data[["open", "close", "low"]].max(axis=1))
        & (data["low"] <= data[["open", "close", "high"]].min(axis=1))
    )
    valid = positive & volume_ok & bounds_ok
    invalid_count = int((~valid).sum())
    if invalid_count:
        raise CandleValidationError(f"{invalid_count} candle(s) failed OHLCV validation")
    return data
