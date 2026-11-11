from __future__ import annotations
import os
import pandas as pd
from twelvedata import TDClient
from ..exceptions import AuthenticationError, ProviderResponseError, RateLimitError
from ..models import CandleRequest
from .base import BaseProvider
class TwelveDataProvider(BaseProvider):
    name = "twelvedata"
    def __init__(self, api_key: str | None = None, default_exchange: str = "Binance"):
        self.api_key = api_key or os.getenv("TWELVE_API_KEY")
        if not self.api_key: raise AuthenticationError("TWELVE_API_KEY is not configured")
        self.client = TDClient(apikey=self.api_key)
        self.default_exchange = default_exchange
    def fetch_historical(self, request: CandleRequest) -> pd.DataFrame: return self._fetch(request)
    def fetch_latest(self, request: CandleRequest) -> pd.DataFrame: return self._fetch(request)
    def _fetch(self, request: CandleRequest) -> pd.DataFrame:
        params = dict(symbol=request.symbol, interval=request.timeframe, outputsize=request.limit,
                      timezone="UTC", exchange=request.exchange or self.default_exchange)
        if request.start: params["start_date"] = request.start.isoformat()
        if request.end: params["end_date"] = request.end.isoformat()
        try:
            result = self.client.time_series(**params).as_pandas()
            if result is None or result.empty: return pd.DataFrame(columns=["datetime","open","high","low","close","volume"])
            result = result.reset_index()
            if "datetime" not in result.columns: result = result.rename(columns={result.columns[0]:"datetime"})
            return result
        except Exception as exc:
            message = str(exc).lower()
            if any(w in message for w in ("api key","unauthorized","invalid token","401")): raise AuthenticationError(str(exc)) from exc
            if any(w in message for w in ("rate","429","limit")): raise RateLimitError(str(exc)) from exc
            raise ProviderResponseError(f"TwelveData request failed: {exc}") from exc
