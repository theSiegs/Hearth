# Household sync (design)

> **Design, version 2.** Version 1 (built in 2026.10.68 to 2026.10.74) gave every TV of a household one shared key and
> joined a TV through Copy profiles. Version 2 gives each TV its own key, makes the household a list of members, and
> folds Copy profiles into sync. What is built and what changes is in [From version 1](#from-version-1).

## Goal

Someone turns on any TV in the house, picks their profile, and finds things as they left them on another TV: their
look and home layout, their Profile Pairing choices, their streaming app PINs, and Continue Watching. No cloud account,
and no Home Assistant needed. Home Assistant, when there, makes it better.

Not a goal: keeping every setting equal. A TV's own settings (its name, Wi-Fi, permissions, the Home Assistant webhook
and token, Home Button Fix, the ad sandbox) stay on that TV.

**One idea for the person using it: "Your TVs".** There is no separate copy, sync and household to understand. Every
Hearth TV is in a household, even when it is the only one. A TV on its own that hears another household on the network
offers to join it; a TV in a household lists its TVs. Joining is the first sync. Settings > Family > **Household sync**
replaces both Copy profiles between TVs and Household sync.

## Terms

- **TV key**: a key pair each TV makes for itself, kept in the Android Keystore (EC P-256, signing only, so it works
  on every supported Android version). It never leaves the TV. The **TV id** is a hash of its public key.
- **Household**: the TVs on one **member list**. The list is itself synced. There is no household-wide secret that
  proves membership; a TV is in because the others list its public key.
- **Entry**: one synced value, with an id, a person, a value, a timestamp, the TV that wrote it, and a deleted flag.
- **Profile match**: profiles differ in number from TV to TV (Android numbers its users per TV), so entries name the
  person by an id made from their Google account, and each TV maps that id to its own profile key; see Who a profile is.

## What syncs

| Kind | Per | Notes |
|---|---|---|
| Members | household | the member list; see Members |
| Profile Pairing | profile and streaming app | the chosen app profile, or "always ask" |
| Streaming app PINs | profile and streaming app | secret |
| Look | profile | wallpaper kind and pictures, day/night picture, gradient, theme, clock/format choices |
| Home layout | profile | the dock, rows, app order, hidden apps, per-profile panel choices |
| Continue Watching | profile | Hearth's own watch history (see below) |
| Parent PIN | household | including every change to it; see Parent PIN |
| Notifications | person, or every adult | Home Assistant's, and a TV asking to join; see [Notifications](#notifications) |

Never synced: the Home Assistant token, the webhook ID, the TV's name (each TV announces its own), permissions,
anything about a TV's hardware. The Home Assistant address and a token are handed over once when a TV joins, when the
adult who allows it says so (see Joining); the TV then makes its own webhook.

**Per person, and per TV.** Everything a person picks for how their home looks follows them; what belongs to the TV
stays on it. Checked setting by setting (SettingsService's keys, the layout's tables, the pictures):

| Follows the person (per profile) | Stays on each TV |
|---|---|
| Wallpaper: gradient, Bing's photo of the day, day/night switching, the picked pictures (any, day, night) | The TV's name, its Home Assistant address, webhook and token, Home Button Fix, the ad sandbox |
| Theme: card shape, accent colour, highlight and click choices, app names under icons | Start on boot, the temperature unit, updates (pre-releases), the setup flow's progress |
| The dock (the Favorites row) and its apps and order, its blur, shadow and background | Watch Next programs a profile hid (Android's ids on this TV; a removed card syncs through Continue Watching) |
| Rows: which rows, their order, sort, size and columns; spacers | Apps not installed here (kept in the person's entry, see below) |
| Which apps are hidden | The once-per-TV notice before the first streaming PIN is typed |
| Top bar pills: date, time and their formats, Wi-Fi data, inputs, notifications, weather and its warnings | A calendar hidden by its id on this TV, from before calendar keys, until the calendars are next read |
| Which calendars a profile hides, each by its key (see Hidden calendars below) | |
| Continue Watching's look (card size, how many, order, progress, description), the apps it leaves out | |
| The Home Assistant panel: on or off, the dashboard, full or not | |
| What Back does on the home screen | |

**The newest change of each item wins.** A look entry and a layout entry each hold a whole profile's, but a
conflict is decided item by item, each with the time it last changed (the entry's `~at` for the look, `at` for the
layout; a TV that doesn't know them ignores them). The items are each setting (each hidden calendar is an item of its
own, "calendar:<key>"), the list of rows and spacers ("rows"),
each row's apps and their order ("row:<id>"; the dock is a row) and each app's hidden or not ("app:<package>"). A TV
notes what changed in a profile since it last looked, with when; when the household's entry arrives, an item changed
here later than the household's last change of it keeps this TV's, the rest take the household's, and the result goes
out. So Alex changing the accent on one TV and the dock on another while they can't see each other keeps both, and a
TV that joins (nothing on it has changed since it started counting) takes the household's, as Joining says. Only a
difference in the look or layout itself goes out, never one in stamps alone, so a TV from before stamps and a newer
one don't trade the same entry back and forth.

**Hidden calendars.** A calendar's id in Android's calendar store is only a row number on that TV, so a profile keeps
the calendars it hides by a **key** instead (TvCalendars.keyOf): "cal:" and the first half of a SHA-256 of the account
(its address in lower case and its type) and the calendar (its owner account, which for a Google calendar is the
calendar's own address and survives a rename; else its name). Where the same Google account is on two TVs, its
calendars have the same keys on both; the key names no account in the clear, and it moves only inside the encrypted
log. Each hidden calendar is a look item of its own, so hiding one on one TV and another on another keeps both, and the
later of hiding and showing one wins. A calendar hidden only where it exists (its account is on one TV) keeps its flag
in the person's look, so it applies when the calendar shows up on another TV; a household entry that doesn't mention a
calendar and has no stamp for it (a TV from before keys, or a TV that just joined) doesn't show it again, nor does one
that gives back this TV's own stamp. A profile's calendars hidden by their id here before keys get their keys the next
time that profile's calendars are read (it's on screen); until then they stay on this TV only. A kids profile's
calendars come from its agent, which reads them in its own user and sends the same keys (a kids profile's agent from
before keys sends none, and its calendars are hidden by their id there, on that TV only). Without household sync a
profile's hidden calendars work as before, by key, on the one TV.

**An app missing on one TV.** A TV without an app leaves it out of the home but keeps the household's place for it
(its row and order, hidden or not, and when that changed) in what it gives, and can't change it: only a TV that has the
app decides about it. Installing the app later brings it back where the person put it.

**Look and layout are where conflicts get visible.** Two TVs with different screen sizes show the same layout, so a
layout entry stores order and choices, never pixel positions. An app that isn't installed on a TV is skipped there and
kept in the entry, so it comes back when the app is installed. Wallpaper pictures are large: an entry carries the
picture's hash, and the picture itself moves only to a TV that lacks that hash. Bing's photo of the day and gradients
are just settings.

**How look and layout are built (step 3).** A profile's look is one entry (`look`: its chosen settings, the same ones a
copy carries) and its layout another (`layout`: apps and whether each is hidden, rows, placements, spacers, without app
names, which are each TV's own). Both are written in a fixed order, so the same layout is always the same text. The
app's side does the work, every 20 seconds while Hearth runs (HouseholdLooksService):

- **Taking.** For each profile, kids' included, whose look or layout entry changed, it merges the household's with this
  TV's item by item (the newest change wins, see What syncs), fits the result to the apps installed here (as a copy
  does) and puts it in place: live when the profile is on screen, else in the profile's saved layout, which comes up
  when someone switches to it. The profile's settings that stay on each TV (its Watch Next programs, and calendars
  hidden by their id here from before keys) are kept as they are. A changed picture is written to the profile's folder. Before a profile first takes
  the household's look on a TV, everything is kept as a backup, as a copy does, so it can be undone in Backup & Restore.
