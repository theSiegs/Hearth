// Hearth's sidebar page, drawn without a browser: what it shows of a kid (their own pause, School time today, today by
// device and app, their Switch) and how it follows what the installed Nintendo integration can do.
// Run: node --test test/js/hearth_panel_test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

let Panel;
globalThis.HTMLElement = class {
  attachShadow() {
    this.shadowRoot = { addEventListener() {}, innerHTML: "", getElementById: () => null, querySelector: () => null };
    return this.shadowRoot;
  }
};
globalThis.customElements = { define: (_name, cls) => (Panel = cls) };
globalThis.CSS = { escape: (s) => String(s) };
globalThis.window = { localStorage: { getItem: () => null, setItem() {} }, location: { hash: "", search: "" } };

const source = readFileSync(fileURLToPath(new URL("../../custom_components/hearth/frontend/hearth-panel.js", import.meta.url)), "utf8");
await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

const SWITCH = {
  device_id: "dev1",
  name: "Sam's Switch",
  target: "nintendo:number.sam_s_switch_max_screentime_today",
  available: true,
  played_minutes: 75,
  player_minutes: 50,
  limit_minutes: 120,
  minutes_left: 45,
  extra_minutes: 30,
  suspended: false,
  playing: true,
  bedtime: null,
  last_synced: null,
  held_by_hearth: false,
  blocking: false,
  entities: {},
};

function panel({ nintendo = {}, sam = {}, controls = [] } = {}) {
  const p = new Panel();
  p._hass = { states: {} };
  p._config = {
    title: "Home",
    persons: [{ id: "person.sam", name: "Sam" }],
    roles: { "person.sam": "kid" },
    groups: [{ id: "all", name: "All screen time", builtin: true, in_all: true, apps: [], added_apps: [] }],
    budgets: { "person.sam": { all: { school: 120, other: 120 } } },
    capabilities: { nintendo: { installed: true, ...nintendo } },
    parental_controls: controls,
    enforce: [],
    sources: [],
    locks: [],
    platforms: ["Windows", "Xbox"],
  };
  p._summary = {
    people: [
      {
        id: "person.sam",
        name: "Sam",
        all: { id: "all", name: "All screen time", used_minutes: 60, minutes_left: 60 },
        groups: [],
        first_party: { nintendo: [SWITCH] },
        targets: [{ id: "hearth:tv1", name: "Kitchen TV", kind: "tv" }],
        devices_today: [{ target: "hearth:tv1", name: "Kitchen TV", minutes: 40 }],
        apps_today: [{ package: "com.example.game", name: "A Game", minutes: 25 }],
        school_time: { start: "2026-11-12T08:00:00-05:00", end: "2026-11-12T15:00:00-05:00" },
        ...sam,
      },
    ],
    devices: [],
    approvals: [],
  };
  p._kid = "person.sam";
  p._watch = { "person.sam": null };
  return p;
}

