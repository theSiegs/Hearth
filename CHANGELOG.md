# Changelog

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

## Unreleased

## 2026.10.78 (pre-release)

- Household sync: a TV asking to join shows up in the **notification Bell** of the TV it asked, on grown-ups' profiles only, and pops up: its name, with **Allow** and **Don't allow**. No Parent PIN, no code to compare, no phone. The joining TV says which TV to allow it on and waits up to five minutes.
- Notifications: the Bell shows each app's real name (system apps no longer show as a package name like com.google.android...), reads the title and text of every notification style, and a tap goes where the app told Google TV it should, opening the app when the notification can't. A notification whose buttons change is updated, so a button pressed is the one shown. Newest first.

## 2026.10.77 (pre-release)

- Household sync is now the one way to keep TVs alike: the **Copy profiles to / from another TV** screens are gone, and so is typing another TV's address. Settings > Profiles opens **Household sync** directly. A new TV chooses Join the household, shows a code, and a parent allows it on their phone or on another TV's Household page.
- Household sync: kids profiles' looks, layouts and wallpapers sync too, like everyone else's.
- Profile Pairing no longer lists the spare user Android keeps ready for the next new profile (it showed as "Profile 13" or similar).
- About Hearth shows this TV's name.

## 2026.10.76 (pre-release)

- Household sync: a backup is kept in Backup & Restore before a profile first takes the household's look, layout or wallpaper on a TV, as a copy does.

## 2026.10.75 (pre-release)

- Household sync, version 2: each TV has its own key, kept in the Android Keystore, and the household is a list of its TVs that syncs like everything else. Two TVs sync only when each signs the exchange with a key on the other's list. Copying profiles with "Add this TV to my household" now hands the new TV a one-time invitation, good for an hour, instead of the household's key.
- Household sync: each other TV on the Household page has **Remove**, after the Parent PIN. A removed TV stops syncing with the rest at once, without a new key for the others, and is told it was removed the next time it tries. Leaving works the same way: the TV removes itself and hands that to the next TV it meets.
- Household sync: **Join the household** now works from the new TV alone. It asks one of your other TVs, shows a six-digit code, and waits while a parent allows it on their phone (with phone approval on) or on that TV's Household page. The code on the phone has to match the one on the screen. The household's Home Assistant settings come along when the new TV has none. The setup step's Join does the same.
- Household sync: each profile's **look, home layout and wallpaper pictures** now follow it to every TV in the household. A TV fits the household's layout to the apps it has, and keeps the household's apps it doesn't have, so they aren't lost for the other TVs. Only pictures someone picked move between TVs; Bing's photo of the day is a setting, and each TV downloads it.
- Household sync: a household from 2026.10.68 to 2026.10.74 converts on its own when its TVs update, keeping who is who.

## 2026.10.74 (pre-release)

