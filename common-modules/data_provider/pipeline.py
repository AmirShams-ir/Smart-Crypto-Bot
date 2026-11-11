from __future__ import annotations

from .database import save_candles
from .gap_detector import detect_missing_candles
from .logger import get_logger
from .normalizer import normalize_candles
from .validators import validate_candles

logger = get_logger()


class DataPipeline:
    def __init__(self, cache=None):
        self.cache = cache

    def process(self, raw_frame, symbol: str, timeframe: str, *, persist: bool = True):
        frame = validate_candles(normalize_candles(raw_frame))
        # Duplicate timestamps are resolved deterministically: keep last provider row.
        duplicate_count = int(frame["datetime"].duplicated(keep="last").sum()) if not frame.empty else 0
        if duplicate_count:
            logger.warning("%s %s: removed %d duplicate candle(s)", symbol, timeframe, duplicate_count)
            frame = frame.drop_duplicates(subset=["datetime"], keep="last")
        frame = frame.sort_values("datetime").reset_index(drop=True)
        gaps = detect_missing_candles(frame, timeframe)
        if gaps:
            logger.warning("%s %s: detected %d missing candle(s); first=%s", symbol, timeframe, len(gaps), gaps[0])
        saved = save_candles(frame, symbol, timeframe) if persist else 0
        return frame, {"saved": saved, "duplicates_removed": duplicate_count, "missing_candles": gaps}
