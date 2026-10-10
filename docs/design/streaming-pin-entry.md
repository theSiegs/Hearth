# Design: entering streaming-app profile PINs for the parent

Status: built. Netflix, Disney+, Apple TV and HBO Max have PIN recipes, none of them tried on a TV yet; Hulu's PIN
screen hasn't been recorded, and Paramount+ is not supported. Builds on Profile Pairing (`ProfilePairingService`), which already opens a streaming app
behind its "Opening Netflix as Alex…" cover card and picks the paired profile on the app's "Who's watching?" screen.

## Goal

When Profile Pairing picks a PIN-protected profile (Netflix Profile Lock, a Disney+ profile PIN, a Max/Paramount+/Apple TV
profile lock), Hearth types that profile's PIN for the parent, behind the cover card, so:

- nobody watching the TV sees the PIN or the keypad;
- the PIN is typed only for the person it belongs to (the right Google TV profile, chosen on purpose);
- a wrong or changed PIN screen never results in guessing, repeated attempts or a lockout.

Later scope (same machinery): an app's parental-control PIN (mature content, leaving an in-app kids profile).

## 1. Accepting the PIN

Where: **Settings → Profiles → Profile Pairing → an app → a profile row → "Profile PIN"** (only rows paired by an
explicit choice, not a name match). **Every supported streaming service keeps its own PINs**, one per app profile: a
Netflix PIN, a Disney+ PIN and a Max PIN are separate entries even when they're the same digits, and changing one
never touches another. Status on the row: *None*, *Saved*, *Saved — not accepted last time*, *Saved — paused (app
changed)*.

How:

1. The parent PIN first (Hearth's shuffled row pad), always, even in an adult profile: whoever sets a profile's
   PIN must be the parent.
2. The streaming PIN is entered **with the same row pad**, twice to confirm; the length follows the app's recipe
   (4 digits for every app seen so far). It is never shown back, only "Saved".
3. Choices on a saved PIN: *Replace*, *Remove*, *Try it now* (opens the app through Profile Pairing with entry on,
   the parent watching the result).

Hearth can't learn a PIN by watching the parent type it in the app (secure keypads don't expose the digits, and it
mustn't try), so entry in Settings is the only way in.

## 2. Storing it securely

- **Key:** an AES-256-GCM key in the **Android Keystore** (`KeyGenParameterSpec`, purpose encrypt/decrypt,
  non-exportable, StrongBox if the TV has it). No user-authentication requirement: Google TV devices have no lock
  screen; the gate is Hearth's parent PIN plus the rules in §5.
- **Data:** per (app package, app profile name) → `{iv, ciphertext, length, savedAt, status}` in a prefs file of its
  own (`pin_vault.xml`), user 0 only.
- **Never leaves the device:** `android:allowBackup="false"` is already set; the vault is excluded from Hearth's own
  backup/export (BackupService), from profile layouts, from the HearthTube provider and from the agent channel.
- **Never in logs or on screen:** no digits, lengths or keypad focus labels in logcat (the same rule as the chooser);
  the accessibility events from a PIN screen aren't logged at all while a recipe drives it.
- **Decrypted only for the length of one entry,** kept in a `char[]` that's wiped after; not in Flutter memory (the
  Flutter side sends the PIN to Java once, at save, and Java encrypts it at once).
- **Wiped** when the profile pairing is removed, the app is uninstalled, or Hearth's parent PIN is removed.

## 3. Hidden behind the cover card

The cover is a full-screen `TYPE_ACCESSIBILITY_OVERLAY` that is **not focusable or touchable**, so the app underneath
still gets focus and Hearth's accessibility actions; that's what lets Hearth drive the keypad behind it. Additions:

- **The cover stays up** from the pick until the PIN screen is gone (success) or entry stops (failure); its text
  changes to "Unlocking…" with the same progress bar. Nothing of the keypad shows.
