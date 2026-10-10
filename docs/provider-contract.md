# Hearth's profile provider: the contract

Hearth shares its state with other apps (today: HearthTube) through one content provider. This page is the
contract: what each column means, when it changes, and what callers may rely on. The provider's `contract_version`
column says which version of this page it implements.

**Current version: 5** (Hearth 2026.10, `ProfileProvider.CONTRACT_VERSION`).

Change rules: adding, removing or changing the meaning of a column or call bumps the version and gets a line in
the history below. A reader that sees a newer version than it knows keeps using the columns it understands; columns
are never reused for a different meaning.

## Where

- Authority: `com.thesiegs.hearth.profile` (debug builds: `com.thesiegs.hearth.debug.profile`). Hearth up to
  2026.10.x answered the same contract at `com.leanbitlab.ltvL.profile`; a client that still accepts it is harmless
  (docs/design/app-id-change.md).
- `content://com.thesiegs.hearth.profile/active`: one row, the columns below.
- `content://com.thesiegs.hearth.profile/wallpaper`: Hearth's current wallpaper picture, read-only
  (`FileNotFoundException` when Hearth shows a gradient instead). Since version 5 only for `com.thesiegs.hearthtube`
  signed with one of the certificates below (a picked wallpaper may be a family photo); anyone else gets
  `FileNotFoundException`. How HearthTube shows Hearth's wallpaper: docs/design/wallpaper-sync.md.
- Observers registered on `/active` are notified whenever a column changes.

