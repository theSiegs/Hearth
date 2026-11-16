"""The website block list (Configure > Website block list) kept in a kid's Microsoft Family Safety by Hearth itself.

A Family Safety that has sync_site_list (a fork's) does it alone (schedule.py hands it the list's address). The
released one (upstream's 2.3.0) hasn't, but has get_sites, block_website and remove_website, so Hearth does what that
service did:

- The list is downloaded once per daily run, from the address an adult typed in Configure (https only, no redirects,
  at most MAX_LIST_BYTES) and read as plain text, one domain per line, "#" comments allowed (a hosts-file line such as
  "0.0.0.0 example.com" gives its last word). Anything that isn't a plain domain (an address, a path, a
  country-wide suffix such as co.uk) is ignored.
- Each kid's blocked and allowed websites are read with get_sites (Microsoft's absolute URLs, compared by host).
- Listed domains not blocked yet are blocked with block_website (one call with the list). A domain that shares a site
  with one the kid is allowed is left out: blocking it would block the allowed site.
- Only domains Hearth itself blocked from this list for this kid earlier, and that the list has since dropped, are
  unblocked, with remove_website (allow_website would put them on the allowed list instead, which nobody asked for).
  What Hearth added is kept in Hearth's storage per kid and list (Scheduler's store, so it survives a restart); a site
  someone removed by hand meanwhile isn't Hearth's any more, and sites Hearth didn't add are never touched. A fork's
  own record of what its sync_site_list added (microsoft_family_safety.site_sync.<entry>) is taken over the first time
  Hearth syncs that list for that kid, so a switch from the fork to the release doesn't strand them.
- Upstream's block_website and remove_website try every site and, when any fails, fail naming the sites done and the
  sites failed (each with Microsoft's error). Hearth reads that answer: the done ones count, the failed ones are
  reported per site (and tried again the next day, as only what was done is recorded).

Nothing changes when the download fails or has no usable domain (an emptied file or an error page would otherwise
read as a list that dropped everything), when the list has more than MAX_DOMAINS, when Microsoft's answer has lost
every site the list added (looks incomplete), or when the list would take back more than half of what it added (looks
cut short).
"""

from __future__ import annotations

import logging
import re
from typing import Any
from urllib.parse import urlsplit

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.storage import Store

from .enforce import FS_DOMAIN

_LOGGER = logging.getLogger(__name__)

# Upstream's services Hearth's own sync needs
SERVICES = ("get_sites", "block_website", "remove_website")
# A list is read up to this size, and pushed only up to this many domains
MAX_LIST_BYTES = 1024 * 1024
MAX_DOMAINS = 2000
# A sync takes back at most half of what its list added, or this many if that's more
REMOVE_FLOOR = 20
DOWNLOAD_TIMEOUT = 60
# The fork's record of what its sync_site_list added (taken over once)
FORK_STORE = f"{FS_DOMAIN}.site_sync"

_LABEL = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
_HOST = re.compile(rf"^(?=.{{1,253}}$){_LABEL}(?:\.{_LABEL})+$")
_IPV4 = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")
# A second-level public suffix (co.uk, com.au): blocking one would block a country's sites. Best effort
_SUFFIX = re.compile(r"^(?:ac|co|com|edu|gov|net|or|org)\.[a-z]{2}$")
# Upstream's answer when a site failed: "... Done: a, b. Failed: c (error); d (error)"
_DONE = re.compile(r"Done: (.*?)\. Failed: (.*)$", re.DOTALL)


class SiteListError(HomeAssistantError):
    """The list couldn't be used, or Microsoft's lists couldn't be trusted: nothing was changed."""


def available(hass: HomeAssistant) -> bool:
    """Hearth can keep the list itself through this Family Safety (it has get_sites, block and remove)."""
    return all(hass.services.has_service(FS_DOMAIN, s) for s in SERVICES)


