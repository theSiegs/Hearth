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
  profile by its Google TV profile name, and each TV maps that name to its own profile key.

## What syncs

| Kind | Per | Notes |
|---|---|---|
| Profile Pairing | profile and streaming app | the chosen app profile, or "always ask" |
| Streaming app PINs | profile and streaming app | secret; encrypted; see Kids |
| Look | profile | wallpaper kind and pictures, day/night picture, gradient, theme, clock/format choices |
| Home layout | profile | the dock, rows, app order, hidden apps, per-profile panel choices |
| Continue Watching | profile | Hearth's own watch history (see below) |
| Parent PIN | household | opt-in; changing it needs the old one on every TV |

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

**Conflicts.** One rule per entry: the newest write wins (a hybrid logical clock keeps TVs with wrong clocks from
winning forever; a tie goes to the lower TV id). A delete is an entry with a deleted flag and a timestamp, kept for 90
days, so a TV that was off can't bring a deleted PIN back. A few kinds merge rather than overwrite: Continue Watching is a
set (union, newest play per title), and a profile's list of hidden apps merges by app.

**Size.** Entries are small, except pictures and watch history. History keeps at most 100 entries per profile, 90 days.
A TV never sends a picture a peer already has.

## Kids

The question for a parent: should a kid's profile follow them from TV to TV? Our default is **no until a parent says
so**, per kids profile: **Settings > Profiles > Kids profiles > Follow this profile to other TVs**, behind the Parent
PIN. When off, that profile's entries aren't sent or taken. PINs for a kids profile are never sent unless that switch
is on and the parent also turns on **PINs**. Synced Continue Watching for a kid is per streaming app profile, so a kid's
card can't appear in a grown-up's row.

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
2. **Pairing and PINs**: the first kinds, over TV to TV; the Household settings screen; the kids switch.
3. **Home Assistant mailbox**.
4. **Continue Watching**.
5. **Look and layout, then wallpaper pictures.**
6. **Hardening**: a security review of the key handling and the wire format before release, long-offline TV tests, a
   test with two TVs whose clocks disagree.

## Open questions

- Do kids' profiles follow a kid by default once a parent turns on the switch, or per kind (look yes, PINs no)?
- Should the Parent PIN sync at all, or stay a per-TV choice with a reminder when TVs disagree?
- How are two profiles with the same name on one TV (an adult and a kid named alike) told apart? (Today names must be
  unique per user; a clash would stop the entry and say so.)
- A TV's own clock can be wrong; do we also ask Home Assistant for the time when it is there?
