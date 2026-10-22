# Household sync (design)

> **Design draft.** Nothing here is built yet. It records what we want and why, so the pieces can be built and
> reviewed one at a time.

## Goal

Someone turns on any TV in the house, picks their profile, and finds things as they left them on another TV: their
look and home layout, their Profile Pairing choices, their streaming app PINs, and Continue Watching. No cloud account,
and no Home Assistant needed. Home Assistant, when there, makes it better.

Not a goal: keeping every setting equal. A TV's own settings (its name, Wi-Fi, permissions, the Home Assistant webhook
and token, Home Button Fix) stay on that TV.

## Terms

- **Household**: the TVs that share one secret key. Joined once, by a parent.
- **Entry**: one synced value, with an id, a profile, a value, a timestamp, the TV that wrote it, and a deleted flag.
- **Profile match**: profiles differ in number from TV to TV (Android numbers its users per TV), so entries name the
  profile by its Google TV profile name, and each TV maps that name to its own profile key. **Profile names must be
  unique across the household** (compared without case or surrounding spaces); see Unique names.

## What syncs

| Kind | Per | Notes |
|---|---|---|
| Profile Pairing | profile and streaming app | the chosen app profile, or "always ask" |
| Streaming app PINs | profile and streaming app | secret; encrypted |
| Look | profile | wallpaper kind and pictures, day/night picture, gradient, theme, clock/format choices |
| Home layout | profile | the dock, rows, app order, hidden apps, per-profile panel choices |
| Continue Watching | profile | Hearth's own watch history (see below) |
| Parent PIN | household | including every change to it; see Parent PIN |

Never synced: the Home Assistant token, the webhook ID, the TV's name, permissions, anything about a TV's hardware.

**Look and layout are where conflicts get visible.** Two TVs with different screen sizes show the same layout, so a
layout entry stores order and choices, never pixel positions. An app that isn't installed on a TV is skipped there and
kept in the entry, so it comes back when the app is installed. Wallpaper pictures are large: an entry carries the
picture's hash, and the picture itself moves in a separate, resumable transfer only to a TV that lacks that hash. Bing's
photo of the day and gradients are just settings.

**Continue Watching** syncs Hearth's own per-profile watch history (the app, title, episode, how far, when, and the
deep link that opens it), not Google's Watch Next, which ends in 2027. Opening an entry on another TV launches the same
title in the streaming app, which resumes from its own account's saved position, so Hearth carries a card, not a
playback position it can't act on. A title finished (95% or more) anywhere is finished everywhere. An entry only moves
when the streaming app profile it was played under is known on the receiving TV.

## Joining

1. On a TV that is already in the household (or on the first TV: Settings > Profiles > Household), a parent chooses
   **Add a TV**, after the Parent PIN.
2. The new TV chooses **Join a household**, after its Parent PIN (or sets one). The two TVs find each other on the home
   network the way Copy profiles does (`_hearth-share._tcp`) and show the same six digits; a parent confirms.
3. They run the existing key exchange. Over that encrypted channel the existing TV sends the **household key**: 32
   random bytes made when the household began, kept in the Android Keystore-wrapped store PinVault uses.
4. The two TVs then run a first sync and show what moved. A TV that was already set up shows what it would change
   before it takes anything (it keeps a backup, as Copy does).

Leaving a household wipes the key and stops syncing; the entries stay as ordinary settings. **Reset the household**
makes a new key; the other TVs then need to join again. This is also how a lost or sold TV is cut off.

## Setup flow

The guided setup gets a step, **Sync with your other TVs**, after Home Assistant and before the wrap-up:

- **Set up a household on this TV** (the first TV; nothing to find): makes the household key and turns the switch on.
- **Join a household** (a later TV): finds the TV that has one, shows the digits, and on a match takes the key and does
  the first sync, as Joining describes. Where this TV already has profiles, the step shows what would change first.
- **Not now** skips it; Settings > Profiles > Household does the same later.

The step is offered on every TV's setup, ahead of the other steps that ask for choices a household could already have
(wallpaper, Profile Pairing, PINs, Parent PIN), so a joined TV doesn't ask for what it is about to receive. A TV that
joins during setup skips those steps and shows them as filled in, with a chance to change any.

## Unique names

Sync matches profiles by name, so two profiles with one name would mix. Names are unique household-wide:

- Hearth already keeps names unique within a TV. With sync, a profile name that another TV in the household already
  uses for a different person isn't allowed: the TV that sees the clash keeps the earlier profile (by creation time) and
  marks the later one **needs a new name**.
- A profile that needs a new name doesn't send or take entries until it has one, and its card on Household says so.
  Nothing is deleted or renamed for it.