async def fetch(hass: HomeAssistant, url: str) -> str:
    """The list at [url] (https only, redirects not followed, at most MAX_LIST_BYTES)."""
    import aiohttp

    if urlsplit(url).scheme != "https":
        raise SiteListError(f"The website list {url} isn't an https address.")
    too_large = f"The website list {url} is larger than {MAX_LIST_BYTES // 1024} KiB."
    body = bytearray()
    try:
        async with async_get_clientsession(hass).get(
            url, timeout=aiohttp.ClientTimeout(total=DOWNLOAD_TIMEOUT), allow_redirects=False
        ) as resp:
            if 300 <= resp.status < 400:
                raise SiteListError(f"The website list {url} redirects elsewhere; give its final https address.")
            if resp.status != 200:
                raise SiteListError(f"The website list {url} answered HTTP {resp.status}.")
            declared = resp.headers.get("Content-Length", "")
            if declared.isdigit() and int(declared) > MAX_LIST_BYTES:
                raise SiteListError(too_large)
            async for chunk in resp.content.iter_chunked(64 * 1024):
                body.extend(chunk)
                if len(body) > MAX_LIST_BYTES:
                    raise SiteListError(too_large)
    except SiteListError:
        raise
    except Exception as err:  # noqa: BLE001 - told as the list's failure
        raise SiteListError(f"Couldn't download the website list {url}: {err}") from err
    # utf-8-sig: a byte order mark would otherwise stick to the first domain
    return body.decode("utf-8-sig", errors="replace")


def parse(text: str, ignored: list[str] | None = None) -> list[str]:
    """Plain domains from a one-per-line list, in order, once each; anything else goes to [ignored]."""
    domains: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        token = body.split()[-1].lower().rstrip(".")
        if token in seen:
            continue
        seen.add(token)
        if _HOST.match(token) and not _IPV4.match(token) and not _SUFFIX.match(token):
            domains.append(token)
        elif ignored is not None:
            ignored.append(token)
    return domains


def site_host(value: Any) -> str | None:
    """"https://www.example.com/path" -> "www.example.com" (Microsoft keeps absolute URLs); None if empty."""
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if "://" in text:
        text = text.split("://", 1)[1]
    host = text.split("/", 1)[0].split(":", 1)[0].lower().rstrip(".")
    return host.removeprefix("*.") or None


def _within(host: str, domain: str) -> bool:
    return host == domain or host.endswith("." + domain)


def allowed_overlaps(allowed: str, domain: str) -> bool:
    """Blocking [domain] would hit a site the kid is allowed (example.com while www.example.com is allowed, or the
    other way round)."""
    return _within(allowed, domain) or _within(domain, allowed)


def split_failure(err: Exception, sites: list[str]) -> tuple[list[str], dict[str, str]]:
    """(done, {site: error}) from upstream's failed block_website / remove_website, which names both. Read as all
    failed with the whole message when it doesn't."""
    message = str(err)
    found = _DONE.search(message)
    if found is None:
        return [], {site: message[:200] for site in sites}
    done_text, failed_text = found.groups()
    done = [] if done_text.strip() == "none" else [s.strip() for s in done_text.split(",") if s.strip()]
    failed: dict[str, str] = {}
    for part in failed_text.split("; "):
        part = part.strip()
        if not part:
            continue
        site, _, error = part.partition(" (")
        failed[site.strip()] = error.rstrip(")").strip()[:200] or message[:200]
    # A site sent but named on neither side (the message cut short): failed, with the whole message
    for site in sites:
        if site not in done and site not in failed:
            failed[site] = message[:200]
    return [s for s in done if s in sites], failed


