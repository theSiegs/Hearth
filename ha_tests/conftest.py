"""Tests for the Home Assistant integration (custom_components/hearth), with pytest-homeassistant-custom-component."""

from pathlib import Path
import sys

import pytest

# The repository root, so custom_components.hearth imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    yield