- Household sync: a TV in no household now shows when your other TVs already have one, names them, and offers **Join the household** (the copy screen that takes the household's key from one of them), with starting a separate household as the second choice. The setup flow's "Sync with your other TVs" step does the same, so a later TV no longer starts a second household by mistake.
- Household sync: the Household page lists the **TVs in this household**: this TV, the ones on now, and when each of the others was last on. Each TV announces its name and writes an entry about itself that syncs, so every TV learns of the others even if they were never on together; a TV that leaves takes its entry away.

## 2026.10.73 (pre-release)

- **Update automatically** now updates Hearth itself too: it checks daily and installs a newer Hearth, without asking, while the TV's screen is off. Only the main user's Hearth does it.

## 2026.10.72 (pre-release)

- Google's ad sandbox: **Keep it off** no longer asks for the Parent PIN; only turning the sandbox back on does.
- Setup flow: when debugging is on, a step after the kids profiles shows the ad sandbox commands and turns it off with one press.

## 2026.10.71 (pre-release)

- Settings > System > **Google's ad sandbox**: **Keep it off** turns off Android's Privacy Sandbox (ad topics, on-device ad auctions and ad measurement, with on-device personalization and federated learning) for the TV's main user, and keeps it off: Hearth checks each time the TV wakes and turns off any part that came back on. It shows the commands first, asks for the Parent PIN if there is one, and turning it off again turns back on exactly what Hearth turned off.

## 2026.10.70 (pre-release)

- Remote buttons: **YouTube button opens HearthTube**, an opt-in switch shown when HearthTube is installed. The remote's YouTube button (Button 3 on Google TV remotes) then opens HearthTube instead of YouTube, in every profile. No button press is needed to set it up.

## 2026.10.69 (pre-release)

- Setup flow: a "Sync with your other TVs" step after the family steps starts a household on this TV (skipped on a TV already in one). Other TVs are added from their Copy screens.
- The Parent PIN prompt can be allowed from a parent's phone: with Home Assistant set up and **Approve switches from my phone** on, the phones of the adults who have it on get an Allow/Deny notification when a kids profile (or anything only a parent may do) asks for the Parent PIN. Typing the PIN still works.

## 2026.10.68 (pre-release)

- After a parent gives a kid more time, Hearth now takes over Google TV's home once the time-up lock clears (it used to stay on Google TV's home until the next profile or Home press).
- Kids profiles no longer list the Play Store: apps added there aren't on Google TV's approved list for the kid and get removed at the next update or restart. Parents add apps in Google TV's Manage apps; the user guide says how.
- Copy profiles between TVs: Streaming app PINs and Home Assistant settings can be ticked as soon as the screen opens (they said "Nothing to send" until a profile was ticked).
- Copy profiles between TVs ignores the spare user Android keeps ready for the next profile; it is no longer offered as a profile to send or to receive into.
- Household sync (first part): TVs can be put in a household, and then keep Profile Pairing choices and saved PINs in step over the home network, encrypted with a key only the household has. People are told apart by their Google account, not their name, so two profiles with the same name never mix. Settings > Profiles > Copy profiles between TVs > Household sync has the one switch; a TV joins by a copy with **Add this TV to my household** ticked. Not yet: the setup-flow step, Parent PIN and look-and-layout sync, Continue Watching, and the Home Assistant mailbox.
- Security: the Home Assistant token is kept encrypted with a key held by the TV's secure hardware, and the Parent PIN is kept as a salted slow hash instead of a plain one. Both are converted the first time they are used; nothing needs to be entered again. (A TV that receives a copied Parent PIN from a TV that has not updated yet still accepts it.)

## 2026.10.67 (pre-release)

- Set up from your phone (Home Assistant): the page now offers to set up TV status for you when you send an administrator's token, and says when it is done. The webhook ID field moved under "I already have a webhook ID".
- Hearth is English only: the 13 machine translations and the Settings > System > Language page are gone (an old language choice in a backup is ignored).

## 2026.10.66 (pre-release)

- TV status: **Create it in Home Assistant for me** (Settings > Home Assistant > TV status, and in the setup flow) makes the helpers and the automation for this TV in Home Assistant, with a new random webhook ID, and turns reporting on. It needs an administrator's token. The Home Assistant side of a TV's status is no longer a manual job.
- Wrong PINs on a PIN pad lock it for 30 seconds after five misses in a row, doubling each time up to five minutes. Hearth checks the certificate's host name when it talks to Home Assistant over https. A kids profile can't be given a Google TV PIN.

## 2026.10.65 (pre-release)

- Copy profiles between TVs on a new TV: with one grown-up profile on each TV, the copy goes onto it whatever the names (kids profiles still need the same name), and streaming PINs are only saved where a parent PIN guards them, this TV's or the one coming with the copy.

## 2026.10.64 (pre-release)

- Copy profiles between TVs can now also send wallpaper pictures (on by default), streaming app PINs, the Home Assistant settings and the parent PIN (each off until the sending parent chooses it, after the parent PIN; the receiving TV chooses again and asks for its own parent PIN). A PIN goes only to a profile paired with that streaming profile and never over one that works; Home Assistant gets a new token made by the sending TV for the other, not a copy of its own; the status webhook id isn't sent. Both TVs need this version.

- Approve switches from my phone: the request also shows as a Home Assistant notification, so someone who opens Home Assistant sees it, and tapping the push no longer opens Home Assistant and dismisses it (use Allow or Deny). A volume, power, media or held key no longer withdraws a request as if someone were typing the PIN.

## 2026.10.63 (pre-release)

- Copy profiles between TVs works on a TV that has no parent PIN yet (a new TV has none): it asks for the PIN only where one is set. 2026.10.62 refused with "Set a parent PIN first".

## 2026.10.62 (pre-release)

- Copy profiles between TVs (Settings > Profiles): a parent at two TVs copies a profile's look, home layout and Profile Pairing choices from one to the other over the home network. Both TVs show the same six digits and a parent says on each that they match before anything is sent. The receiving TV chooses where each profile goes, fits the layout to the apps it has, keeps a backup first (in Backup & Restore) and keeps pairing choices it already has. Streaming PINs, Home Assistant settings, the parent PIN and wallpaper pictures are not copied. Needs trying on two TVs.
- The Home button now turns off "Use Google TV's home" when it opens Hearth, so Hearth takes over after profile switches again.
- Hearth takes over the home after a profile pick even within two minutes of another profile's Google setup screens, and logs why it leaves Google TV's home in front when it does.
- The debugging prompt (to add Hearth to kids profiles) opens Developer options when they are on and only USB debugging is off, instead of telling you to unlock them again.
- Setting up Home Assistant from a phone seals the address, token and webhook id on their way to the TV, as the PIN page does. It needs a recent phone browser, opened from the QR code.
- Continue Watching is on by default (the row still waits for Watch Next access).

