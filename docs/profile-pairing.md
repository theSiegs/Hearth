# Profile Pairing

Google TV profiles share one Android user, so Netflix, Disney+ and the other streaming apps keep a single sign-in
and ask "Who's watching?" every time. Profile Pairing answers that question for you: when Hearth opens one of these
apps, it picks the app profile that goes with the Google TV profile you're using.

Supported apps: **Netflix, Disney+, Apple TV, HBO Max, Paramount+.**

> [!WARNING]
> **This is a bit fragile.** None of these apps offer a way for another app to choose a profile, so Hearth reads
> each app's "Who's watching?" screen the way a screen reader would and presses the remote's buttons for you. When
> an app changes that screen in an update, pairing for that app can stop working (or, rarely, pick the wrong
> profile) until Hearth is updated. When Hearth can't find its way, it leaves the app's own picker up for you.
>
> **Pull requests are welcome** to repair an app that broke or to add another one. Each app's recipe lives in
> `ProfilePairingService.java` (how its picker is spotted, read and moved through); see
> [How each app is read](#how-each-app-is-read) below.

## What you'll see

1. You open Netflix from Hearth.
2. When Netflix shows "Who's watching?", Hearth covers it with **"Opening Netflix as John…"**, moves to your
   profile and selects it. This takes a second or two (longer while the app is still starting).
3. The first time Hearth pairs a profile by name, a note at the bottom of the screen says which profile it chose
   and where to change it.
4. If no app profile matches, the card says **"No matching profile for John. Choose one on the next screen."**
   and leaves the picker to you.

**PINs inside the apps.** Hearth only selects the profile; it never types an app's PIN. If a profile has a lock
in the app (for example Netflix's Profile Lock), the app still asks for it every time. Keep in mind that once an app
is open, anyone can use its own "switch profile" menu, and only the app's PIN stops a kid from switching into a
grown-up profile. So:

- Grown-up profiles in apps kids can also open: keep the app's PIN.
- Apps that only grown-ups' Google TV profiles can open (not approved in the kids profiles): you can drop the
  app's PIN, and Hearth makes those launches PIN-free.

## Turning it on

Open **Settings → Setup checklist** and do the two optional steps:

- **Profile Pairing**: Settings opens Accessibility. Scroll down to *Services*, select
  **Hearth Profile Pairing**, turn on **Enable** and confirm.
- **Hearth voice** (only needed for Netflix): Settings opens *Text to speech*. Under *Preferred engine*, choose
  **Hearth voice**, then **OK** on Android's warning. See [Why Netflix needs Hearth voice](#why-netflix-needs-hearth-voice).

## Choosing who's who

Hearth matches names by itself: "John" goes with "John" and with "John Smith". To change a pairing, open
**Settings → Profile Pairing** (it asks for the parent PIN if one is set):

- Each app shows the profiles Hearth has seen in it. Hearth learns them the first time it sees the app's picker,
  so open each app once from Hearth.
- Inside an app, each Google TV profile (kids profiles are marked) can be set to:
  - **Match by name** (the default),
  - **a specific app profile** (for example John → "Grown Ups" in Disney+), or
  - **Always show the picker**, which leaves that app alone for that person.

Google TV profiles appear in the list once Hearth has seen them in use.

## Why Netflix needs Hearth voice

Most apps describe their profile screen to accessibility services, so Hearth can read the names and select one.
Netflix doesn't: it only *speaks* its profile screen, through the TV's text-to-speech engine, when it thinks a
screen reader is on. Hearth voice is a small text-to-speech engine inside Hearth that hears those words
("Choose a profile… John… 1 of 5 profiles"), so Hearth knows which profile is highlighted and can move to yours.

What Hearth voice does with speech:

- **From the app Profile Pairing is opening, during those few seconds:** it passes the words to Profile Pairing
  and stays silent, so nothing is read aloud.
- **Everything else** (every other app, and the streaming apps at any other time): it hands the text to Google's
  voice and plays the result, so speech sounds the same as before, including for someone using a screen reader.

Netflix only speaks for the few seconds after Hearth opens it; Profile Pairing turns screen-reader mode on just
before opening the app and off right after.

**Why it stays selected.** Android only lets an app change the TV's speech engine with a permission that needs a
computer (adb) to grant, so Hearth can't switch it on just for Netflix and back afterwards. Hearth voice therefore
stays your engine and passes everyone else's speech through to Google. If you'd rather not use it, leave Google as
the engine: Profile Pairing still works for every other app, and Netflix just shows its own picker.

**About Android's warning.** When you choose any speech engine that isn't Google's, Android warns that it "may be
able to collect all the text that will be spoken". Hearth voice doesn't keep or send anything: text from the
streaming apps goes only to Profile Pairing on the TV, and everything else goes straight to Google's voice.

## Privacy

Profile Pairing is idle until Hearth opens one of the supported apps. It then reads only that app's profile screen
and stops as soon as a profile is chosen, the app moves on, or about 25 seconds pass. The only thing it keeps is the
list of profile names each app showed (for the Settings page), on the TV.

Hearth voice listens only while Profile Pairing is opening an app. Turning Profile Pairing off switches that
listening off too: Hearth voice then just passes all speech to Google's voice. To stop using it entirely, choose
Google again under Settings → Accessibility → Text to speech.

## How each app is read

For contributors. Checked on a Google TV (Android 14) in October 2026; apps change, so expect to re-check these.

| App | Package | How Hearth reads the picker | How it picks |
|:---|:---|:---|:---|
| Netflix | `com.netflix.ninja` | Spoken text through Hearth voice: "Choose a Profile", then "<name>", "N of M profiles" as focus moves | Down/Up until the spoken name matches, then OK |
| Disney+ | `com.disney.disneyplus` | Tiles labelled "Access <name>'s profile" | Clicks the tile |
| Apple TV | `com.apple.atve.androidtv.appletv` | With screen-reader mode on: "Who's Watching?" and a Button per profile (the first also reads the heading; the name is the last part) | Clicks the button; falls back to Right/Left and OK |
| HBO Max | `com.wbd.stream` | With screen-reader mode on (and an accessibility *tool*): announcements like "Who's Watching?. <name> Button, 1 of 4" | Right/Left until the announced name matches, then OK |
| Paramount+ | `com.cbs.ott` | Tiles tagged `profile_avatar` (a plain tag since October 2026, `com.cbs.ott:id/profile_avatar` before) with the name on the tile or its first child | Clicks the tile |

To add an app: find what its picker exposes (`adb shell uiautomator dump`, or the accessibility events it sends
with screen-reader mode on), add its package to `ProfilePairing.APPS`, and teach `ProfilePairingService` to spot
the picker, read the names, and select one.

## Troubleshooting

- **Nothing happens:** check that Hearth Profile Pairing is on (Settings → Setup checklist), and open the app
  from Hearth. Opening it from Google TV, a voice search or another app doesn't trigger pairing.
- **Netflix still shows its picker:** choose Hearth voice as the text-to-speech engine.
- **"Restricted setting" when turning it on:** see the note in the [README](../README.md#download).
- **The wrong profile opens:** set the pairing in Settings → Profile Pairing.