**In the owner's user, and in profiles through Hearth's agent.** Android refuses provider access across users,
so an app running in a Google TV profile user (a kid's own copy of an app) can't reach Hearth, which runs in the
owner's user (0). Where a parent has approved Hearth for that profile, Hearth runs there as the profile's agent and
its provider answers with Hearth's own row as Hearth last sent it, except: `service_running` is 1 only while the
agent is connected to Hearth, and the `wallpaper_*` columns and `/wallpaper` are that profile's own wallpaper, the
one Hearth shows for it (its picture, Bing's photo or its gradient), with the same meanings and the same
`wallpaper_version` as in the owner's user. Hearth sends each profile's agent only that profile's wallpaper, a
picture as a JPEG of at most 1920x1080 (center-cropped like the screen shows it), and only while that profile's
settings are the ones in place; `/active` observers there are notified when it arrives. Until the agent has a
picture's current version (just after a switch, or a picture too big to send) it reports `wallpaper_kind`
"gradient" with that profile's `wallpaper_gradient`, and before Hearth has sent it anything, Hearth's gradient with
null `wallpaper_brightness`, `wallpaper_title` and `wallpaper_credit`. `wallpaper_stamp` there is the cached
picture's file time, 0 for a gradient. `verify_parent_pin` is relayed to Hearth (the PIN never leaves it) and returns null when Hearth doesn't
answer within a few seconds. Without an agent, a Hearth installed there answers with defaults only.

**Checking it's really Hearth.** The provider belongs to `com.thesiegs.hearth` (`.debug` for debug builds; up to
2026.10.x `com.leanbitlab.ltvL`) signed with one of:
- release: `243bf074648ab3bfebb260d129e7c8203b407ca7677507ce93dbe72b02396d4c` (CN=Hearth, O=theSiegs; from
  2026.10.10. Earlier builds used `0438047b1a5eefe8693cad8f2b57189a418337bbcbd3c7dbdb79d20884beaf6e`, which a
  client may keep accepting while installs move)
- debug: `6748528ff4d17fd57c30b6c5d522c467920d9951ea5d208597f91b66df9a2bfe`

(SHA-256 of the signing certificate.)

## Columns of `/active`

| Column | Type | Meaning |
|---|---|---|
| `name` | text or null | The active Google TV profile's name as Google TV's profile chooser shows it ("Alex"). Null while Hearth hasn't learned it yet (each profile is named the first time the chooser shows it) or can't tell. For display only: key things by `profile_id`. |
| `profile_id` | text or null | The active profile's lasting key: `user:<serial>` of its Google TV profile user (`user:0` is the TV owner), and for another grown-up's Google account in that same user `user:<serial>:<account>` (`user:0:sam`): grown-ups' profiles share the owner's user, one per account. Set before `name` is known and unchanged when the profile is renamed. What to save per-profile things under; treat it as opaque. Null until Hearth has read it. |
| `kids_profile` | 0/1 | 1 in a Google TV kids profile: the active profile user carries Family Link's supervision restrictions. Independent of which apps a parent approved, and of screen time. |
| `screen_time_up` | 0/1 | 1 while Google TV's kids screen time is up (bedtime, daily limit): seen from its time's-up / bedtime screens, or from the kid's approved apps being blocked in the kid's own profile user. Back to 0 when they're unblocked (bedtime over, bonus time) or the profile changes. Kept across Hearth restarts. Always 0 outside kids profiles. |
| `service_running` | 0/1 | 1 while Hearth's accessibility service runs. Without it Hearth sees no profile switches and no screen time, so `profile_id`, `name`, `kids_profile` and `screen_time_up` can't be trusted: treat 0 as "Hearth isn't watching". |
| `has_parent_pin` | 0/1 | Hearth has a parent PIN (Settings → Parent PIN); `verify_parent_pin` can check one. |
| `accent_color` | text or null | Hearth's accent color as `RRGGBB` hex ("7C4DFF"), or null for Hearth's default. |
| `time_format` | text | Clock format as an ICU / intl pattern; Hearth's default "h:mm a" when never changed. |
| `date_format` | text | Date format as an ICU / intl pattern; Hearth's default "EEE, MMM d" when never changed. |
| `app_language` | text | Hearth's language ("de", "pt-BR"…), or "" to follow the system's. |
| `gradient_uuid` | text or null | The gradient Hearth shows when it has no wallpaper picture. |
| `wallpaper_stamp` | integer | Changes whenever the wallpaper picture does (its file time); 0 when Hearth shows a gradient. Re-read `/wallpaper` when it changes. |
| `profile_ready` | 0/1 | 1 once Hearth's home is complete for the active profile after a switch or start: its layout restored, its Continue Watching read, and (for a profile other than the owner's) its Hearth agent heard from, or 4 seconds passed. Back to 0 at the next switch. Act on profile-specific state when this turns 1, not on the first change of `profile_id`. |
| `switch_generation` | integer | Goes up by one at every profile switch (and when Hearth starts). Tells a new visit to a profile from the same one. |
| `updates_hearthtube` | 0/1 | 1 while Hearth keeps HearthTube up to date: automatic companion updates are on (Settings → Companion apps; on by default when Hearth installed HearthTube) and Hearth is HearthTube's installer of record, so Android lets it update without asking. HearthTube's own updater steps aside meanwhile. Changes when the setting does or HearthTube is installed or updated. |
| `wallpaper_kind` | text | What Hearth's home shows behind everything: "picture" (a picked picture, the day or night one resolved for the time now), "bing" (Bing's photo of the day) or "gradient". For "picture" and "bing", `/wallpaper` opens that file. |
| `wallpaper_version` | integer | Changes whenever what `wallpaper_kind` names does: another picture, the same one replaced (a new pick, a new day's Bing photo), day turning to night, another gradient while one shows. Positive. Re-open `/wallpaper` (or redraw the gradient) when it changes. |
| `wallpaper_brightness` | real or null | How light the wallpaper is, 0 (black) to 1 (white): the picture's average luminance as Hearth measured it, or the gradient's. Null until Hearth has measured what's shown now (for a moment after a change, or after day turns to night while Hearth wasn't running). Hearth darkens its row titles' pills the lighter it is. |
| `wallpaper_gradient` | text (JSON) or null | Hearth's gradient: shown when `wallpaper_kind` is "gradient", and what Hearth falls back to otherwise. `{"type": "linear" or "radial", "colors": ["#AARRGGBB", ...], "stops": [0..1, ...] or null (evenly spaced), "rotation": radians clockwise about the screen's center, "brightness": 0..1}`, plus for linear `"begin"` and `"end"` and for radial `"center"` as `{"x", "y"}` alignments (-1..1 across the screen, x right, y down) and `"radius"` (a fraction of the screen's shorter side). Null before Hearth has described the chosen gradient (a moment after a change, or a Hearth not opened since it was updated). |
| `wallpaper_title` | text or null | When `wallpaper_kind` is "bing": the photo's title as Bing gives it ("A quiet lake"). Otherwise null; also null for a photo fetched before Hearth kept titles. |
| `wallpaper_credit` | text or null | When `wallpaper_kind` is "bing": Bing's caption and credit for the photo ("A quiet lake at dawn (© Photographer/Agency)"), to show where the photo is credited. Otherwise null. |
| `contract_version` | integer | This page's version (5). Missing on Hearth builds from before version 2. |

None of these are secret: everything is on screen in Hearth.

## Calls

`call(uri /active, "verify_parent_pin", pin, null)`: checks a PIN against Hearth's parent PIN without handing out
the PIN or its hash. Only for `com.thesiegs.hearthtube` signed with one of the two certificates above; anyone else
gets null. Returns a Bundle: `ok` (boolean), and when locked, `wait_seconds` (int): five wrong tries lock checks for
a minute.

## History

- **5, new app id** (2026-10): no column changes. Hearth's app id is `com.thesiegs.hearth`, so the authority is
  `com.thesiegs.hearth.profile` (Hearth up to 2026.10.x: `com.leanbitlab.ltvL.profile`).
- **5** (2026-10-09): added `wallpaper_kind`, `wallpaper_version`, `wallpaper_brightness`, `wallpaper_gradient`,
  `wallpaper_title`, `wallpaper_credit`; observers on `/active` are told when the wallpaper changes. `/wallpaper`
  only opens for HearthTube with a trusted signature. In a profile's agent, the wallpaper columns and `/wallpaper`
  are that profile's own wallpaper (same columns and meanings, so no new version for it).
- **4** (2026-10-07): added `updates_hearthtube`. `profile_ready` also turns 1 at most 4 s after a change with
  Hearth off screen.
- **3** (2026-10-07): added `profile_ready` and `switch_generation`.
- **2** (2026-10-07): added `service_running`, `profile_id`, `contract_version`. `kids_profile` now means Family Link
  supervision (was: some app is blocked). `screen_time_up` also comes from the kid's approved apps and clears when
  they're unblocked (was: only Google TV's screens, cleared only by a profile switch). `name` may be null after a
  switch until Hearth learns it. `verify_parent_pin` checks the caller's signing certificate too.
- **1** (before 2026-10-07, no `contract_version` column): `name`, `accent_color`, `time_format`, `date_format`,
  `app_language`, `has_parent_pin`, `gradient_uuid`, `wallpaper_stamp`, `kids_profile`, `screen_time_up`;
  `verify_parent_pin` by package name.
