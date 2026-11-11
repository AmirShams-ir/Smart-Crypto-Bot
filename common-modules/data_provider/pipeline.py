from .database import save_candles
from .gap_detector import detect_missing_candles
from .logger import get_logger
from .normalizer import normalize_candles
from .validators import validate_candles
logger=get_logger()

class DataPipeline:
    def process(self,raw_frame,symbol,timeframe,*,persist=True):
        frame=normalize_candles(raw_frame)
        duplicates=int(frame["datetime"].duplicated(keep="last").sum()) if not frame.empty else 0
        if duplicates:
            logger.warning("%s %s: removed %d duplicate candle(s)",symbol,timeframe,duplicates)
            frame=frame.drop_duplicates(subset=["datetime"],keep="last")
        frame=validate_candles(frame)
        frame=frame.sort_values("datetime").reset_index(drop=True)
        gaps=detect_missing_candles(frame,timeframe)
        if gaps:logger.warning("%s %s: detected %d missing candle(s), first=%s",symbol,timeframe,len(gaps),gaps[0])
        saved=save_candles(frame,symbol,timeframe) if persist else 0
        return frame,{"saved":saved,"duplicates_removed":duplicates,"missing_candles":gaps}
