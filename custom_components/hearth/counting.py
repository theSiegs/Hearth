"""Counting a person's screen time today, each minute once (see docs/home-assistant-integration.md, Counting).

Pure functions, no Home Assistant: a person's day is a set of devices, each seen by one or more sources. For one
device, each app's (or title's) time is the larger of what the sources say, never their sum; time a source can't put
on an app is that source's "rest", counted in the group the source says it is (games, for a Switch).
"""

from __future__ import annotations

from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field

ALL = "all"


@dataclass(frozen=True)
class Reading:
    """One source's view of one device, for one person, today: seconds in all, and per app or title."""

    source: str
    total_s: float
    items: Mapping[str, float] = field(default_factory=dict)
    # The group that time not put on an app belongs to (None: only All screen time)
    rest_group: str | None = None


@dataclass
class DeviceUsage:
    """A device's day, every source merged."""

    total_s: float = 0.0
    items: dict[str, float] = field(default_factory=dict)
    rest_s: float = 0.0
    rest_group: str | None = None
    # Each source's own total, for the breakdown
    sources: dict[str, float] = field(default_factory=dict)


def merge(readings: Iterable[Reading]) -> DeviceUsage:
    usage = DeviceUsage()
    best: Reading | None = None
    for reading in readings:
        usage.sources[reading.source] = max(usage.sources.get(reading.source, 0.0), reading.total_s)
        for item, seconds in reading.items.items():
            usage.items[item] = max(usage.items.get(item, 0.0), seconds)
        if best is None or reading.total_s > best.total_s:
            best = reading
    known = sum(usage.items.values())
    usage.total_s = max(best.total_s if best else 0.0, known)
    usage.rest_s = usage.total_s - known
    usage.rest_group = best.rest_group if best else None
    return usage


def group_seconds(
    devices: Mapping[str, DeviceUsage], groups_of: Callable[[str], set[str]]
) -> dict[str, float]:
    """Seconds per group across [devices]; [groups_of] says which groups an app or title is in (All is added)."""
    out: dict[str, float] = {ALL: 0.0}
    for usage in devices.values():
        out[ALL] += usage.total_s
        for item, seconds in usage.items.items():
            for group in groups_of(item) - {ALL}:
                out[group] = out.get(group, 0.0) + seconds
        if usage.rest_s > 0 and usage.rest_group and usage.rest_group != ALL:
            out[usage.rest_group] = out.get(usage.rest_group, 0.0) + usage.rest_s
    return out
