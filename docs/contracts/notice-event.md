# Notice event (`hearth_notice`)

Owner: Hearth (the Home Assistant integration). Readers: anything in Home Assistant that wants to pass Hearth's
notices on, for example a router that says them on a speaker in the room where an adult is, or a dashboard that lists
them. It is read-only: a listener learns what Hearth told whom, never how to answer it.

Every notice Hearth gives goes through its attention queue (`attention.py`, see
[Attention](../home-assistant-integration.md#attention)): a kid's ask for more time, the Make adult offer, an outside
change with its Block button, a TV check that fails, a suggestion, a `hearth.notify` message. Each time one is
**shown**, **updated** or **cleared**, Hearth fires one `hearth_notice` event on Home Assistant's bus.

Hearth stays the owner of every notice and of every button: the phones' buttons, Hearth's page and a TV's notices
answer it as before. Firing the event never stops or slows a delivery; a failure is logged and the notice goes out.

## Payload (`v: 1`)

```json
{
  "v": 1,
  "change": "shown",
  "key": "hearth_more_3f2a",
  "tag": "hearth_more_3f2a",
  "kind": "ask",
  "urgency": "notice",
  "title": "Sam asks for 30 more minutes",
  "text": "Video ran out. \"Finishing a level\"",
  "audience": {"kind": "adults", "people": ["person.alex", "person.jordan"]},
  "about": {"person": "person.sam", "group": "video"},
  "actions": [{"n": 0, "label": "+30 min"}, {"n": 1, "label": "+60 min"}, {"n": 2, "label": "Not now"}],
  "link": "/hearth?ask=3f2a",
  "channels": ["phone"],
  "sent": "2026-11-23T16:05:00+00:00",
  "expires": "2026-11-23T17:05:00+00:00"
}
```

| Field | Meaning |
|---|---|
| `v` | This payload's version, 1. It goes up only when a field changes meaning or type or goes away; an added field doesn't change it, so ignore fields you don't know. |
| `change` | `shown` (new), `updated` (new words for an item with the same key or tag) or `cleared` (taken off every channel: answered, gone, or replaced by one with another key). |
| `key` | The item's key: unique while it's kept. |
| `tag` | What replaces or clears it on a channel (the phone notification's tag); the key when it has none. |
| `kind` | What it is, a slug: `ask`, `ask_failed`, `adult_offer`, `outside_change`, `app_check`, `device_check`, `device_clock`, `pairing`, `bedtime`, `new_app`, `rules`, `place`, `chore`, `schedule`, `unlimited`, `suggestion`, `approval`, `notify`, or `other`. New kinds may come. |
| `urgency` | `info`, `notice` or `urgent`. |
| `title`, `text` | The same words its phone notification shows (`title` may be empty). |
| `audience.kind` | Who it's for: `adults`, `admins`, `person`, `household`, `devices`, `chosen_phone`, `schedule_phone`. |
| `audience.people` | The person entity ids that resolves to: the adults on Hearth's page who get notices (`adults`), the administrators' persons (`admins`), the one person (`person`), everyone on Hearth's page (`household`); else the persons behind the phones it goes to. May be empty. |
| `about` | Who and which group it's about, when it is (`person`, `group`); nothing else. |
| `actions` | Its buttons, `[{n, label}]`, numbered as the phone's are. Labels only: never a button's service or data, which stay inside Hearth (looked up by key and number when a button is pressed). |
| `link` | The page a tap on the phone opens (relative, `/hearth...`), or null. |
| `channels` | Where Hearth itself sent it: `phone`, `bell` (Home Assistant's notifications), `tv`. |
| `sent`, `expires` | When it was made, and when it goes by itself (null: until cleared). An item that expires isn't announced as cleared: drop it at `expires`. |

A `cleared` event carries the item as it was. An item put back after Home Assistant restarts isn't announced again.

**Privacy.** The event is on Home Assistant's bus, which only administrators may subscribe to in full, and the recorder
keeps events like any other. It carries a kid's ask and its note, as the adults' phones do; never a place's
coordinates, a PIN or a button's data. Hearth's bell rules are unchanged.

**A listener that sends messages too.** A `hearth.notify` message is announced with `kind: notify`: a router that
answers `hearth_notice` by calling `hearth.notify` should skip those, or it will tell itself again.

## Later: answering (not built)

A router that said a notice out loud may one day pass on the answer it heard: "this person answered notice K with
action n, from this device, this sure". That would be a service such as:

```yaml
action: hearth.answer_notice
data:
  key: hearth_more_3f2a   # the event's key
  n: 0                    # the event's action number
  person: person.alex     # who answered, as the router knows it
  device: <device id>     # where it was heard or tapped
  assurance: voice        # how sure: e.g. voice, phone, pin
```

It would repeat the same checks a phone button does: the caller must be an adult on Hearth's page (or an
administrator), the person must be one the notice was for (its audience), the item must still exist and the action must
be one of its own; then the action runs as that person. How sure is sure enough (a voice match alone, say) would be the
household's choice per kind. **It is not built:** nothing in v1 answers a notice except the existing phone buttons,
Hearth's page and a TV's Parent PIN or parent's phone. The event's `key`, `actions[].n` and `audience.people` are what it
would take, so adding it won't change this payload.
