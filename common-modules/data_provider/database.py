from sqlalchemy import text
from core.database import create_symbol_tables, get_engine
def save_candles(frame,symbol: str,timeframe: str)->int:
    if frame is None or frame.empty:return 0
    create_symbol_tables(symbol); engine=get_engine(symbol)
    sql=text("""INSERT OR REPLACE INTO candles (timeframe,datetime,open,high,low,close,volume)
                VALUES (:timeframe,:datetime,:open,:high,:low,:close,:volume)""")
    rows=[{"timeframe":timeframe,"datetime":r["datetime"].isoformat(),"open":float(r["open"]),
           "high":float(r["high"]),"low":float(r["low"]),"close":float(r["close"]),"volume":float(r["volume"])}
          for r in frame.to_dict(orient="records")]
    with engine.begin() as connection: connection.execute(sql,rows)
    return len(rows)
