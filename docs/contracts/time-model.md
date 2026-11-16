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
- There are three ways to give more:
  1. **Bonus time** (`hearth.add_time`): N minutes added to daily time, with **no category**. The kid may spend it
     anywhere. Minutes past any category's limit come out of the same N (one bonus, shared by every category).
     Chores, approved asks, the day-off bonus and adults all give bonus time. It ends at midnight.
  2. **Raise limit** (`hearth.raise_cap`): one category's limit today, by some minutes, to some minutes, or no limit,
     until a time. Daily time is unchanged.
  3. **Allow for a while** (`hearth.allow` {group, minutes}): one category runs for some minutes whatever daily time
     or its limit says, and its minutes meanwhile aren't counted ("more minutes of messaging").
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

    bonus_used = max(0, minutes over daily time, sum over categories of minutes over each limit)
    bonus_left = max(0, N - bonus_used)
    today_left = max(0, daily time + N - used today)
    held_left  = max(0, limit - used in the category) + bonus_left     (0: the category is held)
    left       = min(held_left, today_left)                            (what a person is shown)

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
| `time.used` | int | Minutes counted today (Unlimited minutes left out). |
| `time.unlimited` | object \| null | While Unlimited is on: `{until, open, include_bedtime, text}`. `open`: "until turned off". |
| `time.unlimited_today` | list | Today's ended windows: `{start, end, minutes, settled, text}`. |
| `time.allowed` | list | Categories allowed for a while now (`hearth.allow` of a category): `{id, group, until, text}`; their minutes meanwhile aren't counted. |
| `time.text` | string \| null | The kid's line, ready to show (see Words). |
| `time.adult_text` | string \| null | The adult's line ("... (includes 30 min bonus)"). |
| `time.categories[]` | list | Each category with a limit (or a raised one): `{id, name, limit, limit_today, raised, until, left, used, text, limit_text}`. `limit`: as set for today's kind of day; `limit_today`: in force today (`null`: no limit); `left`: usable (never more than `today_left`); `text`: the kid's line; `limit_text`: the adult's hint. |
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
A client should not offer a category choice.

## Words kids see (exact)

| When | Text |
|---|---|
| Time left today | `1 h 10 min left today` |
| Only bonus time is left | `30 min bonus left` |
| No time left | `No time left today` |
| A category at its limit, daily time left | `Games are done for today · 40 min left for other things` |
| A category with time | `Games: 25 min left` |
| Unlimited with an end | `Unlimited until 6 PM` |
| Unlimited until turned off | `Unlimited (until turned off)` |
| Unlimited ended | `Limits back on · 1 h 10 min left today` |
| A category allowed for a while | `Messaging allowed until 4:25 PM` |
| Ask button | `Ask for bonus time` |
| Chore done | `+20 min bonus earned` |
| Family pause | `Screens paused` |

Durations read `40 min`, `1 h`, `1 h 10 min`; clocks `6 PM`, `6:30 PM`. `time.text` and each
`time.categories[].text` already carry these lines; a client may show them as they come. Adults see, in addition:
`1 h 10 min left today (includes 30 min bonus)` (the parenthesis only while bonus is left), `Games: 2 h limit`,
`Games: no limit`, `Games: 3 h limit today (raised)`, and `Unlimited 2:00–5:10 PM · 3 h 10 min not counted`.

Never say pool, bucket, budget or max to a person; never "grown-up" (it's "adult").

## Origin (coming)

Each bonus, raised limit, Unlimited window and Pause screens record carries where it came from:

| Field | Meaning |
|---|---|
| `kind` | `bonus`, `raise`, `unlimited`, `pause` (and `daily_time` for a today-only daily time override, coming) |
| `source` | `hearth`, `family_link`, `family_safety`, `nintendo`, `chore`, `ask` |
| `by` | The adult's name when known (the person whose Home Assistant user acted; a chore's: who ticked it) |
| `at` | ISO time |
| `detail` | Short text: `Bonus +30`, `Games: limit +30 today`, `Unlimited until 6 PM`, `Pause screens until 7 PM` |
| `text` | Ready to show: `Bonus +30 · added by Alex in Hearth · 3:05 PM` |

They are in `time.origins[]`, `hearth.explain`'s `origins`, and `hearth/config`'s `origins` (by person). Today
`hearth`, `chore` and `ask` are recorded; `family_link`, `family_safety` and `nintendo` (a parent's change in their own
app) come with the next feature. **Pattern for every client:** a status line stays clean; a small "?" or info
affordance beside it shows the origin text on a tap. The TV and Glint should follow it.

## Deprecated (kept for one release, until the release after the one that ships this)

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

- State document, per person: `+ time` (object above). `groups[]` unchanged in shape.
- Summary, per person: `+ time`; per `groups[]` row: `+ held_left`, `+ bonus_left`, `+ raised`; `minutes_left` now
  the usable value.
- `request.group` (the latest ask) is `"all"` for every new ask.
- `hearth.explain`: `group` is the app's category when called by app; `+ pool`, `+ groups`, `+ today_left`,
  `+ bonus_left`, `+ unlimited`, `+ category_limit`, `+ raised_limits`, `+ origins`.
- `hearth/config`: `+ fl_backstop`, `+ fl_backstop_margin`, `+ origins`.
- New services: `add_time`, `remove_time`, `raise_cap`, `raise_cap_end`, `unlimited`, `unlimited_end` (adults only).
- New events: `hearth_unlimited_started {person, until, open}`, `hearth_unlimited_ended {person, id, text}`.
