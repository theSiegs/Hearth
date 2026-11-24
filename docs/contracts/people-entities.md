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
| School today (`sensor.hearth_<kid>_school_today`) | `school`, `half_day`, `off` or `home_today` | `person`; `start`, `end`; `decided_by`; `window_source`; `reason` (with `home_today` only) |

Times are local ISO 8601 with their offset (`2026-11-09T08:10:00-05:00`). Hearth keeps no coordinates: no entity here
has a position.

## Place

`fresh` is false when the latest reading is older than Hearth trusts (20 minutes for a Family Link location); `as_of`
is when that reading was taken. A change of place needs readings that agree before it counts, so `since` can be a few
minutes after the kid actually arrived. The state is recorded; `since`, `source`, `accuracy`, `fresh`, `as_of`, `with`
and `apart_from_adults` are not.

## School today

- `school` and `half_day` follow the household's day type (`sensor.hearth_<household>_day_type`) on a school day.
- `off` is any other day: a weekend, a day off, a holiday, or outside the school year.
- `home_today` is a school day this kid is kept home (`hearth.home_today`, a sick day). That day is a day off for them
  alone: their Day off schedule and limits, and their Family Link School time off for the day. `reason` is the reason
  given (`""` when none).

`start` and `end` are today's School time, as it is, with no travel time added. They come from Family Link's School
time for today's weekday (`window_source: family_link`), ending early on a half day when the schedule says so. Without
Family Link, they come from the School mode of the kid's weekly schedule (`window_source: schedule`). Both are `null`
(and `window_source` is `null`) when the state is `off` or `home_today`, or when no window is known.

`decided_by` says what made today a school day or not: `date` (a date typed in), `rule` (the weekdays of the school
year), `entity`, `calendar`, or `home_today`.

The state changes at midnight, when the day type changes, when a kid is kept home or that's cancelled, and when
Family Link's School time changes.

A change to this page is a contract change: update its test (`ha_tests/test_home_today.py`).