class FsSiteList:
    """What Hearth blocked from website lists in Family Safety: {account: {url: [domains]}}, in [owned] (the
    Scheduler keeps it with its store; [save] asks it to)."""

    def __init__(self, hass: HomeAssistant, owned: dict[str, dict[str, list[str]]], save) -> None:
        self.hass = hass
        self.owned = owned
        self._save = save

    async def _fork_record(self, account: str, url: str) -> set[str]:
        """What a fork's sync_site_list recorded as added for this kid and list (empty when there's none)."""
        found: set[str] = set()
        for entry in self.hass.config_entries.async_entries(FS_DOMAIN):
            try:
                data = await Store(self.hass, 1, f"{FORK_STORE}.{entry.entry_id}").async_load() or {}
            except Exception:  # noqa: BLE001 - another version's store: nothing to take over
                continue
            listed = (data.get(account) or {}).get(url) if isinstance(data, dict) else None
            if isinstance(listed, list):
                found |= {str(d) for d in listed}
        return found

    async def _call(self, service: str, target: dict[str, str], sites: list[str]) -> tuple[list[str], dict[str, str]]:
        """block_website / remove_website for [sites]: (done, {site: error})."""
        if not sites:
            return [], {}
        try:
            await self.hass.services.async_call(FS_DOMAIN, service, {**target, "website": list(sites)}, blocking=True)
        except Exception as err:  # noqa: BLE001 - per site, as upstream answers
            return split_failure(err, sites)
        return list(sites), {}

    async def sync(self, target: dict[str, str], account: str, url: str, domains: list[str]) -> dict[str, Any]:
        """Brings the kid's blocked websites in step with the list's [domains]. What was added, removed, kept,
        skipped (allowed) and failed (site, error). Raises SiteListError when nothing was changed for a reason."""
        if not domains:
            raise SiteListError(f"The website list {url} has no usable domains, so nothing was changed.")
        if len(domains) > MAX_DOMAINS:
            raise SiteListError(f"The website list has {len(domains)} domains, more than {MAX_DOMAINS}.")
        response = await self.hass.services.async_call(
            FS_DOMAIN, "get_sites", dict(target), blocking=True, return_response=True
        )
        if not isinstance(response, dict) or not isinstance(response.get("blocked"), list):
            raise SiteListError("Family Safety's get_sites gave no blocked websites, so nothing was changed.")
        blocked = {h for h in map(site_host, response.get("blocked") or []) if h}
        allowed = {h for h in map(site_host, response.get("allowed") or []) if h}
        lists = self.owned.setdefault(account, {})
        if url not in lists:
            lists[url] = sorted(await self._fork_record(account, url))
        mine = set(lists[url])
        if mine and not blocked:
            raise SiteListError(
                f"Microsoft gave no blocked websites although the list added {len(mine)} for this kid; the answer "
                "looks incomplete, so nothing was changed."
            )
        wanted: list[str] = []
        skipped: list[str] = []
        for domain in domains:
            (skipped if any(allowed_overlaps(a, domain) for a in allowed) else wanted).append(domain)
        insert = [d for d in wanted if d not in blocked]
        kept = [d for d in wanted if d in blocked]
        remove = [d for d in sorted(mine - set(wanted)) if d in blocked]
        if len(remove) > max(REMOVE_FLOOR, len(mine) // 2):
            raise SiteListError(
                f"Hearth won't unblock {len(remove)} of the {len(mine)} sites the list added: it looks cut short. "
                "Nothing was changed."
            )
        # Sites the list added that are gone from Microsoft's (removed by hand) aren't Hearth's any more
        mine &= blocked
        added, failed = await self._call("block_website", target, insert)
        mine |= set(added)
        lists[url] = sorted(mine)
        self._save()
        removed, failed_remove = await self._call("remove_website", target, remove)
        mine -= set(removed)
        lists[url] = sorted(mine)
        self._save()
        failed.update(failed_remove)
        _LOGGER.info(
            "Website list for %s: added %d, removed %d, kept %d, left %d allowed, %d failed",
            account, len(added), len(removed), len(kept), len(skipped), len(failed),
        )
        return {
            "domains": len(domains),
            "added": added,
            "removed": removed,
            "kept": len(kept),
            "skipped_allowed": skipped,
            "failed": [{"site": site, "error": error} for site, error in failed.items()],
            "attempted": len(insert) + len(remove),
        }
