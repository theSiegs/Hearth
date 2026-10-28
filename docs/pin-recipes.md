# PIN recipes

Hearth types a saved profile PIN into a streaming app by following that app's **recipe**: how to recognise the app's
PIN screen, how to find and press its keys, how to tell that each digit went in, and how to read the app's answer.
Recipes are data, run by one engine in Hearth (`DataPinRecipe`), so a recipe broken by an app update can be fixed
without a Hearth release.

- Hearth's own recipes ship inside Hearth: `android/app/src/main/assets/pin-recipes.json`.
- A newer copy lives in this repository: [`pin-entry/recipes.json`](../pin-entry/recipes.json) on `master`. Installed
  copies read it at most every 12 hours while a streaming PIN is saved (the same rhythm as
  [`pin-entry/disabled.json`](../pin-entry/README.md)), and keep the last copy that passed every check.

## When a fetched recipe is used

A recipe from `pin-entry/recipes.json` replaces Hearth's own only when **all** of these hold:

1. The whole file passed every check below. One error anywhere and the file is dropped: Hearth's own recipes are used.
2. It is for an app Hearth already has a recipe for (same `slot` and `package`). A file can't add an app.
3. Its `version` is higher than Hearth's own recipe for that app.
4. Its `engine` is no higher than the engine of the Hearth that reads it (newer recipes are skipped, not half-read).
5. When it has `appVersions`, the installed app's version code is in that range.

`pin-entry/disabled.json` and the switch in Settings still turn typing off on top of any recipe.

To fix a recipe: copy it in `pin-entry/recipes.json`, change what the app changed, raise its `version` by one, and
(when the fix is only for new versions of the app) add `appVersions` with `from`. Update Hearth's own copy in the
next release with the same version, so the two don't drift. `PinRecipeFileTest` checks that the repository copy
parses and is never older than Hearth's own.

To try a file on a TV before it's on `master`, push it to a branch of this repository and point the TV at it:
`adb shell settings put global hearth_pin_recipes_url https://raw.githubusercontent.com/theSiegs/Hearth/<branch>/pin-entry/recipes.json`
(only files in this repository are taken; `adb shell settings delete global hearth_pin_recipes_url` goes back to
`master`). It's read the next time a PIN entry starts; the next one after that uses it.

## What a recipe can and can't do

A recipe only *describes*. Everything Hearth can do with one is built in:

- click a key node whose label is a single digit (or, if a recipe says so, set a named PIN field's text to the
  digits typed so far, when a key won't take the click);
- move the D-pad focus one key at a time and press OK, only once the focused key is confirmed to be the digit;
- read the app's own window (node text, description, view id, clickable, visible) and what the app says.

It can't name another app (view ids are given without a package; Hearth adds the recipe's own), start anything,
open a link, ask for a permission, or use a regular expression. Keys are only pressed in a window of the recipe's
own app. The same rules as always still hold: never type on a screen the recipe doesn't recognise, confirm every
digit before the next, one attempt per launch.

Checks on a file: at most 64 KiB; `schema` must be `1`; strict types (a number is a whole number, not text; a
string is a string); every name a recipe uses must be defined; ids are letters, digits and `_`; every value has
bounds; phrases are lower case; a D-pad layout has each digit once and every route between two digits stays on
digit keys. Fields Hearth doesn't know are ignored, so a recipe can carry notes. A field that would make an older
Hearth match *more* screens must come with a higher `engine`, so older copies skip that recipe.

## The format

```json
{
  "schema": 1,
  "recipes": [
    {
      "slot": "profile",
      "package": "com.disney.disneyplus",
      "version": 1,
      "engine": 1,
      "pinLength": 4,
      "nodes": {"pinScreen": {"id": "enterPinRootView"}, "field": {"id": "pinCodeEditText"}},
      "keys": {"find": {"id": "digitKey"}, "label": "text", "press": "clickableAncestor"},
      "screen": [{"when": [{"node": "pinScreen"}, {"keys": "all"}], "is": "MATCH"}],
      "typing": {"by": "click"},
      "confirm": {"by": "count", "node": "field"},
      "outcome": [{"when": [{"noNode": "pinScreen"}], "is": "ACCEPTED"}]
    }
  ]
}
```

