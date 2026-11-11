from abc import ABC, abstractmethod
import pandas as pd
from ..models import CandleRequest
class BaseProvider(ABC):
    name: str
    @abstractmethod
    def fetch_historical(self, request: CandleRequest) -> pd.DataFrame: raise NotImplementedError
    def fetch_latest(self, request: CandleRequest) -> pd.DataFrame:
        return self.fetch_historical(request)