- At joining, a TV whose profile names clash with the household's shows them before anything moves, and a parent
  renames or skips each.
- The same name on two TVs is the same person: that is how profiles follow people.

## Moving entries

**Encryption.** Every entry, and every message about entries, is sealed with ChaCha20-Poly1305 under a key derived
from the household key (HKDF, with a label per purpose and a fresh nonce), the same primitives as ShareCrypto. A TV that
isn't in the household can't read or forge one.

**Baseline: TV to TV.**
- Each TV announces itself on the home network (`_hearth-sync._tcp`: its household id (a hash, not the key) and port)
  and listens on one port, answering only home-network addresses (LocalNet).
- A TV that changes an entry tells the others it can see ("I have changes after version X"). They pull.
- A TV that wakes, or sees another appear, exchanges **version vectors** (one counter per TV) with it and asks for what
  it lacks. While two TVs are on together they check again every few minutes as a backstop.
- Changes travel only while at least two TVs are awake together. A TV that has been off for days catches up the next
  time it meets any other.

**Optional: Home Assistant as a mailbox.** With the Home Assistant address and a token set, each TV also publishes its
sealed changes to a Home Assistant entity (a `sensor` set through the REST API; contents are ciphertext, and Home
Assistant never gets the key). A TV that wakes reads the mailbox first. Because the mailbox may vanish on a restart of
Home Assistant, every TV republishes what it has on its 10-minute heartbeat; nothing relies on Home Assistant keeping it.
Without Home Assistant everything above still works.

**Conflicts.** One rule per entry: the newest write wins. Each TV stamps entries with its own clock, which Android
sets from the network (and Home Assistant adds nothing to), so the clocks agree to within a second or two and nothing
syncs time itself. A hybrid logical clock keeps a TV whose clock jumps from winning forever; a tie goes to the lower TV
id. A delete is an entry with a deleted flag and a timestamp, kept for 90
days, so a TV that was off can't bring a deleted PIN back. A few kinds merge rather than overwrite: Continue Watching is a
set (union, newest play per title), and a profile's list of hidden apps merges by app.

**Size.** Entries are small, except pictures and watch history. History keeps at most 100 entries per profile, 90 days.
A TV never sends a picture a peer already has.

## One switch

**Settings > Profiles > Household > Sync with my other TVs** is one switch, on by default once a TV has joined a
household, and it covers every profile, kids' included: a kid follows themselves from TV to TV like anyone else.
Turning it off needs the Parent PIN, stops this TV sending and taking entries, and leaves what it has. There are no
per-kind or per-profile switches. A kid's synced Continue Watching is still per streaming app profile, so a kid's card
can't appear in a grown-up's row.

Joining is still a deliberate act (a parent, both TVs, matching digits). "On by default" means a joined TV syncs
everything without further choices.

## Parent PIN

The Parent PIN is one value for the household, and every change to it syncs, like any entry (newest wins). Setting,
changing or removing it needs the current Parent PIN on the TV where it is done, so a kid can't change it on one TV
and carry the change to the rest. A TV that joins takes the household's Parent PIN. A TV that has its own, different
Parent PIN is asked for the household's before it takes it, so a join can't silently replace a PIN.

## Failure and safety

- Each TV applies a received entry only after it decrypts, parses and fits its schema; an unknown kind is kept (not
  applied), so a newer TV's entry survives an older TV. A bad entry is dropped and counted, not applied halfway.
- A TV never applies an entry for a profile it doesn't have; it holds it until the profile appears.
- Pairing with an app profile needs the same app profile name on both TVs' pickers; the entry keeps the name and the
  receiving TV checks it against the names its picker has shown.
- Settings > Profiles > Household shows the TVs in the household, when each was last seen, how many entries are waiting
  to move, and **Sync now**. Each TV can be removed from there.
- No analytics and no outside server. The only outside traffic is the optional Home Assistant mailbox, on the home
  network.

## Build order

1. **Household and storage**: household key, joining, the entry store (SQLite, per kind), the version vector, and
   encryption. Unit tests for merge, deletes, ordering and tampering.
2. **Pairing and PINs**: the first kinds, over TV to TV; the Household settings screen and its one switch.
3. **Home Assistant mailbox**.
4. **Continue Watching**.
5. **Look and layout, then wallpaper pictures.**
6. **Hardening**: a security review of the key handling and the wire format before release, long-offline TV tests, a
   test with two TVs whose clocks disagree.

## Open questions

- Renaming a profile on one TV changes the name everywhere: is that a rename entry (the profile keeps its history) or a
  new profile? A rename entry is assumed; the build must carry it.
