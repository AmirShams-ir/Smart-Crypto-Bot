from .exceptions import CandleValidationError
def validate_candles(frame):
    if frame.empty: return frame
    data = frame.dropna(subset=["datetime","open","high","low","close","volume"]).copy()
    if data.empty: return data
    valid = ((data[["open","high","low","close"]] > 0).all(axis=1)
             & (data["volume"] >= 0)
             & (data["high"] >= data[["open","close","low"]].max(axis=1))
             & (data["low"] <= data[["open","close","high"]].min(axis=1)))
    if not valid.all(): raise CandleValidationError(f"{int((~valid).sum())} candle(s) failed OHLCV validation")
    return data
