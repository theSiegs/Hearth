# Pigeon: assistants that pass word (idea)

> **An idea, not a plan.** This explores people talking to each other through their assistants, and what Hearth and
> Home Assistant already have for it. Nothing here is built. "Pigeon" is a working name.

## The idea in one exchange

Alex, driving home, says to the phone: "Tell Sam I'll be about ten minutes late."

A minute later, the speaker in the kitchen, where Sam is:

"Sam, Alex is running about ten minutes behind and should be home around 6:52. That's after the wash finishes at
6:40, and Alex usually moves it. Should I remind you when it's done, or hold the reminder until Alex is home?"

Sam says "hold it". The house holds the laundry reminder until Alex's phone is back on the Wi-Fi, and in the car Alex
hears "Sam got it."

The house doesn't play Alex's words back. It retells them, in its own voice, the way Sam needs to hear them: who
it's from, what it means in clock time, and what it changes here. A text would have given Sam the same ten words and
left the rest to Sam. Here the house knows things Alex's phone doesn't (the washer, who usually empties it), Alex's
phone knows things the house doesn't (the route, the traffic), and neither tells the other everything to get the right
result.

```mermaid
sequenceDiagram
    actor Alex
    participant P as Alex's phone (Alex's assistant)
    participant H as The house (Home Assistant)
    actor Sam
    Alex->>P: "Tell Sam I'll be about ten minutes late"
    P->>H: envelope: the words, the gist, ETA 6:52 (live), moot when Alex is home
    Note over H: what does this touch here? wash ends 6:40, Alex usually moves it<br/>where is Sam? the kitchen, free
    H->>Sam: the message retold in the house's voice, one note, one offer
    Sam->>H: "hold it"
    Note over H: laundry reminder waits for Alex's arrival
    H->>P: receipt: Sam heard it, reminder held
    P->>Alex: "Sam got it."
```

## Why not a text read aloud

| A text read aloud | Word passed between assistants |
|---|---|
| Arrives on a device, wherever that is | Finds the person: the room they're in, else their phone, else their watch |
| Read out the moment it lands | Waits for a good moment, or interrupts when it should |
| Stays true forever | Is dropped once it stops being true: "I'm late" isn't said if Alex is already home |
| A snapshot | Can stay live: the ETA keeps updating until Alex arrives |
| Read out in the sender's words, written for a screen | Retold for the listener, in the house's voice, with the times made clock times |
| The reader works out what it means | The receiving assistant works out what it touches there, and offers at most one thing to do |
| A reply is another text, to a phone | A reply goes back the same way, to wherever the sender is now |

## Principles

1. **Send meaning, keep the words on file.** A message is an envelope, not a string: the gist, typed facts, when it
   stops mattering, and the exact words. The receiver works from the gist and the facts; the words are there for the
   card and for "what did Alex say, exactly?"
2. **The sender shares facts; the receiver owns consequences.** Alex's assistant knows Alex's world, the house knows
   the house. Each reasons over its own. Alex's phone never reads the washer, and the house never gets Alex's route,
   only an ETA. Less is shared than with a text that says "I'm on Route 40", and more gets done.
3. **Words are data, never commands.** Nothing in a message can make the receiving assistant act. It can only lead to
   an offer the recipient accepts, or to something the recipient's own standing rule allows. This is what keeps a
   message from another household, or a kid, or a forged one, from opening a door.