- **The remote is held:** while a recipe types, `LauncherAccessibilityService.onKeyEvent` swallows remote keys (so a
  stray press can't add a digit), except Back and Home, which **cancel** entry at once and drop the cover.
- **Nothing is spoken:** apps that announce focus (Netflix through Hearth's voice) are listened to, not read aloud.
- **Time limits:** each step ~2 s, the whole entry ~12 s; past either, stop (see §6).

## 4. Recognising each app's PIN entry, and noticing when it changes

### Entry styles (a recipe uses one)

| Style | How Hearth types | Seen in |
|---|---|---|
| **A. Labelled buttons** | `ACTION_CLICK` on the node whose text/description is the digit; no focus walking | apps exposing keypad nodes (Disney+, Paramount+ likely) |
| **B. Focus keypad, readable** | move focus with D-pad global actions, read the focused node, confirm its label is the digit, then OK | Max/Apple TV likely (node tree, focus reported) |
| **C. Focus keypad, spoken** | as B, but the focused key is read from the app's speech through Hearth's voice | Netflix (no readable nodes; speaks "1", "2"…) |
| **D. Text field** | `ACTION_SET_TEXT` on an editable PIN field (or a Hearth IME as last resort) | apps with a hidden EditText |
| **None** | not typed; the cover drops and the parent types | anything unrecognised |

Which apps are which is **Phase 0 research** on the stick, with a throwaway test profile and PIN in each app (never
the real profiles): what identifies the PIN screen, the keypad and its focus, how a digit shows as entered, what
success and a wrong PIN look like, and the lockout policy.

### Recipes

One `PinRecipe` per app, beside the existing picker recipes, with:

- **Screen signature:** package, activity/window class, anchor texts or view ids ("Enter your PIN", "Profile Lock"),
  and the keypad's shape (ten digit keys in a 3×3+1 grid, a delete key).
- **Driver:** the style above and its key map.
- **Progress check:** how an entered digit shows (a filled dot, an announcement) so every digit is confirmed.
- **Outcome checks:** success (the PIN screen's window is gone, the app's home shows) and wrong PIN (error text,
  digits cleared).
- **Known versions:** the app versions the recipe was verified on.

### Change detection (the tricky part)

Before typing, Hearth takes a **structural fingerprint** of the PIN screen: window class, sorted anchor ids, the
keypad's key labels and their relative grid positions, never any entered state. It compares it with the recipe:

- **App version known and fingerprint matches:** type.
- **App updated but fingerprint still matches:** type, then record the new version as verified on success.
- **Fingerprint doesn't match** (new layout, keys moved, keypad unreadable): **don't type a single digit.** Drop the
  cover ("Netflix's PIN screen has changed; enter it yourself this time"), mark the recipe *paused* for that app
  ("PIN entry paused — Netflix changed its PIN screen") until a Hearth update or a supervised *Try it now* proves it
  again.
- **A mid-entry surprise** (focus lands on a non-digit, a key's label doesn't match, the dot doesn't advance): stop
  before the next OK, drop the cover, tell the parent how many digits went in so they can clear them.

Recipes ship in Hearth's code (a fix is a Hearth update). A *Check PIN screen* action in Settings runs only the
recognition step on the open PIN screen and reports "recognised" or what differs, for bug reports. No digits involved.

## 5. When Hearth types it (all must hold)

1. Profile Pairing picked that app profile itself in this launch (not the parent choosing in the app).
2. The active Google TV profile is known and is paired with that app profile by an explicit choice in Settings (a
   kids' profile too, since 2026-10: its app runs in the kid's own user, which Hearth's accessibility service and the
   agent's speech relay reach as they do for picking the profile; its PIN is saved past the parent PIN).
3. A PIN is saved for it, its recipe isn't *paused*, and PIN entry is on for the app. (A PIN marked *not accepted* is
   still tried, once per launch; see §6.)
4. The PIN screen appears within ~6 s of the pick and matches the recipe's fingerprint.

## 6. Outcomes

- **Success:** the PIN screen goes away → drop the cover. Status stays *Saved*.
- **Wrong PIN:** **one attempt per app launch, never retried within it.** Hearth marks the saved PIN *not accepted*
  and, still under the cover, shows a pop-up:
  > **Netflix didn't accept the saved PIN for Alex**
  > Update the saved PIN in Hearth's Settings, or enter it yourself this time.
  > [ **Change PIN** ]  [ Close ]

  - **Change PIN** opens Hearth's Settings straight on that app profile's PIN row (the parent PIN is asked first).
  - **Close** drops the pop-up and the cover and leaves the app's own PIN entry on screen, cleared, for the parent to
    type the PIN by hand.

  The next launch tries the saved PIN once again, and shows the same pop-up if it fails again, until the PIN is
  changed (then the mark clears) or removed.
  - **No give-up state** (decided): a rejected PIN keeps being tried once per launch. The parent typing the right PIN
    by hand after Close resets the app's own count of wrong attempts, so one wrong try per launch doesn't build up
    to a lockout. If the app does show a lockout or "too many attempts" message (part of each recipe), Hearth says
    so and leaves the screen alone.
- **Broken** (anything unexpected, timeout, left the app): stop before any unverified OK, drop the cover, say "Hearth
  couldn't enter the PIN this time; please enter it." Three breaks in a row for an app → *paused* until a successful
  *Try it now*.
- Every outcome writes one log line with the app, the recipe, the step and the reason. Never the PIN.

## 7. Building it

1. **Phase 0 research:** recipes for each app, from throwaway test profiles (the owner sets the test PINs).
2. **Vault + Settings:** Keystore vault in Java (`PinVault`), method-channel calls (save/remove/status, never read),
   the Settings rows with the row pad.
3. **Engine:** a pure-Java state machine (`PinEntryMachine`) fed by recognition events from the recipes, so it's
   unit-tested with fake recipes: success, wrong PIN, fingerprint mismatch, break at digit 2, timeout, left the app,
   kids profile, name-match-only pairing.
4. **Recipes one app at a time,** each with a sanitised node-tree fixture of its PIN screen (structure only) as the
   golden fingerprint, then a device test on the throwaway profile.
5. **Docs:** a PIN section in the Profile Pairing guide (what's stored, where, how to remove it).

## Decisions for the owner

- PINs entered only in Hearth's Settings (no "capture" from the app) — proposed.
- Typed in grown-up and kids' Google TV profiles alike; each profile sees and sets only its own PINs (Settings ›
  Profiles › Streaming app PINs), always past the parent PIN — decided 2026-10.
- One attempt per launch; on a rejection a pop-up offers **Change PIN** (Settings) or **Close** (the app's own PIN
  entry, by hand) — decided; tried again on every launch until changed or removed, with no give-up state.
- Which apps first: Netflix (most profiles locked?), then Disney+, Max, Paramount+, Apple TV.

## 9. What each app's PIN screen does (researched 2026-10-09)

Recorded with research mode (`adb shell settings put global hearth_pin_research <package>`; Profile Pairing logs
what the app shows and says under the tag HearthResearch, every digit masked as "#") while a parent typed a wrong
PIN and then the right one. Recipes: `DisneyPinRecipe`, `AppleTvPinRecipe`, `NetflixPinRecipe`, `MaxPinRecipe`.

| App | PIN screen as Hearth sees it | Typing | Each digit confirmed by | Wrong PIN | Right PIN |
|---|---|---|---|---|---|
| Disney+ | Native views: `enterPinRootView`, keypad `pinCodeKeyboard` (1-9, 0 below), field `pinCodeEditText` | Click the digit's key node | The field's character count (never read beyond its length) | `pinCodeErrorTextView` "Incorrect PIN. Please try again.", field clears | PIN screen gone (home) |
| Apple TV | One row of key nodes described "1".."9", "0", "Delete" (+ "Use Password Instead"); focus reported as accessibility focus | D-pad along the row, OK on the digit | Announcement "N of 4 values entered" | No message; the PIN screen stays and the count restarts | "Loading", then home |
| Netflix | No nodes; speech only, in screen-reader mode: "On the PIN entry screen." ... "This is a keyboard with 4 rows and 3 columns. The last row contains 0 and Delete keys." then the focused key | D-pad in the 3x3 grid, 0 bottom left; OK on the spoken digit | Nothing per digit; "Entered 4 of 4 digits." after the last | "Whoops, wrong PIN. Please try again." | "On the browse screen..." |
| HBO Max | No nodes; announcements: "Enter Your Profile PIN, ..., Numeric Keyboard, 1, Button, Actions are on the far right" | D-pad in the 3x3 grid, 0 alone mid bottom row, actions to the right; OK on the announced digit | An echo of the digit | "That PIN doesn't look right." | "H B O Max Home, ..." |
| Paramount+ | Opens the last profile without a PIN; a PIN only guards leaving it | Not needed | | | |
| Hulu | No nodes or announcements: its own engine draws the screen. It speaks only when a spoken-feedback service is on and TalkBack isn't ("TalkBack doesn't work with the Hulu app"). It has no TTS `<queries>`: Hearth opens apps with share-identity launch options so Hulu can see Hearth voice, and Hearth voice lists a voice so Hulu's `setLanguage` succeeds. Picker: "Who's watching?. <name> profile button. 1 of 5. Press up or down for other profiles" | Not yet (PIN screen still to record) | | | |

All four ask after the 4th digit by themselves. English-only phrases: in another language nothing matches, no PIN is
typed and the parent enters it. Lockout messages weren't seen (no lockout was triggered); "too many" is treated as one.
