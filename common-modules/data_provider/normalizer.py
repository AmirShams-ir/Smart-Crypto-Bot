import pandas as pd
CANDLE_COLUMNS = ["datetime","open","high","low","close","volume"]
def normalize_candles(frame: pd.DataFrame) -> pd.DataFrame:
    if frame is None or frame.empty: return pd.DataFrame(columns=CANDLE_COLUMNS)
    data = frame.copy()
    data.columns = [str(c).lower() for c in data.columns]
    if "datetime" not in data.columns:
        data = data.reset_index()
        data.columns = [str(c).lower() for c in data.columns]
        if "datetime" not in data.columns: data = data.rename(columns={data.columns[0]:"datetime"})
    missing = {"datetime","open","high","low","close"} - set(data.columns)
    if missing: raise ValueError(f"Missing candle columns: {', '.join(sorted(missing))}")
    if "volume" not in data.columns: data["volume"] = 0.0
    data["datetime"] = pd.to_datetime(data["datetime"], utc=True, errors="coerce")
    for col in ("open","high","low","close","volume"): data[col] = pd.to_numeric(data[col], errors="coerce")
    return data[CANDLE_COLUMNS].sort_values("datetime").reset_index(drop=True)
