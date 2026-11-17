# Time model (daily time, limits, bonus time, Unlimited)

Owner: Hearth (the Home Assistant integration). Readers: Glint (the phone launcher) through Hearth's device API and the
`glint` / `hearth` LLM APIs, Hearth TV, and any other paired client. This page says what changed, what a client reads
now, how asks work, the exact words kids see, and what is deprecated. It is additive: contract 3 stays, and every old
field keeps working for one release (see Deprecated).

## What changed

Before, every budget was its own wall. A "+30 games" bonus raised Games only, while All screen time still counted
those minutes, so the day could run out first. Now:

- **Daily time** is the one total for the day (school days / other days, or the weekly schedule). Its id stays `all`.
- **Categories** (Games, YouTube, Streaming, Social, ...) may have a **limit** inside daily time ("Games: 2 h limit").
  A limit never adds time; it only stops one category from taking the whole day.
- There are four ways to give more:
  1. **Bonus time** (`hearth.add_time`): N minutes added to daily time, with **no category**. The kid may spend it
     anywhere. Minutes past any category's limit come out of the same N (one bonus, shared by every category).
     Chores, approved asks, the day-off bonus and adults all give bonus time. It ends at midnight.
  2. **A category's bonus** (`hearth.add_time` with `category`): "+15 min Messaging bonus", usable only in that
     category, past daily time and its limit; spent before the general bonus. Ends at midnight.
  3. **Raise limit** (`hearth.raise_cap`): one category's limit today, by some minutes, to some minutes, or no limit,
     until a time. Daily time is unchanged.
  4. **Unlimited** (`hearth.unlimited`): until a time, "until turned off", or the end of the day (always over at
     midnight). Nothing Hearth holds for daily time or a limit holds the kid, and **the minutes used meanwhile aren't
     counted**: daily time, limits and bonus time pick up exactly where they were. Bedtime, School time and Pause
     screens still apply unless `include_bedtime` (bedtime only).
- Hearth's family pause is called **Pause screens**, so it never reads like a limit change.
- **Messaging counts.** The Messaging category counts toward daily time, and Messages apps are paused like any app
  (daily time or Messaging's limit used up, bedtime, Pause screens). Only calls stay open: the dialer, contacts,
  Settings, Play services, Family Link, the Play Store and Hearth's and Glint's own apps are never paused. A client
  that spared Messages from its own hold because it was outside daily time should hold it like any app now.

### The accounting

    a category's own bonus pays first, for its minutes past its limit or past daily time (minutes past daily time go
      to the categories with a bonus first); what it pays counts in neither daily time nor the limit
    bonus_used = max(0, minutes still over daily time, sum over categories of minutes still over each limit)
    bonus_left = max(0, N - bonus_used)
    today_left = max(0, daily time + N - used today)
    held_left  = max(0, limit - used in the category) + bonus_left + its own bonus left   (0: held)
    left       = min(held_left, today_left + its own bonus left)                         (what a person is shown)

Worked examples are in `ha_tests/test_time_model.py`. Example: daily time 3 h, Games limit 2 h, +30 bonus. After 2 h
30 of games, the bonus is used, Games is held, and the kid has 1 h left for other things.

## What a client reads

### The state document (`GET`/status answer, per person: `profiles[...]` on a TV, the person on a phone)

New, under `time` (always present for a person; values may be `null`):

