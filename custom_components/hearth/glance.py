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
SERVICE_DISMISS = "hearth.dismiss_suggestion"

# What a suggestion offers when the household chose no amount and has no habit yet (history.usual_bonus): All
# screen time a half hour, a group or one device a quarter
SUGGEST_ALL_MINUTES = 30
SUGGEST_MINUTES = 15


def news_key(kind: str, subject: Any = None) -> str:
    """The key of a piece of news: its kind and what it's about ("low:youtube", "ask:<id>", "pause:<until>"). Never a
    count, so it holds while minutes tick down."""
    return kind if subject in (None, "") else f"{kind}:{subject}"


def _item(text: str, level: str, kind: str, subject: Any = None) -> dict[str, str]:
    return {"text": text, "level": level, "key": news_key(kind, subject)}


def _group_word(group_id: str, names: dict[str, str]) -> str:
    return "daily time" if group_id == ALL else (names.get(group_id) or group_id).lower()


def duration(minutes: int | float) -> str:
    """A length of time as every surface writes it (noiwid's hm()): "45 min" under an hour, else "2 h 10", "1 h 05",
    "3 h"."""
    minutes = max(0, int(round(minutes)))
    if minutes < 60:
        return f"{minutes} min"
    hours, rest = divmod(minutes, 60)
    return f"{hours} h" if rest == 0 else f"{hours} h {rest:02d}"


def amount(minutes: int | float) -> str:
    """Minutes in a short form, before "left", "more", "of" or after "+" and "give": the bare number under an hour
    ("10 left", "+15", "give 30?"), else as duration() ("1 h 20 left", "+1 h")."""
    minutes = max(0, int(round(minutes)))
    return str(minutes) if minutes < 60 else duration(minutes)


def clock(iso: str | None) -> str | None:
    """6:30 (local, 12-hour) from an ISO time; "midnight" and "noon" as words."""
    parsed = dt_util.parse_datetime(iso) if iso else None
    if parsed is None:
        return None
    local = dt_util.as_local(parsed)
    if local.minute == 0 and local.hour in (0, 12):
        return "midnight" if local.hour == 0 else "noon"
    return f"{local.hour % 12 or 12}:{local.minute:02d}"


_clock = clock


def till(iso: str | None) -> str:
    """" till 6:30" (with its leading space) from an ISO time, "" without one."""
    at = clock(iso)
    return f" till {at}" if at else ""


_till = till


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
            text = f"{what} ran out · give {amount(ask['minutes'])}?"
        elif ask.get("source") == "family_safety":
            # Family Safety's requested time has no known unit: the adult picks the minutes
            text = f"asks for more time · {ask.get('platform') or 'family safety'}"
        else:
            # Bonus time has no category: "asks for 30 bonus" (an older ask that named a group says it too)
            text = f"asks for {amount(ask['minutes'])} bonus" if ask["group"] == ALL else f"asks for {amount(ask['minutes'])} more · {what}"
        found.append(_item(text, URGENT, "ask", ask["id"]))
    return found


