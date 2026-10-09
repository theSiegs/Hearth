# Wallpaper sync: HearthTube shows Hearth's wallpaper

Goal: both apps show the same wallpaper. When HearthTube runs in Hearth, Hearth is the source of truth: HearthTube
shows Hearth's current wallpaper (a picked picture, the day or night one, Bing's photo of the day, or a gradient)
instead of its own daily Bing photo. Outside Hearth, HearthTube keeps its own.

Hearth's side is done (provider contract version 5, docs/provider-contract.md). This page is what HearthTube does.

## What Hearth offers

Authority `com.leanbitlab.ltvL.profile` (debug Hearth: `com.leanbitlab.ltvL.debug.profile`).

- `content://<authority>/active`: the one-row cursor HearthTube already reads. New wallpaper columns:

  | Column | Type | Use |
  |---|---|---|
  | `wallpaper_kind` | text | "picture", "bing" or "gradient" |
  | `wallpaper_version` | long | changes whenever what's shown changes; the cache key |
  | `wallpaper_brightness` | real or null | 0 (black) .. 1 (white), the shown picture's or gradient's average |
  | `wallpaper_gradient` | JSON text or null | Hearth's gradient (below) |
  | `wallpaper_title` | text or null | Bing photo's title, only when kind is "bing" |
  | `wallpaper_credit` | text or null | Bing's caption and © credit, only when kind is "bing" |
  | `contract_version` | int | 5 or more means the columns above exist |

  The older `wallpaper_stamp` and `gradient_uuid` stay; HearthTube doesn't need them any more.
- `content://<authority>/wallpaper`: `openFile(uri, "r")` / `ContentResolver.openFileDescriptor` /
  `openInputStream` gives the picture Hearth shows right now (day/night already resolved), read-only. Only for
  `com.thesiegs.hearthtube` signed with one of the trusted certificates; `FileNotFoundException` for anyone else and
  when Hearth shows a gradient.
- Hearth calls `notifyChange` on `/active` whenever the wallpaper (or anything else in the row) changes, including
  when its day/night picture swaps at 06:00 and 18:00 while Hearth is running and when the Bing photo is refreshed.

`wallpaper_gradient` JSON, matching how Flutter paints Hearth's gradient:

```json
{"type": "linear", "colors": ["#FF6991C7", "#FFA3BDED"], "stops": null,
 "begin": {"x": -1.0, "y": 0.0}, "end": {"x": 1.0, "y": 0.0}, "rotation": 5.6, "brightness": 0.31}
{"type": "radial", "colors": ["#FFFCB69F", "#FFFFECD2"], "stops": null,
 "center": {"x": 0.0, "y": 0.0}, "radius": 0.5, "rotation": 0.0, "brightness": 0.82}
```

Drawing it on a `w` x `h` screen with `android.graphics` (colors via `Color.parseColor`, stops null = evenly spaced):

- Alignment to pixels: `px = w/2 + x*w/2`, `py = h/2 + y*h/2`.
- linear: `new LinearGradient(begin px/py, end px/py, colors, stops, CLAMP)`, then
  `Matrix m = new Matrix(); m.setRotate((float) Math.toDegrees(rotation), w/2f, h/2f); shader.setLocalMatrix(m)`.
  (Flutter's `GradientRotation` turns clockwise about the center; Android's `setRotate` does too.)
- radial: `new RadialGradient(center px/py, radius * min(w, h), colors, stops, CLAMP)`.
- "type" may be "other" in a future Hearth: fall back to the first color.

## Running in Hearth

HearthTube follows Hearth's wallpaper when all of these hold:

1. Hearth's provider answers: `query(/active)` returns a row with `contract_version >= 5`, and the provider's
   package is `com.leanbitlab.ltvL` (or `.debug`) signed with one of the certificates listed in
   docs/provider-contract.md (HearthTube already checks this).
2. HearthTube was opened from Hearth, or Hearth is the TV's home:
   - `Activity.getLaunchedFromPackage()` (Android 14+) returns `com.leanbitlab.ltvL` (or `.debug`). Hearth launches
     apps with share-identity `ActivityOptions`, so this works for anything opened from Hearth's home, search or
     Continue Watching. It's null when opened some other way, and before Android 14.
   - Otherwise: `PackageManager.resolveActivity(new Intent(ACTION_MAIN).addCategory(CATEGORY_HOME),
     MATCH_DEFAULT_ONLY)` resolves to Hearth. That covers HearthTube opened by voice, a cast or a deep link on a TV
     whose home is Hearth.
   - Or `/active` reports `service_running = 1`. On Google TV the home stays Google TV's own launcher and Hearth
     takes the Home button over through its accessibility service (Home Button Fix), so the check above finds
     Google TV there; a running service means Hearth is the home the family sees. (Found testing on a TV.)

   Decide once per `onStart` (or per new intent) and keep the answer while the activity lives.

