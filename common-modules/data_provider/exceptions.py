class DataProviderError(Exception): pass
class AuthenticationError(DataProviderError): pass
class RateLimitError(DataProviderError): pass
class ProviderResponseError(DataProviderError): pass
class CandleValidationError(DataProviderError): pass