### A recipe

| Field | Meaning |
|---|---|
| `slot` | `profile` (a profile PIN after Profile Pairing picks the profile), `content` (Paramount+'s content PIN) or `google-tv` (Google TV's own PIN screen, after a phone approval) |
| `package` | The app. Allowed: Disney+, Apple TV, Netflix and HBO Max (`profile`), Paramount+ (`content`), Google TV (`google-tv`) |
| `version` | Whole number ≥ 1; a fetched recipe needs a higher one than Hearth's own |
| `engine` | The engine features it needs; this Hearth's is `1` |
| `pinLength` | 4-8 |
| `appVersions` | Optional `{"from": versionCode, "to": versionCode}`, both inclusive and optional |
| `nodes` | Named nodes, each `{"id": "name"}`: the first node with view id `<package>:id/name` |
| `keys` | How the keypad's keys are found (below) |
| `speech` | Rules for what the app says (below) |
| `focusFromEvents` | For D-pad keypads that report focus as accessibility events: how to read the focused key's label (`text`, `description`, `descriptionAfterLastComma`) |
| `screen` | Rules: the first whose conditions all hold says what the window is: `MATCH` (type), `CHANGED` (a PIN screen laid out otherwise: type nothing, pause entry) or `LOCKED_OUT`. None: not the PIN screen yet. At least one must say `MATCH` |
| `typing` | `{"by": "click"}` (optionally `"setTextFallback": "<node>"`) or `{"by": "dpad", "layout": [["1","2","3"], ..., ["", "0"]]}` (rows of keys, `""` for a place without a digit key) |
| `confirm` | How each digit is confirmed (below) |
| `outcome` | Rules after the last digit: `ACCEPTED`, `REJECTED`, `LOCKED_OUT`, or `HEARD` (whatever outcome the speech rules heard last) |
| `stepTimeoutMs`, `outcomeTimeoutMs` | 1000-30000; defaults 2500 (click) or 15000 (D-pad), and 6000 |

### Keys

| Field | Meaning |
|---|---|
| `find` | `{"id": "name"}` (every node with that view id), or `{"walk": depth}` (the whole tree to that depth, 0-40), optionally `"in": "<node>"` (inside a named node, never the node itself) |
| `label` | What a key's label is: `text`, `description`, or `descriptionAfterLastComma` ("…, Keyboard, 1" is "1") |
| `only` | Optional filters: `visible`, `clickable` |
| `mustBeClickable` | A digit-labelled node that isn't clickable spoils the keypad |
| `stopAtKey` | Don't look inside a digit-labelled node |
| `press` | `self` (default) or `clickableAncestor` (the nearest clickable node at or above the label, at most `maxUp` steps, 0-64, default 64; never past `in`) |
| `otherwise` | No clickable ancestor: `fail` (default; the keypad is spoiled) or `self` |
| `duplicates` | A digit seen twice: `last` (default), `first`, or `fail` |
| `extra` | Labels of other keys that must be there too (`["Delete"]`) |

The keypad is **whole** when every digit (and every `extra`) was found and nothing spoiled it. Click typing needs a
whole keypad.

### Conditions

Each is an object with one of these:

