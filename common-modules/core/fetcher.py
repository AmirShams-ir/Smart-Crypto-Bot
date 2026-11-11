from __future__ import annotations
import argparse
from data_provider.config import (DEFAULT_PROVIDER,DEFAULT_EXCHANGE,FETCH_OUTPUTSIZE,REQUESTS_PER_MINUTE,
    MAX_RETRIES,BACKOFF_BASE_SECONDS,BACKOFF_MAX_SECONDS,CACHE_TTL_SECONDS)
from data_provider.manager import ProviderManager
from data_provider.models import CandleRequest
def _client():
    return ProviderManager().create(DEFAULT_PROVIDER,options={"exchange":DEFAULT_EXCHANGE},
        requests_per_minute=REQUESTS_PER_MINUTE,max_retries=MAX_RETRIES,
        backoff_base=BACKOFF_BASE_SECONDS,backoff_max=BACKOFF_MAX_SECONDS,cache_ttl=CACHE_TTL_SECONDS)
def fetch_timeframe(symbol: str,timeframe: str):
    return _client().fetch_historical(CandleRequest(symbol,timeframe,FETCH_OUTPUTSIZE,exchange=DEFAULT_EXCHANGE),persist=False)[0]
def save_candles(frame,symbol,timeframe):
    from data_provider.database import save_candles as persist
    return persist(frame,symbol,timeframe)
def collect_symbol(symbol,timeframes=None):
    from config import DEFAULT_TIMEFRAMES
    from core.database import create_symbol_tables
    selected=timeframes or DEFAULT_TIMEFRAMES; create_symbol_tables(symbol)
    print(f"[SYMBOL] {symbol}"); print(f"[DB] data/{symbol.replace('/','_')}.db")
    client=_client()
    for timeframe in selected:
        try:
            _,report=client.fetch_historical(CandleRequest(symbol,timeframe,FETCH_OUTPUTSIZE,exchange=DEFAULT_EXCHANGE),persist=True)
            print(f"[OK] {symbol} {timeframe}: {report['saved']} candles" if report["saved"] else f"[WARN] {symbol} {timeframe}: no data")
        except Exception as exc:print(f"[ERROR] {symbol} {timeframe}: {exc}")
def update_symbol_timeframe(symbol,timeframe):
    try:
        _,report=_client().fetch_latest(CandleRequest(symbol,timeframe,FETCH_OUTPUTSIZE,exchange=DEFAULT_EXCHANGE),persist=True)
        print(f"[UPDATE] {symbol} {timeframe}: {report['saved']} candles")
    except Exception as exc:print(f"[ERROR] {symbol} {timeframe}: {exc}")
def main():
    parser=argparse.ArgumentParser(description="Fetch market candle data")
    parser.add_argument("--symbol",required=True); parser.add_argument("--timeframe"); parser.add_argument("--bootstrap",action="store_true")
    args=parser.parse_args()
    if args.bootstrap or not args.timeframe:collect_symbol(args.symbol)
    else:update_symbol_timeframe(args.symbol,args.timeframe)
if __name__=="__main__":main()
