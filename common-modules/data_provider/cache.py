from __future__ import annotations

import hashlib
import time
from typing import Any


class MemoryCache:
    """Small bounded in-process TTL cache; no external service required."""

    def __init__(self, ttl_seconds: int = 30, max_items: int = 256):
        self.ttl_seconds = max(0, ttl_seconds)
        self.max_items = max_items
        self._items: dict[str, tuple[float, Any]] = {}

    @staticmethod
    def make_key(*parts: object) -> str:
        return hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()

    def get(self, key: str):
        item = self._items.get(key)
        if item is None:
            return None
        expires, value = item
        if expires < time.monotonic():
            self._items.pop(key, None)
            return None
        return value.copy() if hasattr(value, "copy") else value

    def set(self, key: str, value: Any) -> None:
        if self.ttl_seconds <= 0:
            return
        if len(self._items) >= self.max_items:
            self._items.pop(next(iter(self._items)))
        self._items[key] = (time.monotonic() + self.ttl_seconds, value.copy() if hasattr(value, "copy") else value)
