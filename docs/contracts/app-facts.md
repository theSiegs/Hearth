# App facts: retired

**Status: retired (2026-11).** Hearth no longer reads the App Facts dataset and sends nothing to its relay. The
dataset's repositories are archived. This page stays so older links land somewhere; it describes what Hearth does now.

## What replaced it

Hearth keeps app categories itself (`custom_components/hearth/categories.py`; the full description is in
[home-assistant-integration.md](../home-assistant-integration.md), App categories). For any app, the first answer of:

1. an adult's answer of what the app is (`app_categories` in the options), set on Hearth's page;
2. the **starter list** shipped with the integration (`categories_data/starter.json`, format `hearth.starter/1`),
   made from the dataset's last confirmed answers and hand overrides by `tool/categories_starter.py`;
3. a **store's genre**, looked up once when a kid first uses an app (Google Play, Microsoft Store and Xbox, Steam),
   mapped only where the old classifier was sure;
4. an **AI Task** answer, only with an entity the owner chose, only for an unclear genre, and never confirmed;
5. unknown.

What each value is (its label, default pool, whether it loosens a limit, and System screens' counted-nowhere mark) is
built into Hearth (`categories.BUILTIN_VALUES`), as the dataset's values table was. The household's map from a value
to a pool (`catalog_pools`) is unchanged.

## What leaves the house now

Only a store lookup: one public store id to that store (no household, person or device id, no usage, no cookies),
at most 100 a day. An AI question goes only to the AI Task entity the owner chose. No signed index is fetched, no
relay is called, and no proposals or corrections are sent anywhere.

## Migration

On its first start after the update Hearth removes the catalog's options (`catalog_fetch`, `catalog_share`,
`catalog_share_asked`, `catalog_url`, `catalog_relay`) and its kept copy (`hearth.catalog.<entry>`), once. The
corrections an adult had queued to share become that adult's answers (`app_categories`), and fetching turned off
becomes store lookups off (`category_lookup: false`).

## Formats no longer read

`glint.exchange/1` (the signed index), `glint.catalog/1` (shards), `glint.values/1` (the values table) and
`glint.catalog-propose/1` (the relay's proposals), and the pinned keys `exchange-1` and `exchange-2`.
