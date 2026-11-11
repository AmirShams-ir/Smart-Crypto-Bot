from __future__ import annotations

import logging
from pathlib import Path


def get_logger(name: str = "data_provider") -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    Path("logs").mkdir(parents=True, exist_ok=True)
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler("logs/data-provider.log")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
    logger.addHandler(handler)
    return logger
