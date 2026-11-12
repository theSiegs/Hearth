"""What an adult's app shows of each person and of the household (contract 2 of the household summary, see
docs/home-assistant-integration.md, Household summary): a headline, the other lines, and the actions an adult can take
now as Home Assistant service calls.

Hearth's rules pick the headline, so an app picks up new kinds of news without a release of its own. Each item is
{text, level, key}: text is short and lower case; level is calm, notice or urgent; key names the news (its kind and
its subject, never a count), so it stays the same while minutes tick down and changes when the news does.

Everything here works on the summary's own fields (and the few extras passed in): no Home Assistant state is read.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
from typing import Any

from homeassistant.util import dt as dt_util

from .counting import ALL

CALM = "calm"
NOTICE = "notice"
URGENT = "urgent"

# A bedtime or School time this close is news; a group with less than this left is low
SOON = timedelta(minutes=15)
LOW_MINUTES = 10
BONUS_MINUTES = 15
PAUSE_MINUTES = 30

SERVICE_ANSWER = "hearth.answer_request"


def news_key(kind: str, subject: Any = None) -> str:
    """The key of a piece of news: its kind and what it's about ("low:youtube", "ask:<id>", "pause:<until>"). Never a
    count, so it holds while minutes tick down."""
    return kind if subject in (None, "") else f"{kind}:{subject}"


def _item(text: str, level: str, kind: str, subject: Any = None) -> dict[str, str]:
    return {"text": text, "level": level, "key": news_key(kind, subject)}


def _group_word(group_id: str, names: dict[str, str]) -> str:
    return "screen time" if group_id == ALL else (names.get(group_id) or group_id).lower()


def _clock(iso: str | None) -> str | None:
    """6:30 (local, 12-hour) from an ISO time; "midnight" and "noon" as words."""
    parsed = dt_util.parse_datetime(iso) if iso else None
    if parsed is None:
        return None
    local = dt_util.as_local(parsed)
    if local.minute == 0 and local.hour in (0, 12):
        return "midnight" if local.hour == 0 else "noon"
    return f"{local.hour % 12 or 12}:{local.minute:02d}"


def _till(iso: str | None) -> str:
    clock = _clock(iso)
    return f" till {clock}" if clock else ""


def _action(
    action_id: str, label: str, service: str, data: dict[str, Any], confirm: str | None = None, primary: bool = False
) -> dict[str, Any]:
    action: dict[str, Any] = {"id": action_id, "label": label, "service": service, "data": data}
    if confirm:
        action["confirm"] = confirm
    if primary:
        action["primary"] = True
    return action


def _ask_items(asks: list[dict[str, Any]], names: dict[str, str]) -> list[dict[str, str]]:
    found = []
    for ask in asks:
        what = _group_word(ask["group"], names)
        if ask.get("offered"):
            text = f"{what} ran out · give {ask['minutes']}?"
        elif ask.get("source") == "family_safety":
            # Family Safety's requested time has no known unit: the adult picks the minutes
            text = f"asks for more time · {ask.get('platform') or 'family safety'}"
        else:
            text = f"asks for {ask['minutes']} more · {what}"
        found.append(_item(text, URGENT, "ask", ask["id"]))
    return found


def _ask_actions(asks: list[dict[str, Any]], person_name: str | None = None) -> list[dict[str, Any]]:
    actions = []
    for ask in asks:
        who = f"{person_name.lower()} " if person_name else ""
        actions.append(
            _action(
                f"ask_yes:{ask['id']}",
                f"{who}yes {ask['minutes']}",
                SERVICE_ANSWER,
                {"request_id": ask["id"], "minutes": ask["minutes"]},
                primary=True,
            )
        )
        actions.append(_action(f"ask_no:{ask['id']}", f"{who}no", SERVICE_ANSWER, {"request_id": ask["id"], "deny": True}))
    return actions


def _group_item(group: dict[str, Any], names: dict[str, str]) -> dict[str, str] | None:
    """A group with a budget: out, low or what's left."""
    left = group.get("minutes_left")
    if left is None:
        return None
    word = _group_word(group["id"], names)
    if left <= 0:
        return _item(f"{word} · out", NOTICE, "out", group["id"])
    if left < LOW_MINUTES:
        return _item(f"{word} · {left} left", NOTICE, "low", group["id"])
    return _item(f"{word} · {left} left", CALM, "left", group["id"])


SERVICE_WORDS = {"family_link": "family link", "family_safety": "family safety", "nintendo": "switch"}
APP_WORDS = {"family_link": "the family link app", "family_safety": "the family safety app", "nintendo": "the nintendo app"}


