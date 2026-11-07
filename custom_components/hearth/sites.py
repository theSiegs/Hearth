"""hearth.copy_sites: the websites a kid has blocked (or allowed) in Family Link copied to Family Safety, the other way
round, or both (docs/home-assistant-integration.md, Copy websites).

Both sides are read with their get_sites. A site is compared by its host: lowercase, without a scheme, a leading
"www." or "*.", or a trailing slash, so Family Link's "*.example.org" and Family Safety's "https://example.org/" are the
same site. Copying only ever adds:

- a pattern with a path (example.org/games), or another wildcard (*.example.*), isn't copied ("not_copyable"):
  turning it into a whole site would widen it;
- a site either side's website list sync added (from_list) is left to that sync ("skipped_from_list");
- a site blocked on one side and allowed on the other is left as it is on both ("conflicts").

A blocked site goes to Family Link as its own list sync writes a domain (*.example.org and example.org), an allowed one
as the site only (example.org: an approval isn't widened to every subdomain). Family Safety takes the host.
"""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.core import HomeAssistant

from .enforce import FAMILY_LINK, FAMILY_SAFETY, FS_DOMAIN, enforcers_from_options

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
BLOCKED = "blocked"
ALLOWED = "allowed"
BOTH = "both"
SIDES = (FAMILY_LINK, FAMILY_SAFETY)
FROM_CHOICES = (FAMILY_LINK, FAMILY_SAFETY, BOTH)
LIST_CHOICES = (BLOCKED, ALLOWED, BOTH)
# Family Link calls its allowed list "approved"
_FL_KEYS = {BLOCKED: "blocked", ALLOWED: "approved"}
_FS_KEYS = {BLOCKED: "blocked", ALLOWED: "allowed"}
_OTHER = {BLOCKED: ALLOWED, ALLOWED: BLOCKED}


def host_of(pattern: Any) -> str | None:
    """The site a pattern stands for (example.org), or None when it can't be copied as a whole site: a path, a query,
    a wildcard other than a leading "*.", or not a host at all."""
    text = str(pattern or "").strip().lower()
    if not text or any(c.isspace() for c in text):
        return None
    if "://" in text:
        text = text.split("://", 1)[1]
    text = text.rstrip("/")
    if "/" in text or "?" in text or "#" in text:
        return None
    if text.startswith("*."):
        text = text[2:]
    if text.startswith("www."):
        text = text[4:]
    if "*" in text or "." not in text or text.startswith(".") or text.endswith("."):
        return None
    return text


def _hosts(patterns: Any) -> tuple[set[str], list[str]]:
    """(hosts, patterns that aren't a whole site) of a list."""
    hosts: set[str] = set()
    odd: list[str] = []
    for pattern in patterns or []:
        host = host_of(pattern)
        if host is None:
            odd.append(str(pattern))
        else:
            hosts.add(host)
    return hosts, odd


