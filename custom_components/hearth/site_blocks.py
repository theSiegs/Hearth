"""hearth.block_site and hearth.unblock_site: websites an adult blocks by hand for a kid, in Family Link (Chrome) and
Family Safety, next to the daily website list (docs/home-assistant-integration.md, Block a website).

A site is given as a domain (or a web address, which is cut down to its domain): lowercased, without a scheme, a
path, a port or a leading "www.". An IP address, a wildcard or a bare public suffix (co.uk) is refused, as the website
list refuses them (fs_site_list.parse).

- Family Link gets both forms of a domain, "*.example.com" and "example.com" (Google doesn't say whether the wildcard
  covers the bare domain; its own list sync sends both), with familylink.block_site / remove_site.
- Family Safety gets the domain, with block_website / remove_website (Microsoft keeps absolute URLs; they are compared
  by host, without "www.").

Each side is read first with its get_sites. What Hearth's block added is kept per kid and side (with the schedule in
Home Assistant's storage), and unblock_site only ever removes that: a block made in the Family Link or Family Safety
app stays ("blocked outside Hearth"), and so does one the daily website list added ("on the website list": Family
Link's and a Family Safety fork's get_sites name what their sync_site_list added, `from_list`; Hearth's own Family
Safety sync keeps what it added itself, fs_site_list.py).

With the daily list (the rule):

- A hand block of a domain the list already added is recorded as Hearth's too. When the list later drops it, it stays
  blocked: Hearth's own Family Safety sync leaves it out of what it takes back (and it is the hand block's alone from
  then on); for Family Link and a Family Safety fork, whose sync_site_list Hearth can't tell, Hearth reads the kid's
  sites before the daily sync and blocks again, right after it, what the sync took out of a hand block.
- A hand unblock of a domain the list added leaves it blocked ("kept: on the website list") and forgets Hearth's own
  record of it, so it goes when the list drops it.
- A domain blocked by hand before the list had it isn't the list's (the list adds only what isn't blocked yet): a hand
  unblock removes it, and the next daily sync blocks it again as the list's while the list still lists it.

A call that fails on one side is told for that side (with the error); the other side and the other kids go on. A
Family Safety that names the sites it couldn't change (upstream's answer) gets them told per site. A site is recorded
only once its block call succeeded.
"""

from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError

from . import fs_site_list
from .activity import call_service
from .enforce import FAMILY_LINK, FAMILY_SAFETY, FS_DOMAIN, fs_account_of

if TYPE_CHECKING:
    from .schedule import Scheduler

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
SIDES = (FAMILY_LINK, FAMILY_SAFETY)
# The most sites one call takes
MAX_SITES = 50
ON_LIST = "on the website list"
OUTSIDE = "blocked outside Hearth"
_FL_SERVICES = ("get_sites", "block_site", "remove_site")


def normalize(value: Any) -> str:
    """The domain a hand block is for: "https://www.Example.com:443/page" -> "example.com". Raises ValueError for
    anything that isn't a plain domain (an IP address, a wildcard, a bare public suffix, an empty value)."""
    text = str(value if value is not None else "").strip().lower()
    if not text or any(c.isspace() for c in text):
        raise ValueError(f"Not a website: {value!r}")
    if "://" in text:
        text = text.split("://", 1)[1]
    for cut in ("/", "?", "#"):
        text = text.split(cut, 1)[0]
    text = text.rsplit("@", 1)[-1]
    if text.startswith("["):
        raise ValueError(f"An IP address can't be blocked as a website: {value!r}")
    text = text.split(":", 1)[0].rstrip(".")
    if "*" in text:
        raise ValueError(f"Give a domain, not a wildcard: {value!r} (a domain is blocked with its subdomains)")
    text = text.removeprefix("www.")
    if fs_site_list._IPV4.match(text):
        raise ValueError(f"An IP address can't be blocked as a website: {value!r}")
    if fs_site_list.parse(text) != [text]:
        raise ValueError(f"Not a domain that can be blocked: {value!r}")
    return text


def _patterns(side: str, domain: str) -> list[str]:
    return [f"*.{domain}", domain] if side == FAMILY_LINK else [domain]