# Package segments that name no app (a domain, a platform, a build), and ones that only qualify the one before
_PACKAGE_NOISE = {
    "com", "org", "net", "io", "co", "air", "android", "apps", "app", "mobile", "client", "free", "full", "paid",
    "prod", "release", "main", "phone", "game", "games",
}
_PACKAGE_QUALIFIERS = {"kids", "tv", "lite", "go", "pro", "plus", "hd", "music", "studio"}


def app_name_guess(package: str) -> str:
    """A readable name from a package when no name is known: its last meaningful segment, title-cased
    ("com.roblox.client" -> "Roblox", "com.google.android.apps.youtube.kids" -> "Youtube Kids")."""
    parts = [p for p in package.replace("_", ".").split(".") if p]
    words = [p for p in parts[1:] if p.lower() not in _PACKAGE_NOISE] if len(parts) > 1 else parts
    if not words:
        return (parts[-1] if parts else package).title()
    picked = [words[-1]]
    if picked[0].lower() in _PACKAGE_QUALIFIERS and len(words) > 1:
        picked.insert(0, words[-2])
    return " ".join(picked).title()


def _app_names(person: dict[str, Any]) -> dict[str, str]:
    """package -> name, from the person's apps today (the summary's apps_today)."""
    return {
        str(row["package"]): str(row["name"])
        for row in person.get("apps_today") or []
        if row.get("package") and row.get("name") and row["name"] != row["package"]
    }


def grant_word(grant: dict[str, Any], names: dict[str, str] | None = None) -> str:
    """What a parent's grant lifts, in a few words: "devices", an app's name (never its package), "switch", "xbox".
    An app's name is the grant's own, else one of [names] (package -> name), else a guess from the package."""
    target = grant.get("target") or {}
    kind, value = target.get("kind"), str(target.get("value") or "")
    if kind == "device":
        return "devices"
    if kind == "switch":
        return "switch"
    if kind == "app":
        return (grant.get("name") or (names or {}).get(value) or app_name_guess(value)).lower()
    return value.lower()


def _standing(grant: dict[str, Any]) -> bool:
    """An app's own limit a parent changed in their app: it stands from day to day (Hearth sees it again each day), so
    it's not news. A bonus, an unlock, a changed daily limit, a Switch or a platform let go is a parent's move: news."""
    return (grant.get("target") or {}).get("kind") == "app"


def _list_words(words: list[str]) -> str:
    return words[0] if len(words) == 1 else f"{', '.join(words[:-1])} and {words[-1]}"


