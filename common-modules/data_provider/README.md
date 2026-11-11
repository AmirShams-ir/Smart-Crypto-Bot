# Data-Provider

Provider-agnostic OHLCV ingestion layer.

## Architecture
- `providers/base.py`: adapter contract. Implement `fetch_historical` and optionally `fetch_latest`.
- `providers/twelvedata.py`: TwelveData adapter (API key from `TWELVE_API_KEY`).
- `manager.py`: provider registry and factory.
- `client.py`: request throttling, retry/backoff, TTL cache, and public API.
- `pipeline.py`: UTC normalization, validation, duplicate/missing-candle detection, and persistence.
- `database.py`: writes to existing per-symbol SQLite candle databases.

## Usage
Run from the common-modules directory (same import convention as the existing project):

```python
from data_provider.manager import create_default_client
from data_provider.models import CandleRequest

client = create_default_client()
request = CandleRequest("BTC/USD", "1h", limit=500, exchange="Binance")
frame, report = client.fetch_historical(request)
latest, latest_report = client.fetch_latest(request)
print(report)
```

## Add another provider
Create a class extending `BaseProvider`, implement the two fetch methods (or use the base latest fallback), and register its factory in `ProviderManager`. The shared pipeline and database remain unchanged.

## Environment
- `DATA_PROVIDER=twelvedata`
- `TWELVE_API_KEY=...`
- `DEFAULT_EXCHANGE=Binance`
- `DATA_PROVIDER_RPM=55`
- `DATA_PROVIDER_MAX_RETRIES=4`
- `DATA_PROVIDER_BACKOFF_BASE=1`
- `DATA_PROVIDER_BACKOFF_MAX=30`
- `DATA_PROVIDER_CACHE_TTL=30`
