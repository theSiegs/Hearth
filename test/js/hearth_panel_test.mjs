// Hearth's sidebar page, drawn without a browser: Today (the redesign: For you, a row per kid, the kid's sheet, Undo),
// the Kids tab's Switch card and how it follows what the installed Nintendo integration can do, chores and the catalog.
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

// Today (the redesign): a header line, For you (with the held-back fold), a row per kid with a ring and one line, the
// kid's sheet, Screens now, the adults' line, and Undo instead of confirm

const at = (h, m = 0) => {
  const t = new Date();
  t.setHours(h, m, 0, 0);
  return t;
};
const iso = (h, m = 0) => at(h, m).toISOString();

// Sam out of Games, Alex in bedtime; an adult with 40 minutes today; the clock at [hour]
function today(hour = 16, { sam = {}, alex = {}, household = {}, approvals = [] } = {}) {
  const p = panel({
    sam: {
      kind: "kid",
      all: { id: "all", name: "All screen time", used_minutes: 149, minutes_left: 31, budget: 180, bonus: 0, state: "ok" },
      groups: [
        { id: "all", name: "All screen time", used_minutes: 149, minutes_left: 31, budget: 180, bonus: 0, state: "ok" },
        { id: "games", name: "Games", used_minutes: 125, minutes_left: 0, budget: 120, bonus: 0, state: "out" },
        { id: "youtube", name: "YouTube", used_minutes: 10, minutes_left: 49, budget: 60, bonus: 0, state: "ok" },
        { id: "messaging", name: "Messaging", used_minutes: 8, minutes_left: null, budget: null, bonus: 0, state: "none" },
      ],
      binding: { group: "games", minutes_left: 0 },
      all_by_pool: [
        { id: "games", name: "Games", minutes: 125 },
        { id: "youtube", name: "YouTube", minutes: 10 },
        { id: "other", name: "Other", minutes: 14 },
      ],
      targets: [
        { id: "hearth:tv1", name: "Kitchen TV", display_name: "Kitchen TV", kind: "tv", via: "hearth", left: 31, left_by: "hearth", left_pool: "all", locked: false, locked_kind: null },
        { id: "hearth:tv2", name: "Playroom TV", display_name: "Playroom TV", kind: "tv", via: "hearth", left: 31, left_by: "hearth", left_pool: "all", locked: false, locked_kind: null },
        { id: "fl:d1", name: "SM-X230", display_name: "Sam's tablet", kind: "phone", via: "family_link", left: 31, left_by: "hearth", left_pool: "all", locked: false, locked_kind: null },
        { id: "fs:xbox", name: "Xbox", display_name: "Xbox", kind: "xbox", via: "family_safety", left: 0, left_by: "hearth", left_pool: "games", locked: true, locked_kind: "out" },
        { id: "nintendo:number.s2", name: "Home Switch 2", display_name: "Sam's Switch 2", kind: "switch", via: "nintendo", left: 0, left_by: "hearth", left_pool: "games", locked: true, locked_kind: "out" },
      ],
      devices_today: [
        { target: "nintendo:number.s2", name: "Sam's Switch 2", kind: "switch", minutes: 125 },
        { target: "fl:d1", name: "Sam's tablet", kind: "phone", minutes: 24 },
      ],
      apps_today: [{ package: "com.example.game", name: "A Game", minutes: 25, groups: ["games"] }],
      week: [
        { date: at(12).toISOString().slice(0, 10), minutes: { all: 149, games: 125, youtube: 10 }, out: ["games"], bonus: {}, asks: 0, budget: { all: 180 } },
        { date: "2026-01-01", minutes: {}, out: [], bonus: {}, asks: 0, budget: { all: 180 } },
      ],
      suggestions: [],
      suggestions_held: [],
      ...sam,
    },
  });
  p._config.persons.push({ id: "person.alex", name: "Alex" }, { id: "person.robin", name: "Robin" });
  p._config.roles["person.alex"] = "kid";
  p._config.roles["person.robin"] = "adult";
  p._summary.people.push(
    {
      id: "person.alex",
      name: "Alex",
      kind: "kid",
      all: { id: "all", name: "All screen time", used_minutes: 74, minutes_left: 105, budget: 180, bonus: 0, state: "ok" },
      groups: [{ id: "all", name: "All screen time", used_minutes: 74, minutes_left: 105, budget: 180, bonus: 0, state: "ok" }],
      lock: { kind: "bedtime", until: iso(7), by: ["binary_sensor.alex_tablet_bedtime_active"] },
      locked: true,
      bedtime: { start: iso(21), end: iso(7) },
      targets: [
        { id: "hearth:tv1", name: "Kitchen TV", display_name: "Kitchen TV", kind: "tv", via: "hearth", left: 105, locked: true, locked_kind: "bedtime" },
        { id: "fs:xbox", name: "Xbox", display_name: "Xbox", kind: "xbox", via: "family_safety", left: 105, locked: true, locked_kind: "bedtime" },
      ],
      suggestions: [],
      suggestions_held: [],
      ...alex,
    },
    { id: "person.robin", name: "Robin", kind: "adult", all: { id: "all", used_minutes: 40, minutes_left: null }, groups: [] }
  );
  p._summary.approvals = approvals;
  p._summary.devices = [{ id: "tv1", name: "Kitchen TV", kind: "tv", connected: true, screen: "off", app: "Hearth TV", profile: "Sam" }];
  p._summary.household = { suggestions: [], suggestions_held: [], counts: {}, ...household };
  p._now = () => at(hour);
  return p;
}

