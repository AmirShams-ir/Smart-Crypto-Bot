import os
from .client import DataProviderClient
from .exceptions import DataProviderError
from .providers.twelvedata import TwelveDataProvider

class ProviderManager:
    """Registry/factory. Register additional providers without altering the pipeline."""
    def __init__(self):
        self._factories={"twelvedata":lambda options:TwelveDataProvider(
            api_key=options.get("api_key") or os.getenv("TWELVE_API_KEY"),
            default_exchange=options.get("exchange","Binance"))}
    def register(self,name,factory):
        key=name.strip().lower()
        if not key:raise ValueError("provider name cannot be empty")
        self._factories[key]=factory
    def create(self,name="twelvedata",*,options=None,**client_options):
        key=name.strip().lower()
        if key not in self._factories:raise DataProviderError(f"Unknown data provider: {name}")
        return DataProviderClient(self._factories[key](options or {}),**client_options)

def create_default_client():
    return ProviderManager().create(os.getenv("DATA_PROVIDER","twelvedata"),
        options={"exchange":os.getenv("DEFAULT_EXCHANGE","Binance")})
