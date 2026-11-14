"""Tests for the Home Assistant integration (custom_components/hearth), with pytest-homeassistant-custom-component."""

from pathlib import Path
import sys

import pytest

# The repository root, so custom_components.hearth imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    yield


@pytest.fixture
def no_evening_hold(monkeypatch):
    """No evening cutoff (glance.hold_back holds a kid's suggestions from 21:00 to 6:00 when they have no bedtime), so
    a test that runs at night still sees them. Freezing the clock instead would stall Home Assistant's timers."""
    from custom_components.hearth import glance

    monkeypatch.setattr(glance, "CUTOFF_HOUR", 24)
    monkeypatch.setattr(glance, "MORNING_HOUR", 0)
    yield
