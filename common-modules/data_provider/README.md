# Data-Provider
Provider-agnostic OHLCV ingestion module.
* `providers/base.py`: adapter contract.
* `providers/twelvedata.py`: TwelveData adapter; reads `TWELVE_API_KEY`.
* `manager.py`: provider registry and factory.
* `client.py`: request throttling, retry/backoff and TTL cache.
* `pipeline.py`: UTC normalization, OHLCV validation, duplicate/gap detection and persistence.
* `database.py`: stores candles in the existing per-symbol SQLite database.

Run from `common-modules/`:
```python
from data_provider.manager import create_default_client
from data_provider.models import CandleRequest
client=create_default_client()
candles,report=client.fetch_historical(CandleRequest("BTC/USD","1h",500))
```
Add an adapter extending `BaseProvider` then register it with `ProviderManager.register`.
The shared pipeline and SQLite layer do not need modification.
