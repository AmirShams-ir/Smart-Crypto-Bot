import hashlib, time
class MemoryCache:
    """Bounded in-process TTL cache; no external service dependency."""
    def __init__(self, ttl_seconds=30, max_items=256):
        self.ttl_seconds=max(0,ttl_seconds); self.max_items=max_items; self._items={}
    @staticmethod
    def make_key(*parts): return hashlib.sha256("|".join(map(str,parts)).encode()).hexdigest()
    def get(self,key):
        item=self._items.get(key)
        if item is None:return None
        expires,value=item
        if expires<time.monotonic(): self._items.pop(key,None); return None
        return value.copy() if hasattr(value,"copy") else value
    def set(self,key,value):
        if not self.ttl_seconds:return
        if len(self._items)>=self.max_items:self._items.pop(next(iter(self._items)))
        self._items[key]=(time.monotonic()+self.ttl_seconds,value.copy() if hasattr(value,"copy") else value)