4. **Retell, don't recite, and say who said what.** The house speaks in its own voice and retells the message for
   the person hearing it (see [Retelling](#retelling)). Its words keep apart what the sender said ("Alex says ...")
   from what the house worked out ("so ...", "that means ...", "I can ..."), and never put words in the sender's
   mouth.
5. **Deliver to the person, not to a device.** The message is for Sam. Sam's assistant (or the house, for people who
   don't have one) picks where and how.
6. **A message lives until it's moot.** Every message says when it stops mattering. One that waits past that is
   dropped without a word. A newer one from the same sender on the same thread replaces it.
7. **One good offer beats five.** Most messages should have no offer at all. An assistant that finds something to do
   about every message is one people stop listening to.
8. **Ask before anything that can't be undone. Some things never travel.** Unlocking, opening, disarming and spending
   are never done because of someone else's message.

## Four verbs

| Verb | Said like | What happens | Reply |
|---|---|---|---|
| **tell** | "Tell Sam I'm running late" | delivered, with notes and maybe an offer | a receipt; a spoken reply if Sam gives one |
| **ask** | "Ask Sam if we need milk" | delivered as a question, with choices when there are some | the answer, back to the sender |
| **share** | "Let Sam see my ETA until I'm home" | a live fact the other side can use, until it ends | none |
| **have** | "Have the house turn the porch light on" | not a message: the sender's own request to the house, with the sender's own rights | done or refused |

Keeping **have** apart from **tell** is the important part. "Tell the house to unlock the door" is Alex asking the
house with Alex's own rights, on the path any request from Alex's phone already takes. Put inside a message to Sam, it
is only words Sam hears.

## The envelope

```json
{
  "id": "m-7f3a",
  "thread": "m-7f3a",
  "hops": 0,
  "from": { "person": "alex", "device": "alex-phone", "signed": true },
  "to": [{ "person": "sam" }],
  "verb": "tell",
  "words": "Tell Sam I'll be about ten minutes late",
  "gist": "Alex will be home about ten minutes later than planned.",
  "facts": [
    { "kind": "eta", "at": "18:52", "source": "maps", "live_until": "arrived" },
    { "kind": "can_errand", "detour_minutes": 4, "near_route": ["grocery"] }
  ],
  "may": { "infer": true, "offer": true, "act": [] },
  "urgency": "normal",
  "aloud": "household",
  "moot_when": ["alex is home", "19:30"]
}
```

| Field | What it is |
|---|---|
| `from` | the person, and the device that vouches for them (signed by its key, as TVs sign household entries) |
| `to` | people, a group ("the kids", "everyone"), or a place ("the house") |
| `words` | exactly what was said, as text. Shown on the card and given when asked; never played. No audio is sent |
| `gist` | the sender's assistant's one-line reading of the words, which the receiver retells |
| `facts` | typed, each with its source. A fact can stay live (an ETA) until a stated end |
| `may` | what the receiver may do with it: infer notes, make offers, run named actions (almost always none) |
| `aloud` | who may hear it said in a shared room: anyone, the household, adults only, or no one (phone only) |
| `moot_when` | when to drop it if it hasn't been delivered: an event, a time, or both |
| `thread`, `hops` | the conversation it belongs to, and how many assistants it has passed through |

**Facts say what, not where.** `can_errand` says "a grocery store is on the way, four minutes extra", never the route.
`place` says "at the store", never coordinates. The sender's settings decide which kinds of fact go to whom.

**The sender's assistant checks the facts before it sends.** If Alex says "ten minutes" and the phone's travel time
says twenty, it sends the words as said and the ETA as measured, so the house can say "Alex says ten; the phone says
closer to twenty." Alex isn't asked anything while driving.

## Retelling

The receiving assistant says the message in its own voice, for the person in front of it. The rules keep a retelling
faithful:

- **Turn it around.** "I'll be late" becomes "Alex will be late"; "tell Sam" disappears, since Sam is the one hearing it.
- **Lead with who it's from**, unless the room already knows ("Sam, Alex is running late").
- **Make times clock times** when the facts allow: "ten minutes late" becomes "home around 6:52". When the sender's
  guess and a measured fact differ, say both: "Alex says ten minutes; the phone says closer to twenty."
- **Keep the hedges.** "About", "maybe" and "I think" stay. A guess is never made to sound like a promise.
- **Keep the strength.** A request stays a request and an instruction stays one: "Alex wants you off the TV now" is not
  softened to "Alex wonders if you might stop soon", nor sharpened the other way.
- **Add no reasons.** If Alex didn't say why, the house doesn't guess ("traffic") as if Alex had said it.
- **Mark what's the house's.** What Alex said is "Alex says"; what the house adds is "so", "that means", "I can".
- **Fit the listener.** Shorter for a kid, nothing that the room shouldn't hear (see `aloud`), and in the listener's
  language if it differs from the sender's.

"What did Alex say, exactly?" gets the words as they were sent, read out as a quote.

## Where people are

Pigeon doesn't need to know which room someone is in. It needs to know **which speaker they'll hear**, so it only has
to be as precise as the speakers are spread out, and **how sure it is**, because that decides how it delivers.

No one signal says both who and where. Some say who (a phone, a watch, a voice, a TV profile), some say where (a radar,
a motion sensor), and a few say both for a short while. The house combines one of each.

| Signal | Who | Where | Notes |
|---|---|---|---|
| A voice a speaker just heard | with voice recognition | yes, for a few minutes | the strongest signal while it's fresh |
| A profile on a TV that's on | yes | yes, while it plays | covers the person sitting still on the couch, whom radar misses |
| The mesh Wi-Fi node a phone or watch is on | the device's owner | a floor at best | devices stay on whichever node they joined: in one house the kitchen fridge was on the upstairs node. And it's the phone, not the person: a phone charging on the counter "is" its owner |
| Bluetooth from a watch or phone, heard by a small receiver in each room | the device's owner | room by room | a watch beats a phone, since it's worn. Needs a receiver per room |
| Millimeter-wave radar, as in some voice satellites | no | yes, with how many people and how far | the kind that tracks people (up to three, with positions) sees people moving and loses people sitting still: in one house a satellite's radar was on for 7% of the time the TV in its room was playing. A static-presence kind sees still people better. Fans and curtains fool both |
| Wi-Fi sensing (disturbances in the signals between nodes) | no | an area | in a few router products; it says "something's moving", and a cat counts |
| Motion sensors | no | yes | enough on their own only when one person is home |

**Combining them.** For each person, the house keeps where it last placed them and how sure it is (Home Assistant's
Bayesian sensor does this kind of combining). Simple rules carry most of it:

- With one person home, any occupied room with a speaker is theirs.
- A radar counts its room as occupied if it saw someone in the last 10 to 15 minutes, so a person sitting still
  between movements isn't lost.
- The radar never says who. It says which rooms are occupied, which narrows what the who signals have to decide.
- A TV profile on screen settles its room for as long as something plays.

**How sure decides how it's delivered.**

| The house is | It |
|---|---|
| Sure: a fresh voice, a TV profile, or the only one home | says it in that room |
| Fairly sure | knocks first (below) |
| Not sure | sends it to their phone and says nothing aloud |

It never says a message in every room to find someone.

**The knock.** When the house thinks Sam is in the kitchen but isn't sure, the kitchen speaker says only "Sam, there's a
message from Alex" and listens. "Go ahead" (or "yes", "what is it") confirms Sam is there, and the message follows.
Silence, or someone else answering, sends it to Sam's phone. Nothing private is said to the wrong person, and the
answer is a fresh who-and-where signal for the next message.

**Distance sets the volume.** A radar that knows how far away the person is lets the speaker talk softly to someone
right next to it and louder to someone across the room.

**Where someone is is used to deliver, never reported.** The sender hears "Sam got it", not where Sam was, and the house
keeps no record of where people have been beyond what the next delivery needs.

## Delivering: finding the person, and the moment

**Where.** The speaker the person will hear, chosen as in [Where people are](#where-people-are). How sure the house is
decides whether it says the message, knocks first, or sends it to the phone.

**When.** By urgency and what the person is doing:

| They are | low | normal | urgent |
|---|---|---|---|
| Free, near a speaker | at the next quiet moment | now | now |
| Watching TV | the TV's notification Bell | a small card on the TV, no pause | pause, then the card |
| On a call, or in a meeting on their calendar | after it | after it, with a phone card now | phone, then watch |
| Asleep (a bedroom, at night) | morning | morning, if not moot by then | phone and watch, then the bedroom speaker |
| Driving | later | spoken in the car, short | spoken in the car now |

**Urgent climbs a ladder**: the room they're in, their phone loudly, their watch, then every speaker. It stops at the
first sign they got it, and the sender hears which step did it.

**Receipts.** sent, delivered (a device said or showed it), heard (they answered, dismissed it or said "OK"), done (an
offer was taken). The sender's assistant says only the one that matters, and for a low message, nothing.

**Aloud is a privacy choice.** A message said in a room is heard by everyone in it. `aloud: adults` waits for a room
with no kids in it (no kid's voice heard, no kid's profile on the TV there), and otherwise goes to the phone.

## Consequences: what a message touches

The receiving side keeps a small **commitments index**: the things it knows are due in the next few hours. It is
built from what the house already has, not imagined by a model.

| Kind | Comes from | Example |
|---|---|---|
| A device finishing | appliances' end times | the wash ends at 18:40 |
| A plan with people in it | calendars | Scouts pickup at 19:00, Alex driving |
| Something waiting for an arrival | arrival automations | porch light and heat when Alex gets home |
| Something someone usually does | who did it the last few times | Alex moves the wash to the dryer |
| A limit or a schedule | screen time, bedtimes | Robin's TV time ends at 19:00 |
| A message waiting for someone | Pigeon itself | Kit asked Alex to sign a form |
| A list | to-dos and shopping lists | milk, eggs |

Each item carries the actions it offers: an appliance can delay its start, a plan can tell its people or change its
driver, an arrival routine can follow a live ETA, a reminder can be held for someone.

**The pass.** For every item due before the message is moot (and up to half an hour after), check whether a fact moves
it: lateness moves "usually does" and "plan with people" items; an errand fact meets the shopping list; an arrival
starts the arrival items. Every hit is a candidate with its item's actions. Most of this is arithmetic on times. A
language model then ranks the candidates and words the note, choosing only from the index and only the actions an item
lists. It can't add an item or name an action.

**The so-what filter.** A candidate is said only if it:

- names a real item in the index,
- happens before the message is moot,
- isn't already handled (the recipient or a rule dealt with it),
- would cost more to miss than to hear about.

At most one offer is spoken; any others go on the card. If nothing passes, only the message is said. An offer declined
three times in a similar situation stops being made, and "don't ask me that again" works.

**Opportunities, not only problems.** The same pass finds good news: Alex passes a store and milk is on the list; Alex is
two minutes out, so the kids can be told; dinner moved, so Robin's show can end at the episode's end instead of
mid-scene.

## Acting

| Level | What | Examples | Needs |
|---|---|---|---|
| **Say** | words only | "Alex won't be here when the wash ends" | nothing |
| **Offer** | a reversible action, run on the recipient's yes | hold a reminder, delay the dishwasher, tell the kids | the recipient's yes, within two minutes |
| **Rule** | a reversible action, run without asking and said afterwards | arrival lights follow Alex's live ETA | a rule the recipient set up for this kind of message |
| **Never by message** | unlocking, opening, disarming, spending | door, garage, alarm, orders | the person's own **have**, on its own path |

An offer runs once: the first yes runs it, a second yes finds it gone, and a yes heard after the offer expired only
clears it. This is the same rule as a Home Assistant button in the Bell ([household sync](household-sync.md#notifications)),
for the same reason.

## Replies and conversations

- **A reply goes back by the sender's state now.** Alex, driving, hears a short spoken reply; at a desk, a card.
- **Asks carry their choices**, so the answer can be one word and comes back typed: `{"choice": "thai"}`.
- **Polls.** "Ask everyone: pizza or tacos?" Each person is asked where they are. The sender gets the tally when everyone
  has answered or at a deadline: "Pizza 3, tacos 1. Robin says no olives."
- **Settle before asking.** Before passing an ask to a person, the receiving assistant checks whether it already knows
  the answer and may say it ("Is Sam home?" from presence, if Sam allows that for family). Then no one is bothered.
- **Assistants don't start new conversations about a message.** They answer, send receipts, and pass on answers. They
  never message a third person because of something they read, unless their own person says to. A thread passes
  through at most four assistants; after that only people can continue it. This keeps two assistants from talking to
  each other forever, and a household's assistants from spreading a message nobody chose to send.

## The fun ones

**Land the plane.** Sam to the kitchen speaker: "Tell Robin dinner's in ten." The TV in the den has Robin's profile on,
and the episode has seven minutes left. The card: "Sam says dinner's in ten. This episode ends in 7 minutes, a good place
to stop." The next episode doesn't autoplay. A deadline turns into a natural stopping point.

**Parental weight.** A parent's message to a kid can pause the TV. A sibling's can't. Kit says "tell Robin to get off
the TV": Robin gets a card, and the show keeps playing.

**Homework, then minutes.** Kit to the speaker: "Tell Dad my homework's done." (The house keeps a **people book**:
who's who, and what each person calls the others.) Alex's phone: "Kit says homework's done. Give Kit 30 more minutes
today?" "Yes." Hearth's bonus for today goes up, and Kit's TV says "Alex gave you 30 more minutes."

**Surprise-safe.** "Tell Sam I got the tickets for Robin's birthday. Don't let Robin hear." The words make it
`aloud: adults`. Robin is in the room with Sam, so it goes to Sam's phone as a card marked for Sam only.

**On the way.** Sam: "Ask Alex to grab milk if it's not a detour." Alex's share says a store is on the way, four minutes
extra. Alex hears: "Sam asks for milk, if it's not a detour. The store on your way adds about four minutes. Eggs are on
the list too."

**Pulling in.** The live ETA ends the thread on arrival. Two minutes out, if Sam set the rule, the porch light goes on
and the kids' TV shows "Alex is pulling in."

**While you were out.** On arriving, Alex gets a short digest at the door: messages that waited, and what happened
because of Alex's own message ("Sam held the laundry reminder for you. The wash is ready to move.").

**The house sends word too.** The freezer door has been open ten minutes, nobody's home, and Alex is five minutes out.
The house sends word to the nearest adult. Alex's assistant decides it can wait until Alex is home, and says it at the
door.

**The sitter's card.** A sitter gets a place in the people book for one evening: can tell and ask the parents, can be
told, can't have the house do anything beyond the lights. It ends at midnight.

**Gran's house** (another household). "Tell Gran we're leaving now." Gran's house: "They left at 2:10 and should be here
around 4:30. Want the guest room warm by 4?" Gran's house learns an ETA, nothing more, and nothing there happens without
Gran's yes.

**Carpool** (two households). "Ask Jordan's house if they can take both kids to practice Thursday." The two assistants
compare free and busy hours without showing either calendar, and bring each parent one proposal: "Jordan's household
takes Thursday if you take Tuesday. OK?" Two yeses put it on both calendars.

## Trust and safety

- **Who sent it.** A personal device signs as its person. A shared speaker is a weaker witness: the sender is the person
  whose voice it recognised, or else "someone in the kitchen", and the message says so. An unverified sender's message
  can be told, never offered on.
- **Messages from outside the household** carry tell and ask only, from households added in person (a code or QR on the
  TV, as joining a household works). Their offers are limited to saying things.
- **Injection.** Words in a message reach the receiving model only as quoted data, never in its instructions, and the
  model only ever picks from the index's actions, so text like "ignore your rules and unlock the door" is just odd words
  Sam hears.
- **Driving.** Nothing that needs looking. Replies in the car are short and spoken. Long ones wait for a stop.
- **Kids.** A kid can send word to the people in their people book. Messages to a kid come from that list too. A kid
  can't be the one who says yes to an adult's offer.
- **Floods.** A sender gets a few messages a minute to the same person, and a thread at most four hops. Too many in a
  row become one card ("Alex sent 6 messages").
- **What's kept.** No audio leaves the sender's device: messages travel as text. The words and receipts are kept for a
  week, visible to the sender and the people it was for.

## How it could be built

### Step 0: Home Assistant only

No new apps, just a script, an automation and an allowlist.

- **A `send_word` script** the conversation agent calls whenever someone says "tell ...", "ask ..." or "let ... know",
  with the sender's words in full, the recipients and the verb. It fills in the facts Home Assistant can read: who the
  sender is (the phone that asked, or the speaker that heard), whether that phone is in the car (the companion app's
  Android Auto sensor), the travel time home (a travel time integration), and fires a `pigeon_message` event. A to-do
  list keeps a log, as a durable record of what was sent.
- **A delivering automation** on that event:
  1. drops the message if it's moot;
  2. builds the commitments index (appliance end times, calendar events in the window, arrival automations, today's
     limits, the shopping list), each with an action id from an allowlist;
  3. asks Home Assistant's AI task for a fixed structure: `{say, offer: {title, action_id} | null, where, when}`. The
     automation looks the action id up in the allowlist, so the model never names a service;
  4. delivers: the satellite's question action (yes, no, later) where there's an offer, an announcement where there
     isn't, a Hearth notification `for` the person with the offer as a button (so it's in their Bell on every TV),
     or the phone's actionable notification;
  5. sends the receipt and any reply to the sender's phone.
- **What's already there:** Hearth notifications for one person, with buttons that run once
  ([Home Assistant](home-assistant.md#notifications)), and the TV's status for "who's watching what"
  ([TV status](home-assistant.md#tv-status)).

### Step 1: Hearth

- Messages are `notice` entries in the household log, so a message for Robin is in Robin's Bell on every TV, and
  cleared on one, cleared on all.
- **Land the plane** from the TV's status (what's playing, and where it is in it, where the app reports that; HearthTube
  always knows).
- Parental weight: a parent's message may pause; nobody else's does.
- Whose profile is on screen, as a who-and-where signal for delivery (see [Where people are](#where-people-are)).
- A kids profile can send word from the remote's microphone to the people in its people book.

### Step 2: phones as personal assistants

- Hearth Mobile (or the companion app) is each person's assistant: it signs envelopes with its own key, holds their
  shares (live ETA, errands), and speaks to them in the car.
- Away from home, messages reach the house through the integration's webhook and mailbox
  ([away from home](home-assistant-integration.md#away-from-home), [mailbox](home-assistant-integration.md#household-sync-mailbox)).

### Step 3: other households

- A household publishes a card of what it accepts (tell, ask, polls, free and busy hours), and keys are swapped in
  person.
- An open agent-to-agent protocol carries it between households, so it isn't one app's network.

## Open questions

- How often does the knock get annoying, and when is it worth adding a Bluetooth receiver or a static-presence radar
  to a room instead?
- When a message is long, should the house retell only the point ("Alex said more about the car; want all of it?")?
- How does a sender check a retelling? A "read back" setting, where the sender's assistant says how the house will put
  it before it goes, for messages that matter?
- Who sees the household's message log: the people in each message only, or parents too?
- How "usually does" is learned without feeling watched, and how a person says "that's not my job any more".
- A message to "the kids": every kid, or the ones home?