const GAMES_OUT = {
  key: "more:games",
  reason: "group_out",
  group: "games",
  minutes: 15,
  sentence: "Sam's Games time is up",
  detail: "Used 2 h 05 of 2 h · 31 min of screen time left",
  text: "games ran out · give 15?",
  actions: [
    { id: "suggest:more:games:15", label: "+15", service: "hearth.add_bonus", data: { person: "person.sam", minutes: 15, group: "games" }, primary: true },
    { id: "suggest:more:games:30", label: "+30", service: "hearth.add_bonus", data: { person: "person.sam", minutes: 30, group: "games" } },
    { id: "suggest_dismiss:more:games", label: "not today", service: "hearth.dismiss_suggestion", data: { person: "person.sam", key: "more:games" } },
  ],
};

test("Today: one line per kid, bedtime last and faded, a ring around the initial and no +15 in a lock", () => {
  const html = today(16)._page();
  assert.match(html, /<h1>Today<\/h1>/);
  assert.match(html, /4:00 pm · 1 of 2 in bedtime/);
  const kids = html.split('class="card kid').slice(1);
  assert.equal(kids.length, 2);
  assert.match(kids[0], /data-kid="person.sam"[^]*Games ran out<\/b> · 31 min left overall/);
  assert.match(kids[1], /^ asleep"[^]*data-kid="person.alex"[^]*Bedtime till 7:00/);
  assert.match(kids[1], /class="ring tone-night"/);
  assert.match(kids[0], /class="ring tone-low"/);
  // Sam's row offers +15 Games (time is what stops him, before his cutoff); Alex's none
  assert.match(kids[0], /data-action="give" data-person="person.sam" data-group="games" data-minutes="15"/);
  assert.doesNotMatch(kids[1], /data-action="give"/);
  // The old Today is gone: no family by pool, no "Suggested now", no confirm
  assert.doesNotMatch(html, /Family today, by pool|Suggested now|kid-row/);
});

test("For you is honest when it's empty, and folds what's held back with why", () => {
  const held = [
    { ...GAMES_OUT, person: "person.sam", person_name: "Sam", held: "after_cutoff", why: "after 9:00 pm" },
    { key: "more:youtube", person: "person.alex", person_name: "Alex", held: "lock", why: "in bedtime till 7:00", sentence: "Alex's YouTube time is up" },
    { key: "x", person: "person.alex", held: "more", why: "another for them shows first", sentence: "Behind another one" },
  ];
  const html = today(23, { household: { suggestions_held: held } })._page();
  assert.match(html, /<h1>Tonight<\/h1>/);
  assert.match(html, /Sam still up/);
  assert.match(html, /Nothing needs you tonight/);
  assert.match(html, /2 suggestions held back · why/);
  assert.match(html, /<li><span>Alex&#39;s YouTube time is up<\/span><span>in bedtime till 7:00<\/span><\/li>/);
  assert.doesNotMatch(html, /Behind another one/);
  // After 9 pm Sam's row has no +15 either
  assert.doesNotMatch(html.split('class="card kid')[1], /data-action="give"/);
  assert.match(today(16)._page(), /Nothing needs you<\/div>/);
});

test("a suggestion shows as a sentence with +15, 30 and Not today; a request comes first with its own buttons", () => {
  let html = today(16, { sam: { suggestions: [GAMES_OUT] } })._page();
  assert.match(html, /1 thing for you/);
  assert.match(html, /<div class="t">Sam&#39;s Games time is up<\/div><div class="d">Used 2 h 05 of 2 h · 31 min of screen time left<\/div>/);
  assert.match(html, /data-action="sugg-give" data-person="person.sam" data-id="suggest:more:games:15">[^]*?15 min<\/button>/);
  assert.match(html, /data-action="sugg-dismiss" data-person="person.sam" data-key="more:games"[^>]*>Not today/);
  // The row covers Sam: no second +15 on his kid row
  assert.doesNotMatch(html.split('class="card kid')[1], /data-action="give"/);
  const ask = { type: "more_time", id: "q1", person: "person.sam", person_name: "Sam", minutes: 30, group: "games", asked: iso(15, 59) };
  html = today(16, { approvals: [ask], sam: { suggestions: [], suggestions_held: [{ ...GAMES_OUT, held: "more", why: "a request from them comes first" }] } })._page();
  assert.match(html, /Sam asks for 30 more min/);
  assert.match(html, /Games · just now/);
  assert.match(html, /data-action="ask-give" data-request="q1"[^>]*data-minutes="30"[^>]*>Give 30 min/);
  assert.match(html, /data-action="ask-no" data-request="q1"/);
  assert.match(html, /\+1 more for Sam · <button class="lnk" data-action="kid-sheet" data-kid="person.sam">See/);
});

test("the kid's sheet: a lock box during bedtime, Allow an app instead of Give time, and the devices as one row", () => {
  const p = today(23);
  p._hass.entities = { "binary_sensor.alex_tablet_bedtime_active": { platform: "familylink" } };
  p._sel = "person.alex";
  p._sheetOpen = true;
  const html = p._page();
  const sheet = html.slice(html.indexOf('class="detail on"'));
  assert.match(sheet, /Bedtime till 7:00<\/div>[^]*Set in Family Link\. Every screen is off for Alex until then, so extra time wouldn&#39;t help\./);
  assert.match(sheet, /data-action="allow-open"/);
  assert.doesNotMatch(sheet, /data-action="give-open" aria/);
  assert.doesNotMatch(sheet, /data-action="kid-pause"/);
  assert.match(sheet, /All 2 screens|Kitchen TV, Xbox/);
  assert.match(sheet, /Everything follows the lock/);
  // More: Give time anyway
  p._moreOpen = true;
  assert.match(p._page(), /Give time anyway<small>Counts after bedtime ends/);
});

test("the kid's sheet: today split by pool, lanes that open to apps and consoles, devices grouped by state", () => {
  const p = today(16);
  p._sel = "person.sam";
  p._sheetOpen = true;
  p._exp = new Set(["person.sam|pool|games"]);
  const html = p._page();
  const sheet = html.slice(html.indexOf('class="detail on"'));
  assert.match(sheet, /2 h 29 <small>used · 31 min left<\/small>/);
  assert.equal((sheet.match(/<div class="stack"[^]*?<\/div>/)[0].match(/<i /g) || []).length, 3);
  assert.match(sheet, /<span class="nm"><i [^>]*><\/i>Games<\/span>[^]*?class="v t-out">Out/);
  assert.match(sheet, /A Game<\/span><span>25 min/);
  assert.match(sheet, /On Switch 2<\/span><span>2 h 05/);
  assert.match(sheet, /data-action="give" data-person="person.sam" data-group="games" data-minutes="15">\+15 Games/);
  assert.match(sheet, /Not counted|No limit: Messaging 8 min/);
  // Devices: the two out together, the TVs and the tablet together; names without "Sam's", never the model id
  assert.match(sheet, /<div class="t">Xbox, Switch 2<\/div>[^]*?Games ran out/);
  assert.match(sheet, /<div class="t">2 TVs, Tablet<\/div>[^]*?Follows screen time[^]*?31 min left/);
  assert.doesNotMatch(sheet, />SM-X230</);
  // The week: only the recorded day, and the note that history is short
  assert.equal((sheet.match(/class="wb"/g) || []).length, 1);
  assert.match(sheet, /Hearth started counting today/);
  assert.match(sheet, /ran out at some point: Games/);
});

test("exceptions read as sentences: who allowed what, and what Hearth is blocking and why", () => {
  const app = (value, name) => ({ id: value, via: "family_link", target: { kind: "app", value }, until: iso(23, 59), endable: false, name });
  const p = today(16, {
    sam: {
      grants: Array.from({ length: 9 }, (_, i) => app(`com.example.app${i}`, `App ${i}`)),
      sync: { family_link: { held: ["com.a", "com.b", "com.c", "com.d"], why: { "com.a": "budget", "com.b": "budget", "com.c": "budget", "com.d": "budget" }, names: {} } },
      allows: [{ id: "a1", group: "youtube", until: iso(18) }],
    },
  });
  p._sel = "person.sam";
  p._sheetOpen = true;
  const html = p._page();
  assert.match(html, /9 apps are allowed without a limit till 11:59\. Someone changed their limits in the Family Link app\./);
  assert.doesNotMatch(html, />com\.example/);
  assert.match(html, /Hearth is blocking 4 apps on Sam&#39;s Family Link devices because Games ran out\./);
  assert.match(html, /You allowed YouTube till 6:00\. <button class="lnk" data-action="allow-end"/);
});

test("Screens now collapses to one row when nothing plays; the adults get one line", () => {
  const p = today(16);
  let html = p._page();
  assert.match(html, /Nothing playing<\/div><div class="d">1 TV off · no console or Switch in use/);
  assert.doesNotMatch(html, />Sam<\/span>/);
  assert.match(html, /Adults today: Robin 40 min · no limits/);
  p._summary.devices[0].screen = "on";
  p._summary.devices[0].app = "Hearth TV";
  html = p._page();
  assert.match(html, /Kitchen TV<\/div><div class="d">Home screen · Sam/);
});

test("a gift applies at once and offers Undo, which takes back just that", async () => {
  const p = today(16);
  const calls = [];
  p._hass.callService = async (domain, service, data) => calls.push([service, data]);
  p._render = () => {};
  await p._act("give", { dataset: { person: "person.sam", group: "games", minutes: "15" } });
  assert.deepEqual(calls, [["add_bonus", { person: "person.sam", minutes: 15, group: "games" }]]);
  assert.equal(p._undo.text, "Gave Sam 15 min of Games");
  assert.match(p._page(), /<button data-action="undo">Undo<\/button>/);
  await p._act("undo", { dataset: {} });
  assert.deepEqual(calls[1], ["remove_bonus", { person: "person.sam", minutes: 15, group: "games" }]);
  clearTimeout(p._undoTimer);
});

test("Not today hides the row at once and runs only when its Undo is gone; Undo brings it back", async () => {
  const p = today(16, { sam: { suggestions: [GAMES_OUT] } });
  const calls = [];
  p._hass.callService = async (domain, service, data) => calls.push([service, data]);
  p._render = () => {};
  await p._act("sugg-dismiss", { dataset: { person: "person.sam", key: "more:games", id: "suggest_dismiss:more:games" } });
  assert.doesNotMatch(p._page(), /Sam&#39;s Games time is up/);
  assert.deepEqual(calls, []);
  await p._act("undo", { dataset: {} });
  assert.match(p._page(), /Sam&#39;s Games time is up/);
  assert.deepEqual(calls, []);
  // Again, and the page closes before the Undo is gone: it runs then
  await p._act("sugg-dismiss", { dataset: { person: "person.sam", key: "more:games", id: "suggest_dismiss:more:games" } });
  p.disconnectedCallback();
  await new Promise((r) => setTimeout(r, 0));
  assert.deepEqual(calls, [["dismiss_suggestion", { person: "person.sam", key: "more:games" }]]);
  clearTimeout(p._undoTimer);
  for (const w of p._deferred.values()) clearTimeout(w.timer);
});

test("the other tabs: names first with ids in tooltips, Home Assistant's other users folded away", () => {
  const p = panel();
  p._config.apps = [
    { package: "com.example.game", name: "A Game", group: "games" },
    { package: "com.example.app.ardtest", name: "Test build", group: "other" },
  ];
  p._config.groups.push({ id: "games", name: "Games", builtin: true, in_all: true, apps: [], added_apps: [] });
  let html = p._appsTab();
  assert.match(html, /<div title="com.example.game">A Game/);
  assert.doesNotMatch(html, /<div class="muted small">com\.example\.game/);
  assert.doesNotMatch(html, /Test build/);
  p._config.persons.push({ id: "person.helper", name: "helper" });
  html = p._familyTab();
  assert.match(html, /Others in Home Assistant \(1\)/);
  assert.ok(html.indexOf(">Sam<") < html.indexOf("Others in Home Assistant"));
  p._config.sources = [{ id: "s1", entity_id: "sensor.sam_tablet_screen_time", person: "person.sam", name: "Sam's tablet", group: "games" }];
  html = p._sourcesCard({ id: "person.sam", name: "Sam" });
  assert.match(html, /title="sensor.sam_tablet_screen_time"><div>Sam&#39;s tablet<\/div><div class="muted small">Counts in Games</);
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

test("Check these: the shared catalog's guesses and disagreements, kept with Right or moved, with a tick to share", () => {
  const p = panel();
  p._config.groups.push({ id: "games", name: "Games", builtin: true, in_all: true, apps: [], added_apps: [] });
  p._config.check_these = [
    { package: "com.example.maybe", name: "Maybe Game", group: "games", why: "shared catalog suggests game", suggested: true, shareable: true },
    { package: "x:xboxplt:0123456789abcdef", name: "Hub", group: "other", why: "shared catalog says companion, the device says game", suggested: false, shareable: false },
  ];
  p._config.apps = [{ package: "com.example.moved", name: "Moved", group: "games", moved: true, catalog_says: "companion" }];
  p._config.catalog = { fetch: true, share: true, asked: true, keys: 380, values: ["game", "youtube"], pools: { game: "games" }, own_pools: {}, waiting: { keys: 2, corrections: 1 } };
  const html = p._appsTab();
  assert.match(html, /<h3><ha-icon icon="mdi:help-circle-outline"><\/ha-icon>Check these<\/h3>/);
  assert.match(html, /data-action="app-confirm" data-app="com.example.maybe" data-group="games">Right/);
  assert.match(html, /data-change="app-group" data-app="com.example.maybe" data-idx="0"/);
  assert.match(html, /id="catalog-suggest-0"/);
  // A key the catalog can't take (Family Safety's own id) has no tick
  assert.doesNotMatch(html, /id="catalog-suggest-1"/);
  assert.match(html, /the shared catalog now says companion/);
  // Nothing to check: no card
  p._config.check_these = [];
  assert.doesNotMatch(p._appsTab(), /Check these/);
});

test("the shared catalog's setting asks once before sharing, and maps kinds of apps to groups", () => {
  const p = panel();
  p._config.groups.push({ id: "games", name: "Games", builtin: true, in_all: true, apps: [], added_apps: [] });
  p._config.catalog = {
    fetch: true, share: false, asked: false, keys: 380, origin: "bundled", values: ["game", "companion"],
    pools: { game: "games", companion: "other" }, own_pools: { companion: "games" },
  };
  let html = p._catalogCard();
  assert.match(html, /data-change="catalog-fetch" checked/);
  assert.match(html, /data-action="catalog-share-on">Turn on/);
  assert.match(html, /never who uses them/);
  assert.match(html, /the copy Hearth came with/);
  assert.match(html, /Hearth's default \(Games\)/);
  assert.match(html, /<option value="games" selected>Games<\/option>/);
  p._config.catalog = { ...p._config.catalog, asked: true };
  html = p._catalogCard();
  assert.doesNotMatch(html, /catalog-share-on/);
  assert.match(html, /data-change="catalog-share" >/);
});

test("App facts and Sharing app data say what they do without naming an app", () => {
  const p = panel();
  p._config.catalog = { fetch: true, share: false, asked: false, keys: 380, values: [], pools: {}, own_pools: {} };
  p._config.share_app_data = ["person.sam"];
  const facts = p._catalogCard();
  assert.match(facts, /App facts<\/h3>/);
  assert.match(facts, /A public list of what apps are/);
  const sharing = p._sharingCard();
  assert.match(sharing, /Sharing app data<\/h3>/);
  assert.match(sharing, /Off here turns it off on their devices/);
  assert.match(sharing, /data-change="share-app-data" data-person="person.sam" checked/);
  for (const html of [facts, sharing]) assert.doesNotMatch(html, /Glint|tile/i);
});

test("a paired device shows its app, its checks and what's kept for it; a pairing shows the app it brings", () => {
  const p = panel();
  p._config.client_settings = { "com.example.launcher": { count: 3, bytes: 12 * 1024, labels: ["Example rules", "com.example.launcher · kids"] } };
  const lines = p._deviceClientLines({
    id: "phone1", kind: "mobile", person: "person.sam",
    client: { id: "com.example.launcher", companions: [] },
    client_reported: { id: "com.example.launcher", version: "1.4.2" },
    checks: [{ id: "home_app", ok: true, label: "Home app" }, { id: "hearth_client", ok: false, label: "App differs from pairing" }],
  });
  assert.match(lines, /App: com.example.launcher 1.4.2/);
  assert.match(lines, /✓ Home app/);
  assert.match(lines, /class="warn">✗ App differs from pairing/);
  assert.match(lines, /Settings kept for com.example.launcher: 3 \(12 KB\) · Example rules, com.example.launcher · kids/);
  assert.match(lines, /data-action="client-settings-clear" data-client="com.example.launcher">Remove/);
  // Paired before the app said what it is
  assert.match(p._deviceClientLines({ client: null, client_reported: { id: "com.example.launcher" }, checks: [] }), /not confirmed: pair again/);
  assert.equal(p._deviceClientLines({ client: null, client_reported: null, checks: [] }), "");

  p._config.pairings = [{ pairing_id: "p1", name: "Sam's phone", kind: "mobile", code: "123456", client: { id: "com.example.launcher", companions: ["com.example.launcher.phone"] } }];
  assert.match(p._pairingCards(), /App: com.example.launcher \(and com.example.launcher.phone\)/);
});

// The Schedule tab (the weekly schedule)
const SCHOOL_TUE = [["06:45", "free"], ["07:45", "school"], ["15:15", "free"], ["16:00", "homework"], ["17:00", "free"], ["21:30", "sleep"]];
function scheduled({ todayChange = null, empty = false } = {}) {
  const p = panel();
  const days = Object.fromEntries(
    ["mon", "tue", "wed", "thu", "fri", "sat", "sun", "day_off"].map((k, i) => [
      k,
      {
        changes: empty ? [] : (i < 5 ? SCHOOL_TUE : [["08:30", "free"], ["22:30", "sleep"]]).map((c) => [...c]),
        limits: { all: i < 5 ? 180 : 240, games: 60 },
      },
    ])
  );
  p._sched = {
    today: "2026-11-24",
    modes: {
      sleep: { name: "Sleep", allows: "nothing", builtin: true, description: "Bedtime: screens locked." },
      school: { name: "School", allows: "school", builtin: true, description: "School time." },
      free: { name: "Free time", allows: "everything", builtin: true, description: "Everything." },
      homework: { name: "Homework", allows: "some", closed: ["games"], description: "Games closed." },
    },
    groups: [{ id: "all", name: "All screen time", in_all: true }, { id: "games", name: "Games", in_all: true }],
    week: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].map((k, i) => ({ date: `2026-11-${23 + i}`, key: k, type: i === 3 ? "day_off" : i < 5 ? "school" : "weekend" })),
    coming_up: [{ date: "2026-11-26", type: "day_off", source: "typed" }],
    kids: [
      {
        id: "person.sam",
        name: "Sam",
        set: !empty,
        days,
        half_day: { school_ends: "12:00", early: null, limits: "day_off" },
        today: todayChange,
        this_week: ["mon", "tue", "wed", "day_off", "fri", "sat", "sun"].map((u, i) => ({ date: `2026-11-${23 + i}`, uses: u })),
        controls: ["family_link"],
        now: empty
          ? null
          : {
              mode: { id: "homework", name: "Homework", allows: "some", until: "2026-11-24T17:00:00", closed: ["games"] },
              next: { at: "2026-11-24T17:00:00", mode: "free", name: "Free time" },
              bedtime: { at: "2026-11-24T21:30:00", wake: "2026-11-25T06:45:00" },
              day: { date: "2026-11-24", uses: "tue", changed_today: Boolean(todayChange) },
            },
      },
    ],
  };
  p._tab = "schedule";
  p._wide = true;
  p._schDayKey = "tue";
  const sent = [];
  p._hass.callWS = async (m) => {
    sent.push(m);
    return { schedule: p._sched, undo: "tok" };
  };
  p._render = () => {};
  return { p, sent };
}

test("Schedule: the week with the night carried over, the now card, and the day's editor with handles", () => {
  const { p } = scheduled();
  const html = p._page();
  assert.match(html, /data-tab="schedule"/);
  assert.match(html, /Sam: Homework until 5 PM, then Free time/);
  assert.match(html, /Bedtime at 9:30 PM/);
  // Seven weekday rows, the Day off and the Half day
  assert.equal((html.match(/class="s-wrow"/g) || []).length, 9);
  assert.match(html, /26 Nov: day off/);
  // Monday's night comes from Sunday's Sleep, drawn faded
  assert.match(html, /class="s-seg carried"[^>]*title="Sleep midnight–6:45 AM"/);
  assert.equal((html.match(/class="s-hnd"/g) || []).length, 6);
  assert.match(html, /From Mon<\/span>/);
  assert.match(html, /Every Tuesday<\/button><button data-action="sch-scope" data-scope="today"/);
  assert.match(html, /Keeps its own bedtime and School time for now/);
});

test("Schedule: a half day ends School at its time and takes the Day off's limits", () => {
  const { p } = scheduled();
  const kid = p._schKid();
  const half = p._schDay(kid, "half_day");
  assert.deepEqual(half.changes.slice(1, 3), [[465, "school"], [720, "free"]]);
  assert.equal(half.limits.all, 240);
  kid.half_day.limits = "weekday";
  assert.equal(p._schDay(kid, "half_day").limits.all, 180);
});

test("Schedule: edits snap, merge and go to the server; Today only goes to today's change", async () => {
  const { p, sent } = scheduled();
  // A time typed off the quarter hour snaps
  await p._schAct("sch-time", { dataset: { i: "3" }, value: "16:07" });
  assert.equal(sent[0].type, "hearth/schedule/set");
  assert.deepEqual(sent[0].days, ["tue"]);
  assert.deepEqual(sent[0].changes[3], ["16:00", "homework"]);
  // Homework turned Free time merges with its neighbours
  await p._schAct("sch-modesel", { dataset: { i: "3" }, value: "free" });
  assert.deepEqual(sent[1].changes.map((c) => c[1]), ["free", "school", "free", "sleep"]);
  // Remove a change: the one before runs on
  await p._schAct("sch-del", { dataset: { i: "1" } });
  assert.deepEqual(sent[2].changes, [["06:45", "free"], ["21:30", "sleep"]]);
  // Today only
  p._schScope = "today";
  await p._schAct("sch-del", { dataset: { i: "0" } });
  assert.equal(sent[3].type, "hearth/schedule/today");
  assert.deepEqual(sent[3].changes, [["21:30", "sleep"]]);
  clearTimeout(p._undoTimer);
  clearTimeout(p._toastTimer);
});

test("Schedule: limits step by 15 minutes up to No limit, and the copy dialog names its count", async () => {
  const { p, sent } = scheduled();
  await p._schAct("sch-lim", { dataset: { group: "games", v: "15" } });
  assert.match(p._page(), /<output>1 h 15<\/output>/);
  clearTimeout(p._schLimTimer);
  const kid = p._schKid();
  kid.days.tue.limits.games = 600;
  await p._schAct("sch-lim", { dataset: { group: "games", v: "15" } });
  assert.equal(kid.days.tue.limits.games, null);
  clearTimeout(p._schLimTimer);
  await p._schAct("sch-dlg", { dataset: { dlg: "copy" } });
  await p._schAct("sch-q", { dataset: { q: "school" } });
  assert.match(p._page(), /Copy to 4 days/);
  await p._schAct("sch-copy", { dataset: {} });
  assert.deepEqual(sent.at(-1), { type: "hearth/schedule/copy", from: "person.sam", day: "tue", to_days: ["mon", "wed", "thu", "fri"], times: true, limits: true });
  assert.equal(p._undo.text, "Copied Tuesday to Mon, Wed, Thu, Fri");
  clearTimeout(p._undoTimer);
});

test("Schedule: a kid with no times yet, and a today-only change with Back to the schedule", () => {
  let { p } = scheduled({ empty: true });
  let html = p._page();
  assert.match(html, /Sam has no times yet/);
  assert.match(html, /No times yet: the day's limits count/);
  ({ p } = scheduled({ todayChange: { date: "2026-11-24", changes: [["07:00", "free"], ["22:00", "sleep"]], limits: null } }));
  p._schScope = "today";
  html = p._page();
  assert.match(html, /Changed for today only/);
  assert.match(html, /data-action="sch-resume"/);
  assert.match(html, /Changed for today<\/span>/);
});
