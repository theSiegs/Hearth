# A TV's entities in Home Assistant (contract)

Other Home Assistant integrations may read a paired TV's entities. These are stable; anything not listed here may
change without notice. Find a TV's entities from its profile sensor; never guess entity ids or unique-id suffixes
(entity ids follow the device's name and the user may rename them).

| Entity | State | Attributes |
|---|---|---|
| Profile sensor (`sensor.<tv>_profile`) | the profile's display name | `profile_id`, `profile_ref` (`name:<slug>`, stable across reinstalls), `kids_profile` (bool), `state_entity`, `media_title_entity` (the entity ids below, or `null` while not registered) |
| State sensor (`state_entity`) | `playing`, `paused`, `idle` or `off` (see `TV_STATES`) | none |
| Media title sensor (`media_title_entity`) | the title playing, when the TV knows it | `album`, `duration_s`, `now_playing_available` |
| `binary_sensor.<tv>_kids_profile` | on in a kids profile | none |

Not offered yet: the position in what's playing (minutes left). The TV reports a duration but no position; a reader
that needs it uses the TV's own `media_player` if one exists.

A change to this table is a contract change: update this page and its test (`ha_tests/test_init.py`,
`test_pair_then_post_status`).