| Condition | Holds when |
|---|---|
| `{"node": n}` / `{"noNode": n}` | the named node is there / isn't |
| `{"nodeShowsText": n}` | the named node is there, visible, with text |
| `{"text": "…"}` | a node's text or description holds this text (any case) |
| `{"keys": "all"}` / `"some"` / `"notAll"` | the keypad is whole / partly there / not whole |
| `{"inApp": true}` / `false` | the window is (isn't) the recipe's app |
| `{"flag": f}` / `{"noFlag": f}` | a speech rule set the flag (or didn't) |
| `{"heard": true}` | a speech rule heard an outcome |
| `{"sinceLastDigitMs": ms}` | at least this long since the last digit went in |
| `{"countDropped": true}` | (`orOnLastDigit` of a count only) the field shows fewer digits than before the press |

### Speech rules

What the app says (through Hearth voice, or as an accessibility announcement) is lower-cased and trimmed, then each
rule is tried in order: `{"when": [phrases], "do": [effects], "stop": true}`. When all its phrases are found, its
effects happen; unless `"stop": false`, no later rule is tried.

A phrase is `{"equals": …}`, `{"contains": …}` or `{"startsWith": …}`: plain lower-case text, with at most three
placeholders, separated by text, at most one of them `{field}`:

- `{d}`: one digit; `{n}`: one to three digits; `{field}`: 1-200 characters other than a comma.

The first placeholder is what the rule captures (no placeholder: the whole text). Phrases are matched by hand,
leftmost and longest first, never as regular expressions.

Effects: `{"set": "flag"}`, `{"focus": true}` (the capture is the focused key's label), `{"outcome": "ACCEPTED"}` or
`"REJECTED"`, `{"echo": true}` (a digit just went in), `{"count": true}` (the capture is how many digits are in;
needs `{d}` or `{n}` first).

### Confirming a digit

| `confirm.by` | Typing | The digit is in when |
|---|---|---|
| `click` | click | the key took the click |
| `count` | click | the `node`'s digit count (`countAs`: `length` of its text, or `dots`: non-space characters, none while it shows its hint) is one more than before; or, for the last digit, any of `orOnLastDigit` (lists of conditions) holds |
| `spokenCount` | dpad | the last `count` heard is the number of digits so far |
| `echo` | dpad | an `echo` was heard since OK; or, for the last digit, any of `orOnLastDigit` (only `flag`, `noFlag`, `heard`) |
| `settle` | dpad | `settleMs` (50-5000) after OK: for apps that say nothing per digit |

`pollMs` (20-1000, default 100) and `waitMs` (100-10000, default 1500) set how often and how long a confirmation is
looked for.

## What each recipe does

| App | Recognised by | Typed by | Each digit confirmed by | Answer |
|---|---|---|---|---|
| Disney+ | `enterPinRootView`, `pinCodeKeyboard`, `pinCodeEditText` and ten `digitKey` labels with clickable keys | clicking the digit's key | the field's length | `pinCodeErrorTextView` shown: rejected; PIN screen gone: accepted |
| Apple TV | one row of clickable keys described "1"…"0" and "Delete" | D-pad along the row (focus events) | "N of 4 values entered" | keypad gone: accepted; still up 3 s after: rejected |
| Netflix | "On the PIN entry screen", then its 4×3 keyboard described | D-pad in the 3×3 grid, 0 bottom left (the focused key is spoken) | 0.4 s after OK (it says nothing per digit) | "wrong PIN" / "On the browse screen" |
| HBO Max | "Enter your profile PIN" with "Numeric Keyboard, <key>, Button" | D-pad in the 3×3 grid, 0 alone in the middle below | the digit's echo; for the last, its answer | "look right" / "H B O Max Home" |
| Paramount+ (content PIN) | `pinEdit` and `tvPinKeyboard` with ten digit keys ("Enter your PIN to watch" alone: changed) | clicking the digit's key; setting `pinEdit` if a key won't take it | the field's dots | dialog gone: accepted; still up 2.5 s after: rejected |
| Google TV | ten clickable digit texts, each once, in Google TV's window | clicking the digit's key | the click | keypad gone: accepted; still up 2.5 s after: rejected |

## Not in the data

Kept in Hearth's code, because they're about safety or the TV rather than one app's screen:

- **When** a PIN may be typed at all (whose PIN, which profile, locks, rejections, pauses; `ProfilePairingService`,
  `ContentPin.whyNot`), the cover card and holding the remote, and the one-attempt state machine
  (`PinEntryMachine`).
- Noticing Paramount+'s content PIN dialog from its window text (`ContentPin.isDialogText`): it decides when an entry
  *starts* in an app Hearth didn't open, so a fetched file mustn't widen it.
- The D-pad route between keys (rows first, except into 0's row) and its limits (10 moves a digit, 1.5 s a move).
- Which apps exist and how their profiles are picked (Profile Pairing).
