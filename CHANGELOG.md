# Changelog

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

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
