# Client settings (`hearth.client-settings/1`)

Owner: Hearth. Part of [device API contract 3](device-api.md).

Hearth keeps small JSON documents for apps paired with it, by client (the app's package, e.g.
`com.example.launcher`), scope (`household`, `person:person.sam`, `device:phone-sam-01`) and name. Hearth never reads
`data`. Adults (HA administrators, HA users linked to an adult, adults' paired devices) write household and person
documents; a kid's paired device writes only its own device documents, or its own person's documents with a
parent-PIN grant from `verify_pin`. At most 64 KB per document, 16 per client and scope, 1 MB per client. Optimistic
writes with `if_etag` (`409 changed`). A device sees its documents' etags in its state document and fetches changed
ones. Removing a device deletes its device documents. Example: a launcher on Sam's phone at 192.0.2.10 reads
`person:person.sam/kids`, which an adult saved from their own phone.

## Address

- `client`: the client id locked at the device's pairing (a device can't name another).
- `scope`: `household`, `person:<person entity id>` (`person:person.sam`) or `device:<device id>`.
- `name`: `[a-z0-9][a-z0-9._-]{0,63}`.

## Document

```json
{"format": "hearth.client-settings/1", "client": "com.example.launcher", "scope": "person:person.sam",
 "name": "kids", "schema": "example.kids/2", "label": "Example kids settings", "etag": "c0ffee12d00dfeed",
 "updated": "2026-12-01T18:02:11Z", "updated_by": "adult", "data": {}}
```

- `data`: any JSON object. Hearth parses only the envelope.
- `schema`: the client's own label for its format (`[A-Za-z0-9][A-Za-z0-9._/:-]{0,63}`), stored and shown in listings.
- `label`: optional, at most 40 characters (control characters are stripped; longer is 400). Hearth's page shows it
  verbatim on the device row's "Settings kept for …" line; without one it shows `<client> · <name>`.
- `etag`, `updated`, `updated_by`: set by Hearth. `updated_by` is `adult` (an adult in HA, or an adult's device),
  `kid_device` (a kid's device, its own device scope), `device` (a TV, its own device scope) or `pin` (a write a PIN
  grant allowed).

## Limits

| Limit | Value |
|---|---|
| `data` per document (compact JSON, UTF-8) | 65,536 bytes (64 KiB): over it, `413 too_large` |
| Documents per client and scope | 16: a 17th name is `413 too_many` (replacing one is fine) |
| All of a client's `data` together | 1,048,576 bytes (1 MiB): over it, `413 too_large` |
| Request body (PUT) | 131,072 bytes |
| Calls per device | 60 a minute (`429 too_often`) |

## Who may write

| Scope | HA administrator, or an HA user linked to an adult | Adult's paired device | Kid's paired device | Kid's paired device with a PIN grant | TV |
|---|---|---|---|---|---|
| `household` | yes | yes | no | **no** | with a grant |
| `person:<p>` | yes | yes | no | its own person only | with a grant |
| `device:<d>` | yes | its own device | its own device | its own device | its own device |

A phone whose person isn't an adult on Hearth's page counts as a kid's. A kid's device can't loosen anything kept at
person or household scope: only an adult, or the parent PIN typed on the device, can change those. **So anything that
restricts a kid belongs at person scope, never in the kid device's own device scope**, which the kid's device writes
freely. Nothing in client settings changes what Hearth holds or allows.

**Offline.** A client never queues a person-scope change made on a kid's device for later: with Home Assistant
unreachable, it's refused ("needs Home Assistant right now").

## Who may read

- An adult in HA: everything.
- A device: its client's `household` documents, its own device's, and its own person's. An adult's device reads every
  person's; a TV reads the people of its profiles.

## Device API

Header `X-Hearth-Secret` as on every device endpoint.

| Call | Answer |
|---|---|
| `GET /api/hearth/device/{id}/settings/{scope}/{name}` | `200` the document; `404 none`; `403 forbidden` |
| `PUT /api/hearth/device/{id}/settings/{scope}/{name}` `{"schema", "data", "label"?, "if_etag"?, "grant"?}` | `200 {"etag", "updated_by"}`; `403 forbidden`; `409 changed {"etag"}` (`"etag": null`: there is no document now); `413 too_large` / `too_many`; `400 bad_request` |
| `DELETE` the same, body `{"if_etag"?, "grant"?}` (optional) | `200 {"ok": true}`; `404 none`; as above |

- `if_etag`: the etag the document must have now; `null`: only when there is none yet; left out: any.
- `grant`: the `verify_pin` grant, also accepted as header `X-Hearth-Grant`. It's spent only when it was needed.
- `403 no_client`: the device was paired without a client (or before contract 3): pair again.
- The device's state document carries `"client_settings": {"<scope>/<name>": "<etag>"}` for every document it may
  read. The etags are part of the document's `version`, so any change (an adult's, or another of the person's
  devices') wakes its `/wait` and sends one push "changed" ping; a device's own write may too, once.

## WebSocket (adults in HA)

| Command | Effect |
|---|---|
| `hearth/client_settings/list` `{client?}` | `{"documents": [envelope + "size", …]}`, never `data` |
| `hearth/client_settings/get` `{client, scope, name}` | the document |
| `hearth/client_settings/set` `{client, scope, name, schema, data, label?, if_etag?}` | the envelope; `updated_by: adult` |
| `hearth/client_settings/delete` `{client, scope, name, if_etag?}` | `{"ok": true}` |
| `hearth/client_settings/subscribe` `{client?, person?}` | events `{client, scope, name, etag}` (`etag` null: it went). With `person`: that person's documents and the device documents of their paired devices, nobody else's |
| `hearth/client_settings/clear` `{client}` | administrators (Hearth's page): removes everything kept for the client |

A kid's own HA user gets none of these.

## Events

`hearth_client_settings_changed` `{client, scope, name}`, with no contents.

## Storage and backups

An HA `Store` (`.storage/hearth.client_settings.<entry>`). Removing a device deletes its device documents; person and
household documents stay until an adult removes them (Hearth's page: "Settings kept for … · Remove"). Because they're
in `.storage`, **client settings are in every Home Assistant backup**: keep short-lived data, such as notification
candidates, short-lived (overwrite or delete it), and never put secrets in it.