In a Google TV profile other than the owner's, HearthTube reaches Hearth through Hearth's agent there: the same
columns and `/wallpaper`, answering with that profile's own wallpaper (below). Nothing changes for HearthTube.

## Each profile's own wallpaper

Every Google TV profile, kids' and grown-ups', has its own look in Hearth, and HearthTube in that profile shows it.

- Hearth's settings (gradient, Bing on or off, day/night pictures on or off) are saved and restored per profile
  (ProfileService, BackupService profile layouts). The pictures a profile picks are its own too: they live in
  `app_flutter/wallpapers/<profile key>/` (`wallpaper`, `wallpaper_day`, `wallpaper_night`; the key "user:11" as
  `user_11`). The folder used is the one of `device_layout_owner`, the profile whose settings are in place, so the
  pictures always match the settings (WallpaperService.setProfile after each switch; HearthWallpaper.java reads the
  same key). Bing's photo of the day is the same for everyone and stays in `app_flutter/wallpaper_bing`.
- Pictures from before this (in `app_flutter/` itself) become the TV owner's (`user:0`) the first time Hearth starts
  with it. A new profile starts with no picture (its gradient), a kids profile with Bing's photo.
- Backups and exports hold settings and layouts, not pictures, as before.

### Getting it to the profile's user

HearthTube in a profile runs in that profile's Android user and reads the provider of Hearth's agent there, which
can't read Hearth's files in the owner's user. So Hearth sends it over the agent channel (AgentHub, one JSON line;
AgentWallpaper.java):

- `{"type":"wallpaper","profile":"user:11","kind","version","brightness","gradient","title","credit","image"}`:
  the v5 wallpaper columns as Hearth's provider has them, and for "picture" and "bing" the picture as a base64 JPEG,
  center-cropped and scaled down to at most 1920x1080 (what the screen shows; never enlarged; EXIF rotation applied),
  at most 3 MB (quality 85, then 70; bigger and it isn't sent).
- Only to the agent of the profile whose wallpaper it is: Hearth sends it only when `device_layout_owner` is that
  agent's profile key, and the agent drops a message for another profile. No profile's picture reaches another
  profile's user. (The agents of profiles that aren't active aren't running anyway: Google TV stops their users.)
- When: when the agent connects (its user starts on a switch to the profile) and whenever Hearth's provider row
  changes (Flutter publishes a new wallpaper state on a pick, a gradient, Bing on or off or a new photo, the
  day/night swap, and the switch itself, since the state carries the profile). Repeats are skipped; the picture goes
  only when the agent doesn't have that `wallpaper_version` (the agent says which it has in its hello).
- The agent keeps the picture in its files dir (`hearth_wallpaper.jpg`, written whole then renamed) and the columns
  in its preferences, notifies `/active`, and serves them with the same `wallpaper_version`. It reports "gradient"
  while it lacks the current version's picture, and deletes the picture when the profile goes to a gradient.

## What HearthTube does in Hearth

- Background: read `/active`; by `wallpaper_kind`:
  - "picture" or "bing": open `/wallpaper`, decode (sampled to the screen size), draw center-crop (Hearth uses
    `BoxFit.cover`). Cache the decoded bitmap keyed by `wallpaper_version`; re-open only when the version changes.
    If the open fails (Hearth just switched to a gradient, or an old Hearth), draw `wallpaper_gradient`, and if
    that's null too, black.
  - "gradient": draw `wallpaper_gradient` as above.
- Keep the shade on top as now (#59 / #26 / #73 black top to middle to bottom), so the look matches Hearth's home.
- Brightness: where HearthTube darkens text backgrounds for light wallpapers, use `wallpaper_brightness` (or the
  gradient's `brightness`); when null, measure the bitmap itself or assume 0.5.
- Changes: register a `ContentObserver` on `/active` while visible; on change, re-query, and reload only if
  `wallpaper_version` changed. Also re-query in `onStart` (Hearth may not have been running to notify, for example
  day turning to night).
- Its own Bing photo: don't download or show it while in Hearth. In Settings, replace the Bing wallpaper option
  with a line like "Wallpaper follows Hearth" (or show the option disabled with that note).
- Credit: About shows Hearth's `wallpaper_title` and `wallpaper_credit` when `wallpaper_kind` is "bing", and no
  photo credit for "picture" or "gradient". HearthTube's own credit shows only outside Hearth, with its own photo.

## Outside Hearth

Unchanged: HearthTube's own daily Bing photo and its credit in About. When it goes back to running in Hearth, it
switches to Hearth's wallpaper again at the next `onStart`.

## Compatibility

- Hearth before contract 5 (no `wallpaper_kind` column): keep today's behavior (`wallpaper_stamp` and
  `/wallpaper`, or HearthTube's own Bing photo).
- `/wallpaper` used to open for any app; it now checks HearthTube's package and signature, which current HearthTube
  builds pass.
