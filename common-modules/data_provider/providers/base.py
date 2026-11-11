from __future__ import annotations

from abc import ABC, abstractmethod
import pandas as pd

from ..models import CandleRequest


class BaseProvider(ABC):
    """Provider adapters return a DataFrame using the shared candle schema."""

    name: str

    @abstractmethod
    def fetch_historical(self, request: CandleRequest) -> pd.DataFrame:
        raise NotImplementedError

    def fetch_latest(self, request: CandleRequest) -> pd.DataFrame:
        """Default latest implementation; adapters may override for native endpoints."""
        return self.fetch_historical(request)
