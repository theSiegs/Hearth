# A kid's entities in Home Assistant (contract)

Other integrations and automations may read these per-kid Hearth entities. They are stable; anything not listed here
may change without notice. Each one has a `person` attribute, the `person.*` entity id it belongs to: find a kid's
entities by that attribute, never by building entity ids from names (entity ids follow the person's name, and the user
may rename them).

| Entity | State | Attributes |
|---|---|---|
| Place (`sensor.hearth_<kid>_place`) | a place key: `home`, `school`, a favorite place's key (`practice`), `away`, or unknown | `person`; `name` (the place's name); `since`; `source` (`family_link` or `person`); `accuracy` (metres, or `null`); `fresh` (bool); `as_of`; `with` (the `person.*` ids they're with, or `null`); `apart_from_adults` (bool, or `null` when unknown) |
| Mode (`sensor.hearth_<kid>_mode`) | the mode's key in their weekly schedule (`sleep`, `school`, `free`, or one the household made) | `person`; `name`; `since`; `until`; `next` (`{at, mode}`); `today_changed`; `source` (`schedule` or `locks`) |
| Bedtime (`sensor.hearth_<kid>_bedtime`) | tonight's bedtime (timestamp), or unknown | `person`; `wake` (tomorrow's wake, ISO); `source` |
| Locked (`binary_sensor.hearth_<kid>_locked`) | on while a lock holds their Hearth devices (bedtime, School time, a pause) | `person`; `locked_by` (entity ids) |
| Playing (`sensor.hearth_<kid>_playing`) | what's on (the show, else the title, app or package of the first entry), or unknown when nothing | `person`; `playing` (a list, below) |
| School today (`sensor.hearth_<kid>_school_today`) | `school`, `half_day`, `off` or `home_today` | `person`; `start`, `end`; `decided_by`; `window_source`; `reason` (with `home_today` only) |

Times are local ISO 8601 with their offset (`2026-11-09T08:10:00-05:00`). Hearth keeps no coordinates: no entity here
has a position.

Each phone's and tablet's Last interaction sensor carries the same `person` attribute (its owner), and a TV says who
switched to which profile: see [device-presence.md](device-presence.md).

## Place

`fresh` is false when the latest reading is older than Hearth trusts (20 minutes for a Family Link location); `as_of`
is when that reading was taken. A change of place needs readings that agree before it counts, so `since` can be a few
minutes after the kid actually arrived. The state is recorded; `since`, `source`, `accuracy`, `fresh`, `as_of`, `with`
and `apart_from_adults` are not.

## Playing

Every person has one (adults too). `playing` has an entry per thing they're on now, anywhere Hearth sees, and is
`[]` when nothing:

```yaml
state: Minecraft
person: person.alex
playing:
  - kind: game          # video, music, game or app
    app: Minecraft
    package: null
    title: Minecraft
    series: null
    artist: null
    episode: null
    device: Xbox          # the device's or source's name
    state: playing
    since: "2026-11-25T21:02:10+00:00"
    area_id: den          # the room (a Home Assistant area id), or null
    active: null          # true, false, or null when it can't be told
```

`area_id` is set only when Hearth knows the room, else `null` (never a guess):

| Entry | `area_id` | `active` |
|---|---|---|
| A Hearth TV's app | the TV's own Home Assistant device's area | `true` while its media plays, `false` while paused; `null` for an app with no media playing (a game, a menu) |
| Xbox (a live source: the Xbox integration's now playing) | the console's area, only while the console is on: the console set for the source (`hearth.set_play_area` `source` + `console`), whose media player isn't off and, when it names a title, names the same one; else, with none set, the Xbox integration's media player that is on with the same title, when exactly one room has one. Played on a PC, the cloud or a console that's off or has no area: `null` | `true`/`false` only while a set console's media player says `playing`/`paused` (media apps); a game shows `on`: `null`. Now playing stays on a game left open at its menu, so it can't tell play from a game left running |
| A kid's Switch | only while the dock signal set for that Switch (`hearth.set_play_area` `switch` + `dock`) says docked: a binary sensor, switch or input boolean that is `on`, or a power sensor (the dock's plug) above `above` watts. The room is the one set (`area_id`), else the signal entity's own area. No signal, or one `unknown`/`unavailable`: `null`. Handheld: `null` | from their player's minutes (Nintendo uploads them every 5 to 10 minutes): `true` while they grew in the last window (15 minutes by default), `false` once watched fresh for a whole window without growing, `null` without a player's minutes sensor (only a Playing sensor or friend presence) |
| A phone's app (companion app source) | `null` (a phone moves with its kid) | `true` (only listed while the screen is on and interactive) |

A TV can't say whether a Switch is docked to it: a Hearth TV is a Google TV puck on one of the TV's inputs and reads
"off" whenever another input (the Switch's) is showing, just as when the TV is off. So the TV's state is never used
for a Switch.

The state is unchanged (what's on, not "playing"), so existing readers keep working; `active` is the "being played
now" signal. `playing` is recorded; `area_id` and `active` change with it, within a minute of a dock signal or console changing
(Hearth looks at least once a minute; a source's own change shows at once). They're on this sensor only, not in the
household's documents for devices (`playing` there is unchanged).

## School today

- `school` and `half_day` follow the household's day type (`sensor.hearth_<household>_day_type`) on a school day.
- `off` is any other day: a weekend, a day off, a holiday, or outside the school year.
- `home_today` is a school day this kid is kept home (`hearth.home_today`, a sick day). That day is a day off for them
  alone: their Day off schedule and limits, and their Family Link School time off for the day. `reason` is the reason
  given (`""` when none).

`start` and `end` are today's School time, as it is, with no travel time added. They come from Family Link's School
time for today's weekday (`window_source: family_link`), ending early on a half day when the schedule says so. Without
Family Link, they come from the School mode of the kid's weekly schedule (`window_source: schedule`). Both are `null`
(and `window_source` is `null`) when the state is `off` or `home_today`, when no window is known, or when the kid's
Family Link School time is switched off (other than by Hearth's own School time off), since the times left in Family
Link then aren't a schedule anyone keeps.

`decided_by` says what made today a school day or not: `date` (a date typed in), `rule` (the weekdays of the school
year), `entity`, `calendar`, or `home_today`.

The state changes at midnight, when the day type changes, when a kid is kept home or that's cancelled, and when
Family Link's School time changes.

A change to this page is a contract change: update its tests (`ha_tests/test_home_today.py`,
`ha_tests/test_play_area.py`).