| Field | Type | Meaning |
|---|---|---|
| `time.today_left` | int \| null | Minutes the kid can use today, bonus included. `null`: no daily time set. |
| `time.today_minutes` | int \| null | Today's daily time with bonus (`base_minutes + bonus`). |
| `time.base_minutes` | int \| null | Today's daily time without bonus (after any time an adult took away). |
| `time.bonus` | int | Bonus time given today (adults, asks, chores, day-off). |
| `time.bonus_left` | int | Bonus time not used yet. |
| `time.bonus_origin` | string \| null | The id of the latest bonus origin today (its ⓘ). |
| `time.used` | int | Daily time used today, whole minutes (rounded), Unlimited minutes left out. |
| `time.unlimited` | object \| null | While Unlimited is on: `{until, open, include_bedtime, text, origin}`. `until`: local ISO, the latest end of its grants; `open`: "until turned off" (still over at midnight); `origin`: the latest Unlimited origin's id. |
| `time.unlimited_today` | list | Today's ended windows: `{start, end, minutes, settled, text}`. |
| `time.text` | string \| null | The kid's line, ready to show (see Words). |
| `time.adult_text` | string \| null | The adult's line ("... (includes 30 min bonus)"). |
| `time.by_category[]` | list | Today's counted minutes by category, `{id, name, minutes}` in the household's category order, then `{id: "other", name: "Other"}` for apps in no category. Each minute once, and the minutes add up to `time.used` exactly (largest remainders). Categories with no minutes are left out; empty when nothing is counted. The page's daily-time bar shows the same split. |
| `time.uncounted` | int | Whole minutes used today but not counted in daily time: categories outside it (and Accessibility) plus Unlimited windows. Never inside `by_category`. |
| `time.categories[]` | list | Each category with a limit, a raised limit or its own bonus today: `{id, name, limit, limit_today, raised, until, left, used, text, limit_text, bonus, bonus_left, origin}`. `limit`: as set for today's kind of day (`null`: none); `limit_today`: in force today (`null`: no limit); `raised`: bool; `until`: the raises' latest end (`null`: midnight); `left`: usable (its limit, the bonus left and its own bonus left, never more than `today_left` + its own bonus left); `used`: its minutes today; `text`: the kid's line (`null` while Unlimited); `limit_text`: the adult's hint; `bonus`/`bonus_left`: its own bonus today; `origin`: the latest raise's origin id when raised, else `null`. |
| `time.category_bonuses[]` | list | Categories with their own bonus today, with a limit or not: `{id, name, bonus, bonus_left, origin, left, text}`. `origin`: the latest bonus origin of that category; `text`: `Messaging: 15 min bonus left`, or `Messaging: bonus used` once it's spent. |
| `time.origins[]` | list | Where today's statuses came from (see Origin), newest first. |

Unchanged: `groups[]` with `{id, name, minutes_left, apps, except}`. A category's `groups[].minutes_left` is
`held_left` (what holds its apps: its limit plus the bonus left), so a client that holds apps by it keeps working.
Daily time's (`id: "all"`) is `today_left`. Show `time.*` to people; hold by `groups[]`.

### The household summary (`hearth/summary`, `GET /api/hearth/household`)

Each person gains `time` (as above). Each `groups[]` row gains `held_left`, `bonus_left` and `raised`
(`{add, to, no_cap, until}` or `null`); its `minutes_left` is now the usable value (`left`), and `held_left` the hold
value. `bonus` on a category row is what its raised limit adds, not bonus time.

### `hearth.explain`

