# Data-Provider
Provider-agnostic OHLCV ingestion module.

## Responsibilities
- Provider API authentication is isolated in each adapter.
- Shared request throttling and retry/backoff are in `client.py`.
- Historical and latest candle calls use one adapter contract.
- Provider timestamps normalize to UTC.
- OHLCV values and candle structure are validated.
- Duplicate timestamps are removed; missing expected candles are reported.
- Errors are written to `logs/data-provider.log`.
- Bounded process-local TTL cache avoids repeated API calls.
- Candles persist in the existing per-symbol SQLite files.

## Quick start (run from common-modules/)
```python
from data_provider.manager import create_default_client
from data_provider.models import CandleRequest
client = create_default_client()
candles, report = client.fetch_historical(CandleRequest("BTC/USD", "1h", 500))
latest, latest_report = client.fetch_latest(CandleRequest("BTC/USD", "1h", 100))
```

## Add a provider
Implement `BaseProvider.fetch_historical()` and optionally `fetch_latest()`.
Register a factory with `ProviderManager.register(name, factory)`. The shared
client, normalization, validation, cache and database do not need provider-specific
changes.

## Configuration
`DATA_PROVIDER=twelvedata`, `TWELVE_API_KEY`, `DEFAULT_EXCHANGE=Binance`,
`FETCH_OUTPUTSIZE=500`, `DATA_PROVIDER_RPM=55`,
`DATA_PROVIDER_MAX_RETRIES=4`, `DATA_PROVIDER_BACKOFF_BASE=1`,
`DATA_PROVIDER_BACKOFF_MAX=30`, `DATA_PROVIDER_CACHE_TTL=30`.