## 2026.10.61 (pre-release)

- Hearth on a kids profile no longer gets Hearth's adb key. Hearth in your own profile now re-checks the kids' copies once a day (keeps them from being removed, and lets them read Watch Next and the calendars), and tells a copy that still has the key to delete it; a copy does that the next time its profile starts. If Hearth is ever uninstalled without Settings > Profiles > Remove, the kids' copies stay: docs/development.md says how to release them.

## 2026.10.60 (pre-release)

- Waking the TV can open Google TV's profile chooser instead of the PIN screen: Settings > Profiles > Choose a profile when the TV wakes (every time, or after some minutes asleep). A profile with a PIN asks for it before it opens. It is off until you turn it on, and kids profiles are left alone.
- Disney+: a profile with a PIN is picked and its PIN screen is no longer taken for the profile picker, so the PIN can be typed.
- The Home Assistant panel draws no list of who is where for a map card; a person's tile shows the map when it is focused.
- The log says when Home Assistant took a phone-approval request.

## 2026.10.59 (pre-release)

- **Hearth now needs Android 9 or newer.** A TV on an older Android won't be offered this update.
- Hearth's link to Home Assistant (its notifications and the TV's status) keeps running when Android switches Home Button Fix off, for instance after an update. The pop-up itself still needs Home Button Fix: while it is off, Hearth tells Home Assistant it can't show one. Nothing new to set up.
- Hearth puts itself back on a kids profile by itself even when the TV's USB debugging switch reads off, as long as the TV still trusts Hearth.
- Failures that used to pass silently are now written to the log (never a name or a PIN), so a feature that quietly stays off can be traced.
- A call between Hearth's screens and the TV that failed could leave a setting waiting for good; it now ends with an error instead.

## 2026.10.58 (pre-release)

- Home Assistant's setup asks whether HearthTube may share the title and channel of what's playing (Settings > Home Assistant can change it later).
- Include pre-releases (Settings > Check for Updates) starts on in a pre-release build and off in a release build.
- The home's dock, frosted glass and background are Hearth's own and lighter on the TV; the connection indicator reads the network through a smaller, newer reader.
- "Adult" instead of "grown-up" throughout; the docs are up to date and sorted by who reads them.

## 2026.10.57 (pre-release)

- Approve switches from your phone (Settings > Profiles, in your own profile; needs Home Assistant and its phone app): when Google TV asks for your PIN to open your profile, your phone gets Allow and Deny, and Allow has Hearth enter your Google TV PIN. Typing the PIN with the remote always works too; a key pressed on the PIN screen withdraws the phone's request. Your Google TV PIN can be saved there or on the phone page.
- Shared streaming apps close on a switch between grown-ups even when the TV's USB debugging switch has turned itself off.

## 2026.10.56 (pre-release)

- Disney+: profiles with a PIN are found and picked too (Disney+ labels them differently).
- Streaming app PINs can be set from a phone: Settings > Profiles > Streaming app PINs > Set up PINs on your phone shows a QR code; the PINs typed on the phone are encrypted there, with a one-time key from the QR code, before they reach the TV.
- Remote keys respond faster: Hearth does less on the thread every remote key waits for (app images, Continue Watching, reading Google TV's profile chooser), and asks for focus and scroll events only while Google TV's own screens are up.
- Logs name nobody in Hearth's Flutter part either.

## 2026.10.55 (pre-release)

- Streaming app PINs belong to the Google TV profile that saved them: another profile paired with the same app profile no longer gets that PIN typed. In a grown-up's profile, Hearth types it only when that profile has its own Google TV PIN. Saved PINs move to the profiles paired with them; the app asks for its PIN until the Google TV PIN is on.
- After two PINs in a row that the app doesn't take, Hearth stops typing it until it's saved again. Changing a pairing that has a PIN needs the parent PIN and removes that PIN.
- Settings > Profiles > Streaming app PINs has one switch that turns PIN typing off, and lists the last 20 entries (app, time, outcome; never a name or a PIN). Before the first PIN is saved, a parent reads what Hearth will do, including that the services' terms may not allow it.
- Hearth doesn't type PINs in an app version listed in its repository as one its recipes don't handle (checked at most twice a day while a PIN is saved).
- Hearth and its helpers in the kids' profiles prove to each other that they share a key, without sending it; no other app on the TV can pose as either.
- Profile Pairing listens only to the app it's handling; its research mode ends by itself after 30 minutes. Logs show a stand-in instead of each person's name.

## 2026.10.54 (pre-release)

- Profile button: the remote's profile button opens the profile chooser straight away, and holding it locks your profile (Google TV's PIN screen). Where there's nothing to lock (no Google TV PIN), a hold opens the chooser. It's set up once in Settings > Remote buttons, where it can be changed or restored to Google TV's own. Kids' profiles keep Google TV's own handling.
- Profile switches: switching to a kid's profile shows the welcome card and gives Google TV its moment for bedtime, also when coming from a grown-up's profile. A switch between grown-ups isn't taken as cancelled while Google TV is still catching up. Hearth comes back when one of Google TV's screens (such as its PIN screen) closes onto Google's home, and when Home is pressed there. The volume bar, the keyboard and other pop-ups no longer stop Hearth from coming back. Fewer lost remote presses right after switching to a kid's profile.

