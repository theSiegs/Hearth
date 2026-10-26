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

Never synced: the Home Assistant token, the webhook ID, the TV's name (each TV announces its own), permissions,
anything about a TV's hardware. The Home Assistant address is handed over once when a TV joins (see Joining); the TV
then makes its own webhook and asks for its own token.

**Look and layout are where conflicts get visible.** Two TVs with different screen sizes show the same layout, so a
layout entry stores order and choices, never pixel positions. An app that isn't installed on a TV is skipped there and
kept in the entry, so it comes back when the app is installed. Wallpaper pictures are large: an entry carries the
picture's hash, and the picture itself moves only to a TV that lacks that hash. Bing's photo of the day and gradients
are just settings.

**How look and layout are built (step 3).** A profile's look is one entry (`look`: its chosen settings, the same ones a
copy carries) and its layout another (`layout`: apps and whether each is hidden, rows, placements, spacers, without app
names, which are each TV's own). Both are written in a fixed order, so the same layout is always the same text. The
app's side does the work, every 20 seconds while Hearth runs (HouseholdLooksService):

- **Taking.** For each profile, kids' included, whose look or layout entry changed, it fits the household's to the apps
  installed here (as a copy does) and puts it in place: live when the profile is on screen, else in the profile's saved
  layout, which comes up when someone switches to it. A changed picture is written to the profile's folder. Before a
  profile first takes the household's look on a TV, everything is kept as a backup, as a copy does, so it can be undone
  in Backup & Restore.
- **Giving.** The profile on screen goes out when its look, layout or a picked picture differs from what this TV last
  took or gave. Its layout keeps the household's apps that aren't installed here, and their places in rows it still has,
  so a TV without an app doesn't take it away from the others.
- What this TV last took or gave is remembered per profile (by fingerprint), so taking the household's doesn't send it
  straight back, and two TVs settle on one layout.
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

## Members

The member list is entries of kind `member`, one per TV: its public key, its name, which member added it and when.
Every TV on the list keeps the whole list, so each knows every other, even two that are never on together.

- **A TV syncs only with listed TVs.** Each exchange begins with both TVs proving they hold the private key of a listed
  member (see Moving entries). A TV not on this TV's list gets nothing and can send nothing.
- **Adding** a TV is one new `member` entry, written by the member that approved the join.
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
3. The household TV puts the request in its **notification Bell**, on adults' profiles only (never while a kids
   profile is on), and pops it up: "Kitchen wants to join your TVs", with **Allow** and **Don't allow**. No Parent PIN
   and no code to compare: the TV's name is what the person checks. Clearing it is Don't allow. (The code still binds
   the session; no one compares it, so a device on the network that put itself between the two TVs, and named itself
   after the new TV, could be let in: a trade chosen for a home network.)
4. On Allow, the household TV sends an invitation over the sealed session (the same one a copy hands over: see
   Joining until step 2 is built), and a Home Assistant address and a new token of its own when the new TV has none.
   The new TV joins with it, and their first exchange lists it.
5. **A TV that already has its own setup**: for an entry both have, the household's wins; settings only this TV has are
   kept and synced out. A backup is kept before a profile first takes the household's look (see Look and layout); a
   preview of what changes is not built yet.

The new TV never sends the Parent PIN, and nothing secret moves before the Allow. Denying, or no answer in five
minutes (time to walk to the other TV and turn it on), ends it with nothing sent. A household TV answers one request at
a time, and after one that wasn't allowed it ignores requests for 30 seconds, so a TV can't flood its Bell.

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
profile's list of hidden apps merges by app.

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
  runs Joining above; once joined, the look screen isn't shown (the profile's look comes from the household). Not now
  is final for this run: the family card doesn't ask again, nor offer to start a separate household.
- **None is heard**: no screen. The family card's last step offers **Start a household**, for the TVs set up later;
  if a household is heard by then (the other TV came on meanwhile), that step offers Join instead.

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

**Joining until step 2 is built.** A copy with "Add this TV to my household" ticked hands the new TV an invitation
instead of the household key: the household's id and person salt, the sending TV's id and public key, and a random
secret that admits one TV, once, within an hour. The new TV lists the sending TV and proves the secret at their first
exchange; the sending TV then lists it. A copy from a TV still on version 1 still hands over the version 1 key, and the
receiving TV converts at once.

## Build order

1. **TV keys and the member list** (built): the signed channel, member entries and final removals, invitations through
   the copy, conversion from version 1, leave and remove (a Remove action on the Household page's TV list). Unit tests
   for the channel (an outsider, a forged id, a spent invitation, a removed TV either way round), removal never losing,
   leaving, and conversion.
2. **Joining from the new TV** (built, except the preview of what changes): the join request, the join code, phone
   approval through the household TV, the on-screen fallback on its Household page, the first sync.
3. **Look and layout, then wallpaper pictures** (built, every profile, kids' included).
4. **Your TVs page and the setup step**; Copy profiles leaves Settings.
5. **Home Assistant mailbox**, sealed per member.
6. **Continue Watching**.
7. **Hardening**: a security review of the channel, the join and conversion before release; long-offline TV tests; a
   test with two TVs whose clocks disagree.

## Open questions

- Renaming a profile on one TV changes the name everywhere: is that a rename entry (the profile keeps its history) or a
  new profile? A rename entry is assumed; the build must carry it.
- The on-screen fallback for joining needs a parent at both TVs. A Parent PIN typed on the new TV would avoid that, but
  it must not reach a device pretending to be a household TV, which needs a password-authenticated key exchange
  (CPace or SPAKE2) rather than the plain one. Worth it only if many households run without phone approval.
