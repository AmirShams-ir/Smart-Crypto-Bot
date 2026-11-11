from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


@dataclass(frozen=True)
class CandleRequest:
    symbol: str
    timeframe: str
    limit: int = 500
    start: datetime | None = None
    end: datetime | None = None
    exchange: str | None = None

    def __post_init__(self) -> None:
        if not self.symbol.strip():
            raise ValueError("symbol cannot be empty")
        if not self.timeframe.strip():
            raise ValueError("timeframe cannot be empty")
        if self.limit < 1:
            raise ValueError("limit must be positive")
        if self.start and self.end and self.start >= self.end:
            raise ValueError("start must be earlier than end")


@dataclass
class ProviderConfig:
    name: str
    options: dict[str, Any] = field(default_factory=dict)
    api_key_env: str | None = None
    requests_per_minute: int = 60
    max_retries: int = 4
    backoff_base_seconds: float = 1.0
    backoff_max_seconds: float = 30.0
    cache_ttl_seconds: int = 30
