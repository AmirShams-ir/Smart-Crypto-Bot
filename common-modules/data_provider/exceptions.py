class DataProviderError(Exception):
    """Base exception for provider and pipeline errors."""


class AuthenticationError(DataProviderError):
    pass


class RateLimitError(DataProviderError):
    pass


class ProviderResponseError(DataProviderError):
    pass


class CandleValidationError(DataProviderError):
    pass