## 2026.10.53 (pre-release)

- Security: Hearth's helper in a profile only opens other apps' public screens, never Hearth's own, and passes on no access to Hearth's files. Reading Netflix's and Apple TV's profile and PIN screens and tidying the Home Assistant address can no longer be slowed down by unusual text. The CI workflow only reads the repository.

## 2026.10.52 (pre-release)

- Paramount+ content PIN: save it once in Settings > Profiles > Streaming app PINs, and Hearth types it (behind its cover card) when a title asks for it, only in a grown-up's profile that has its own Google TV profile PIN. Kids' profiles and unlocked profiles keep Paramount+'s own prompt. A wrong PIN is reported, not retried.

## 2026.10.51 (pre-release)

- Weather: the forecast opens on a summary, today's in the day and tonight's from 5 PM (the sky, the high and low or tonight's low, the chance of rain or snow, now or tomorrow's high). OK goes on to the next hours, the next days and back.
- Calendar: without calendar access the date and time can still be selected, and OK asks for access.

## 2026.10.50 (pre-release)

- Home Assistant panel: selecting a person shows where they are on a small map, with home marked. The map is drawn from map pieces of the area around home, fetched once and kept on the TV, so the map service never learns where anyone is; someone farther away (or without a position) shows their status as before.

## 2026.10.49 (pre-release)

