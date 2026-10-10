# Changelog

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

## 2026.10.29 (pre-release)

- YouTube allowance: no play time lost when a kids profile's helper is briefly disconnected; a Home Assistant lock (bedtime, school time) keeps Hearth's own minutes as Hearth's, with Home Assistant's message; Home Assistant can give its per-profile limits as the entity's state.
- Home Assistant status: usage goes out every 2 minutes while watching (changes still go out at once).

## 2026.10.28 (pre-release)

- YouTube time per day (Settings → Profiles; in a kids profile past the parent PIN): how long HearthTube may play a day for that profile. Hearth counts it on the TV; Home Assistant, if you use it, can add a limit shared with the family's other devices (the stricter wins). HearthTube enforces it once it has its matching update.
- Hearth keeps today's app and playing time per profile, and with Home Assistant set up sends it with the TV's status, along with when screen time came up or cleared.

## 2026.10.27 (pre-release)

- Continue Watching per profile, from Hearth's own history: what each profile plays is recorded on the TV (title, episode, how far it got), so its entries are its own, shows from apps that don't fill Google TV's Continue Watching list (Hulu, Paramount+) appear too, and an entry an app dropped when someone else used it (Netflix keeps only its current profile's) stays until that profile opens the app again.

## 2026.10.26 (pre-release)