test("a kid's card has their own pause, School time today and today by device and app", () => {
  const html = panel()._page();
  assert.match(html, /data-action="kid-pause" data-person="person.sam"/);
  assert.match(html, /data-action="school-off"/);
  assert.match(html, /Today by device and app/);
  assert.match(html, /data-action="device-bonus"[^>]*data-target="hearth:tv1"/);
  assert.match(html, /A Game/);
  assert.match(html, /<summary>Device limits<\/summary>/);
  assert.match(html, /Sam&#39;s Switch · Nintendo: played 1 h 15 \(theirs 50 min\) · limit 2 h · 45 min left · \+30 min extra · playing now/);
});

test("a paused kid ends their pause; School time taken off shows and comes back", () => {
  const html = panel({
    sam: { pause: { reason: "Dinner", until: "2026-11-12T19:00:00-05:00" }, school_time_off: [{ date: "2026-11-12", from: null, reason: "Trip" }] },
  })._page();
  assert.match(html, /data-action="kid-pause-end"/);
  assert.doesNotMatch(html, /data-action="kid-pause" /);
  assert.match(html, /No School time today · Trip/);
  assert.match(html, /data-action="school-off-cancel"/);
  assert.doesNotMatch(html, /data-action="school-off" /);
});

test("the Switch card offers only what core's Nintendo integration has", () => {
  const p = panel({ nintendo: { add_bonus: true, bonus_min: 5, bonus_max: 30, unlimited: false, cancel_bonus: false, list_apps: false } });
  p._tab = "kids";
  const html = p._page();
  assert.match(html, /data-action="nin-bonus"[^>]*data-minutes="15"/);
  assert.match(html, /data-action="nin-bonus"[^>]*data-minutes="30"/);
  assert.doesNotMatch(html, /data-action="nin-bonus"[^>]*data-minutes="60"/);
  assert.doesNotMatch(html, /data-minutes="-1"/);
  assert.doesNotMatch(html, /nin-bonus-cancel/);
  assert.doesNotMatch(html, /Games and the allow list/);
  // Hearth's own extra time on the Switch
  assert.match(html, /data-action="device-bonus"[^>]*data-target="nintendo:number.sam_s_switch_max_screentime_today"/);
});

test("a patched Nintendo integration adds an hour, the rest of today, cancel and the allow list", () => {
  const p = panel({ nintendo: { add_bonus: true, bonus_min: 5, bonus_max: 360, unlimited: true, cancel_bonus: true, list_apps: true, set_app_allowed: true } });
  p._tab = "kids";
  p._switchApps = { dev1: [{ application_id: "0100A", name: "A Puzzle", allowed: true }] };
  const html = p._page();
  assert.match(html, /data-minutes="60"/);
  assert.match(html, /data-minutes="-1"/);
  assert.match(html, /data-action="nin-bonus-cancel"/);
  assert.match(html, /data-change="nin-allow"[^>]*data-app="0100A"[^>]*checked/);
});

test("while Hearth holds the Switch, Nintendo's own extra time waits", () => {
  const p = panel({ nintendo: { add_bonus: true, bonus_min: 5, bonus_max: 30 } });
  p._summary.people[0].first_party.nintendo = [{ ...SWITCH, held_by_hearth: true }];
  p._tab = "kids";
  const html = p._page();
  assert.doesNotMatch(html, /data-action="nin-bonus"/);
  assert.match(html, /waits while Hearth holds the Switch/);
});

test("no Nintendo integration: no Switch card", () => {
  const p = panel();
  p._config.capabilities.nintendo = { installed: false };
  p._summary.people[0].first_party = {};
  p._tab = "kids";
  assert.doesNotMatch(p._page(), /mdi:nintendo-switch/);
});

test("a parental control that isn't working shows on Today", () => {
  const html = panel({
    controls: [
      { domain: "microsoft_family_safety", name: "Microsoft Family Safety", entries: [{ title: "Family", state: "loaded" }], connection: { state: "degraded", reauth_required: false } },
    ],
  })._page();
  assert.match(html, /A parental control needs a look/);
  assert.match(html, /Microsoft Family Safety: connection degraded/);
  assert.doesNotMatch(panel()._page(), /needs a look/);
});

test("a lock chip names its kind and end; what locks them is only in the tooltip", () => {
  const p = panel({
    sam: { locked: true, locked_by: ["binary_sensor.phone_school_time_active"], lock: { kind: "school_time", until: "2026-11-12T15:00:00-05:00" } },
  });
  p._hass.states["binary_sensor.phone_school_time_active"] = { attributes: { friendly_name: "Sam's Phone School Time Active" } };
  const html = p._page();
  assert.match(html, /title="Locked by Sam&#39;s Phone School Time Active"><ha-icon icon="mdi:school-outline"><\/ha-icon>School time till \d+:00<\/span>/);
  assert.doesNotMatch(html, />Locked: /);
});

test("a parent's app grants are put together by name, never by package", () => {
  const app = (value, name) => ({ id: value, via: "family_link", source: "from the Family Link app", target: { kind: "app", value }, until: "2026-11-13T00:00:00-05:00", reason: "the app's limit was changed in the Family Link app", endable: false, ...(name ? { name } : {}) });
  const few = panel({ sam: { grants: [app("com.spotify.music", "Spotify"), app("com.pandora.android", "Pandora")] } })._page();
  assert.match(few, /Pandora and Spotify open · Family Link till midnight/);
  const many = Array.from({ length: 9 }, (_, i) => app(`com.example.app${i}`, `App ${i}`));
  const html = panel({ sam: { grants: many } })._page();
  assert.match(html, /9 apps open · Family Link till midnight/);
  assert.match(html, /title="App 0, App 1, App 2/);
  assert.doesNotMatch(html, />com\.example/);
});

test("what Hearth holds reads by app name and why, under Device limits", () => {
  const html = panel({
    sam: {
      sync: {
        family_link: {
          held: ["com.google.android.apps.messaging"],
          why: { "com.google.android.apps.messaging": "school_time" },
          names: { "com.google.android.apps.messaging": "Google Messages", "com.example.music": "Music" },
          error: null,
          last: { at: "2026-11-12T10:00:00Z", outcomes: { "com.example.music": "restored" } },
        },
      },
    },
  })._page();
  assert.match(html, /Family Link: holding Google Messages for School time · put back Music/);
  assert.doesNotMatch(html, /holding com\./);
});

// The time-use design (fix-list item 10)

function twoKids() {
  const p = panel();
  p._config.persons.push({ id: "person.alex", name: "Alex" });
  p._config.roles["person.alex"] = "kid";
  p._summary.people.push({
    id: "person.alex",
    name: "Alex",
    all: { id: "all", name: "All screen time", used_minutes: 23, minutes_left: 172, budget: 180, bonus: 15 },
    groups: [],
  });
  return p;
}

test("Today shows a compact row per kid; the full card opens on a tap", () => {
  const p = twoKids();
  let html = p._page();
  assert.match(html, /class="kid-row[^"]*" data-action="kid-open" data-enter="kid-open" data-kid="person.alex"/);
  assert.match(html, /data-kid="person.sam"/);
  // No ring, and no full card until a row is tapped
  assert.doesNotMatch(html, /class="ring/);
  assert.doesNotMatch(html, /id="kid-person.sam"/);
  // No give button on a row without something to answer
  assert.doesNotMatch(html, /kid-row[^]*?data-action="bonus"/);
  p._todayKid = "person.sam";
  html = p._page();
  assert.match(html, /id="kid-person.sam"/);
  assert.doesNotMatch(html, /id="kid-person.alex"/);
});

test("a row has a button only for a waiting request or a suggestion", () => {
  const p = twoKids();
  p._summary.approvals = [{ type: "more_time", id: "q1", person: "person.alex", person_name: "Alex", minutes: 30, group: "all" }];
  p._summary.household = {
    suggestions: [
      { key: "more:youtube", person: "person.sam", person_name: "Sam", text: "youtube ran out", actions: [{ id: "bonus:youtube", label: "+15 youtube", service: "hearth.add_bonus", data: {} }] },
    ],
  };
  p._summary.people[0].actions = [];
  const html = p._page();
  const rows = html.split('class="kid-row').slice(1);
  const alex = rows.find((r) => r.includes('data-kid="person.alex"'));
  const sam = rows.find((r) => r.includes('data-kid="person.sam"'));
  assert.match(alex, /data-action="answer" data-request="q1" data-minutes="30"[^>]*>Yes 30</);
  assert.match(sam, /data-action="glance" data-id="bonus:youtube"[^>]*>\+15 youtube</);
});

test("All screen time is one bar split by pool plus other, with the limit, the bonus and a lane per pool", () => {
  const html = panel({
    sam: {
      all: { id: "all", name: "All screen time", used_minutes: 23, minutes_left: 172, budget: 180, bonus: 15, state: "ok" },
      groups: [
        { id: "youtube", name: "YouTube", used_minutes: 7, minutes_left: 53, budget: 60, bonus: 0, state: "ok" },
        { id: "games", name: "Games", used_minutes: 10, minutes_left: 110, budget: 120, bonus: 0, state: "ok" },
        { id: "messaging", name: "Messaging", used_minutes: 2, minutes_left: null, budget: null, bonus: 0 },
      ],
      all_by_pool: [
        { id: "games", name: "Games", minutes: 10 },
        { id: "youtube", name: "YouTube", minutes: 7 },
        { id: "other", name: "Other", minutes: 6 },
      ],
    },
  })._page();
  assert.match(html, /<span class="strong">All screen time<\/span>.*23 of 3 h 15/s);
  assert.equal((html.match(/class="seg /g) || []).length, 3);
  assert.match(html, /class="seg other"[^>]*title="Other: 6 min"/);
  // The limit at 180 of 195 minutes, the bonus hatched after it
  assert.match(html, /class="bonus" style="left:92.31%;width:7.69%"/);
  assert.match(html, /class="limit" style="left:92.31%"/);
  // A lane per budgeted pool, fewest left first, on the same scale; the rest in one muted line
  assert.match(html, /class="lane role-ok"><span class="bar-label">YouTube<\/span>[^]*?class="limit" style="left:30.77%"[^]*?53 left/);
  assert.match(html, /<span class="bar-label">Games<\/span>/);
  assert.ok(html.indexOf(">YouTube</span>") < html.indexOf(">Games</span>"));
  assert.match(html, /No limit: messaging 2 min/);
});

test("the day strip runs from wake to bedtime, else 6 to 10", () => {
  const today = new Date();
  const at = (h, m = 0) => new Date(today.getFullYear(), today.getMonth(), today.getDate(), h, m).toISOString();
  let html = panel({ sam: { bedtime: { start: at(20, 30), end: at(7) }, school_time: { start: at(8), end: at(15) } } })._page();
  assert.match(html, /class="strip"/);
  const ticks = (h) => [...h.matchAll(/<div class="strip-x">(.*?)<\/div>/gs)][0][1].match(/>(\d+)</g).map((t) => t.slice(1, -1));
  assert.deepEqual(ticks(html), ["7", "9", "11", "1", "3", "5", "7", "9"]);
  // The half hour after bedtime is shaded; School time is striped
  assert.match(html, /class="night" style="left:96.43%;width:3.57%"/);
  assert.match(html, /class="school"/);
  assert.match(html, /bedtime at 8:30/);
  html = panel()._page();
  assert.deepEqual(ticks(html), ["6", "8", "10", "12", "2", "4", "6", "8", "10"]);
});

test("each device shows the time left there as the server worked it out", () => {
  const html = panel({
    sam: {
      targets: [
        { id: "fl:d1", name: "Phone", kind: "phone", via: "family_link", left: 103, left_by: "google", left_pool: null, locked: false, locked_kind: null },
        { id: "fs:xbox", name: "Xbox", kind: "xbox", via: "family_safety", left: 120, left_by: "hearth", left_pool: "games", locked: false, locked_kind: null },
        { id: "hearth:tv1", name: "Kitchen TV", kind: "tv", via: "hearth", left: 157, left_by: "hearth", left_pool: "all", locked: true, locked_kind: "school_time" },
        { id: "hearth:p1", name: "Phone", kind: "phone", via: "hearth", same_as: null, left: 157, left_by: "hearth", locked: false },
      ],
    },
  })._page();
  const tiles = html.split(/class="tile[" ]/).slice(1);
  assert.equal(tiles.length, 4);
  assert.match(tiles[0], /Phone<\/div><div class="strong">1 h 43 left<\/div><div class="muted small">by google</);
  assert.match(tiles[1], /2 h left<\/div><div class="muted small">games, by hearth</);
  assert.match(tiles[2], /^locked"[^]*Locked<\/div><div class="muted small">school time</);
  // An older summary without the fields: no tiles
  assert.doesNotMatch(panel()._page(), /class="tiles"/);
});

test("the Chores card: today's list with tick, Give and Undo, the tasks and the balance", () => {
  const p = panel();
  p._tab = "kids";
  p._todo = {
    "person.sam": {
      today: [
        { id: "t1:2026-11-13", task: "t1", title: "Feed the cat", reward: "+15 min Games", done: true, granted: "t1:2026-11-13#1", by: "adult" },
        { id: "t2:2026-11-13", task: "t2", title: "Teeth", reward: "+5 min Games", done: true, granted: null, by: "adult" },
        { id: "t3", task: "t3", title: "Math sheet", reward: null, done: false, granted: null, by: "kid" },
      ],
      tasks: [
        { id: "t1", title: "Feed the cat", repeat: { kind: "weekdays", days: [0, 1, 2, 3, 4] }, due_time: "07:30", reward: { pool: "all", minutes: 15 } },
        { id: "t4", title: "Mow", repeat: { kind: "after_done", n: 7 }, reward: { cents: 500 } },
      ],
      ledger: [{ key: "t1:2026-11-13#1", kind: "earned", title: "Feed the cat", day: "2026-11-13", pool: "all", minutes: 15 }],
      balance_cents: 1250,
    },
  };
  const html = p._page();
  assert.match(html, /<h3><ha-icon icon="mdi:checkbox-marked-circle-outline"><\/ha-icon>Chores<\/h3>/);
  assert.match(html, /data-change="todo-check"[^>]*data-item="t1:2026-11-13" checked/);
  assert.match(html, /data-action="todo-undo"[^>]*data-key="t1:2026-11-13#1"/);
  // Done with no reward given (a shared screen's tick): Give
  assert.match(html, /no reward given<\/span><button class="btn" data-action="todo-give"[^>]*data-item="t2:2026-11-13"/);
  assert.match(html, /Math sheet <span class="chip small">Sam's own<\/span>/);
  assert.match(html, /Mon to Fri · by 07:30 · \+15 min All screen time/);
  assert.match(html, /7 days after done · \+\$5\.00/);
  assert.match(html, /Balance: <b>\$12\.50<\/b>/);
  assert.match(html, /data-action="todo-add" data-person="person.sam"/);
});

test("the Chores card says when the list couldn't be read", () => {
  const p = panel();
  p._tab = "kids";
  p._todo = { "person.sam": null };
  assert.match(p._page(), /The to-do list couldn't be read/);
});
