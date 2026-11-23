# Hearth TV contract

Owner: Hearth (the Home Assistant integration, `custom_components/hearth`), because it is the server. This page is the
contract between it and Hearth TV (the Google TV app, [theSiegs/HearthTV](https://github.com/theSiegs/HearthTV)):
every call between the two, what each side sends and reads, and what each does without the other. It is an inventory
of the code on both sides as of 2026.11.53, not a design. The generic device API that any client relies on is
[device-api.md](device-api.md) (contract 3); where this page overlaps it, it links there instead of repeating it.

**A change to this contract needs this page and both contract tests updated together:**
`ha_tests/test_hearth_tv_contract.py` (here) and the fixture test in Hearth TV
(`android/app/src/test/java/com/thesiegs/hearth/TvStateDocumentFixtureTest.java`). Both read the same fixture,
`contract_fixtures/tv_state_document.json`, which is kept in both repos (here `ha_tests/contract_fixtures/`, in Hearth
TV `android/app/src/test/resources/contract_fixtures/`). **The two copies must stay identical.**

Citations: `HA:` paths are in this repo under `custom_components/hearth/`. `TV:` paths are in Hearth TV under
`android/app/src/main/java/com/thesiegs/hearth/` (and `lib/` for Flutter). Line numbers are as of 2026.11.53.

TV-side docs that belong with this page (they live in Hearth TV):
[tv-remote-api.md](https://github.com/theSiegs/HearthTV/blob/master/docs/tv-remote-api.md) (phones talking to a TV),
[household-sync.md](https://github.com/theSiegs/HearthTV/blob/master/docs/household-sync.md) (TV-to-TV sync),
[provider-contract.md](https://github.com/theSiegs/HearthTV/blob/master/docs/provider-contract.md) (HearthTube reading
Hearth TV), [pin-recipes.md](https://github.com/theSiegs/HearthTV/blob/master/docs/pin-recipes.md) (streaming-app PIN
screens).

## The state document

<!-- hearth-tv-contract:state-document -->
```text
contract: 3
always: profiles youtube_blocks commands people version contract
optional: adult_phones notices parent_pins_version parent_pins client_settings
```
<!-- /hearth-tv-contract:state-document -->

The block above is read by `ha_tests/test_hearth_tv_contract.py`: `contract` must be `const.CONTRACT`, a TV's document
must carry every `always` key and no key outside the two lists, and the shared fixture's `document` must carry exactly
the listed keys. Keep its format (`name: word word ...`) and its two markers.

A TV gets its state document as `state` in every status answer (`POST .../status`, below). It is built by
`Household.document_for` (HA: household.py:2068-2132).

| Key | When | What | TV reads it |
|---|---|---|---|
| `profiles` | always | `{profile_id: person document}` for each profile in this status's `usage_today` or `profile_id` that is mapped to a person (household.py:2078-2083). Person document below | yes (TV: HaAllowance.java:219-302) |
| `youtube_blocks` | always | `{profile_id: {videos, channels, words, labels}}` for every mapped profile (household.py:2086-2090; watch.py:214-225) | yes (TV: ParentBlocks.java:155-183) |
| `commands` | always | one-shot commands (`hearth.play_on_tv`) for this TV (household.py:2093; commands.py:126-128) | **no**: the TV doesn't declare `commands.play` (TV: HaStatusReporter.java:56-59) |
| `people` | always | `{profile_id: person}` for the mapped profiles (household.py:2096) | yes (TV: HaAllowance.java:138-164) |
| `adult_phones` | an adult profile's person has a companion app | `{profile_id: [notify service]}` (household.py:2101-2102, 2134-2144) | yes (TV: PhoneApproval.java:155-162) |
| `notices` | the TV declared cap `notices` | attention items for TVs, `[{key, tag, title, message, urgency, actions[{id, title}], for?, expires?}]` (household.py:2105-2106; attention.py:121-136) | yes (TV: HaNotices.java:72-102) |
| `parent_pins_version` | some adult has a Parent PIN | hash of the list below (household.py:2110-2121) | yes, and sent back in the status |
| `parent_pins` | as above, and the TV's `parent_pins_version` differs | `[{person, name, hash, profiles}]`, salted hashes, never a PIN (household.py:2111-2123) | yes (TV: HaParentPins.java:47-73) |
| `client_settings` | the TV paired with a `client` (contract 3) | `{"<scope>/<name>": etag}` ([client-settings.md](client-settings.md); household.py:2128-2129) | no |
| `version` | always | 16 hex characters of the document's hash; the long poll compares it (household.py:2130) | yes (TV: HaStatusReporter.java:630) |
| `contract` | always | `const.CONTRACT`, now 3 (household.py:2131; const.py:11) | **no**, never checked |

**Each person document** (`profiles[<id>]`, HA: household.py:1903-1973; the full meaning is in
[device-api.md](device-api.md) and [time-model.md](time-model.md)): `person`, `groups[]` (`id`, `name`,
`minutes_left`, `apps`, `except`, `closed`, and paused or closed groups), `time`, `locked`, `lock`, `pause`,
`bedtime_lifted`, `next_lock`, `never_held`, `never_paused`, `playing`, `schedule`, `share_app_data` (always false),
`todo`, `request` (the latest ask, asks.py:122-133), `youtube_blocks`, `allow_ends`, and for a stretch without Home
Assistant `lifts` and `tomorrow`. What a TV makes of each moment is pinned by the shared fixture's `moments`
(`ha_tests/test_client_contract.py` here, `TvStateDocumentFixtureTest` there).

## Pairing and tickets

Endpoints are in HA: api.py; the TV calls them from TV: HaIntegration.java. All take only local addresses (`not_local`
otherwise). The device secret goes in `X-Hearth-Secret`.

| Call | HA | TV |
|---|---|---|
| `POST /api/hearth/pair` `{device_id, kind: "tv", name, model, version, nonce, client}` -> `{pairing_id, code, expires_in, approvers}` | api.py:111-187 | HaIntegration.java:141-163 (from Flutter `startHaPairing`, MainActivity.java:705-718) |
| `GET /api/hearth/pair/<id>` (`X-Hearth-Nonce`) -> `pending`, `denied`, or once `approved` with `device_id, secret, urls, person, role, push, client, contract` | api.py:190-242 | HaIntegration.java:169-193 |
| `POST /api/hearth/device/<id>/ticket` `{kind: "tv"}` or `{kind: "mobile", person}` (a paired TV vouches; single use, 5 min) | api.py:245-279; const.py:33-34 | HaIntegration.java:199-217, used by Household.haRound (Household.java:418-436) |
| `POST /api/hearth/pair/redeem` `{ticket, device_id, kind, name, model, version, client}` -> the approved answer | api.py:282-321 | HaIntegration.java:228-266 (a refusal: not ticketed again for 1 h) |

The TV sends `client` `{id: "com.thesiegs.hearth", version, contract: 3}` with no companions (TV:
HaIntegration.java:592-602; [device-api.md, `client`](device-api.md#client)). Codes, approvers and who may approve:
[device-api.md](device-api.md#pairing-who-is-asked-and-confirming-your-own-phone-additive-within-contract-3).

"Home Assistant once": a paired TV writes household-sync entries `ha_state` (paired or left) and `ha_ticket`, and the
other TVs of the household redeem tickets with no code (TV: HouseholdHa.java; Household.java:377-463). A TV unpaired
on purpose or removed in Home Assistant sets `ha_integration_left` and isn't paired again that way
(HouseholdHa.java:49-63).

**Unpairing.** Home Assistant answers 401 `not_paired` to a device it doesn't know (api.py, every device view). The
TV unpairs itself only after 401s that keep coming for 10 minutes (gaps of at most 5 minutes), because Home Assistant
answers 401 for a moment while it restarts (TV: HaIntegration.java:42-49, 344-358). It then clears its secret, sets
`ha_integration_left` and forgets the YouTube blocks Home Assistant set (HaIntegration.java:268-288, 558-566). 404,
503, 429 and network failures never unpair.

## Posts from the TV

### Status

`POST /api/hearth/device/<id>/status` (HA: api.py:345-383; cleaned by status.py:137-177, unknown fields dropped; at
most 64 KB and 20 posts a minute, const.py:41-45). The TV builds it in TV: HaStatusReporter.java:367-481 and sends it
1.5 s after a change (foreground app, media session, screen, lock, profile), every 2 minutes as a heartbeat, after an
ask, after the long poll says changed, and at start (HaStatusReporter.java:44-152, 276-280).

What the TV sends: `screen`, `state`, `app`, `app_package`, `profile`, `profile_id`, `profile_ref`, `kids_profile`,
`profiles` (`{key: {name, ref, kids}}`), `day` (the TV's own date), `seconds_today`, `app_seconds_today`,
`playing_seconds_today`, `usage_today` (per profile: `seconds`, `apps`, `playing`, `profile_name`, `profile_ref`),
`allowed_apps`, `app_categories`, `screen_time_*` (Google TV's own screen-time screen), `media_*`,
`now_playing_available`, `pin_lockouts`, `parent_pins_version`, `checks` (`[{id: "accessibility", ok, label}]`),
`caps`, `client`, and `local_rules` until each profile's are taken. It does not send `utc_offset_minutes`,
`commands_done` or `contract` at the top level.

The answer: `{ok, contract, state, day, clock_off?, local_rules_taken?, push?}` (api.py:368-383). The TV reads `state`
and `local_rules_taken` only (TV: HaStatusReporter.java:625-649); `state` replaces its stored copy whole, no merging
(HaAllowance.java:205-209). Counts, Hearth's day and `clock_off`: [device-api.md, Hearth's day](device-api.md#hearths-day-additive-within-contract-3).

`local_rules`: `{profile_id: {all: {weekday, weekend}, groups: [{id, weekday, weekend}]}}` (HA: status.py:204-224).
Home Assistant takes them once per TV and profile as a kid's first budgets, only when the kid has none yet, and says
so in `local_rules_taken` (HA: hub.py:434-435; household.py:3363-3391; limits.py:720-742; api.py:376-378). The TV
stops sending a profile's rules once it is listed (TV: LocalAllowance.java:79-94).

### Asks, PIN events, playing

| Call | HA | TV |
|---|---|---|
| `POST .../ask` `{minutes: 15/30/45/60, group, note?, profile_id}` -> `{ok, request}`; 409 `already_open`, 429 `cooldown`, 404 `no_person`. The answer arrives as the person document's `request` | api.py:594-641 | HaIntegration.java:519-550 (MainActivity.java:683-699; RemoteTv.java:461-466) |
| `POST .../verify_pin` `{pin}` -> `{ok, person, grant, ...}`; one lockout shared with `notice` | api.py:428-513 | HaIntegration.java:399-416; a failure to reach Home Assistant falls back to the kept hashes (HaParentPins.java:127-138); `grant` isn't read |
| `POST .../notice` `{key, action, pin}` or `{key, action, approval: "phone"}` | api.py:516-591 | HaIntegration.java:423-432; HaNotices.java:301-310 |
| `POST .../switch_approval` `{profile_id, phone?}`, `GET`/`DELETE .../switch_approval/<id>` | api.py:644-737 | HaIntegration.java:460-508; PhoneApproval.java:324-383 (404 without an error: falls back to the panel token) |
| `POST .../events` `{events: [{type: "video_started", profile_id, t, v, title, ch, cid, pa?}]}` (HearthTube's starts in kids profiles) | api.py:386-425 | HaIntegration.java:301-330, after each good status |
| PIN lockouts: status `pin_lockouts` (only goes up) | status.py:53-54 | HaStatusReporter.java |
| Playing: status `state`, `media_*`, `playing_seconds_today` | status.py:22-56; household.py:3394 | HaStatusReporter.java |

The settings (`.../settings/<scope>/<name>`) and `end_grant` endpoints exist for every client
([client-settings.md](client-settings.md)); Hearth TV doesn't call them.

## Capabilities

The TV declares `caps: ["events", "notices"]` (TV: HaStatusReporter.java:56-59). Home Assistant knows `commands.play`,
`events`, `push`, `notices` and drops others (HA: const.py:67-71; status.py:179-184). A device that never sent `caps`
gets its kind's defaults, for a TV `commands.play` and `events` (const.py:74-82; hub.py:318-324). The TV leaves out
`commands.play` on purpose: it doesn't run `commands`, so `hearth.play_on_tv` is refused for it instead of expiring.

## Pushes and pings

- **Long poll** (the only push to a TV): `GET .../wait?version=<v>&timeout=<s>` -> `{changed}`, held at most 55 s
  (HA: api.py:740-780; wait.py:1-31). Pairings, people, watch, notices and commands wake it. The TV holds one while
  paired and its screen is on (timeout 50), posts its status on `changed: true`, asks again at once on `false`,
  retries in 30 s on an error and in 10 min on 404 (TV: HaStatusReporter.java:81-89, 211-263; HaIntegration.java:371-393).
- **ntfy push** (`push` cap) is for phones only; the TV doesn't declare it (HA: push.py).

## Home Assistant -> TV

Home Assistant never calls the TV. Everything reaches it through the state document of a status answer, woken by the
long poll.

The TV's local port 7676 (TV: HaNotificationServer.java:20-34, 128-160: `msg`, `title`, `duration`, `camera`,
`actions`, `for`, `tag`; local network only, no secret) is **not part of this contract**: the integration never calls
it (no reference in `custom_components/hearth`). It is for a household's own `rest_command`s
([home-assistant.md, Notifications](../home-assistant.md#notifications)); the integration's way is `notices`. Likewise
the TV's panel token calls (`/api/services`, `/api/states`, `/api/websocket` for `mobile_app_notification_action`,
TV: HaApi.java:139-180; HaEventSession.java) use Home Assistant's own API, not Hearth's.

## Versioning

`contract` goes up only when a field changes meaning or type, becomes required, or goes away; an added field doesn't
change it (HA: const.py:6-11; [home-assistant-integration.md, Contract](../home-assistant-integration.md#contract)).

| | Home Assistant | Hearth TV |
|---|---|---|
| Says its version | `contract` in the approved pair answer, every status answer and every state document | `client.contract: 3` in the pair body and status |
| A newer peer | drops unknown status fields and caps (status.py:137-184) | ignores unknown fields (reads with `opt*`) |
| An older peer | a TV with no `caps` gets its kind's defaults; with no `client`, no client settings | an older Home Assistant without `tomorrow` or `lifts`: falls back to today's base minutes (HaAllowance.java:685-686) |
| Checks the other's number | stores it for display only (status.py:55-56) | **never** checks `contract` |

## Without Home Assistant

The owner's decision (2026-11-10): the TV has its own rules, synced TV-to-TV; once paired, Home Assistant wins outright
and the TV keeps the last rules while Home Assistant is offline; the first pairing imports the TV's rules; without
Home Assistant a kid's minutes are shared across TVs.

The switch is `LocalAllowance.homeAssistantDecides` = paired (TV: LocalAllowance.java:44-48): paired, the TV never uses
its own rules, online or not; unpaired, it does (HaAllowance.forProfile/entryFor, HaAllowance.java:398-416). The last
word is Home Assistant's whole document, kept in preferences with no expiry (HaAllowance.java:183-210). After 10
minutes with no word the TV counts down itself (`STALE_AFTER_MS`, `staleCountdown`, HaAllowance.java:446-518).

| | Never paired | Paired, Home Assistant unreachable | Conflict |
|---|---|---|---|
| Budgets and counts | The TV's rules (`LocalRules`: All screen time and groups, weekday/weekend minutes) (TV: LocalRules.java:52-108). Minutes used = this TV's time in front plus the other TVs' household `usage` entries, published every 2 min, kept 3 days (LocalAllowance.java:146-153; Household.java:44, 526-564; HouseholdUsage.java:34-58) | Last document kept, no time limit. After 10 min the TV counts its own time in front down from the last `minutes_left`; lifts end at `until` + 3 min (HaAllowance.java:561-616); a new day starts from `tomorrow`'s minutes (`carriedOver`, HaAllowance.java:746-797). Other TVs' time isn't counted. On return the TV posts its cumulative `usage_today`; Home Assistant's count (never down within its day) is the new word | Paired: Home Assistant outright. Never paired: rules newest-wins between TVs, usage summed |
| Bedtime | Local `bedtime` {from, to, days} gives `lock`/`next_lock` `by: "hearth"` (LocalRules.java:94-106) | The TV starts `next_lock` itself 3 min after it's due with no word since (Allowance.java:129-147), ends it at `until` or the schedule's wake time (HaAllowance.java:310-333) | Home Assistant |
| School time | none | only as a `next_lock` or `tomorrow.next_lock` Home Assistant named (HaAllowance.java:767-774) | Home Assistant |
| Pauses | none (remote API `hold` refused, RemoteSession.java:368-374) | a `pause` with `until` holds until then; without `until`, until Home Assistant speaks (HaAllowance.java:826-829) | Home Assistant |
| Locks and holds | bedtime only; mid-session hold by the a11y service | as kept: `lock` with `until` until then, without `until` until Home Assistant speaks (HaAllowance.java:757-759) | Home Assistant |
| Asks and approvals | none: no ask is offered (lib/models/ha_lock_state.dart:178-180); remote API asks UNSUPPORTED (RemoteSession.java:358-361, 468-476) | the ask fails `unreachable`; nothing is queued | Home Assistant (first answer wins) |
| Parent PIN | the household's own `parent_pin` hash, synced newest-wins (Household.java:1400-1454; lib/providers/household_parent_pin.dart) | Home Assistant's hashes, kept sealed, check PINs locally (HaParentPins.java:12-22, 127-138) | Home Assistant's hashes replace the TV's while paired |
| Kid profiles and the kids-profile lock | the TV's own (ProfileLock.java, KidsProfiles.java: no Home Assistant dependency) | unchanged | the TV (Home Assistant only maps profiles to people) |
| Notices | only what a household pushes to port 7676 | the last `notices` stay in the Bell until a new document (Household.java:1808-1871) | Home Assistant |
| Household sync between TVs | everything syncs (profiles, PINs, rules, usage) | still syncs; `rules` and `usage` keep being written but aren't used (Household.java:500-547; LocalAllowance.java:111) | per entry kind (newest wins; usage per TV) |

### Gaps

Where the code differs from the decision, or the behaviour is undefined (TV paths as above):

1. **Unpairing falls back to rules that may be stale.** Local rules apply again at once, but they were not edited
   while Home Assistant decided; Home Assistant's last budgets aren't carried back (LocalAllowance.java:44-48;
   Household.java:500-524).
2. **Multi-day outage.** `carriedOver` reuses `tomorrow` for every later day without checking `tomorrow.date`: day 3
   onward gets day 2's minutes and day 2's first lock only (HaAllowance.java:688-736, 746-797). Undefined what a third
   day should be.
3. **`tomorrow.daily_minutes` isn't read**; daily time comes only from a `tomorrow.groups` entry `all`
   (HaAllowance.java:688-706 vs HA household.py, `_tomorrow_document`).
4. **No staleness limit.** The last word holds forever; a pause or lock with no `until` holds until Home Assistant
   returns, for days if need be (HaAllowance.java:757-759, 826-829). The decision says "keep the last rules" but not for
   how long.
5. **Minutes aren't shared across TVs while paired and offline.** Each TV counts only its own time against the last
   word; the household `usage` entries aren't summed in HA mode (LocalAllowance.java:111). Two TVs can each spend the
   whole remainder.
6. **The offline tail across midnight is lost**: only today's `usage_today` is ever sent, so yesterday's time counted
   offline never reaches Home Assistant (UsageToday.java:108-115).
7. **First-pairing import is partial.** Bedtime, `notCounted`, apps and category groups aren't taken; a TV group with
   no match in Home Assistant is dropped; nothing is taken when the kid already has budgets (HA: status.py:204-224;
   household.py:3363-3366; limits.py:720-742). The import is per TV and profile, not once per household.
8. **A paired TV's profile missing from the document** (a kid mapped to nobody, or not yet posted) has no limits at all,
   with no local fallback; an ask gets `no_person` (HaAllowance.java:415-438, 808-809; HaIntegration.java:547).
9. **A removed integration never unpairs**: 404 and 503 keep the last word forever; only 10 minutes of 401s unpair
   (HaIntegration.java:42-49, 344-358).
10. **Hearth's day.** The TV sends its own `day` and ignores the answer's `day` and `clock_off`; it doesn't send
    `utc_offset_minutes` ([device-api.md](device-api.md#hearths-day-additive-within-contract-3) says a client should
    count from Hearth's day) (TvClock.java:10-22; HaStatusReporter.java:625-649).
11. **`contract` is never checked by the TV**: a contract 4 Home Assistant would be read as 3.
12. **No local asks, pauses or School time** without Home Assistant (RemoteSession.java:358-378, 468-476;
    LocalRules.java:20-33). The decision gives the TV its own rules but says nothing on asks without Home Assistant.
13. **Local bedtime has no heads-up**: BedtimeHeadsUp returns when unpaired (BedtimeHeadsUp.java:37), though
    LocalAllowance.java:21-24 says it works the same.
14. **Parent PIN after unpairing** stays Home Assistant's last hashes, not the household's, until an adult sets a new
    one (HaParentPins.java:19-21, 112-131).
15. **Left-over Home Assistant state after unpairing**: integration notices in the Bell aren't cleared (they're only
    processed when a document arrives), and `people`, `profiles` and `adult_phones` stay in preferences
    (HaStatusReporter.java:640; Household.java:1814-1871; PhoneApproval.java:165-167).
16. **The old per-TV YouTube limit** (`Allowance.dailyMinutes`) still applies without Home Assistant beside the local
    rules, stricter wins (Allowance.java:66-75, 89-102): two rule sources where the decision has one.
17. **`commands` (`hearth.play_on_tv`) isn't supported** by the TV; the cap is left out so the service refuses it
    (HaStatusReporter.java:56-59).
18. **A second channel outside the contract**: port 7676 and the panel-token calls (phone approval, Parent approval,
    notification buttons) reach Home Assistant without the pairing secret (HaNotificationServer.java;
    PhoneApproval.java:213-216; ParentApproval.java:200-239).