- Grown-ups' profiles that share the TV's main user (Google accounts added in Google TV's chooser) are profiles of their own in Hearth: switching to one brings its own home, look, dock, name and photo, and its own Continue Watching (whatever was watched while it was on). Hearth knows whose profile is on from Google TV's home, which says who's logged in. The first switch to a new one waits about 15 seconds on Google TV's home.
- Weather forecast: the headings say Hourly and Daily.

## 2026.10.25 (pre-release)

- Weather forecast: with the top bar's weather selected, the coming hours show over the home; OK swaps them for the next five days.

## 2026.10.24 (pre-release)

- The Home button closes Settings, side panels, dialogs and the Home Assistant panel.
- One temperature unit for the whole TV, starting from its region's (Fahrenheit in the US).

## 2026.10.23 (pre-release)

- Groundwork for grown-up profiles that share the TV's main user: Hearth notes Google TV's profile switches in its log.

## 2026.10.22 (pre-release)

- Holding the profile button locks the profile again: Google TV's Verify it's you screen stays up, instead of the chooser opening over it.
- Letting go after holding OK no longer also counts as a press.

## 2026.10.21 (pre-release)

- Setup cards show each item with a check or an open circle for how it stands, and say Next, Leave it as it is / Set up what's missing, or Not now / Turn on.
- Google TV's spare, never-used profile no longer shows up as another adult's profile, and Hearth isn't put on it.
- The temperature is in Fahrenheit on TVs in the US (and the few other places that use it) until a unit is picked.

## 2026.10.20 (pre-release)

- Holding OK on an app always opens its menu; the held key no longer goes on to open Add to section.

## 2026.10.19 (pre-release)

- Blocking an app with Family Link (and unblocking it) no longer removes it from a kids' profile's dock and sections.

## 2026.10.18 (pre-release)

- First-run setup: a guided flow on a new TV (the Home button, the home app, then family, watching, a look for the home, smart home, TV & power and updates), Set up Hearth in Settings, and a chip on the home for anything left. TVs already set up aren't taken over.
- Four looks to start from: Hearth, Photo of the day, Calm dark and Bold.
- The phone setup page also takes a Home Assistant webhook ID for TV status.
- Start on boot is on unless it was turned off.

## 2026.10.17 (pre-release)

- "Use Google TV's home" in TV & power: a switch that leaves Google TV's own home in front until it's turned off. It replaces "Use Google TV for now" in System.

## 2026.10.16 (pre-release)

- A profile name Hearth got wrong after a failed switch corrects itself.

## 2026.10.15 (pre-release)

- Profile switching works normally again while a newly added profile can't start, and a wrong profile name corrects itself.

## 2026.10.14 (pre-release)

- Notifications can be opened, and their buttons pressed, from Hearth's notifications panel.
- A newly added Google TV profile can be switched to more reliably.
- Only HearthTube signed with Hearth's release key gets parent PIN checks.

## 2026.10.13 (pre-release)

- A newly added Google TV profile can be switched to: Hearth waits while Google TV sets it up.
- The fade behind Continue Watching and search reaches both edges of the screen.

## 2026.10.12 (pre-release)

- Continue Watching shows "See all" only once it has three programs.

## 2026.10.11 (pre-release)

- Settings, Inputs, Notifications and the Home Assistant panel no longer darken the home screen behind them.
- "Lock my profile" is now "Lock Profile".

## 2026.10.10 (pre-release)

**New signing key** (CN=Hearth). Builds up to 2026.10.09 were signed with the key inherited from the
project Hearth started from, so they can't update to this one: uninstall the old Hearth first.

## 2026.10.09 (pre-release)

**New app id.** Hearth is now `com.thesiegs.hearth` (it was `com.leanbitlab.ltvL`, inherited from LTvLauncher).
It installs as a new app: back up with the old Hearth (Settings → System → Backup & Restore), install this one,
restore, and uninstall the old one. See [docs/design/app-id-change.md](docs/design/app-id-change.md).

**Google TV profiles**
- Hearth knows the active profile from Google TV itself, with each profile's photo in the top bar, its own home
  layout, wallpaper and Continue Watching.
- Profile Pairing picks your profile in Netflix, Disney+, Apple TV, HBO Max and Paramount+, also in other
  profiles, and can type a saved profile PIN for you (Netflix, Disney+, Apple TV and HBO Max).
- Lock my profile, using Google TV's own profile lock: from Settings, by holding the profile button, from a remote
  button, or when the TV sleeps.

**Kids and families**
- Hearth on other profiles: puts Hearth and HearthTube on kids' and other adults' profiles and keeps them installed;
  Uninstall Hearth cleans them up first.
- Hearth stays out of the way of Google TV's bedtime and screen time screens.
- Kids see their own settings plus one "Parent settings" row; only risky settings ask for the parent PIN.

**Home screen**
- Search, in Continue Watching's spot: results show where to watch now and open in the app; adult titles never show.
- Row titles on a pill that darkens with the wallpaper; a dark fade behind details in Continue Watching and search.
- Each profile has its own wallpaper pictures; Bing's photo of the day updates the day it comes out; HearthTube can
  show Hearth's wallpaper.
- Many focus and navigation fixes: something is always selected, Left on a sub page goes back, the dock and
  Favorites keep the selection.

**Remote and TV**
- Remote buttons: press and hold actions, Home Assistant scenes and scripts, "Ask Google", lock my profile; remaps
  can apply only on Hearth's home screen.
- Hearth keeps HearthTube up to date.
- Include pre-releases (Settings → System → Updates, on by default): Hearth and HearthTube updates include early
  test builds. Every release is a pre-release while Hearth is in early development.
- Settings regrouped into eight sections.

**Home Assistant**
- The status webhook adds `profile_id`, a stable key for the profile, and kids screen time details.
- Pop-ups with live cameras and action buttons; phone setup by QR code.

**Everything else**
- Translated into 13 languages besides English.
- About shows the wallpaper photo's credit and the TMDB notice.

## 2026.10.05

The first Hearth release.

- New name, icon and banner.
- Favorites dock: a frosted bar along the bottom of a wallpaper-first home screen. Up brings in Continue Watching;
  Down brings the dock back.
- Continue Watching shows cover art again. Below the dock, apps wrap as a grid over a blurred wallpaper.
- Left at the left edge opens Settings; Right closes it. New Appearance settings for the dock.
- Persistent notifications can be dismissed. Updates pick the right APK for the device.

## Before Hearth

Hearth started from [LTvLauncher](https://github.com/leanbitlab-org/LtvLauncher), which descends from
[FLauncher](https://gitlab.com/flauncher/flauncher). Their history is in this repository's git log.