def _ask_actions(asks: list[dict[str, Any]], person_name: str | None = None) -> list[dict[str, Any]]:
    actions = []
    for ask in asks:
        who = f"{person_name.lower()} " if person_name else ""
        actions.append(
            _action(
                f"ask_yes:{ask['id']}",
                f"{who}yes {amount(ask['minutes'])}",
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
        # A category at its limit while daily time remains: "games · done for today"
        if group["id"] != ALL and group.get("held_left") == 0:
            return _item(f"{word} · done for today", NOTICE, "out", group["id"])
        return _item(f"{word} · out", NOTICE, "out", group["id"])
    if left < LOW_MINUTES:
        return _item(f"{word} · {amount(left)} left", NOTICE, "low", group["id"])
    return _item(f"{word} · {amount(left)} left", CALM, "left", group["id"])


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
    """Google's, Microsoft's or Nintendo's own limit stopping a device of theirs now, and a parent's own Family Safety
    lock."""
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
    for row in first_party.get("nintendo", []):
        if row.get("blocking"):
            found.append(
                _item(f"{str(row.get('name') or 'switch').lower()} · nintendo's own limit", NOTICE, "device_limit",
                      row.get("device_id"))
            )
    return found


# A sync error older than this isn't news any more (Hearth's page still shows it, under Device limits)
STALE_ERROR = timedelta(days=1)


def _sync_items(sync: dict[str, Any], now: datetime | None = None) -> list[dict[str, str]]:
    """A parental control Hearth couldn't hold or let go through (its last error), within the last day."""
    found = []
    for kind, status in sorted(sync.items()):
        last = status.get("last") or {}
        error = status.get("error") or last.get("error")
        when = dt_util.parse_datetime(str(status.get("failed_at") or last.get("at") or ""))
        if error and now is not None and when is not None and now - when > STALE_ERROR:
            continue
        if error:
            found.append(_item(f"{SERVICE_WORDS.get(kind, kind)} · didn't take", NOTICE, "sync_error", kind))
    return found


def _extra_text(extra: dict[str, Any], names: dict[str, str]) -> str:
    where = (extra.get("name") or extra["target"]).lower()
    what = "" if extra.get("group") in (None, ALL) else f"{_group_word(extra['group'], names)} "
    if extra.get("kind") == "allow":
        return f"{where} · {what}open{_till(extra.get('until'))}"
    if extra.get("via") == "hearth":
        return f"{where} · {what}{amount(extra.get('minutes_left') or 0)} left there"
    if extra.get("via") == "family_link":
        return f"{where} · +{amount(extra.get('minutes_left') or 0)} {what}in family link".replace("  ", " ")
    return f"{where} · {what}open{_till(extra.get('until'))}"


def _paused_key(paused: dict[str, Any]) -> str:
    return f"app:{paused['app']}" if paused.get("app") else f"group:{paused['group']}"


def _paused_word(paused: dict[str, Any], names: dict[str, str]) -> str:
    if paused.get("app"):
        return (paused.get("name") or paused["app"]).lower()
    return names.get(paused["group"], paused.get("name") or paused["group"]).lower()


def _amounts(first: int, over: int = 0) -> list[int]:
    """The two amounts a suggestion offers: its own, and a quarter or a half hour beside it. When the group is already
    [over] its limit, both cover that first: the usual amount plus it, and a quarter hour more."""
    if over:
        return [first, first + 15]
    return [first, 30 if first == 15 else 15]


def _suggestion(
    person: str, key: str, text: str, reason: str, minutes: int, data: dict[str, Any], over: int = 0, **about: Any
) -> dict[str, Any]:
    # Bonus time has no category (time_model.py): a give is hearth.add_time; extra time on one device stays add_bonus
    on_device = "device" in data
    actions = [
        _action(
            f"suggest:{key}:{given}",
            f"+{amount(given)}",
            "hearth.add_bonus" if on_device else "hearth.add_time",
            {"person": person, "minutes": given, **data} if on_device else {"person": person, "minutes": given},
            primary=given == minutes,
        )
        for given in _amounts(minutes, over)
    ]
    actions.append(_action(f"suggest_dismiss:{key}", "not today", SERVICE_DISMISS, {"person": person, "key": key}))
    # over: minutes already past the limit (0 when it isn't really over), for a page that says what a give leaves
    return {"key": key, "text": text, "level": NOTICE, "reason": reason, "minutes": minutes, "over": over, **about,
            "actions": actions}


def device_word(target: dict[str, Any] | None) -> str:
    """A device as a person reads it: its display name (targets.py: the name given in Home Assistant, a source's,
    else its label), never a model id when a better one is known."""
    if not target:
        return "device"
    return str(target.get("display_name") or target.get("name") or "device")


def _category_word(group_id: str, names: dict[str, str]) -> str:
    """A category as a sentence names it: as named ("YouTube", "Games"), "daily time" for All."""
    return "daily time" if group_id == ALL else str(names.get(group_id) or group_id)


def _possessive(name: str) -> str:
    return f"{name}'s"


def _whose_device(person: dict[str, Any], target: dict[str, Any] | None) -> str:
    """"Sam's Xbox"; a name that says whose already stays ("Sam's tablet", never "Sam's Sam's tablet")."""
    word = device_word(target)
    name = str(person.get("name") or "")
    return word if name and word.casefold().startswith(f"{name}'s ".casefold()) else f"{_possessive(name or 'Their')} {word}"


def _on_device(target: dict[str, Any] | None) -> str:
    """"the Xbox"; "Sam's tablet" (a name that says whose takes no "the")."""
    word = device_word(target)
    return word if "'s " in word or word == "Windows" else f"the {word}"


# Minutes past a limit that count as really over (less is counting catching up with a hold that's already on)
OVER_MIN = 10


def _over(group_row: dict[str, Any]) -> int:
    """How far past its limit (budget plus today's extra time) a group is, rounded up to 5 minutes; 0 when it isn't,
    or only by the few minutes counting runs behind enforcement (under OVER_MIN)."""
    budget = group_row.get("budget")
    if budget is None or budget < 0:
        return 0
    past = (group_row.get("used_minutes") or 0) - budget - max(0, group_row.get("bonus") or 0)
    return 0 if past < OVER_MIN else -(-int(past) // 5) * 5


def _sentence(person: dict[str, Any], reason: str, group: str, target: dict[str, Any] | None, via: str | None,
              names: dict[str, str]) -> tuple[str, str]:
    """A suggestion as one sentence and a detail line, for a page that writes sentences (the panel's For you):
    "Sam's YouTube time is up" / "Used 1 h 14 of 1 h · 1 h 45 of screen time left"; "Sam's Xbox is stopped by
    Microsoft's limit" / "Microsoft's own limit for today"."""
    who = _possessive(str(person.get("name") or person.get("id") or "Their"))
    whole = next((g for g in person.get("groups") or [] if g["id"] == ALL), None)
    if reason == "group_out":
        group_row = next((g for g in person.get("groups") or [] if g["id"] == group), {}) or {}
        if group == ALL:
            title = f"{person.get('name') or 'They'} ran out of daily time"
        else:
            title = f"{who} {_category_word(group, names)} time is up"
        given = max(0, group_row.get("bonus") or 0)
        if given:
            title = title.replace(" is up", " is still up").replace(" ran out of", " is still out of")
        budget = group_row.get("budget")
        cap = None if budget is None else budget + given
        used = group_row.get("used_minutes") or 0
        parts = [f"Used {duration(used)} of {duration(cap)}" if cap is not None else f"Used {duration(used)}"]
        if given:
            parts[0] += f" (with {duration(given)} bonus)" if group == ALL else f" (limit raised by {duration(given)})"
        over = _over(group_row)
        if over:
            parts.append(f"{duration(over)} over")
        if group != ALL:
            left = (whole or {}).get("minutes_left")
            parts.append("no daily time set" if left is None else f"{duration(left)} of daily time left")
        return title, " · ".join(parts)
    company = {"family_link": "Google", "family_safety": "Microsoft", "nintendo": "Nintendo"}.get(via or "", "its own")
    title = f"{_whose_device(person, target)} is stopped by {company}'s limit"
    return title, f"{company}'s own limit for today"


def _device_target(row: dict[str, Any], via: str, targets: list[dict[str, Any]]) -> dict[str, Any] | None:
    """The person's device (targets.py) a first-party row is about."""
    if via == "family_link":
        wanted = f"fl:{row.get('device_id')}"
        return next((t for t in targets if t["id"] == wanted), None)
    if via == "family_safety":
        wanted = f"fs:{str(row.get('platform') or '').lower()}"
        return next((t for t in targets if t["id"] == wanted), None)
    switches = [t for t in targets if t.get("via") == "nintendo"]
    named = [t for t in switches if str(t.get("name") or "").casefold() == str(row.get("name") or "").casefold()]
    return (named or switches)[0] if len(named or switches) == 1 else None


def suggestions(
    person: dict[str, Any],
    asks: list[dict[str, Any]],
    allows: list[dict[str, Any]],
    hints: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """What an adult will likely be asked for next, with the answer ready (round 2, decisions 3 and 4).

    A Hearth group out of time: give more of that group. When All screen time is out, only All: more of a group
    wouldn't open anything. A device stopped by Google's, Microsoft's or Nintendo's own limit while Hearth's time
    isn't out: extra time on that device. Never while a request for it waits (its yes and no are the actions then), an
    allow already lifts it, extra time on that device runs, or an adult put it off today.

    hints: {"dismissed": keys put off today, "minutes": {group or device id: minutes the household chose},
    "usual": {group: minutes usually given (history.usual_bonus)}}.
    """
    hints = hints or {}
    dismissed = set(hints.get("dismissed") or ())
    chosen = hints.get("minutes") or {}
    usual = hints.get("usual") or {}
    entity = person["id"]
    names = {g["id"]: g["name"] for g in person.get("groups", [])}
    asked = {a.get("group") for a in asks}
    allowed = {a.get("group") for a in allows if a.get("group")}
    if any(a.get("source") == "family_safety" for a in asks):
        asked.add("device:family_safety")
    found: list[dict[str, Any]] = []

    def minutes_for(key: str, group: str, device: bool = False) -> int:
        given = chosen.get(key) or (None if device else chosen.get(group) or usual.get(group))
        return int(given) if given else (SUGGEST_ALL_MINUTES if group == ALL and not device else SUGGEST_MINUTES)

    out = [
        g for g in person.get("groups", [])
        if g.get("minutes_left") is not None and g["minutes_left"] <= 0 and g["id"] not in allowed
    ]
    all_out = any(g["id"] == ALL for g in out) and ALL not in allowed
    for group in out:
        if (all_out and group["id"] != ALL) or group["id"] in asked:
            continue
        key = news_key("more", group["id"])
        if key in dismissed:
            continue
        word = _group_word(group["id"], names)
        minutes = minutes_for(group["id"], group["id"])
        # Already over by more than the usual amount (time counted past the limit, or a give that didn't cover it):
        # offer enough to catch up and still leave the usual amount, so a tap really opens it again
        over = _over(group)
        if over:
            minutes = over + minutes
        sentence, detail = _sentence(person, "group_out", group["id"], None, None, names)
        found.append(
            _suggestion(entity, key, f"{word} ran out · give {amount(minutes)}?", "group_out", minutes,
                        {"group": group["id"]}, over=over, group=group["id"], sentence=sentence, detail=detail)
        )
    if all_out:
        return found
    # Their own limits: only where Hearth's time isn't what stops them
    targets = person.get("targets") or []
    extras = {e.get("target") for e in person.get("device_extras") or []}
    for via, rows in (person.get("first_party") or {}).items():
        if via == "family_safety" and "device:family_safety" in asked:
            continue
        for row in rows:
            if not row.get("blocking"):
                continue
            target = _device_target(row, via, targets)
            if target is None or target["id"] in extras:
                continue
            key = news_key("device", target["id"])
            if key in dismissed:
                continue
            word = device_word(target).lower()
            whose = {"family_link": "google's", "family_safety": "microsoft's", "nintendo": "nintendo's"}.get(via, "its")
            minutes = minutes_for(target["id"], ALL, device=True)
            sentence, detail = _sentence(person, "device_limit", ALL, target, via, names)
            found.append(
                _suggestion(entity, key, f"{word} · {whose} limit · give {amount(minutes)}?", "device_limit", minutes,
                            {"group": ALL, "device": target["id"]}, device=target["id"], sentence=sentence,
                            detail=detail)
            )
    return found


# Why a suggestion waits (hold_back): `held` in the summary's suggestions_held, with a few words in `why`
HOLD_LOCK = "lock"
HOLD_PAUSE = "paused"
HOLD_BEDTIME = "after_bedtime"
HOLD_CUTOFF = "after_cutoff"
HOLD_NOT_IN_USE = "not_in_use"
HOLD_MORE = "more"
# Without a bedtime, suggestions wait from this hour of the evening to MORNING
CUTOFF_HOUR = 21
MORNING_HOUR = 6
_LOCK_WORDS = {"bedtime": "in bedtime", "school_time": "in School time", "other": "locked"}


def _in_use(person: dict[str, Any], device: str, asks: list[dict[str, Any]]) -> bool:
    """The device is in use now: something plays there (a playing sensor, a live source, a TV's now playing) or a
    waiting request came from it."""
    if any(p.get("target") == device for p in person.get("playing") or []):
        return True
    for ask in asks:
        if ask.get("device_id") and f"hearth:{ask['device_id']}" == device:
            return True
        if ask.get("platform") and f"fs:{str(ask['platform']).lower()}" == device:
            return True
    return False


def _hold(person: dict[str, Any], suggestion: dict[str, Any], asks: list[dict[str, Any]], now: datetime) -> tuple[str, str] | None:
    """Why [suggestion] waits now, as (code, a few words), or None to show it."""
    pause = person.get("pause")
    if pause:
        return HOLD_PAUSE, f"paused{till(pause.get('until'))}"
    lock = person.get("lock") or {}
    if lock.get("kind") in LOCK_KINDS:
        return HOLD_LOCK, f"{_LOCK_WORDS[lock['kind']]}{till(lock.get('until'))}"
    local = dt_util.as_local(now)
    bedtime = person.get("bedtime") or {}
    start = dt_util.parse_datetime(bedtime.get("start") or "") if bedtime else None
    wake = dt_util.parse_datetime(bedtime.get("end") or "") if bedtime else None
    if start is not None:
        if now >= start:
            return HOLD_BEDTIME, f"after bedtime ({clock(bedtime['start'])})"
        if wake is not None and now < wake:
            return HOLD_BEDTIME, f"before wake-up ({clock(bedtime['end'])})"
    elif local.hour >= CUTOFF_HOUR or local.hour < MORNING_HOUR:
        return HOLD_CUTOFF, f"after {CUTOFF_HOUR - 12}:00 pm"
    if suggestion.get("reason") == "device_limit" and not _in_use(person, suggestion.get("device") or "", asks):
        target = next((t for t in person.get("targets") or [] if t.get("id") == suggestion.get("device")), None)
        return HOLD_NOT_IN_USE, f"not on {_on_device(target)} now"
    return None


def hold_back(
    person: dict[str, Any], found: list[dict[str, Any]], asks: list[dict[str, Any]], now: datetime
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """The suggestions to show now and the ones held back (the redesign's rules): none during a lock, a pause, after
    the kid's bedtime starts (or after 21:00 without a bedtime, till 6:00), and a device's own limit only while that
    device is in use. At most one shows per kid, and none while a request of theirs waits (the request comes first):
    the rest are held as "more". Each held one is the suggestion with `held` (the code) and `why` (a few words: "in
    bedtime till 7:00")."""
    shown: list[dict[str, Any]] = []
    held: list[dict[str, Any]] = []
    for suggestion in found:
        why = _hold(person, suggestion, asks, now)
        if why is None and (asks or shown):
            why = (HOLD_MORE, "a request from them comes first" if asks else "another for them shows first")
        if why is None:
            shown.append(suggestion)
        else:
            held.append({**suggestion, "held": why[0], "why": why[1]})
    return shown, held


# The color role of a group and of a person (docs/home-assistant-integration.md, Household summary, `state`): a surface
# picks its own hues, never the role
OK = "ok"
LOW = "low"
OUT = "out"
NONE = "none"
ALLOWED = "allowed"
PAUSED = "paused"
HELD = "held"
LOCKED = "locked"
LOCK_KINDS = {"bedtime": "bedtime", "school_time": "school time", "other": "locked"}


def _lifted_groups(allows: list[dict[str, Any]], groups: list[dict[str, Any]]) -> set[str]:
    """The groups an adult's allow lifts now: an allow of All screen time lifts every group."""
    allowed = {a["group"] for a in allows if a.get("group")}
    return {g["id"] for g in groups} if ALL in allowed else allowed


def group_state(group: dict[str, Any], allowed: set[str], paused: set[str]) -> str:
    """paused (an adult paused the group), allowed (an allow lifts it), else by its minutes left: out, low (under
    LOW_MINUTES), ok, or none (no budget today)."""
    if group["id"] in paused:
        return PAUSED
    if group["id"] in allowed:
        return ALLOWED
    left = group.get("minutes_left")
    if left is None:
        return NONE
    if left <= 0:
        return OUT
    return LOW if left < LOW_MINUTES else OK


def binding_group(groups: list[dict[str, Any]], allowed: set[str]) -> dict[str, Any] | None:
    """The group that stops them first: out, else the fewest minutes left; All screen time on a tie (more of a group
    wouldn't open anything then). Groups an allow lifts and groups without a budget never bind."""
    limited = [g for g in groups if g.get("minutes_left") is not None and g["id"] not in allowed]
    if not limited:
        return None
    return min(limited, key=lambda g: (max(0, g["minutes_left"]), g["id"] != ALL))


def _blocked(person: dict[str, Any]) -> bool:
    """A first-party control holds a device of theirs: Hearth's hold through it, or Google's, Microsoft's or
    Nintendo's own limit, or Google TV's own Kids limit."""
    if person.get("held_by") or person.get("google_tv_limit"):
        return True
    return any(row.get("blocking") or row.get("parent_lock") for rows in (person.get("first_party") or {}).values()
               for row in rows)


def person_state(person: dict[str, Any], binding: dict[str, Any] | None) -> str:
    """paused (the family pause), locked (bedtime, School time or another lock now), out (the binding group is out),
    held (a first-party control holds a device), low (the binding group under LOW_MINUTES), ok, none (no limit)."""
    if person.get("pause"):
        return PAUSED
    if (person.get("lock") or {}).get("kind") in LOCK_KINDS:
        return LOCKED
    if binding is not None and binding["minutes_left"] <= 0:
        return OUT
    if _blocked(person):
        return HELD
    if binding is None:
        return NONE
    return LOW if binding["minutes_left"] < LOW_MINUTES else OK


def day_line(
    person: dict[str, Any], binding: dict[str, Any] | None, allows: list[dict[str, Any]], names: dict[str, str]
) -> dict[str, str]:
    """The today line of a kid's tile: `<All used> of <All budget> · <binding group> · <its left>`.

    "2 h 10 of 3 h · games · 10 left"; All binding: "2 h 10 of 3 h · 50 left"; a group out: "3 h of 3 h · games out"
    (All: "out of time"); no budget for All: "1 h 20 today · games · 10 left"; nothing limited: "1 h 20 today · no
    limit" (or "· allowed till 8:00" under an allow of All). A family pause or a lock replaces it: "paused · dinner
    till 6:30", "bedtime till 7:00". The budget is today's with its bonus. The key names what the line says, never a
    count."""
    pause = person.get("pause")
    if pause:
        reason = (pause.get("reason") or "").strip().lower()
        return _item(f"paused{' · ' + reason if reason else ''}{till(pause.get('until'))}", URGENT, "day",
                     f"pause:{pause.get('until')}")
    lock = person.get("lock") or {}
    if lock.get("kind") in LOCK_KINDS:
        return _item(f"{LOCK_KINDS[lock['kind']]}{till(lock.get('until'))}", NOTICE, "day",
                     f"lock:{lock['kind']}:{lock.get('until')}")
    whole = person.get("all") or {}
    used = whole.get("used_minutes") or 0
    if whole.get("budget") is not None:
        start = f"{amount(used)} of {amount(whole['budget'] + (whole.get('bonus') or 0))}"
    else:
        start = f"{duration(used)} today"
    if binding is None:
        allow_all = next((a for a in allows if a.get("group") == ALL), None)
        if allow_all is not None:
            return _item(f"{start} · allowed{till(allow_all.get('until'))}", NOTICE, "day", "allowed:all")
        return _item(f"{start} · no limit", CALM, "day", "none")
    left = max(0, binding["minutes_left"])
    group = binding["id"]
    word = "" if group == ALL else f"{_group_word(group, names)}"
    if left <= 0:
        text = f"{start} · out of time" if group == ALL else f"{start} · {word} out"
        return _item(text, URGENT if group == ALL else NOTICE, "day", f"out:{group}")
    state = LOW if left < LOW_MINUTES else "left"
    text = f"{start} · {amount(left)} left" if group == ALL else f"{start} · {word} · {amount(left)} left"
    return _item(text, NOTICE if state == LOW else CALM, "day", f"{state}:{group}")


def person_states(person: dict[str, Any], allows: list[dict[str, Any]]) -> dict[str, Any]:
    """Each group's `state` and `limited` (set in place, so `all` has them too), and the person's `binding`,
    `day_line` and `state` (contract 2, decided here so every surface draws the same)."""
    groups = person.get("groups") or []
    names = {g["id"]: g["name"] for g in groups}
    allowed = _lifted_groups(allows, groups)
    paused = {p["group"] for p in person.get("pauses") or [] if p.get("group") and not p.get("app")}
    for group in groups:
        group["state"] = group_state(group, allowed, paused)
        # No budget today: a surface may hide it (the TV, a phone app) or mute it (the panel)
        group["limited"] = group.get("minutes_left") is not None
    binds = binding_group(groups, allowed)
    return {
        "binding": None if binds is None else {"group": binds["id"], "minutes_left": max(0, binds["minutes_left"])},
        "day_line": day_line(person, binds, allows, names),
        "state": person_state(person, None if binds is None else {"minutes_left": max(0, binds["minutes_left"])}),
    }


def person_glance(
    person: dict[str, Any],
    asks: list[dict[str, Any]],
    allows: list[dict[str, Any]],
    school_time_off: list[dict[str, Any]],
    now: datetime,
    grants: list[dict[str, Any]] | None = None,
    answered: list[dict[str, Any]] | None = None,
    hints: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """A person's headline, lines, actions and suggestions, from their part of the summary.

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
            _item(f"screens paused{' · ' + reason if reason else ''}{_till(pause.get('until'))}", URGENT, "pause", pause.get("until"))
        )
    # Unlimited (hearth.unlimited): its line instead of daily time's
    if unlimited := (person.get("time") or {}).get("unlimited"):
        news.append(_item(str(unlimited.get("text") or "unlimited").lower(), NOTICE, "unlimited", unlimited.get("until")))
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
    news += _sync_items(person.get("sync") or {}, now)
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
    # One way to give more: bonus time (no category; time_model.py)
    if groups:
        actions.append(
            _action(
                "bonus",
                f"+{amount(BONUS_MINUTES)} bonus",
                "hearth.add_time",
                {"person": entity, "minutes": BONUS_MINUTES},
                primary=any(g["minutes_left"] <= 0 for g in groups),
            )
        )
    if (person.get("time") or {}).get("unlimited"):
        actions.append(_action("unlimited_end", "end unlimited", "hearth.unlimited_end", {"people": [entity]}))
    if pause:
        actions.append(_action("pause_end", "end pause screens", "hearth.pause_end", {"people": [entity]}))
    else:
        actions.append(
            _action(
                "pause",
                f"pause screens {duration(PAUSE_MINUTES)}",
                "hearth.pause",
                {"people": [entity], "minutes": PAUSE_MINUTES},
                confirm=f"pause {name.lower()} for {duration(PAUSE_MINUTES)}?",
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
    shown, held = hold_back(person, suggestions(person, asks, allows, hints), asks, now)
    return {
        "headline": headline,
        "lines": lines,
        "actions": actions,
        # What shows now (at most one), and what waits with why (hold_back)
        "suggestions": shown,
        "suggestions_held": held,
        **person_states(person, allows),
    }


def household_glance(people: list[dict[str, Any]], approvals: list[dict[str, Any]]) -> dict[str, Any]:
    """The household's headline and actions, from the summary's people and approvals (as the reader may see them:
    pairing codes only for an administrator)."""
    asks = [a for a in approvals if a.get("type") == "more_time"]
    pairings = [a for a in approvals if a.get("type") == "pairing"]
    paused = [p for p in people if p.get("pause")]
    kids = [p for p in people if p.get("kind") == "kid"]
    if asks:
        text = (
            f"{asks[0]['person_name'].lower()} asks for {amount(asks[0]['minutes'])} more"
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
                f"pause everyone {duration(PAUSE_MINUTES)}",
                "hearth.pause",
                {"minutes": PAUSE_MINUTES},
                confirm=f"pause everyone for {duration(PAUSE_MINUTES)}?",
            )
        )
    # Every person's suggestions, the household's urgent first: out of All screen time before a group or a device
    found = [
        {**s, "person": p["id"], "person_name": p.get("name") or p["id"]}
        for p in people
        for s in p.get("suggestions") or []
    ]
    found.sort(key=lambda s: (s.get("group") != ALL, s["reason"] != "group_out"))
    # And the ones held back, with why (hold_back): the page's "held back · why"
    held = [
        {**s, "person": p["id"], "person_name": p.get("name") or p["id"]}
        for p in people
        for s in p.get("suggestions_held") or []
    ]
    # Who needs an adult now: a kid with a waiting request or a suggestion showing (one row each on the page)
    needs = {a["person"] for a in asks} | {s["person"] for s in found}
    # What a tile's badge and the TV's top row count, so no surface counts on its own: kids by their `state`
    counts = {
        "asks": len(asks),
        "suggestions": len(found),
        "pairings": len(pairings),
        "paused": len(paused),
        **{state: sum(1 for p in kids if p.get("state") == state) for state in (OUT, LOW, LOCKED, HELD)},
        # ("held" above counts kids a first-party control holds)
        "suggestions_held": sum(1 for s in held if s.get("held") != HOLD_MORE),
        "needs": len(needs),
    }
    return {"headline": headline, "actions": actions, "suggestions": found, "suggestions_held": held, "counts": counts}