Called with an app it now returns the app's category: `group` and `pool` are the app's category id (never `null` for a
categorized app), and `groups` lists every group it counts in. New: `today_left`, `bonus_left`, `unlimited`,
`category_limit` (the category's `time.categories[]` entry), `raised_limits`, `origins`.

## How asks work

A kid asks for **bonus time**, with no category. `POST /api/hearth/device/{id}/ask` and the TV's ask still accept
`group`, but Hearth records every ask as `group: "all"` and an approval gives bonus time (`hearth.add_time`), whatever
group was sent. The ask's `request.group` in the state document is `"all"`. Amounts are unchanged (15, 30, 45, 60).
A client should not offer a category choice. (An adult, or an assistant asked for "more minutes of messaging", gives a category's bonus with `hearth.add_time` and `category`.)

## Words kids see (exact)

| When | Text |
|---|---|
| Time left today | `1 h 10 min left today` |
| Only bonus time is left | `30 min bonus left` |
| No time left | `No time left today` |
| A category at its limit, daily time left | `Games are done for today · 40 min left for other things` |
| A category with time | `Games: 25 min left` |
| Only a category's own bonus is left | `Messaging: 15 min bonus left` |
| A category's bonus given (adults, chores) | `+15 min Messaging bonus` |
| Unlimited with an end | `Unlimited until 6 PM` |
| Unlimited until turned off | `Unlimited (until turned off)` |
| Unlimited ended | `Limits back on · 1 h 10 min left today` |
| Ask button | `Ask for bonus time` |
| Chore done | `+20 min bonus earned` |
| Family pause | `Screens paused` |

Durations read `40 min`, `1 h`, `1 h 10 min`; clocks `6 PM`, `6:30 PM`. `time.text` and each
`time.categories[].text` already carry these lines; a client may show them as they come. Adults see, in addition:
`1 h 10 min left today (includes 30 min bonus)` (the parenthesis only while bonus is left), `Games: 2 h limit`,
`Games: no limit`, `Games limit today: 3 h (raised)`, and `Unlimited 2:00–5:10 PM · 3 h 10 min not counted`.

Never say pool, bucket, budget or max to a person; never "grown-up" (it's "adult").

## Grants

Each bonus (general or a category's), raised limit and Unlimited is a grant of its own, linked to its origin by the
same id. What's in effect is computed from the active grants:

- **Bonus**: the sum of the grants (each less what an end took back). Spent bonus minutes are put on the oldest grants
  first (chores before them).
- **Raised limit**: raises "by" add up; a "to" or "no limit" sets a floor, and the highest wins.
- **Unlimited**: on while any Unlimited grant is, to the latest end of them (or until turned off). One window of
  uncounted time, extended by a second grant, never two.

`hearth.end_grant {origin_id}` (adults only, in the action log; also `POST /api/hearth/device/<id>/end_grant` from an
adult's device) ends exactly that grant: a bonus's unused part only (at most min(its minutes, the unused total)), one
raise or one Unlimited grant (the others stay in effect), a chore's reward (undone), or Pause screens. Each origin's
`end` is `{service: "hearth.end_grant", data: {origin_id}}`. The older services keep meaning "all":
`hearth.raise_cap_end` ends every raise of a category, `hearth.unlimited_end` every Unlimited grant. On the first start
after the upgrade, today's bonus, category bonuses, raised limits and a running Unlimited become one grant each, with
their latest origin's id.

Also, for the record:

- `hearth.remove_time` takes back only what bonus grants still give, newest first; it never cuts daily time itself.
- Nothing takes time away from daily time itself. The older `hearth.add_bonus` with negative minutes and the
  daily-time bonus number entity set lower take back bonus given (newest grant first), never more than the net bonus.
- An ask answered twice: the second answer is refused with `not_open` (`hearth.answer_request` raises a validation
  error; the WebSocket answers `not_open`).

## Never paused

The state document (phone and TV, per person) has `never_paused: [packages]`: what Hearth never pauses for any reason,
the same list Family Link's per-app hold uses (calls: dialer and contacts; Settings, Play services, Family Link and its
helper, the Play Store, Hearth's and Glint's apps, `android`, and the keyboards and voice typing: Gboard, Samsung Keyboard, SwiftKey and its beta, Fleksy, Grammarly's keyboard, Google's speech services) with the launchers, keyboards Hearth's categories place in System screens, and accessibility apps. A
client holds everything else when a group it holds is out of time or paused, Messaging included.

## Origin

Each bonus, raised limit, Unlimited window and Pause screens record carries where it came from:

| Field | Meaning |
|---|---|
| `kind` | `bonus` (a category's has `group`), `raise` (with `group`), `unlimited`, `pause` (`daily_time`, a today-only daily time override, is coming) |
| `source` | `hearth`, `family_link`, `family_safety`, `nintendo`, `chore`, `ask` |
| `by` | The adult's name when known (the person whose Home Assistant user acted; a chore's: who ticked it) |
| `at` | ISO time |
| `detail` | Short text: `Bonus +30`, `Games: limit +30 today`, `Unlimited until 6 PM`, `Pause screens until 7 PM` |
| `text` | Ready to show: `Bonus +30 · added by Alex in Hearth · 3:05 PM` |
| `minutes`, `group`, `chore` | When they apply: a bonus's minutes, the category, a chore reward's ledger key |
| `id` | Stable for the day: status lines link to it (`bonus_origin`, `origin` on categories, category bonuses and Unlimited) |
| `endable` | Whether something of it can still be ended now: a bonus grant with unused minutes, an active raise or Unlimited grant, a chore's reward not undone, Pause screens still on |
| `end` | `{service: "hearth.end_grant", data: {origin_id}}` while something of it can be ended (see Grants), else `null` |

They are in `time.origins[]` (the state document and the household summary, `hearth/summary` and `GET /api/hearth/household`: each person's today's changes, newest first, for adult phones), `hearth.explain`'s `origins`, and `hearth/config`'s `origins` (by person). Today
`hearth`, `chore` and `ask` are recorded; `family_link`, `family_safety` and `nintendo` (a parent's change in their own
app) come with the next feature. **Pattern for every client:** a status line stays clean; a small "?" or info
affordance beside it shows the origin text on a tap. The TV and Glint should follow it.

### Ending a grant: what comes back

`hearth.end_grant {origin_id}` (response optional; adults only) answers `{person, kind, ...}`:

| `kind` | Other fields | What it did |
|---|---|---|
| `bonus` | `taken`: int | Took back that grant's unused minutes (spent minutes are put on the oldest givers first) |
| `raise` | `group` | Ended that raise; the category's other raises stay |
| `unlimited` | `still_on`: bool | Ended that grant; Unlimited stays on (to the latest end of the others) when `still_on` |
| `chore` | none | Undid the chore's reward |
| `pause` | none | Ended Pause screens for the person |

Nothing left to end: a validation error, `Nothing of it is left to end` (an origin that isn't `endable`), or `No such
grant today` (an unknown id). Nothing changes then.

From an adult's phone: `POST /api/hearth/device/{device_id}/end_grant` (header `X-Hearth-Secret`; the device's person
must be an adult) with `{"origin_id"}` runs `hearth.end_grant` as that adult's Home Assistant user (in the action log,
`why: end_grant:<id>`):

- 200 `{"ok": true, "ended": {person, kind, ...}}` (the service's answer above);
- 404 `{"error": "not_found"}`: no such origin today, or nothing of it left to end;
- 403 `not_adult` (the device's person isn't an adult) or `not_local`; 401 `not_paired`; 429 `too_often`;
  400 `bad_request` (no `origin_id`), or `{"error": "failed", "detail": ...}` when the service refused it.

## What the grant services answer

Each service that gives something answers the origin it recorded, so a client can link to it, show its ⓘ or end it
later (`hearth.end_grant`). For one person: `origin_id`. For every call: `origin_ids` `{person: id or null}` (null: the
call gave nothing for that person, so no origin was recorded, as with 0 minutes).

| Service | Answer |
|---|---|
| `hearth.add_time` (general or `category`) | `{origin_id, origin_ids, <person>: {...time view..., origin_id}}`: each person's `time` as in the state document |
| `hearth.raise_cap` | `{origin_id, origin_ids, <person>: {category, add, to, no_cap, until, origin_id}}`: the raise in effect after it (all grants together) |
| `hearth.unlimited` | `{origin_id, origin_ids, id, until: {person: ISO}, text: {person: line}}` (`id`: the allow behind it) |
| `hearth.add_bonus` (older name) | `{origin_id, origin_ids}`; with `device`, as before: `{id, until}` (extra time on one device has no origin) |
| `hearth.pause` | Pause screens (the family pause): `{origin_id, origin_ids}`; a pause of one app or group: `{}` |

The device API has no other adult action that gives time; asks are answered by an adult (`hearth.answer_request`, the
phones' notification buttons), and the bonus they give records an origin with `source: ask`.

## Unchanged this release

Extra time on one device (`hearth.add_bonus` or `hearth.allow` with `device`, device_extra.py, the summary's
`device_extras`) is unchanged.

## Deprecated (kept for one release: until the release after 2026.11.23)

- `hearth.add_bonus` with a `group`: raises that category's limit (as `hearth.raise_cap` by minutes). Without a group,
  or with `all`: bonus time (as `hearth.add_time`). `hearth.remove_bonus` likewise.
- `number.hearth_<person>_<group>_bonus_today` for a category: reads and sets what its raised limit adds today. Daily
  time's (`..._all_screen_time_bonus_today`) is bonus time.
- An ask's `group`: accepted and ignored (always `all`).
- The LLM tool `hearth_add_bonus` is gone (an LLM tool list isn't stored anywhere): use `hearth_add_time`,
  `hearth_raise_limit`, `hearth_unlimited`, `hearth_unlimited_end`.
- Entity ids don't change: `sensor.hearth_<person>_all_screen_time_minutes_left` is now named "Daily time left", the
  budget numbers "Daily time on school days" and "Games limit on school days". New: `sensor.hearth_<person>_bonus_time_left`.

## Payload changes, exactly

- State document, per person: `+ time` (object above, with `by_category` and `uncounted`). `groups[]` unchanged in shape.
- Summary, per person: `+ time`; per `groups[]` row: `+ held_left`, `+ bonus_left`, `+ raised`; `minutes_left` now
  the usable value.
- `request.group` (the latest ask) is `"all"` for every new ask.
- `hearth.explain`: `group` is the app's category when called by app; `+ pool`, `+ groups`, `+ today_left`,
  `+ bonus_left`, `+ unlimited`, `+ category_limit`, `+ raised_limits`, `+ origins`.
- `hearth/config`: `+ fl_backstop`, `+ fl_backstop_margin`, `+ origins`.
- State document, per person: `+ never_paused`; `time.bonus_origin`, `origin` on raised categories, category bonuses and Unlimited; each origin `+ id`, `+ endable`, `+ end`.
- New: `POST /api/hearth/device/{device_id}/end_grant` (adults' devices) and the service `hearth.end_grant`; an origin's `end` names it.
- Grant services answer `origin_id` / `origin_ids` (see What the grant services answer); `hearth.pause` now answers.
- New services: `add_time`, `remove_time`, `raise_cap`, `raise_cap_end`, `unlimited`, `unlimited_end` (adults only).
- New events: `hearth_unlimited_started {person, until, open}`, `hearth_unlimited_ended {person, id, text}`.