def _grant_items(grants: list[dict[str, Any]], names: dict[str, str]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """A parent's grants: (news, standing). News is one notice per grant ("switch open · the nintendo app till 9:00");
    standing grants (calm) are put together by where they came from and when they end: "roblox open · ...", "youtube
    kids and roblox open · ...", up to 3 named, then "16 apps open · the family link app till midnight"."""
    news = []
    together: dict[tuple[Any, Any], list[dict[str, Any]]] = {}
    for grant in grants:
        if _standing(grant):
            together.setdefault((grant.get("via"), grant.get("until")), []).append(grant)
            continue
        news.append(
            _item(
                f"{grant_word(grant, names)} open · {APP_WORDS.get(grant.get('via'), 'their app')}"
                f"{_till(grant.get('until'))}",
                NOTICE,
                "grant",
                grant["id"],
            )
        )
    standing = []
    for (via, until), group in together.items():
        where = f"{APP_WORDS.get(via, 'their app')}{_till(until)}"
        if len(group) == 1:
            standing.append(_item(f"{grant_word(group[0], names)} open · {where}", CALM, "grant", group[0]["id"]))
            continue
        words = sorted(dict.fromkeys(grant_word(g, names) for g in group))
        what = _list_words(words) if len(group) <= 3 else f"{len(group)} apps"
        # The key names the set of apps (not their names, which may resolve later): stable from refresh to refresh
        apps = hashlib.sha256(
            ",".join(sorted(str((g.get("target") or {}).get("value")) for g in group)).encode()
        ).hexdigest()[:10]
        standing.append(_item(f"{what} open · {where}", CALM, "grants", f"{via}:{until}:{apps}"))
    return news, standing


def _first_party_items(first_party: dict[str, Any]) -> list[dict[str, str]]:
    """Google's or Microsoft's own limit stopping a device of theirs now, and a parent's own Family Safety lock."""
    found = []
    for row in first_party.get("family_link", []):
        if row.get("blocking"):
            found.append(
                _item(f"{str(row.get('device') or 'phone').lower()} · google's own limit", NOTICE, "device_limit",
                      row.get("entity_id"))
            )
    for row in first_party.get("family_safety", []):
        platform = str(row.get("platform") or "").lower()
        if row.get("parent_lock"):
            found.append(
                _item(f"{platform} locked in family safety{_till(row.get('override_until'))}", NOTICE, "parent_lock",
                      platform)
            )
        elif row.get("blocking"):
            found.append(_item(f"{platform} · microsoft's own limit", NOTICE, "device_limit", platform))
    return found


def _sync_items(sync: dict[str, Any]) -> list[dict[str, str]]:
    """A parental control Hearth couldn't hold or let go through (its last error)."""
    found = []
    for kind, status in sorted(sync.items()):
        error = status.get("error") or (status.get("last") or {}).get("error")
        if error:
            found.append(_item(f"{SERVICE_WORDS.get(kind, kind)} · didn't take", NOTICE, "sync_error", kind))
    return found


def _extra_text(extra: dict[str, Any], names: dict[str, str]) -> str:
    where = (extra.get("name") or extra["target"]).lower()
    what = "" if extra.get("group") in (None, ALL) else f"{_group_word(extra['group'], names)} "
    if extra.get("kind") == "allow":
        return f"{where} · {what}open{_till(extra.get('until'))}"
    if extra.get("via") == "hearth":
        return f"{where} · {what}{extra.get('minutes_left') or 0} left there"
    if extra.get("via") == "family_link":
        return f"{where} · +{extra.get('minutes_left') or 0} {what}in family link".replace("  ", " ")
    return f"{where} · {what}open{_till(extra.get('until'))}"


def _paused_key(paused: dict[str, Any]) -> str:
    return f"app:{paused['app']}" if paused.get("app") else f"group:{paused['group']}"


def _paused_word(paused: dict[str, Any], names: dict[str, str]) -> str:
    if paused.get("app"):
        return (paused.get("name") or paused["app"]).lower()
    return names.get(paused["group"], paused.get("name") or paused["group"]).lower()


def person_glance(
    person: dict[str, Any],
    asks: list[dict[str, Any]],
    allows: list[dict[str, Any]],
    school_time_off: list[dict[str, Any]],
    now: datetime,
    grants: list[dict[str, Any]] | None = None,
    answered: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """A person's headline, lines and actions, from their part of the summary.

    asks: their waiting requests for more time (as in approvals); allows: their allows now (Allow.view(person));
    school_time_off: School time taken off for them today (Off.view()); grants: their parent grants (Grant.view());
    answered: their requests answered in a first-party app lately (Asks.answered_elsewhere). The person's
    first_party and sync fields (Google's and Microsoft's own limits, what Hearth did through each parental control)
    are read from [person].

    The headline is the first of: urgent (a waiting ask, a pause, out of All screen time), notice (a bedtime or School
    time lock now, one starting within 15 minutes, a group out or under 10 minutes, an allow, School time off today),
    calm (the most-used limited group's minutes left, else "all clear"). The lines are the rest, then each limited
    group, what's playing, the next lock and, last, the app limits a parent changed in their own app (calm, put
    together by app and end, never the headline).
    """
    entity = person["id"]
    names = {g["id"]: g["name"] for g in person.get("groups", [])}
    groups = [g for g in person.get("groups", []) if g.get("minutes_left") is not None]
    whole = next((g for g in groups if g["id"] == ALL), None)
    allowed_all = any(a.get("group") == ALL for a in allows)
    pause = person.get("pause")
    lock = person.get("lock")
    upcoming = person.get("next_lock")

    news: list[dict[str, str]] = _ask_items(asks, names)
    if pause:
        reason = (pause.get("reason") or "").strip().lower()
        news.append(
            _item(f"paused{' · ' + reason if reason else ''}{_till(pause.get('until'))}", URGENT, "pause", pause.get("until"))
        )
    if whole is not None and whole["minutes_left"] <= 0 and not allowed_all:
        news.append(_item("out of time", URGENT, "out", ALL))
    if lock and lock.get("kind") in ("bedtime", "school_time", "other") and not pause:
        word = {"bedtime": "bedtime", "school_time": "school time"}.get(lock["kind"], "locked")
        news.append(_item(f"{word}{_till(lock.get('until'))}", NOTICE, "lock", f"{lock['kind']}:{lock.get('until')}"))
    # Google TV's own Kids daily limit holds them on a TV: like a lock, and only Google TV's settings lift it
    if (on := person.get("google_tv_limit")) and not pause:
        news.append(_item("google tv's own limit", NOTICE, "google_limit", on[0]))
    if upcoming and (at := dt_util.parse_datetime(upcoming.get("at") or "")) is not None and now < at <= now + SOON:
        word = "bedtime" if upcoming.get("kind") == "bedtime" else "school time"
        minutes = max(1, int((at - now).total_seconds() // 60))
        news.append(_item(f"{word} in {minutes} min", NOTICE, "soon", f"{upcoming.get('kind')}:{upcoming['at']}"))
    # Groups out or low, the fewest minutes first (All screen time's own "out" is above)
    for group in sorted(groups, key=lambda g: g["minutes_left"]):
        item = _group_item(group, names)
        if item is not None and item["level"] == NOTICE and not (group["id"] == ALL and group["minutes_left"] <= 0):
            news.append(item)
    for allow in allows:
        what = _group_word(allow["group"], names) if allow.get("group") else (allow.get("app") or "an app").lower()
        news.append(_item(f"{what} allowed{_till(allow.get('until'))}", NOTICE, "allow", allow["id"]))
    for off in school_time_off:
        news.append(_item("no school time today", NOTICE, "school_off", off["id"]))
    # Extra time on one device: "xbox · +30 till 6:30", "kitchen · 25 left there", "pixel · games open till 8:00"
    for extra in person.get("device_extras") or []:
        news.append(_item(_extra_text(extra, names), NOTICE, "device_bonus", extra["target"]))
    # An adult's pause of one app or group: "youtube paused · homework till 19:00"
    for paused in person.get("pauses") or []:
        reason = (paused.get("reason") or "").strip().lower()
        news.append(
            _item(
                f"{_paused_word(paused, names)} paused{' · ' + reason if reason else ''}{_till(paused.get('until'))}",
                NOTICE,
                "paused",
                _paused_key(paused),
            )
        )
    # The parents' own apps: what a parent opened there, their own limits and locks, and what didn't take
    app_names = _app_names(person)
    grant_news, standing = _grant_items(grants or [], app_names)
    news += grant_news
    news += _first_party_items(person.get("first_party") or {})
    news += _sync_items(person.get("sync") or {})
    for ask in answered or []:
        news.append(_item(f"request {ask.get('text') or 'answered in the app'}", CALM, "answered", ask["id"]))

    if news:
        headline = news[0]
    else:
        # The most-used group with a limit (All screen time only when it's the only one)
        limited = [g for g in groups if g["id"] != ALL] or groups
        best = max(limited, key=lambda g: g.get("used_minutes") or 0, default=None)
        headline = _group_item(best, names) if best is not None else _item("all clear", CALM, "clear")

    lines: list[dict[str, str]] = []
    seen = {headline["key"]}

    def add(item: dict[str, str] | None) -> None:
        if item is not None and item["key"] not in seen:
            seen.add(item["key"])
            lines.append(item)

    for item in news:
        add(item)
    for group in sorted(groups, key=lambda g: (g["id"] != ALL, g["name"].lower())):
        add(_group_item(group, names))
    for playing in person.get("playing", []):
        what = (playing.get("app") or playing.get("package") or "something").lower()
        where = (playing.get("device") or "").lower()
        add(_item(f"{what}{' · ' + where if where else ''}", CALM, "playing", playing.get("package") or what))
    if upcoming and (word := {"bedtime": "bedtime", "school_time": "school time"}.get(upcoming.get("kind"))):
        clock = _clock(upcoming.get("at"))
        add(_item(f"{word} at {clock}" if clock else word, CALM, "next", f"{upcoming.get('kind')}:{upcoming.get('at')}"))
    # Last: what a parent left open in their app's own app limits (never the headline)
    for item in standing:
        add(item)

    name = person.get("name") or entity
    actions = _ask_actions(asks)
    for group in sorted(groups, key=lambda g: g["minutes_left"]):
        actions.append(
            _action(
                f"bonus:{group['id']}",
                f"+{BONUS_MINUTES} {_group_word(group['id'], names)}",
                "hearth.add_bonus",
                {"person": entity, "minutes": BONUS_MINUTES, "group": group["id"]},
                primary=group["minutes_left"] <= 0,
            )
        )
    if pause:
        actions.append(_action("pause_end", "end the pause", "hearth.pause_end", {"people": [entity]}))
    else:
        actions.append(
            _action(
                "pause",
                f"pause {PAUSE_MINUTES} min",
                "hearth.pause",
                {"people": [entity], "minutes": PAUSE_MINUTES},
                confirm=f"pause {name.lower()} for {PAUSE_MINUTES} min?",
            )
        )
    for target in dict.fromkeys(e["target"] for e in person.get("device_extras") or []):
        where = next(e["name"] for e in person["device_extras"] if e["target"] == target).lower()
        actions.append(
            _action(
                f"device_bonus_end:{target}",
                f"end {where} extra time",
                "hearth.allow_end",
                {"people": [entity], "device": target},
                confirm=f"end {name.lower()}'s extra time on {where}?",
            )
        )
    # School time not over yet today and not already off: "no school time today"
    window = person.get("school_time") or {}
    if (end := dt_util.parse_datetime(window.get("end") or "")) is not None and now < end and not school_time_off:
        actions.append(
            _action(
                "school_off",
                "no school time today",
                "hearth.school_time_off",
                {"people": [entity]},
                confirm=f"no school time today for {name.lower()}?",
            )
        )
    for paused in person.get("pauses") or []:
        what = {"app": paused["app"]} if paused.get("app") else {"group": paused["group"]}
        actions.append(
            _action(
                f"pause_end:{_paused_key(paused)}",
                f"end {_paused_word(paused, names)} pause",
                "hearth.pause_end",
                {"people": [entity], **what},
            )
        )
    for allow in allows:
        what = {"group": allow["group"]} if allow.get("group") else {"app": allow["app"]}
        word = _group_word(allow["group"], names) if allow.get("group") else allow["app"].lower()
        actions.append(
            _action(
                f"allow_end:{allow['id']}",
                f"end {word} allow",
                "hearth.allow_end",
                {"people": [entity], **what},
                confirm=f"stop allowing {word} for {name.lower()}?",
            )
        )
    # A parent's grant an adult may end from here: only where that's a write in the parent's app (a bonus reset,
    # extra time cancelled, the Switch or platform locked again)
    for grant in grants or []:
        if not grant.get("endable"):
            continue
        word = grant_word(grant, app_names)
        actions.append(
            _action(
                f"grant_end:{grant['id']}",
                f"end {word} ({APP_WORDS.get(grant.get('via'), 'their app').removeprefix('the ')})",
                "hearth.allow_end",
                {"id": grant["id"]},
                confirm=f"end what {APP_WORDS.get(grant.get('via'), 'their app')} gave {name.lower()}?",
            )
        )
    return {"headline": headline, "lines": lines, "actions": actions}


def household_glance(people: list[dict[str, Any]], approvals: list[dict[str, Any]]) -> dict[str, Any]:
    """The household's headline and actions, from the summary's people and approvals (as the reader may see them:
    pairing codes only for an administrator)."""
    asks = [a for a in approvals if a.get("type") == "more_time"]
    pairings = [a for a in approvals if a.get("type") == "pairing"]
    paused = [p for p in people if p.get("pause")]
    kids = [p for p in people if p.get("kind") == "kid"]
    if asks:
        text = (
            f"{asks[0]['person_name'].lower()} asks for {asks[0]['minutes']} more"
            if len(asks) == 1
            else f"{len(asks)} asks waiting"
        )
        headline = _item(text, URGENT, "asks", ",".join(sorted(a["id"] for a in asks)))
    elif paused:
        until = max(p["pause"]["until"] for p in paused)
        who = "everyone" if len(paused) == len(people) else (
            paused[0]["name"].lower() if len(paused) == 1 else f"{len(paused)} people"
        )
        headline = _item(f"{who} paused{_till(until)}", NOTICE, "pause", until)
    elif pairings:
        text = "a device waits to pair" if len(pairings) == 1 else f"{len(pairings)} devices wait to pair"
        headline = _item(text, NOTICE, "pairing", ",".join(sorted(p["code"] for p in pairings)))
    elif out := [p for p in kids if (p.get("all") or {}).get("minutes_left") == 0]:
        headline = _item(
            f"{out[0]['name'].lower()} is out of time" if len(out) == 1 else f"{len(out)} out of time",
            NOTICE,
            "out",
            ",".join(sorted(p["id"] for p in out)),
        )
    else:
        headline = _item("all clear", CALM, "clear")

    actions = []
    names = {p["id"]: p.get("name") or p["id"] for p in people}
    for ask in asks:
        actions += _ask_actions([ask], names.get(ask["person"], ask.get("person_name")))
    if paused:
        actions.append(_action("pause_end", "end the pause", "hearth.pause_end", {}))
    if len(paused) < len(people):
        actions.append(
            _action(
                "pause_all",
                f"pause everyone {PAUSE_MINUTES} min",
                "hearth.pause",
                {"minutes": PAUSE_MINUTES},
                confirm=f"pause everyone for {PAUSE_MINUTES} min?",
            )
        )
    return {"headline": headline, "actions": actions}