def _fs_host(value: Any) -> str | None:
    host = fs_site_list.site_host(value)
    return host.removeprefix("www.") if host else None


class SiteBlocks:
    """What Hearth's hand blocks added: {person: {side: {domain: [patterns]}}} (the Scheduler keeps it with its store;
    [save] asks it to)."""

    def __init__(self, hass: HomeAssistant, scheduler: Scheduler) -> None:
        self.hass = hass
        self.scheduler = scheduler
        self.owned: dict[str, dict[str, dict[str, list[str]]]] = {}
        # One change at a time: a block, an unblock, or a daily list sync of a kid with hand blocks
        self.lock = asyncio.Lock()

    def load(self, raw: Any) -> None:
        self.owned = {}
        if not isinstance(raw, dict):
            return
        for person, sides in raw.items():
            if not isinstance(sides, dict):
                continue
            for side, domains in sides.items():
                if side not in SIDES or not isinstance(domains, dict):
                    continue
                kept = {
                    str(d): [str(p) for p in patterns]
                    for d, patterns in domains.items()
                    if isinstance(patterns, list) and patterns
                }
                if kept:
                    self.owned.setdefault(str(person), {})[side] = kept

    def dump(self) -> dict[str, Any]:
        return self.owned

    def _save(self) -> None:
        # Empty people and sides go
        self.owned = {
            person: {side: domains for side, domains in sides.items() if domains}
            for person, sides in self.owned.items()
            if any(sides.values())
        }
        self.scheduler._save()

    def view(self, person: str) -> dict[str, list[str]]:
        """The kid's hand-blocked domains by side, for their sensor and Hearth's page."""
        return {side: sorted(domains) for side, domains in (self.owned.get(person) or {}).items() if domains}

    def domains(self, person: str, side: str) -> set[str]:
        return set((self.owned.get(person) or {}).get(side) or {})

    def _record(self, person: str, side: str) -> dict[str, list[str]]:
        return self.owned.setdefault(person, {}).setdefault(side, {})

    # The sides

    def targets(self, person: str) -> dict[str, dict[str, str]]:
        """The kid's sides (Configure > Enforce) and the target data of each."""
        out: dict[str, dict[str, str]] = {}
        fl_entity = self.scheduler.family_link_entity(person)
        if fl_entity:
            out[FAMILY_LINK] = {"entity_id": fl_entity}
        fs_entity = self.scheduler.family_safety_entity(person)
        if fs_entity:
            out[FAMILY_SAFETY] = {"entity_id": fs_entity} if "." in fs_entity else {"account_id": fs_entity}
        return out

    def _usable(self, side: str) -> bool:
        if side == FAMILY_LINK:
            return all(self.hass.services.has_service(FL_DOMAIN, s) for s in _FL_SERVICES)
        return fs_site_list.available(self.hass)

    def _fs_own_listed(self, target: dict[str, str]) -> set[str]:
        """What Hearth's own Family Safety sync added from website lists for this kid (fs_site_list.py)."""
        entity = target.get("entity_id") or target.get("account_id") or ""
        account = fs_account_of(self.hass, entity) or entity
        lists = self.scheduler.fs_sites.owned.get(account) or {}
        return {str(d) for domains in lists.values() for d in domains}

    async def _read(self, side: str, target: dict[str, str], person: str) -> tuple[set[str], set[str]]:
        """(blocked, added by the website list) of one side, as patterns of that side."""
        domain = FL_DOMAIN if side == FAMILY_LINK else FS_DOMAIN
        response = await call_service(
            self.hass, domain, "get_sites", dict(target), blocking=True, return_response=True, person=person,
            why="hand site block",
        )
        if not isinstance(response, dict) or not isinstance(response.get("blocked"), list):
            raise HomeAssistantError(f"{side}'s get_sites gave no blocked websites")
        if side == FAMILY_LINK:
            blocked = {str(p).strip().lower() for p in response["blocked"]}
            listed = {str(p).strip().lower() for p in response.get("from_list") or []}
            return blocked, listed & blocked
        blocked = {h for h in map(_fs_host, response["blocked"]) if h}
        listed = {h for h in map(_fs_host, response.get("from_list") or []) if h}
        listed |= self._fs_own_listed(target)
        return blocked, listed & blocked

    async def _write(
        self, side: str, target: dict[str, str], block: bool, patterns: list[str], person: str
    ) -> dict[str, str]:
        """Blocks or removes [patterns] on one side: {pattern: error} of the ones that failed."""
        if not patterns:
            return {}
        if side == FAMILY_LINK:
            service = "block_site" if block else "remove_site"
            try:
                await call_service(
                    self.hass, FL_DOMAIN, service, {**target, "sites": list(patterns)}, blocking=True, person=person,
                    why="hand site block",
                )
            except Exception as err:  # noqa: BLE001 - told per site; the other side goes on
                return {p: str(err)[:200] for p in patterns}
            return {}
        service = "block_website" if block else "remove_website"
        try:
            await call_service(
                self.hass, FS_DOMAIN, service, {**target, "website": list(patterns)}, blocking=True, person=person,
                why="hand site block",
            )
        except Exception as err:  # noqa: BLE001 - upstream names the sites done and failed
            return fs_site_list.split_failure(err, list(patterns))[1]
        return {}

    # hearth.block_site / hearth.unblock_site

    async def block(self, people: list[str], domains: list[str]) -> dict[str, Any]:
        """Blocks [domains] for each of [people] on each side they have: {person: {side: {done, already, failed}}}."""
        async with self.lock:
            out: dict[str, Any] = {}
            for person in people:
                out[person] = {}
                for side, target in self.targets(person).items():
                    out[person][side] = await self._block_side(person, side, target, domains)
            self._save()
            return out

    async def _block_side(
        self, person: str, side: str, target: dict[str, str], domains: list[str]
    ) -> dict[str, Any]:
        result: dict[str, Any] = {"done": [], "already": [], "failed": []}
        if not self._usable(side):
            result["failed"] = [{"site": d, "error": f"this {side} can't read or change its websites (update it)"} for d in domains]
            return result
        try:
            blocked, listed = await self._read(side, target, person)
        except Exception as err:  # noqa: BLE001 - this side is told as failed; the rest go on
            _LOGGER.warning("Hearth couldn't read %s's websites from %s: %s", person, side, err)
            result["failed"] = [{"site": d, "error": str(err)[:200]} for d in domains]
            return result
        record = self._record(person, side)
        missing: dict[str, list[str]] = {}
        for domain in domains:
            patterns = _patterns(side, domain)
            absent = [p for p in patterns if p not in blocked]
            on_list = [p for p in patterns if p in listed]
            if absent:
                missing[domain] = absent
                continue
            result["already"].append(domain)
            if domain not in record and on_list:
                # The list's: claimed, so the list dropping it doesn't open it
                record[domain] = on_list
        failed = await self._write(side, target, True, [p for absent in missing.values() for p in absent], person)
        for domain, absent in missing.items():
            errors = [failed[p] for p in absent if p in failed]
            done = [p for p in absent if p not in failed]
            on_list = [p for p in _patterns(side, domain) if p in listed]
            mine = sorted(set(record.get(domain) or []) | set(done) | set(on_list))
            if mine:
                record[domain] = mine
            if errors:
                result["failed"].append({"site": domain, "error": errors[0]})
            else:
                result["done"].append(domain)
        if result["failed"]:
            _LOGGER.warning("Hearth couldn't block %s for %s in %s: %s", [f["site"] for f in result["failed"]], person, side, result["failed"][0]["error"])
        return result

    async def unblock(self, people: list[str], domains: list[str]) -> dict[str, Any]:
        """Takes back Hearth's hand blocks of [domains]: {person: {side: {done, already, kept, failed}}}."""
        async with self.lock:
            out: dict[str, Any] = {}
            for person in people:
                out[person] = {}
                for side, target in self.targets(person).items():
                    out[person][side] = await self._unblock_side(person, side, target, domains)
            self._save()
            return out

    async def _unblock_side(
        self, person: str, side: str, target: dict[str, str], domains: list[str]
    ) -> dict[str, Any]:
        result: dict[str, Any] = {"done": [], "already": [], "kept": [], "failed": []}
        if not self._usable(side):
            result["failed"] = [{"site": d, "error": f"this {side} can't read or change its websites (update it)"} for d in domains]
            return result
        try:
            blocked, listed = await self._read(side, target, person)
        except Exception as err:  # noqa: BLE001 - this side is told as failed; the rest go on
            _LOGGER.warning("Hearth couldn't read %s's websites from %s: %s", person, side, err)
            result["failed"] = [{"site": d, "error": str(err)[:200]} for d in domains]
            return result
        record = self._record(person, side)
        remove: dict[str, list[str]] = {}
        others: dict[str, list[str]] = {}
        for domain in domains:
            patterns = _patterns(side, domain)
            blocked_now = [p for p in patterns if p in blocked]
            mine = record.get(domain)
            if any(p in listed for p in blocked_now):
                # The list's: it stays, and goes when the list drops it
                record.pop(domain, None)
                result["kept"].append({"site": domain, "reason": ON_LIST})
                continue
            if mine is None:
                if blocked_now:
                    result["kept"].append({"site": domain, "reason": OUTSIDE})
                else:
                    result["already"].append(domain)
                continue
            theirs = [p for p in blocked_now if p not in mine]
            ours = [p for p in mine if p in blocked]
            if not ours:
                # Removed meanwhile (in the provider's app): nothing of Hearth's left
                record.pop(domain, None)
                if theirs:
                    result["kept"].append({"site": domain, "reason": OUTSIDE})
                else:
                    result["already"].append(domain)
                continue
            remove[domain] = ours
            others[domain] = theirs
        failed = await self._write(side, target, False, [p for ours in remove.values() for p in ours], person)
        for domain, ours in remove.items():
            errors = [failed[p] for p in ours if p in failed]
            if errors:
                # Still Hearth's: only what was removed is let go
                record[domain] = [p for p in ours if p in failed]
                result["failed"].append({"site": domain, "error": errors[0]})
                continue
            record.pop(domain, None)
            result["done"].append(domain)
            if others[domain]:
                # Family Link: a parent's own *.example.com (or example.com) next to Hearth's
                result["kept"].append({"site": domain, "reason": OUTSIDE, "patterns": others[domain]})
        return result

    # The daily list (schedule.py)

    async def at_risk(self, person: str, side: str, target: dict[str, str]) -> dict[str, list[str]]:
        """Before a provider's own sync_site_list: the hand-blocked patterns the list added too, which the sync takes
        out when the list drops them. Empty (without a read) when the kid has no hand blocks on that side."""
        record = (self.owned.get(person) or {}).get(side) or {}
        if not record or not self._usable(side):
            return {}
        try:
            _blocked, listed = await self._read(side, target, person)
        except Exception as err:  # noqa: BLE001 - the sync goes on; told in the log
            _LOGGER.warning("Hearth couldn't read %s's websites from %s before the website list: %s", person, side, err)
            return {}
        out = {d: [p for p in patterns if p in listed] for d, patterns in record.items()}
        return {d: patterns for d, patterns in out.items() if patterns}

    async def restore(self, person: str, side: str, target: dict[str, str], at_risk: dict[str, list[str]]) -> list[str]:
        """After the sync: blocks again what it took out of a hand block. The domains blocked again."""
        if not at_risk:
            return []
        try:
            blocked, _listed = await self._read(side, target, person)
        except Exception as err:  # noqa: BLE001 - told in the log
            _LOGGER.warning("Hearth couldn't read %s's websites from %s after the website list: %s", person, side, err)
            return []
        gone = {d: [p for p in patterns if p not in blocked] for d, patterns in at_risk.items()}
        gone = {d: patterns for d, patterns in gone.items() if patterns}
        if not gone:
            return []
        failed = await self._write(side, target, True, [p for patterns in gone.values() for p in patterns], person)
        if failed:
            _LOGGER.warning(
                "Hearth couldn't block again %s's hand-blocked sites the website list dropped in %s: %s",
                person, side, ", ".join(sorted(failed)),
            )
        again = sorted(d for d, patterns in gone.items() if not any(p in failed for p in patterns))
        if again:
            _LOGGER.info("Blocked again for %s in %s (blocked by hand, dropped by the website list): %s", person, side, again)
        return again
