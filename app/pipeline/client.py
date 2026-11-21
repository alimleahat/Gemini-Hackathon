"""Gemini API client factory.

Loads GEMINI_API_KEY from the repository root .env file without ever
hardcoding or committing secrets.
"""

import os
from functools import lru_cache
from dotenv import load_dotenv
from google import genai

from app.config import ENV_FILE


def _load_api_key() -> str:
    load_dotenv(ENV_FILE, override=False)
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError(
            f"Missing GEMINI_API_KEY. Please make sure {ENV_FILE} contains GEMINI_API_KEY=..."
        )
    return api_key


@lru_cache(maxsize=1)
def get_client() -> genai.Client:
    """Standard v1 client for Interactions API (gemini-4-neon, gemini-4-hydrogen)."""
    return genai.Client(api_key=_load_api_key())


@lru_cache(maxsize=1)
def get_beta_client() -> genai.Client:
    """v1beta client required for the Decisions API (gemini-decision-1)."""
    return genai.Client(
        api_key=_load_api_key(),
        http_options={"api_version": "v1beta"},
    )