- YouTube time per day applies to kids' profiles only: a grown-up's profile is never limited or locked (a limit set on a grown-up's profile by an older Hearth is ignored). Each kid's is set on their page in Settings > Profiles > Kids' profiles.

## 2026.10.48 (pre-release)

- Home Assistant panel: no "Open the full dashboard" row (the setting to show Home Assistant's own page instead stays). App icons in the screen time cards are kept on the TV for 30 days and show offline too.

## 2026.10.47 (pre-release)

- Fixed: after Hearth's "Hi, <name>" card on a switch to a kid's profile, Hearth now takes over instead of leaving Google TV's kids home up.

## 2026.10.46 (pre-release)

- Kids' bedtime and time-up screens show again when switching to a kid's profile: Hearth gives Google TV's kids home the 3 seconds it needs (measured on the TV) and shows its own "Hi, <name>" card over it meanwhile.
- Home Assistant panel: app icons (pictures) in text cards and entity pictures on tiles; when a card the selection is on goes away (a player stops), the selection moves to the next one down.

## 2026.10.45 (pre-release)

- Profile photos: any profile without a PIN is photographed from Google TV's chooser when its tile is selected for a moment (the kids' photos fill in).

## 2026.10.44 (pre-release)

- The Home Assistant panel is now drawn by Hearth from your dashboard, so everything in it works with the remote: thermostats (− / + and modes), players (play/pause, skip, volume), lights (on/off, brightness), scenes, sensors, cards that show only when something is on, text cards with headings and icons, and where everyone is. Cards Hearth can't draw are left out; "Open the full dashboard" at the bottom shows Home Assistant's own page, and a setting can make that the default.

## 2026.10.43 (pre-release)

- Calendar: the date and time now show the TV's own Google calendars (each profile its own account's, kids' profiles included), with no Home Assistant needed. Choose calendars in Settings > Home screen > Status bar > Calendars. Needs calendar access (read only, stays on the TV).
- Data usage: select the data pill to see which apps used the TV's data (today, this week or this month with OK), the connection, and VPN; the pill says "No internet" when the TV is offline. On Ethernet, Android doesn't count data per app.
- Kids' profile photos are picked up on any visit to Google TV's profile chooser, not only a slow one.
- Continue Watching: an app that bounces straight back to Hearth (Paramount+ when already running) is opened again, unless a button was pressed.

## 2026.10.42 (pre-release)

- The selection lands where it should with the dock on or off: on the first app at the top (not an empty section) without the dock; after removing or hiding the selected app; after closing search results; when switching the dock in Settings (the selection stays in Settings); and moving the first app keeps the page at the top.

## 2026.10.41 (pre-release)

- The top bar's pills (profile name, data, weather, date and time) share one look: the same height and darkness. The weather pill shows just the current conditions (warnings like "Rain tomorrow" are off by default, under Status bar settings).
- Settings: Applications is now under Home screen.

## 2026.10.40 (pre-release)

- Fixed: switching to a grown-up's profile could leave Google TV's home up (after an account check, Hearth took a tab on Google TV's home for a new profile).

## 2026.10.39 (pre-release)

- Home Assistant settings: a text field only becomes editable after pressing OK on it, so moving through the page never opens the keyboard.

## 2026.10.38 (pre-release)

- Calendar: with Home Assistant set up, the date and time in the top bar show the rest of today's events when selected, and OK shows the next 7 days. Settings > Home Assistant > Calendars picks which calendars each profile shows. Without Home Assistant nothing changes.

## 2026.10.37 (pre-release)

- After switching to a grown-up's profile with its PIN, Hearth comes back instead of leaving Google TV's home up.
- Grown-ups aren't asked for the parent PIN while they're using the remote; it's asked again after five minutes without a button press. Kids' profiles always ask.
- Streaming apps shared by the grown-ups ask who's watching after a profile switch, so Profile Pairing picks the right app profile (Netflix opened in the last person's profile).
- Disney+ profiles with a PIN are recognized, so they can be matched and chosen in Profile Pairing.
- Continue Watching: an entry belongs to the profile that last had the app, even if another profile played it earlier.

## 2026.10.36 (pre-release)

- Kids' bedtime and time-up screens show again: Hearth gives Google TV's kids home a moment before covering it every time (it had stopped once the kid's apps looked unblocked, which kept Google from ever blocking them).
- Continue Watching in kids' profiles shows what the kid watched (Hearth's copy there couldn't read the list). Grown-ups' entries are no longer cut to the newest 20 before Hearth knows whose they are.
- An episode no longer shows twice in Continue Watching when the app names show and episode together.
- Home Assistant panel: each profile can pick its own dashboard and view from Home Assistant's list.

## 2026.10.35 (pre-release)

- Home while browsing the apps goes back to the dock, or to the first app at the top when the dock is off (it also ends a search). With the dock off, a profile switch now lands on the first app too.
- The Home Assistant panel opens at once: its dashboard loads in the background when the panel is on and stays loaded while it's closed (it's let go if Android runs short of memory).

## 2026.10.34 (pre-release)

- The remote's profile button opens Google TV's profile chooser again (Hearth was covering it with its home).
- Switching between grown-ups' profiles no longer falls back to the last profile when Google TV's home is slow to say who's logged in.
- After a profile switch that Google TV cancels, the selection goes back to the dock (or the first row without a dock), not the top bar.

## 2026.10.33 (pre-release)

- Kids' profiles: Hearth (and HearthTube, when it's installed) goes on every kids' profile from the setup flow, and new kids' profiles get it automatically. Settings → Profiles shows each kid as Ready or Needs a fix with one Fix button, and a page per kid with how Hearth stands there, HearthTube, and its YouTube time per day, set without switching profiles. HearthTube can be added to a kid from that page, even from inside the kid's profile.
- Streaming app PINs (Settings → Profiles): each profile sets its own, kids' profiles included (behind the parent PIN), without pairing by hand first.
- Pushing Hearth into grown-ups' profiles is gone (they share the TV's main user).

## 2026.10.32 (pre-release)

- With HearthTube installed, kids profiles watch YouTube only in HearthTube (where their YouTube time applies): YouTube's own app is hidden, and opening it anyway opens HearthTube. Grown-ups' profiles start with YouTube hidden too.

## 2026.10.31 (pre-release)

- Dismissing one notification no longer dismisses all of that app's notifications (Android's group summary no longer shows as a notification of its own).
- The weather shows in the top bar by default (once there's weather to show).

## 2026.10.30 (pre-release)

- After entering the PIN on Google TV's profile lock (when the TV wakes, or Lock Profile), Hearth comes back about a second sooner.

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
