from __future__ import annotations

import os
import pandas as pd
from twelvedata import TDClient

from ..exceptions import AuthenticationError, ProviderResponseError
from ..models import CandleRequest
from .base import BaseProvider


class TwelveDataProvider(BaseProvider):
    name = "twelvedata"

    def __init__(self, api_key: str | None = None, default_exchange: str = "Binance"):
        self.api_key = api_key or os.getenv("TWELVE_API_KEY")
        if not self.api_key:
            raise AuthenticationError("TWELVE_API_KEY is not configured")
        self.client = TDClient(apikey=self.api_key)
        self.default_exchange = default_exchange

    def fetch_historical(self, request: CandleRequest) -> pd.DataFrame:
        return self._fetch(request)

    def fetch_latest(self, request: CandleRequest) -> pd.DataFrame:
        # TwelveData time_series provides the most recent series; limit keeps the
        # request bounded. Provider-specific latest endpoint can be substituted here.
        return self._fetch(request)

    def _fetch(self, request: CandleRequest) -> pd.DataFrame:
        params = {
            "symbol": request.symbol,
            "interval": request.timeframe,
            "outputsize": request.limit,
            "timezone": "UTC",
            "exchange": request.exchange or self.default_exchange,
        }
        if request.start:
            params["start_date"] = request.start.isoformat()
        if request.end:
            params["end_date"] = request.end.isoformat()
        try:
            series = self.client.time_series(**params)
            frame = series.as_pandas()
            if frame is None or frame.empty:
                return pd.DataFrame(columns=[
                    "datetime", "open", "high", "low", "close", "volume"
                ])
            frame = frame.reset_index()
            if "datetime" not in frame.columns:
                first = frame.columns[0]
                frame = frame.rename(columns={first: "datetime"})
            return frame
        except Exception as exc:
            message = str(exc).lower()
            if any(token in message for token in ("api key", "unauthorized", "invalid token", "401")):
                raise AuthenticationError(str(exc)) from exc
            if "rate" in message or "429" in message or "limit" in message:
                from ..exceptions import RateLimitError
                raise RateLimitError(str(exc)) from exc
            raise ProviderResponseError(f"TwelveData request failed: {exc}") from exc
