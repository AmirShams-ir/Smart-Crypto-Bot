from __future__ import annotations

import os

from .client import DataProviderClient
from .exceptions import DataProviderError
from .models import CandleRequest
from .providers.twelvedata import TwelveDataProvider


class ProviderManager:
    """Registry/factory for provider adapters."""

    def __init__(self):
        self._factories = {"twelvedata": self._create_twelvedata}

    @staticmethod
    def _create_twelvedata(options: dict):
        return TwelveDataProvider(
            api_key=options.get("api_key") or os.getenv("TWELVE_API_KEY"),
            default_exchange=options.get("exchange", "Binance"),
        )

    def register(self, name: str, factory) -> None:
        normalized = name.strip().lower()
        if not normalized:
            raise ValueError("provider name cannot be empty")
        self._factories[normalized] = factory

    def create(self, name: str = "twelvedata", *, options: dict | None = None, **client_options):
        key = name.strip().lower()
        if key not in self._factories:
            raise DataProviderError(f"Unknown data provider: {name}")
        adapter = self._factories[key](options or {})
        return DataProviderClient(adapter, **client_options)


def create_default_client():
    return ProviderManager().create(
        os.getenv("DATA_PROVIDER", "twelvedata"),
        options={"exchange": os.getenv("DEFAULT_EXCHANGE", "Binance")},
    )