- **Giving.** The profile on screen goes out when its look or layout differs from the household's, or a picked picture
  from what this TV last took or gave; so does any other profile here that the household has no look or layout for yet
  (one set up only on this TV, or on a TV that just joined). Its layout keeps the household's apps that aren't
  installed here, and their places in rows it still has, so a TV without an app doesn't take it away from the others.
- What this TV last took or gave is remembered per profile (by fingerprint), so taking the household's doesn't send it
  straight back, and two TVs settle on one layout; and so is each item as this TV last had it and when it changed
  here, so a change made here between two rounds isn't lost to the household's.
- **Pictures.** Only pictures someone picked for a profile move between TVs. Bing's photo of the day is a setting, and
  each TV downloads it; a future Google Photos source would be the same, its album or photos a setting and each TV
  fetching them. A picked picture goes out as the screen shows it (a JPEG of at most 1920x1080, as a copy sends it), is
  kept once per TV by its SHA-256 (HouseholdPictures), and moves at the end of an exchange to a TV whose entries name it
  and lacks it. A TV checks that a picture it takes is a JPEG of a wallpaper's size and has the hash it asked for.
- **Kids profiles** sync like any other: Hearth in the owner's user is every profile's home and keeps each one's layout
  (a kids profile's own Android user only runs Hearth as its agent), and a kid is the same person on every TV by their
  Google account, as for PINs and pairings. A kid's layout is fitted to the apps installed here, and the apps a kids
  profile hides by default are hidden again when it is switched to.

**Continue Watching** syncs Hearth's own per-profile watch history (the app, title, episode, how far, when, and the
deep link that opens it), not Google's Watch Next, which ends in 2027. Opening an entry on another TV launches the same
title in the streaming app, which resumes from its own account's saved position, so Hearth carries a card, not a
playback position it can't act on. A title finished (95% or more) anywhere is finished everywhere. An entry only moves
when the streaming app profile it was played under is known on the receiving TV.

