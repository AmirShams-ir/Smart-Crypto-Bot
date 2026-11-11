from __future__ import annotations

from sqlalchemy import text

from core.database import create_symbol_tables, get_engine


def save_candles(frame, symbol: str, timeframe: str) -> int:
    """Persist candles in the existing per-symbol SQLite database schema."""
    if frame is None or frame.empty:
        return 0
    create_symbol_tables(symbol)
    engine = get_engine(symbol)
    records = frame.to_dict(orient="records")
    sql = text("""
        INSERT OR REPLACE INTO candles
        (timeframe, datetime, open, high, low, close, volume)
        VALUES (:timeframe, :datetime, :open, :high, :low, :close, :volume)
    """)
    with engine.begin() as connection:
        connection.execute(sql, [
            {
                "timeframe": timeframe,
                "datetime": row["datetime"].isoformat(),
                "open": float(row["open"]),
                "high": float(row["high"]),
                "low": float(row["low"]),
                "close": float(row["close"]),
                "volume": float(row["volume"]),
            }
            for row in records
        ])
    return len(records)
