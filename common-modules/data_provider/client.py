import time
from .cache import MemoryCache
from .exceptions import RateLimitError
from .logger import get_logger
from .pipeline import DataPipeline
logger=get_logger()

class DataProviderClient:
    """Shared rate limiter, retry/backoff, cache and OHLCV processing facade."""
    def __init__(self,provider,*,max_retries=4,backoff_base=1.0,backoff_max=30.0,
                 requests_per_minute=55,cache_ttl=30):
        self.provider=provider
        self.max_retries=max_retries
        self.backoff_base=backoff_base
        self.backoff_max=backoff_max
        self.min_interval=60.0/max(1,requests_per_minute)
        self._last_request=0.0
        self.cache=MemoryCache(cache_ttl)
        self.pipeline=DataPipeline()

    def _call(self,method,request):
        for attempt in range(self.max_retries+1):
            wait=self.min_interval-(time.monotonic()-self._last_request)
            if wait>0:time.sleep(wait)
            try:
                result=method(request)
                self._last_request=time.monotonic()
                return result
            except Exception as exc:
                self._last_request=time.monotonic()
                if attempt>=self.max_retries:
                    logger.exception("Provider %s request failed",self.provider.name)
                    raise
                delay=min(self.backoff_max,self.backoff_base*(2**attempt))
                logger.warning("Provider %s request error (%s); retry %d/%d in %.1fs",
                    self.provider.name,exc,attempt+1,self.max_retries,delay)
                time.sleep(delay)
        raise RuntimeError("unreachable retry state")

    def _fetch(self,kind,method,request,persist):
        key=self.cache.make_key(self.provider.name,kind,request)
        raw=self.cache.get(key)
        if raw is None:
            raw=self._call(method,request)
            self.cache.set(key,raw)
        return self.pipeline.process(raw,request.symbol,request.timeframe,persist=persist)

    def fetch_historical(self,request,*,persist=True):
        return self._fetch("historical",self.provider.fetch_historical,request,persist)
    def fetch_latest(self,request,*,persist=True):
        return self._fetch("latest",self.provider.fetch_latest,request,persist)