**How Continue Watching is built (step 6).** One `watch` entry per person, app and title: the item is
`played|<package>|<title|episode>` for what an app said was playing (WatchHistory's played entries) or
`kept|<package>|<app's id or title>` for a Watch Next entry Hearth kept for the person, the value its title, episode,
length, position and time, plus for a kept one the Watch Next row itself (deep link included, and only for the app it's
filed under). The Java side does all of it (HouseholdWatch, Household), so it runs whenever Hearth's accessibility
service does, Hearth's screen open or not:

- **Giving.** A play saved here (PlaybackRecorder, every few seconds while something plays) or Continue Watching read
  here asks for a sweep a minute later; the five-minute periodic round and the service starting sweep too. A sweep
  writes each person's 40 newest titles of this TV's own (not ones taken from the household) that differ from the
  log, then the usual exchange follows two seconds later. A title isn't written over a newer play from another TV,
  nor over a removal, unless it was played here since.
- **Taking.** After every exchange, the entries it brought go into the watch history as the household's (a `shared`
  column, so they never go back out as this TV's), when they're newer than what this TV has for that title and less
  than 90 days old. Every round and every service start applies them all again, for a profile whose Google account
  Hearth has only seen since. A kept one shows as an entry the app here doesn't list, until its person opens that app
  here (then the app's own list is the truth).
- **Removing.** Taking a card out of Continue Watching, or the app letting one go for its own profile, deletes the
  entry; the other TVs drop it unless it was played there since.
- **Showing.** Continue Watching shows the profile on screen its own synced titles as it shows its own played and kept
  ones; one from an app that isn't installed here stays in the history but isn't shown. A "continue" card whose title
  its profile has since played to the end, on any TV, is left out (an up-next card stays).
- **Kids profiles.** A kids profile is its own Android user with one profile in it, so every Watch Next entry its agent
  reports is that kid's. Each report (AgentHub's `watchNext`, as it arrives, and each read of the kid's row) goes
  through WatchHistory: the rows are kept under the kid's profile key, one the kid's list no longer has is let go
  (it was finished or removed there, so it goes from the other TVs too), and the household's entries for the kid that
  the list lacks are added, in apps the kid has (approved there). The kid is the same person on every TV as for looks
  and PINs (their Google account, else their name). Only the kid's own entries are read for the kid's row, and the
  adults' row reads only the owner's user's, so a kid's card never shows to an adult or another kid, nor an adult's to
  a kid. What plays in a kids profile's apps isn't seen (its media sessions are in its own user), so a kid's titles
  are their Watch Next entries only. Opening a kid's card from another TV goes through the kid's agent as any of
  their cards does (the app opens in the kid's user from the deep link).
- **Posters.** A kept card's poster address is the app's on the TV that sent it, which another TV often can't load. So
  a kept card goes out with its poster as a household picture: read as for the row, a JPEG at most 320 px wide and
  64 KB, named by its SHA-256 in the entry's value (`ph`) and kept in HouseholdPictures, made once per poster address
  (WatchHistory's `posters` table; an address that gave none is tried again after a day; ten new ones a round at
  most). Pictures move as wallpapers do (asked for by hash when missing, checked as a JPEG of that hash), wallpapers
  first. The receiving TV shows the card with `hearth-poster:<hash>` as its poster, served from that file. A picture
  goes when no live entry names it any more, after each exchange. A kid's poster whose address is in the kid's own user
  (content://) can't be read from the owner's, so only one with a web address goes along.
- Entries older than WatchHistory's 90 days leave every TV's log.

## Members

The member list is entries of kind `member`, one per TV: its public key, its name, which member added it and when.
Every TV on the list keeps the whole list, so each knows every other, even two that are never on together.

- **A TV syncs only with listed TVs.** Each exchange begins with both TVs proving they hold the private key of a listed
  member (see Moving entries). A TV not on this TV's list gets nothing and can send nothing.
- **Adding** a TV is one new `member` entry, written by the member that approved the join, naming itself as the TV
  that added it, and signed with its TV key (see [What's checked](#whats-checked)).
- **Removing** a TV deletes its `member` entry (the removal). It spreads like any change, and each TV that takes it
  stops talking to that TV. No key changes, and the TVs that stay do nothing.
- **A removal is final for that key.** It beats any write for that TV, a later one included, nothing written after it
  replaces it, and it is never purged. A removed TV comes back only by joining again, which gives it a new TV key and so a new
  id; it shows as a new member.
- Each TV still writes its name into its own `member` entry when renamed, and refreshes it once a day, so the list shows
  current names and when each TV was last on.

**Removing, from the person's side.** Each TV on the Your TVs page has **Remove from household**. On this TV's own row
it means leave; on another TV's row it removes that TV. Removing another TV asks a parent (Parent PIN, or phone
approval where it's on). A TV that hasn't been seen for 60 days is marked "Not seen for 2 months" with Remove next to
it; nothing is ever removed on its own.

**Leaving** (removing this TV) writes this TV's own removal and tries to hand it to the TVs that are on now (for up to
ten seconds). The first exchange that carries it ends the household here: the TV deletes its key, its entries and its
member list. If no other TV is on, the TV stays only to do that, taking no settings from the household and giving none,
until the first household TV it meets, for up to 90 days; until then the others still list it, as they would a TV that
was switched off.

**A removed TV that was off** finds out when it next tries to sync: the TV it reaches refuses it and says why, in a
message signed by that TV's key. It then shows "This TV was removed from the household", drops what it held, and offers
Join.

**What removal can't do.** A removed TV keeps the copies of entries it already had (true of any design), and between a
removal and the moment a given TV hears of it, a removed TV and that TV can still exchange entries. These are the
family's own TVs, so that window is accepted; it closes as soon as either of them meets a TV that has the removal.

## Joining

A TV joins from its own screen, and someone allows it from the notification Bell of the TV it asked.

1. The new TV, on its own, hears TVs of a household on the network (`_hearth-sync._tcp`; each announces its TV id, its
   household's id and its name). Your TVs, and the setup step, show that household's TVs and a **Join** button.
2. Join connects to one of those TVs that is on, on its sync port (a sleeping TV answers too: its sync service runs with
   the screen off), and says it is a join request (`HHJ1`), with its name. They run Copy profiles' key exchange, in
   which each side commits to its key before seeing the other's, so a device in the middle can't steer the result, and
   both derive the same join code (six digits). The new TV says which TV it asked: "Allow it on Office".
3. The household TV puts the request in its **notification Bell**, and in the Bells of the household's other TVs (see
   [Notifications](#notifications)), on adults' profiles only (never while a kids profile is on), and pops it up:
   "Kitchen wants to join your TVs", with **Allow** and **Don't allow**, answered on any of them. The request shows
   the join code, "Check that the new TV shows 123 456 before you choose Allow", so the adult compares it with the new
   TV's screen: a device on the network that put itself between the two TVs (and named itself after the new TV) gets
   another code. No Parent PIN: accepting needs none. Clearing it is Don't allow.
4. On Allow, the household TV sends an invitation over the sealed session (see The invitation, below). When the new
   TV has no Home Assistant connection and asks for one, and the asked TV has one, the TV where Allow was chosen first
   asks on its own: "Also give Kitchen this TV's Home Assistant connection?", with **Give it** and **Don't give it**.
   No is the default: clearing it, or a minute without an answer, joins the TV without it. Given, the asked TV makes a
   new long-lived token with its own (as before), so it is for the Home Assistant user this TV's token is, the one its
   Home Assistant panel signs in as, and shows in that user's profile, where it can be revoked.
   The new TV joins with it, and their first exchange lists it.
5. **A TV that already has its own setup**: for an entry both have, the household's wins; settings only this TV has are
   kept and synced out. Before anything is replaced the new TV shows what will change and keeps a copy to put back
   (see Before joining, below).

The new TV never sends the Parent PIN, and nothing secret moves before the Allow. Denying, or no answer in five
minutes (time to walk to the other TV and turn it on), ends it with nothing sent; so does the new TV hanging up (backing
out, or going off): the asked TV sees the connection close within a second and takes the request out of every Bell. A
household TV answers one request at a time, and after one that wasn't allowed it ignores requests for 30 seconds, and
requests from that address for longer each time one in a row isn't allowed (30 seconds, then a minute, two, and so on
up to an hour; a day without one, or one allowed, starts it over), so a device can't keep the Bells full.

**Before joining: what changes, and putting it back.** "The household wins" means a TV with its own setup loses
things on joining, so it shows them first and keeps a copy:

- **Held.** A TV that joined through a request (HouseholdJoining) is *reviewing* until someone decides. It is a
  member and exchanges entries, but takes none of the household's settings and gives none of its own: no pairings or
  PINs are applied or published (HouseholdBridge), and the app neither takes nor gives looks, layouts, pictures or the
  Parent PIN. Continue Watching isn't held: it only adds the household's titles, it replaces nothing.
- **Preview.** Once the first exchange has brought the household's entries, the join screen lists what would change,
  per person and only where it differs from this TV: "These will change on this TV: Alex: look, home layout, 2
  wallpaper pictures, the profiles picked in 3 streaming apps, 1 saved PIN", plus the Parent PIN when this TV has none
  and the household has one (a different Parent PIN here is kept until it's entered, see Parent PIN), and saved PINs for
  the whole TV. The Java side counts pairings and PINs (HouseholdJoinReview.changes); the app compares looks, layouts
  (only the apps installed here count) and pictures. When nothing would change it goes on without asking.
- **Join and use these** keeps the copy, then ends the hold: the household's entries are applied and the next round
  takes its looks (the newest-change rule finds nothing here newer, so the household's win, as before). **Don't join**
  leaves the household (see Leaving); nothing on this TV changed. **Later** closes the screen; the Household page
  offers **Finish joining** until someone decides, and the TV stays held meanwhile. If the entries haven't come yet,
  the screen says so (the TV that let this one in may have gone off).
- **The copy.** The app keeps each listed profile's look and layout (the live one as its backup, the others' saved
  layouts) and its wallpaper pictures in a folder of its own, and the Java side keeps every profile's Profile Pairing
  choices and saved PINs (the TV's own too), sealed under a Keystore key as other secrets are. Kept 14 days, then
  deleted, whether or not anyone opens the Household page: both sides check when Hearth starts and once a day. The
  usual Backup & Restore backup is still made too.
- **Put back.** The Household page shows **Put back this TV's settings from before it joined** while the copy is kept
  (asking for the Parent PIN where there is one). It restores the looks, layouts and pictures, and the pairings and
  PINs this TV had, and deletes the copy. What the household added that this TV never had (a PIN for another app) stays:
  taking it away would take it from every TV. The TV stays in the household, and what was put back is the newest
  change, so the other TVs take it too for the same people; to keep a TV different, leave the household instead.

**The first TV** makes its TV key and a one-TV member list during setup, so there is no "start a household" step. A TV
on its own that hears a different household on the network still offers Join; **Start a separate household** only
exists as a small choice under it, for the rare home that wants two.

## Who a profile is

Google TV makes the profiles, not Hearth, so Hearth can't stop two profiles getting the same name when they are created.
It doesn't need to: sync identifies a person by their **Google account**, not by their name.

- Hearth already reads each profile's Google account address from Google TV's profile chooser (the calendars use it).
  Sync turns it into a **person id**: a keyed hash of the address under the household's **person salt**, 32 random bytes
  the first TV makes and a joining TV receives. The address itself never leaves a TV.
- The salt isn't a membership secret and isn't changed when a TV is removed: entries only travel between members, who
  can read the addresses on their own screens anyway. It keeps the addresses out of the entries themselves (and out of
  the Home Assistant mailbox), and makes ids differ from one household to another.
- Entries name the person by that id. Two people called the same are two ids and never mix; one person who is renamed in
  Google TV keeps their entries; the same person on two TVs is the same id.
- The name stays for display only (Your TVs says "Alex's" settings, not an id).
- A profile whose address Hearth hasn't seen yet (it hasn't been shown in the chooser) has no person id yet; it neither
  sends nor takes entries until the chooser has shown it, which happens the first time anyone picks a profile. Nothing is
  renamed and no one is asked anything.
- An address can be in two profiles on one TV (an adult added twice); the first one seen counts, the second is left out,
  so one person's settings are never applied twice.

## Notifications

A notification one TV receives is in the notification Bell of every TV of the household, cleared on one is cleared on
all, and each shows only to the profile it is for. Two kinds so far: Home Assistant's, and a TV asking to join. Apps'
own Android notifications stay on their TV (they belong to that TV's apps, and their buttons only work there).

**Who a notification is for.**

- **A person.** Home Assistant names them with the notification's `for` field: a profile's name ("Alex"), its Google
  account address, or its key as Hearth's Home Assistant integration lists profiles ("user:10"). The TV that receives
  it turns that into the person id (see Who a profile is), so every TV shows it to the same person, whatever their
  profile is called or numbered there. A name two profiles share names neither. A `for` that no profile on the
  receiving TV is gets a 404 from that TV and is shown to no one: a notification meant for one person is never shown
  to someone else.
- **No one named: every adult.** A notification without `for` is the household's ("The wash is done", "Someone is at
  the door"), so it goes in every adult's Bell. The other choice, the adult on screen when it came, fails when a kid
  is on, or no one is: the notification would belong to no one, or to whoever had last been on. (Open question.)
- **Kids' profiles** see nothing for every adult and nothing for another person. A notification addressed to a kid
  (`for` naming the kid's profile) shows in that kid's Bell only.
- **The pop-up** over what's playing works as before for a notification for everyone (Home Assistant chose to send it
  to that TV). One for a person pops up only when that person's profile is on screen; otherwise it is only in their
  Bell. A notification that came from another TV pops up as a small card when it is under two minutes old and the
  profile it is for is on screen (a TV asking to join, while it waits).

**How it travels.** Each notification is one `notice` entry in the household log: the person is the target person id,
or "" for every adult; the item names the notification; the value holds what it says (title and text, cut to 200 and
1,000 characters), when it was written and when it ends, and Home Assistant's buttons (below). The camera stays in
the pop-up of the TV that received it. The item of a Home Assistant notification is a hash of its person and its `tag` when it has one (a later one
with the same tag replaces it, as on Home Assistant's phone app), else of its person, title and text, so the same
notification sent to every TV (one `notify` per TV) is one notification, not one per TV, and sent again after it was
cleared it shows again (a newer write). A TV that isn't in a household, or has sync off, keeps its notifications to
itself, in memory only.

**Clearing.** Clearing one in the Bell (or **Clear all**, which leaves a TV asking to join) writes a delete for that
entry, which reaches the other TVs like any change; the newest write wins, so a clear beats the notification it cleared
and loses to the same notification sent again later. Home Assistant can clear one with the message
`clear_notification` and its `tag`. A notification for every adult cleared by one adult is cleared for all of them.

**Buttons.** A Home Assistant notification's buttons (up to three, each a title and a service call, as
HaNotificationServer allowed them) travel in its entry, so every TV's Bell shows them, and a notification from another
TV pops up with them when Hearth's accessibility service can draw the card (else as the small card, without them).

- **What travels.** Only buttons the receiving TV's server allowed: a title, a service `domain.service`, data that is
  an object of at most 1,000 characters. All of them or none (none when one doesn't fit), so a button's number is the
  same in the pop-up and in every Bell. Every TV checks them again, the same way, when it reads the entry; an entry
  with a button that fails is shown without buttons. An entry can't name anything Home Assistant's own notification
  couldn't.
- **Pressing.** On a TV with its own Home Assistant connection (an address and a token), or on the TV that received it,
  pressing a button deletes the notification (so it goes from every TV, as a clear does) and then calls the service
  with that TV's token. A TV without one writes a `notice_press` entry for the notification (same person and item):
  the button's number and when the notification was written. It hides the notification at once there, and on every
  TV that has the press.
- **Run once.** The TV that wrote the notification takes a press for a notification it still holds, written at that
  time (a later one with the same tag isn't the one pressed), with a button of that number in its own copy. It deletes
  the notification first, then runs the button from its own copy, so the press never names a service, it runs at most
  once there, and a second press anywhere finds the notification gone. A press it hears more than two minutes after it
  was pressed only clears it (an "Unlock door" mustn't happen long after because a TV was off). Presses leave the log
  with notifications, three days after they were written.
- **Who can press.** Only what the Bell shows the profile on screen, so kids' profiles never get an adult's buttons.
  The pop-up on the TV that received a notification for everyone works as before over any profile (Home Assistant
  sent it to that TV), and pressing there clears it from every Bell too.
- **What isn't guaranteed.** Two TVs that each have their own Home Assistant connection, pressed within the same
  couple of seconds (before an exchange), can each call the service; so can one of them and the receiving TV when a
  press from a third TV reaches the receiving TV first. A press asked of a TV that is off and stays off runs nothing,
  and the notification stays hidden where the press is held.

**Expiry.** A notification, cleared or not, leaves every TV's log three days after it was written, and the Bell before
that if its own end comes first (a join request's, five minutes). Its delete is always newer than what it cleared, so
the delete stays as long as the notification could come back from a TV that was off.

**A TV asking to join.** The TV that was asked (it holds the request's connection) writes a `notice` for every adult,
its item `join:<a random id>`, naming the TV that asks and itself, with the join code and whether allowing it asks
about the Home Assistant connection. Every other TV shows it in adults' Bells with **Allow** and **Don't allow** ("It
asked Office, which lets it in. Check that the new TV shows 123 456 before you choose Allow"); the asked TV shows its
own Bell item, as before. An answer on another TV is a `join_answer` entry for that item (`{"allow", "ha"}`: an Allow
asks about the connection there first, and says what was chosen), which reaches the asked TV with the next exchange
(two seconds later, both being on); that TV takes it as if pressed on its own screen. An Allow from a TV of an older
build says nothing about the connection, so it isn't given; a request from an older asked TV carries no code (its
Bell item says so in its old words) and its Allow asks nothing more: that older TV hands over its connection on any
Allow, as it always did, until it updates. The request is still decided once:
the asked TV takes the first answer it hears, its own or another TV's, and a later one changes nothing. When the
request ends (answered, or five minutes without an answer), the asked TV deletes its notice, which takes it from every
Bell. A TV that answered hides the request at once. Clearing it is Don't allow, as on the asked TV.

**Privacy.** A notification's text is an entry like any other: sealed at rest under the TV's Keystore key, sealed in
each exchange, and, when the Home Assistant mailbox is built, sealed per member there. Only the household's TVs read
it; people are named by their person id, never their address. A log line about a notification never holds its text.

**How it's built.** HouseholdNotices (the rules), Household (writing, clearing, answering and what the Bell shows the
profile on screen, on the household thread), HearthBellItems (the Bell's items and buttons) and HaNotificationServer
(`for`, `tag` and the buttons it allows).

## Moving entries

**The channel.** Two members open an exchange with a fresh ECDH (P-256) each, and each signs the transcript (both
ephemeral keys and both TV ids) with its TV key. Each side checks the other's signature against the public key on its
member list, and that the id isn't removed. Every frame after that is sealed with ChaCha20-Poly1305 under keys derived
(HKDF) from the shared secret, with a counter per direction, so the exchange can't be read, altered or replayed, and only
listed TVs can take part.

**At rest.** Each TV keeps its entries sealed under a Keystore key of its own (a PIN entry holds the PIN), as version 1
does.

**Baseline: TV to TV.**
- Each TV announces itself on the home network (`_hearth-sync._tcp`: its TV id, its household id, its name and port)
  and listens on one port, answering only home-network addresses (LocalNet). The household id is a hash of the first
  TV's id; it names the household and proves nothing.
- A TV that changes an entry tells the others it can see. They pull.
- A TV that wakes, or sees another appear, exchanges **version vectors** (one counter per TV) with it and asks for what
  it lacks. While two TVs are on together they check again every few minutes as a backstop.
- Changes travel only while at least two TVs are awake together. A TV that has been off for days catches up the next
  time it meets any other.

**Optional: Home Assistant as a mailbox.** With the Home Assistant address and a token set, each TV also publishes its
changes to a Home Assistant entity (a `sensor` set through the REST API), sealed separately for each member's public key,
so Home Assistant only ever holds ciphertext and a removed TV can't open anything written after its removal. A household
is a handful of TVs, so sealing per member is cheap. Because the mailbox may vanish on a restart of Home Assistant,
every TV republishes what it has on its 10-minute heartbeat; nothing relies on Home Assistant keeping it. Without Home
Assistant everything above still works.

**Conflicts.** One rule per entry: the newest write wins. Each TV stamps entries with its own clock, which Android
sets from the network, so the clocks agree to within a second or two and nothing syncs time itself. A hybrid logical
clock keeps a TV whose clock jumps from winning forever; a tie goes to the lower TV id. A delete is an entry with a
deleted flag and a timestamp, kept for 90 days, so a TV that was off can't bring a deleted PIN back. Exceptions:
removals never lose and are never purged; Continue Watching is a set (union, newest play per title); a
profile's look and layout merge item by item, each setting, row and app on its own (see What syncs).

**Size.** Entries are small, except pictures and watch history. History keeps at most 100 entries per profile, 90 days.
A TV never sends a picture a peer already has.

## One switch

**Settings > Family > Household sync > Sync with my other TVs** is one switch, on by default, and it covers every profile,
kids' included: a kid follows themselves from TV to TV like anyone else. Turning it off needs the Parent PIN, stops this
TV sending and taking entries, and leaves what it has; the TV stays on the member list. There are no per-kind or
per-profile switches. A kid's synced Continue Watching is still per streaming app profile, so a kid's card can't appear
in an adult's row.

## Parent PIN

The Parent PIN is one value for the household, and every change to it syncs, like any entry (newest wins). It syncs as
a salted hash, never the PIN. Setting, changing or removing it needs the current Parent PIN on the TV where it is done,
so a kid can't change it on one TV and carry the change to the rest. A TV that joins takes the household's Parent PIN.
A TV that has its own, different Parent PIN is asked for the household's before it takes it, so a join can't silently
replace a PIN.

**How it's built.** One `parent_pin` entry for the whole household (profile "", item ""), its value the stored hash.
The app's side decides (HouseholdParentPin, every 20 seconds while Hearth runs, with the looks), remembering the hash it
last took or gave:

- No Parent PIN here: the household's is taken, so a TV set up by joining needs no Parent PIN step.
- Here before joining, and different: kept. **Settings > Family** shows **Use your other TVs' Parent PIN**, which takes
  the household's once it's entered here. Until then this TV's own changes don't go out either.
- Changed or removed here since (which took the PIN here): it goes out. Changed or removed on another TV: this TV
  follows. A household with none takes the first TV's.
- Leaving the household forgets what was taken or given; the PIN stays. The Java side's check of the PIN (HearthTube,
  the kids profiles' agent) reads the salted form too, so a PIN taken from the household works there.

## Your TVs (the page)

```
Your TVs
Profiles, looks and saved PINs follow you to every TV.

  [TV] Office        This TV
  [TV] Kitchen       On now
  [TV] Study         Last on yesterday

  [x] Keep my TVs in step
  Sync now
```

Choosing a TV opens its row's actions: rename (this TV only), Remove from household. On a TV on its own that hears a
household, the list is that household's TVs, with **Join** above it and Start a separate household small below. Text
stays short; no step lists and no internal terms ("Profile Pairing" appears only as the name of its own page).

## Setup flow

The guided setup listens for households from its first screen. Its **Join your other TVs** screen comes right after
the essentials (the Home button, the home app), before the cards, so the household's choices arrive before the steps
that would ask for them:

- **A household is on the network**: the screen names its TVs, with **Join the household** and Not now. Joining there
  runs Joining above; once joined, the look, Parent PIN and Profile Pairing screens aren't shown (they come from the
  household). Profile Pairing's switch is still each TV's own: Hearth turns it on over its own adb, at once when the TV
  trusts Hearth's key already, else with the ad tracking step's one approval; failing both it stays in Settings'
  checklist. Not now is final for this run: the flow doesn't ask again, nor offer to start a separate household.
- **Not heard yet**: when the flow gets there within 5 seconds of opening (a rerun with the essentials on), the screen
  says it's looking, with Skip, and moves on by itself if no household answers.
- **None is heard**: no screen. A **Sync with your other TVs** step just before Finish offers **Start a household**,
  for the TVs set up later; if a household is heard by then (the other TV came on meanwhile), it offers Join instead.
  Finish lists the TV as in step with the others, or the household as left for later.

## What's checked

What a TV checks before it takes part or takes something, and what that guards against.

- **The channel.** Only a TV that signs the exchange with the key on this TV's member list takes part (Moving
  entries); a removed one is told, an unknown one refused unless it proves an invitation (or, converting, the version 1
  key).
- **No connection holds the household thread unproven.** Everything that touches the entries runs on one household
  thread, so a connection that sends its opening a byte at a time could stall sync for every TV. A connection this TV
  accepts is read on a network thread (four at most) until the other side has proved it holds the key of the id it
  gave, within 20 seconds in all or it is closed; only then does it go to the household thread, which checks the member
  list before reading anything more and refuses a TV not on it at once. A TV this TV connects to (anything can announce
  itself) has 20 seconds to prove it's a member before the connection is closed.
- **Two TVs syncing with each other at once don't wait on each other.** Both ends of every exchange run on their TV's
  household thread, so two TVs that open one with each other at the same moment (right after a join, each hears the
  other and syncs) would each hold its thread on its own and wait for the other's until both time out. An exchange
  another TV opens waits while this TV runs one of its own, unless the other TV comes first (the lower TV id): then this
  TV's gives way, its connection closed, and the other's, which goes both ways, goes on at once (HouseholdTurns). So
  of two TVs, or a ring of them, one always goes on.
- **What an exchange brings goes on.** When an exchange brought entries that changed something, or listed a TV that
  proved an invitation, the TV syncs with the household's other TVs on now a couple of seconds later, rather than at
  the next change or five-minute check: a TV that just joined is refused by the others until the entry listing it
  reaches them. A TV that is refused for not being listed makes the TV that refused it sync with the others soon too
  (at most every 30 seconds), in case one of them just let it in.
- **Joining.** The join code binds the session between the two TVs and is shown on both: the new TV's screen and the
  request in the household's Bells (and its Allow dialog). No PIN: whoever answers is trusted to compare the code.
  Nothing secret moves before Allow, and the Home Assistant connection only after its own question, answered yes.
  A request ends when the asking TV hangs up, and one address asking again and again waits longer each time. Its
  buttons answer only while an adult's profile is on: a kids profile's Bell never lists it, and the Bell refuses an
  answer sent while a kids profile is on.
- **Member, removal and Parent PIN entries are signed.** Each carries its writer's signature (ECDSA with its TV key,
  over every field of the entry: kind, person, item, value, clock, writer and sequence). A TV takes one only when its
  writer is on its member list at that moment (not unknown, not removed) and the signature checks against the writer's
  listed key. So a TV that was removed, or never admitted, can't add, remove or rename TVs or change the Parent PIN,
  even through a TV that hasn't heard of the removal; and a member can't write those in another member's name.
- **Admissions.** A `member` entry must hold the key its TV id was made from, and one for another TV (an admission)
  must name its writer as the TV that added it. So every TV on the list shows which member added it, and an admission
  can't be put in another member's name. What it can't stop: a TV that is a member, while it is one, can list a key of
  its own making in its own name. Such a TV shows on Your TVs (named, added by that member) and is removed there like
  any other; removing the member that added it doesn't remove it by itself, since that would also remove the TVs it
  rightly let in.
- **An entry refused** is still counted as seen, so it isn't sent again and again; it never changes anything.
- **Sequences in another TV's name.** Entries travel through any member, so a TV takes entries written by TVs it isn't
  talking to, and counts each one's sequence in its version vector. A member could hand on an entry in another TV's
  name with a sequence far past anything that TV wrote; the vector would then count that TV's real entries as seen and
  never ask for them. Signing every entry would stop it, but costs a Keystore signature per play saved. Instead the TV
  that wrote them is believed about its own count: in an exchange, each side's vector says how many entries it wrote
  itself. A TV told it has counted more of the other's than that drops the entries in its name past that count (they
  were never written by it; removals and the signed kinds, which their signatures vouch for, are kept), and asks for
  all of that TV's entries again; and a TV that sees the other count more of its own entries than it wrote sends it all
  of them. So such entries stall another TV's only until the TVs that took them meet that TV, and a forged one never
  outlives that meeting. (It also mends a TV whose log was lost and that started counting again.) Content written in
  another TV's name isn't otherwise stopped for the unsigned kinds: any member can write those in its own name anyway.
- **Continue Watching cards from another TV** carry a deep link that TV wrote. Opening any card, the link is held as
  the kids profiles' agent holds what it opens: no flags that would hand out access to Hearth's files, never one of
  Hearth's own screens, and only another app's exported screen. A card from the household must also open in its own
  app (the one it is filed under): its link is resolved only in that app, and refused when it names another.
- **Older builds.** A TV on a build from before signing doesn't sign. Each TV says in its own member entry, and in
  its exchanges and invitations, that it signs; a TV listed as signing has unsigned entries in its name refused, and no
  entry can take back that a TV signs. A TV not listed as signing (an older build) is taken as before, unsigned, and
  what it writes can't claim another TV signs. So while an older TV is in the household, a member could write unsigned
  entries in that older TV's name; this ends when it updates (Hearth updates itself), its next own entry then saying it
  signs. An older TV also drops signatures when it passes entries on, so a TV that hears another only through an older
  one may miss that TV's renames and the TVs it added until it meets it or the older one updates.

## Failure and safety

- Each TV applies a received entry only after the channel opens, it parses, and it fits its schema; an unknown kind is
  kept (not applied), so a newer TV's entry survives an older TV. A bad entry is dropped and counted, not applied
  halfway.
- A TV never applies an entry for a profile it doesn't have; it holds it until the profile appears.
- Pairing with an app profile needs the same app profile name on both TVs' pickers; the entry keeps the name and the
  receiving TV checks it against the names its picker has shown.
- A TV whose Keystore key is gone (a factory reset, a restore) has no TV key and no entries; it is a new TV and joins
  again. The household marks its old id as not seen and offers Remove after 60 days.
- No analytics and no outside server. The only outside traffic is the optional Home Assistant mailbox, on the home
  network.

## From version 1

Built in 2026.10.68 to 2026.10.74, and kept: the entry log and its merge rules, version vectors, the `_hearth-sync._tcp`
announcement (with the TV name attribute), the one switch, Profile Pairing and PIN entries, people by Google account,
the member list shown on the Household page (`tv` entries, which become `member` entries), and the household-to-join
notice.

Changed in version 2:

| Version 1 | Version 2 |
|---|---|
| One household key on every TV proves membership and seals entries and exchanges | A TV key per TV; the synced member list says who is in; exchanges are signed and sealed per pair |
| Person ids keyed by the household key | Keyed by the person salt |
| Join through Copy profiles, digits on both screens | Join from the new TV, approved on a parent's phone (or on the household TV) |
| Leaving wipes the key; cutting a TV off means resetting the household | Remove from household: one removal, nothing else changes |
| "Start a household on this TV" | Every TV is in one from setup |
| Copy profiles between TVs, separate from sync | Gone from Settings once look and layout sync; Backup & restore stays for a TV off the network |

**Converting a version 1 household.** On updating, a TV that holds a version 1 household key makes its TV key, and the
first exchange between two such TVs runs under the version 1 key one last time to trade public keys and write both
`member` entries; the person salt is taken from the version 1 key (HKDF, the label of the old person key), so person ids
don't change and no entry is rewritten. A converted TV keeps the version 1 key for 90 days from its first exchange, only
to admit the household's other TVs as they convert, then drops it. A TV still on version 1 can't sync with a converted
one; it converts when it updates (Hearth updates itself in the background), and a TV that never updates is removed like
any other.

**The invitation.** An allowed join hands the new TV an invitation instead of a household key: the household's id
and person salt, the inviting TV's id and public key, and a random secret that admits one TV, once, within an hour.
The new TV lists the inviting TV and proves the secret at their first exchange; the inviting TV then lists it. (Until
joining from the new TV was built, a copy of profiles with "Add this TV to my household" ticked handed it over, and a
copy from a TV still on version 1 handed over the version 1 key. Copy profiles and its code are gone; a TV still on
version 1 converts as above when it updates.)

## Build order

1. **TV keys and the member list** (built): the signed channel, member entries and final removals, invitations through
   the copy, conversion from version 1, leave and remove (a Remove action on the Household page's TV list). Unit tests
   for the channel (an outsider, a forged id, a spent invitation, a removed TV either way round), removal never losing,
   leaving, and conversion.
2. **Joining from the new TV** (built): the join request, the join code, phone approval through the household TV, the
   on-screen fallback on its Household page, the first sync, and the preview and copy before the household's settings
   replace this TV's.
3. **Look and layout, then wallpaper pictures** (built, every profile, kids' included).
4. **Your TVs page and the setup step**; Copy profiles leaves Settings (done, and its code is removed: the join keeps
   only ShareSession's key exchange and ShareCrypto).
5. **Home Assistant mailbox**, sealed per member.
6. **Continue Watching** (built), the **Parent PIN** (built), and **Notifications** (built: Home Assistant's in every
   TV's Bell, for a person or every adult, cleared everywhere; a TV asking to join answered from any TV; not yet tried
   on two TVs).
7. **Hardening**: a security review of the channel, the join and conversion before release; long-offline TV tests; a
   test with two TVs whose clocks disagree.

## Open questions

- Renaming a profile on one TV changes the name everywhere: is that a rename entry (the profile keeps its history) or a
  new profile? A rename entry is assumed; the build must carry it.
- The on-screen fallback for joining needs a parent at both TVs. A Parent PIN typed on the new TV would avoid that, but
  it must not reach a device pretending to be a household TV, which needs a password-authenticated key exchange
  (CPace or SPAKE2) rather than the plain one. Worth it only if many households run without phone approval.
- Home Assistant's buttons stay on the TV that received the notification. Carrying them to the other TVs' Bells
  would let any household TV ask another to call a Home Assistant service; worth it?

Decided by the owner:

- Notifications without `for` go to every adult (not only the adult on screen when they came).
- A notification for every adult cleared by one adult is cleared for all adults (no per-person clear).
- A notification for everyone still pops up over a kids profile on the TV that received it (a doorbell camera is for
  whoever is watching).
- Putting back the copy from before joining does not leave the household: the TV stays in, and what was put back goes
  out as the newest change (see Put back). Only a reset or a deliberate leave or remove takes a TV out.
- Hidden calendars follow the person, by a key made from the calendar's account and the calendar (see Hidden
  calendars).
