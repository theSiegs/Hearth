# App facts: Hearth's side

Owner of the data: the App Facts dataset (both clients' leads review changes). Owner of this page: Hearth.

App facts is a neutral, public, signed dataset of what an app **is**: a category, a finer detail, a cross-platform app
slug, a name, and whether that's confirmed or only suggested. Hearth reads it to put apps in pools; which pool a
fact goes to is the household's own choice (Hearth's page > App facts > Which group each kind of app goes to).

Today it's published from the glint-recipes repository under its current format ids (`glint.exchange/1`,
`glint.catalog/1`, `glint.catalog-propose/1`) and keys (`exchange-1`, `exchange-2`). Moving it to its own repository
with `appfacts.*` formats and its own keys is a later step: the new URL, keys and formats will replace these in one
Hearth release, with no overlap. Until then this page describes the rules both sides keep.

## Reading

**Source.** The signed index at `catalog_url` (by default the publisher's Pages URL): `index.json`,
`index.json.sig`, then the shards it names. A generic user agent and `If-None-Match`; nothing else is sent.

**Cadence.** Once a day at a random minute; at startup when the copy is over a day old; never per app.

**Verify, in order** (any failure keeps the last good copy):

1. Ed25519 over the exact bytes of `index.json`, with one pinned key.
2. The index's `format`.
3. `seq` at least the cached `seq` (lower is a rollback).
4. Per shard: the SHA-256 matches the index, its `format`, and `platform` equals the shard's name.
5. **An index that lists no catalog, no shards, or only shards Hearth doesn't read keeps the current copy.** It never
   empties it.

**Shard entries** (example):

```json
{"android:com.example.chat": {"app": "example-chat", "name": "Example Chat", "category": "messaging",
                              "state": "confirmed", "source": "play", "checked": "2026-12-01"}}
```

Unknown fields, values, shards and namespaces are ignored. `category` is one of the ten Android categories; `detail`
(`youtube`, `streaming`, `education`, `companion`, `system`) is add-only.

**Absent or unverifiable:** the last good copy, then the snapshot bundled with the integration, then each device's
own category, then Other. Nothing gets looser when the facts are missing: an unknown app is Other, which still counts
toward All screen time.

**Not used for enforcement:** a future `parental_control` flag never exempts anything from pausing. What Hearth never
pauses is its own list plus each device's client locked at pairing ([device-api.md](device-api.md)).

## Writing (proposals)

Only while sending is on (an HA administrator's choice, asked once). Weekly, to the relay's `/challenge` then
`/propose`: at most 20 keys and 10 corrections, sorted, with no household, person or device id, no usage, times or
counts. A key is sent only if the dataset lacks it, it was seen on an adult or on a person with `share_app_data`, and
it isn't a messaging app. Answers: `202` taken; `400`/`403` dropped, never resent; `429` wait; `404`/`410` no
endpoint, wait.

## Consent per person: `share_app_data`

A per-person option (Hearth's page > Sharing app data), in each person's state document. It gates Hearth's own
proposals (kids' apps are proposed only when it's on) and tells a client to turn its own sharing off when it's
`false`. It replaced `tile_exchange_share` (moved once, as it was, when the integration loads).
