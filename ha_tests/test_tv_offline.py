"""What a TV is told for a stretch without Home Assistant (docs/contracts/device-api.md): tomorrow's base minutes and
first lock ("tomorrow"), each lift's end and the minutes after it ("lifts"), and the next lock's own end
("next_lock.until")."""

from datetime import datetime, timedelta

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN

from test_init import _post
from test_people import KID, _household_with_sam, _tv_status
from test_time_model import _call, _set
from test_weekly import SCHOOL_DAY, _schedule

SAM = "person.sam"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _local(year: int, month: int, day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=dt_util.get_default_time_zone())


async def _document(client, secret) -> dict:
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    return body["state"]["profiles"][KID]


async def _budget(hass: HomeAssistant, group: str, minutes: int, days: str) -> None:
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": SAM, "group": group, "minutes": minutes, "days": days}, blocking=True
    )
    await hass.async_block_till_done()


# Tomorrow


async def test_tomorrow_is_its_own_kind_of_day_without_today_s_bonus(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """On a Friday, tomorrow's minutes are a weekend's; today's bonus time isn't in them."""
    freezer.move_to(_local(2026, 11, 20, 12))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _budget(hass, "all", 60, "school_days")
    await _budget(hass, "all", 120, "other_days")
    await _budget(hass, "video", 30, "school_days")
    await _budget(hass, "video", 90, "other_days")
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": SAM, "group": "all", "minutes": 30}, blocking=True)
    await hass.async_block_till_done()

    tomorrow = (await _document(client, secret))["tomorrow"]
    assert tomorrow["date"] == "2026-11-21"
    assert tomorrow["daily_minutes"] == 120
    assert {g["id"]: g["minutes"] for g in tomorrow["groups"]} == {"all": 120, "video": 90}
    # Groups sent today as they'll be tomorrow carry no apps again
    assert all("apps" not in g for g in tomorrow["groups"])


async def test_tomorrow_names_its_school_time_and_today_s_lock_its_wake(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """With the weekly schedule only: tonight's Sleep is the next lock until tomorrow's wake, and tomorrow's first lock
    after waking is School time, with its end."""
    freezer.move_to(_local(2026, 11, 17, 20))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)

    document = await _document(client, secret)
    assert document["next_lock"] == {
        "at": _local(2026, 11, 17, 21, 30).isoformat(),
        "by": "schedule",
        "kind": "bedtime",
        "until": _local(2026, 11, 18, 6, 45).isoformat(),
    }
    assert document["tomorrow"]["next_lock"] == {
        "at": _local(2026, 11, 18, 7, 45).isoformat(),
        "by": "schedule",
        "kind": "school_time",
        "until": _local(2026, 11, 18, 15, 15).isoformat(),
    }


async def test_tomorrow_names_no_school_time_on_a_free_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(_local(2026, 11, 17, 20))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _schedule(hass, days=["every_day"], changes=[{"at": "08:00", "mode": "free"}, {"at": "21:00", "mode": "sleep"}])
    tomorrow = (await _document(client, secret))["tomorrow"]
    # Its first lock after waking is the night's Sleep, until the morning after
    assert tomorrow["next_lock"]["kind"] == "bedtime"
    assert tomorrow["next_lock"]["at"] == _local(2026, 11, 18, 21).isoformat()
    assert tomorrow["next_lock"]["until"] == _local(2026, 11, 19, 8).isoformat()


# Lifts


async def test_unlimited_with_an_end_lists_every_group_with_its_minutes_after(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(_local(2026, 11, 17, 17))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _set(hass, "video", 30)
    await _call(hass, "unlimited", {"person": SAM, "until": "18:00"})

    document = await _document(client, secret)
    assert not [g for g in document["groups"] if g["id"] in ("all", "video")]
    lifts = {lift["group"]: lift for lift in document["lifts"]}
    assert set(lifts) == {"all", "video"}
    end = _local(2026, 11, 17, 18).isoformat()
    assert lifts["all"]["until"] == end and lifts["all"]["minutes_after"] == 45
    assert "com.android.systemui" in lifts["all"]["except"]
    assert lifts["video"]["until"] == end and lifts["video"]["minutes_after"] == 20
    assert "com.thesiegs.hearthtube" in lifts["video"]["apps"] and lifts["video"]["in_daily"] is True


async def test_a_lift_until_midnight_isn_t_listed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The new day starts over (tomorrow) for an allow that lasts the day."""
    freezer.move_to(_local(2026, 11, 17, 17))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _set(hass, "all", 60)
    await _set(hass, "video", 30)
    await _call(hass, "allow", {"people": [SAM], "group": "video"})
    document = await _document(client, secret)
    assert "lifts" not in document
    assert "video" not in [g["id"] for g in document["groups"]]