class CopySites:
    """One hearth.copy_sites call."""

    def __init__(self, hass: HomeAssistant, options: dict[str, Any]) -> None:
        self.hass = hass
        self.targets: dict[str, dict[str, str]] = {}
        for e in enforcers_from_options(options):
            if e.kind in SIDES:
                self.targets.setdefault(e.person, {})[e.kind] = e.entity_id

    def people_with_both(self) -> list[str]:
        return sorted(p for p, sides in self.targets.items() if all(s in sides for s in SIDES))

    def _fs_target(self, entity_id: str) -> dict[str, str]:
        return {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}

    async def _read(self, side: str, entity_id: str) -> dict[str, Any]:
        if side == FAMILY_LINK:
            domain, data = FL_DOMAIN, {"entity_id": entity_id}
        else:
            domain, data = FS_DOMAIN, self._fs_target(entity_id)
        response = await self.hass.services.async_call(domain, "get_sites", data, blocking=True, return_response=True)
        return response if isinstance(response, dict) else {}

    async def _write(self, side: str, entity_id: str, kind: str, hosts: list[str]) -> None:
        if side == FAMILY_LINK:
            if kind == BLOCKED:
                # As Family Link's own list sync writes a domain: the site and its subdomains
                sites = [p for host in hosts for p in (f"*.{host}", host)]
            else:
                sites = list(hosts)
            service = "block_site" if kind == BLOCKED else "allow_site"
            await self.hass.services.async_call(
                FL_DOMAIN, service, {"entity_id": entity_id, "sites": sites}, blocking=True
            )
            return
        service = "block_website" if kind == BLOCKED else "allow_website"
        await self.hass.services.async_call(
            FS_DOMAIN, service, {**self._fs_target(entity_id), "website": list(hosts)}, blocking=True
        )

    async def person(self, person: str, source: str, lists: str, dry_run: bool) -> dict[str, Any]:
        sides = self.targets.get(person, {})
        missing = [s for s in SIDES if s not in sides]
        missing += [
            s
            for s, domain in ((FAMILY_LINK, FL_DOMAIN), (FAMILY_SAFETY, FS_DOMAIN))
            if s in sides and not self.hass.services.has_service(domain, "get_sites")
        ]
        if missing:
            # Configure > Enforce has no such side for them, or that integration can't read its lists (too old)
            return {"missing": sorted(set(missing))}
        read: dict[str, dict[str, Any]] = {}
        for side in SIDES:
            try:
                read[side] = await self._read(side, sides[side])
            except Exception as err:  # noqa: BLE001 - told in the answer, the other people go on
                _LOGGER.warning("Hearth couldn't read %s's websites from %s: %s", person, side, err)
                return {"error": f"{side}: {str(err)[:200]}"}
        keys = {FAMILY_LINK: _FL_KEYS, FAMILY_SAFETY: _FS_KEYS}
        hosts: dict[str, dict[str, set[str]]] = {}
        odd: dict[str, dict[str, list[str]]] = {}
        from_list: set[str] = set()
        for side in SIDES:
            hosts[side], odd[side] = {}, {}
            for kind in (BLOCKED, ALLOWED):
                hosts[side][kind], odd[side][kind] = _hosts(read[side].get(keys[side][kind]))
            from_list |= _hosts(read[side].get("from_list"))[0]
        sources = SIDES if source == BOTH else (source,)
        kinds = (BLOCKED, ALLOWED) if lists == BOTH else (lists,)
        add: dict[str, dict[str, set[str]]] = {side: {kind: set() for kind in kinds} for side in SIDES}
        skipped: set[str] = set()
        conflicts: dict[str, dict[str, str]] = {}
        not_copyable: list[dict[str, str]] = []
        for side in sources:
            other = FAMILY_SAFETY if side == FAMILY_LINK else FAMILY_LINK
            for kind in kinds:
                not_copyable += [{"site": p, "from": side, "list": kind} for p in odd[side][kind]]
                for host in sorted(hosts[side][kind]):
                    if host in hosts[other][kind]:
                        continue
                    if host in from_list:
                        skipped.add(host)
                    elif host in hosts[other][_OTHER[kind]]:
                        conflicts[host] = {side: kind, other: _OTHER[kind]}
                    else:
                        add[other][kind].add(host)
        # A site blocked on one side and allowed on the other is a conflict, whichever way it would go
        for kind in kinds:
            for side in SIDES:
                add[side][kind] -= set(conflicts)
        result: dict[str, Any] = {
            "added_to_fl": {kind: sorted(add[FAMILY_LINK][kind]) for kind in kinds},
            "added_to_fs": {kind: sorted(add[FAMILY_SAFETY][kind]) for kind in kinds},
            "skipped_from_list": sorted(skipped),
            "conflicts": [{"site": host, **sides_of} for host, sides_of in sorted(conflicts.items())],
            "not_copyable": not_copyable,
        }
        if dry_run:
            return result
        errors: list[str] = []
        for side in SIDES:
            for kind in kinds:
                chosen = sorted(add[side][kind])
                if not chosen:
                    continue
                try:
                    await self._write(side, sides[side], kind, chosen)
                except Exception as err:  # noqa: BLE001 - told in the answer, the rest goes on
                    _LOGGER.warning("Hearth couldn't add %s's %s websites to %s: %s", person, kind, side, err)
                    errors.append(f"{side} {kind}: {str(err)[:200]}")
                    result["added_to_fl" if side == FAMILY_LINK else "added_to_fs"][kind] = []
        if errors:
            result["error"] = "; ".join(errors)
        return result
