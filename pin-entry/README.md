# Streaming PIN entry: the files Hearth reads from here

## Recipes

`recipes.json` holds the recipes Hearth follows to type a saved PIN in each streaming app. Hearth ships its own
copy and uses one from here only when it's newer and passes every check; see [PIN recipes](../docs/pin-recipes.md)
for the format, the checks and how to fix a recipe.

## App versions Hearth doesn't type PINs in

`disabled.json` lists app versions whose PIN screens Hearth's recipes are known not to handle. Hearth reads it from
`master` at most every 12 hours while a streaming PIN is saved on the TV, and doesn't type PINs in a listed version
until a Hearth update fixes the recipe and the entry is removed. The list can only turn typing off, so a stale or
missing list never makes Hearth type where it shouldn't.

```json
{
  "version": 1,
  "disabled": [
    {"package": "com.example.tv", "from": 120000, "to": 120999, "note": "its PIN screen changed in 12.0"}
  ]
}
```

`from` and `to` are the app's version codes, both inclusive and both optional (left out: every version).
