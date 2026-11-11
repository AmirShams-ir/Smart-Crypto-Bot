from __future__ import annotations

import time
from typing import Callable

from .cache import MemoryCache
from .exceptions import RateLimitError
from .logger import get_logger
from .models import CandleRequest
from .normalizer import normalize_candles
from .pipeline import DataPipeline

logger = get_logger()


class DataProviderClient:
    """Shared retry/rate-limit/cache/pipeline facade over a provider adapter."""

    def __init__(self, provider, *, max_retries: int = 4, backoff_base: float = 1.0,
                 backoff_max: float = 30.0, requests_per_minute: int = 60,
                 cache_ttl: int = 30):
        self.provider = provider
        self.max_retries = max_retries
        self.backoff_base = backoff_base
        self.backoff_max = backoff_max
        self.min_interval = 60.0 / max(1, requests_per_minute)
        self._last_request = 0.0
        self.cache = MemoryCache(cache_ttl)
        self.pipeline = DataPipeline(self.cache)

    def _call(self, method: Callable, request: CandleRequest):
        for attempt in range(self.max_retries + 1):
            elapsed = time.monotonic() - self._last_request
            if elapsed < self.min_interval:
                time.sleep(self.min_interval - elapsed)
            try:
                result = method(request)
                self._last_request = time.monotonic()
                return result
            except RateLimitError:
                self._last_request = time.monotonic()
                if attempt >= self.max_retries:
                    raise
                delay = min(self.backoff_max, self.backoff_base * (2 ** attempt))
                logger.warning("Rate limited by %s; retry %d/%d in %.1fs",
                               self.provider.name, attempt + 1, self.max_retries, delay)
                time.sleep(delay)
            except Exception:
                if attempt >= self.max_retries:
                    logger.exception("Provider %s request failed", self.provider.name)
                    raise
                delay = min(self.backoff_max, self.backoff_base * (2 ** attempt))
                logger.warning("Provider %s request error; retry %d/%d in %.1fs",
                               self.provider.name, attempt + 1, self.max_retries, delay)
                time.sleep(delay)
        raise RuntimeError("unreachable retry state")

    def fetch_historical(self, request: CandleRequest, *, persist: bool = True):
        key = self.cache.make_key(self.provider.name, "historical", request)
        raw = self.cache.get(key)
        if raw is None:
            raw = self._call(self.provider.fetch_historical, request)
            self.cache.set(key, raw)
        return self.pipeline.process(raw, request.symbol, request.timeframe, persist=persist)

    def fetch_latest(self, request: CandleRequest, *, persist: bool = True):
        key = self.cache.make_key(self.provider.name, "latest", request)
        raw = self.cache.get(key)
        if raw is None:
            raw = self._call(self.provider.fetch_latest, request)
            self.cache.set(key, raw)
        return self.pipeline.process(raw, request.symbol, request.timeframe, persist=persist)
