// Hearth's sidebar page, drawn without a browser: Today (the redesign: For you, a row per kid, the kid's sheet, Undo),
// the Kids tab's Switch card and how it follows what the installed Nintendo integration can do, chores and app categories.
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
      time: {
        today_left: 31, today_minutes: 180, base_minutes: 180, bonus: 0, bonus_left: 0, used: 149, unlimited: null, unlimited_today: [],
        text: "31 min left today", adult_text: "31 min left today",
        categories: [
          { id: "games", name: "Games", limit: 120, limit_today: 120, raised: false, until: null, left: 0, used: 125,
            text: "Games are done for today · 31 min left for other things", limit_text: "Games: 2 h limit" },
          { id: "youtube", name: "YouTube", limit: 60, limit_today: 60, raised: false, until: null, left: 49, used: 10,
            text: "YouTube: 49 min left", limit_text: "YouTube: 1 h limit" },
        ],
        origins: [{ kind: "bonus", source: "hearth", by: "Robin", at: iso(15, 5), detail: "Bonus +30", text: "Bonus +30 · added by Robin in Hearth · 3:05 PM" }],
      },
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
  assert.match(kids[0], /data-kid="person.sam"[^]*Games are done for today · 31 min left for other things<\/b>/);
  assert.match(kids[1], /^ asleep"[^]*data-kid="person.alex"[^]*Bedtime till 7:00/);
  assert.match(kids[1], /class="ring tone-night"/);
  assert.match(kids[0], /class="ring tone-low"/);
  // Sam's row offers +15 bonus time (time is what stops him, before his cutoff; no category); Alex's none
  assert.match(kids[0], /data-action="give" data-person="person.sam" data-minutes="15" aria-label="Give Sam 15 min bonus"/);
  // A small "?" beside the line opens where it came from
  assert.match(kids[0], /data-action="origin" data-key="row\|person.sam" aria-label="Where this came from" aria-expanded="false">\?<\/button>/);
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

test("a suggestion shows as a sentence with +15, the + box and Dismiss; a request comes first with its own buttons", () => {
  let html = today(16, { sam: { suggestions: [GAMES_OUT] } })._page();
  // The second amount gave way to the "+" box
  assert.doesNotMatch(html, /data-id="suggest:more:games:30"/);
  assert.match(html, /<button class="b sq" data-action="give-menu" data-menu="list\|person.sam\|more:games" aria-label="More choices" aria-haspopup="menu" aria-expanded="false">/);
  assert.match(html, /1 thing for you/);
  assert.match(html, /<div class="t">Sam&#39;s Games time is up<\/div><div class="d">Used 2 h 05 of 2 h · 31 min of screen time left<\/div>/);
  assert.match(html, /data-action="sugg-give" data-person="person.sam" data-id="suggest:more:games:15">[^]*?15 min<\/button>/);
  assert.match(html, /data-action="sugg-dismiss" data-person="person.sam" data-key="more:games"[^>]*>Dismiss/);
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
  assert.match(sheet, /Bedtime till 7:00<\/div>[^]*Set in Family Link\. Every screen is off for Alex until then\. Bonus time pauses bedtime while it lasts\./);
  assert.match(sheet, /data-action="allow-open"/);
  assert.doesNotMatch(sheet, /data-action="give-open" aria/);
  assert.doesNotMatch(sheet, /data-action="kid-pause"/);
  assert.match(sheet, /All 2 screens|Kitchen TV, Xbox/);
  assert.match(sheet, /Everything follows the lock/);
  // More: bonus time at bedtime pauses it while it lasts; Unlimited is still offered
  p._moreOpen = true;
  assert.match(p._page(), /Bonus time<small>Pauses bedtime while it lasts/);
  assert.match(p._page().split('class="detail on"')[1], /data-action="unlimited-open"/);
});

test("the kid's sheet: one daily time bar with each limit as a marker, category lines that open to apps, devices by state", () => {
  const p = today(16);
  p._sel = "person.sam";
  p._sheetOpen = true;
  p._exp = new Set(["person.sam|cat|games"]);
  const html = p._page();
  const sheet = html.slice(html.indexOf('class="detail on"'));
  assert.match(sheet, /<h3>Daily time <span>of 3 h<\/span>/);
  assert.match(sheet, /2 h 29 <small>used · 31 min left today<\/small>/);
  const bar = sheet.match(/<div class="stack"[^]*?<\/div>/)[0];
  assert.equal((bar.match(/<i /g) || []).length, 3);
  // Games' and YouTube's limits as markers on the one bar
  assert.equal((bar.match(/class="mark"/g) || []).length, 2);
  assert.match(sheet, /<span class="nm"><i [^>]*><\/i>Games are done for today · 31 min left for other things<\/span>[^]*?2 h limit/);
  assert.match(sheet, /YouTube: 49 min left<\/span>[^]*?1 h limit/);
  // No bar per category
  assert.doesNotMatch(sheet, /class="lane"[^]*?<span class="bar">/);
  assert.match(sheet, /A Game<\/span><span>25 min/);
  assert.match(sheet, /On Switch 2<\/span><span>2 h 05/);
  assert.match(sheet, /data-action="raise-open" data-group="games">Raise limit/);
  assert.doesNotMatch(sheet, /\+15 Games/);
  assert.match(sheet, /Not counted|No limit: Messaging 8 min/);
  // Devices: the two out together, the TVs and the tablet together; names without "Sam's", never the model id
  assert.match(sheet, /<div class="t">Xbox, Switch 2<\/div>[^]*?Games ran out/);
  assert.match(sheet, /<div class="t">2 TVs, Tablet<\/div>[^]*?Follows daily time[^]*?31 min left/);
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
  // Bonus time has no category, whatever an older button named
  assert.deepEqual(calls, [["add_time", { person: "person.sam", minutes: 15 }]]);
  assert.equal(p._undo.text, "Gave Sam 15 min bonus");
  assert.match(p._page(), /<button data-action="undo">Undo<\/button>/);
  await p._act("undo", { dataset: {} });
  assert.deepEqual(calls[1], ["remove_time", { person: "person.sam", minutes: 15 }]);
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

// The "+" box: 15, 30, 1 h and Unlock for today, on For you's suggestions and in the kid's sheet

const GAMES_OVER = {
  ...GAMES_OUT,
  minutes: 25,
  over: 10,
  detail: "Used 2 h 10 of 2 h · 10 min over · 31 min of screen time left",
  actions: [
    { id: "suggest:more:games:25", label: "+25", service: "hearth.add_bonus", data: { person: "person.sam", minutes: 25, group: "games" }, primary: true },
    { id: "suggest:more:games:40", label: "+40", service: "hearth.add_bonus", data: { person: "person.sam", minutes: 40, group: "games" } },
    GAMES_OUT.actions[2],
  ],
};

const XBOX_OUT = {
  key: "device:fs:xbox",
  reason: "device_limit",
  group: "all",
  device: "fs:xbox",
  minutes: 15,
  over: 0,
  sentence: "Sam's Xbox is stopped by Microsoft's limit",
  detail: "Microsoft's own limit for today",
  actions: [
    { id: "suggest:device:fs:xbox:15", label: "+15", service: "hearth.add_bonus", data: { person: "person.sam", minutes: 15, group: "all", device: "fs:xbox" }, primary: true },
    { id: "suggest:device:fs:xbox:30", label: "+30", service: "hearth.add_bonus", data: { person: "person.sam", minutes: 30, group: "all", device: "fs:xbox" } },
    { id: "suggest_dismiss:device:fs:xbox", label: "not today", service: "hearth.dismiss_suggestion", data: { person: "person.sam", key: "device:fs:xbox" } },
  ],
};

const menuOf = (html) => html.match(/<div class="givemenu"[^]*?<\/span>/)?.[0] || "";

test("the + box opens a menu of bonus +15, +30, +1 h and No limit today for the suggestion's own category", async () => {
  const p = today(16, { sam: { suggestions: [GAMES_OUT] } });
  p._render = () => {};
  assert.equal(menuOf(p._page()), "");
  await p._act("give-menu", { dataset: { menu: "list|person.sam|more:games" } });
  const html = p._page();
  assert.match(html, /data-menu="list\|person.sam\|more:games"[^>]*aria-expanded="true"/);
  const menu = menuOf(html);
  assert.match(menu, /role="menu" aria-label="Bonus time"/);
  const items = [...menu.matchAll(/<button role="menuitem" ([^>]*)>([^<]*)/g)].map((m) => [m[1], m[2]]);
  assert.deepEqual(items.map((i) => i[1]), ["+15 min", "+30 min", "+1 h", ""]);
  for (const [attrs, , m] of items.slice(0, 3).map((i, n) => [...i, [15, 30, 60][n]]))
    assert.equal(attrs, `data-action="menu-give" data-person="person.sam" data-group="games" data-minutes="${m}"`);
  assert.match(menu, /data-action="menu-unlock" data-person="person.sam" data-group="games">[^]*No Games limit today<small>A raised limit, ends at midnight<\/small>/);
  // Not over: no line under the items
  assert.doesNotMatch(menu, /gnote/);
  // The same box again closes it
  await p._act("give-menu", { dataset: { menu: "list|person.sam|more:games" } });
  assert.equal(menuOf(p._page()), "");
});

test("a catch-up suggestion keeps its own amount first; the menu stays at 15, 30, 1 h and says how far over", () => {
  const p = today(16, { sam: { suggestions: [GAMES_OVER] } });
  p._giveMenu = "list|person.sam|more:games";
  const html = p._page();
  assert.match(html, /data-action="sugg-give" data-person="person.sam" data-id="suggest:more:games:25">[^]*?25 min<\/button>/);
  assert.doesNotMatch(html, /suggest:more:games:40/);
  const menu = menuOf(html);
  assert.deepEqual([...menu.matchAll(/data-minutes="(\d+)"/g)].map((m) => m[1]), ["15", "30", "60"]);
  assert.match(menu, /<div class="gnote">10 min over: \+15 leaves 5<\/div>/);
  // 20 over: +30 is the first that leaves some; past an hour, none does
  p._summary.people[0].suggestions = [{ ...GAMES_OVER, over: 20 }];
  assert.match(menuOf(p._page()), />20 min over: \+30 leaves 10</);
  p._summary.people[0].suggestions = [{ ...GAMES_OVER, over: 75 }];
  assert.match(menuOf(p._page()), />1 h 15 over: \+1 h won't cover it</);
});

test("each amount in the menu applies at once with Undo; on a device it answers with an id that Undo ends", async () => {
  const p = today(16, { sam: { suggestions: [GAMES_OUT] } });
  const calls = [];
  p._hass.callService = async (domain, service, data) => calls.push([service, data]);
  p._render = () => {};
  for (const minutes of [15, 30, 60]) {
    p._giveMenu = "list|person.sam|more:games";
    await p._act("menu-give", { dataset: { person: "person.sam", group: "games", minutes: String(minutes) } });
    assert.equal(p._giveMenu, null);
    assert.deepEqual(calls.at(-1), ["add_time", { person: "person.sam", minutes }]);
    assert.equal(p._undo.text, `Gave Sam ${minutes} min bonus`);
  }
  await p._act("undo", { dataset: {} });
  assert.deepEqual(calls.at(-1), ["remove_time", { person: "person.sam", minutes: 60 }]);
  // A device's suggestion: its device goes with the give
  const q = today(16, { sam: { suggestions: [XBOX_OUT] } });
  const ws = [];
  const qcalls = [];
  q._hass.callWS = async (m) => (ws.push(m), { response: { id: "dx_1" } });
  q._hass.callService = async (domain, service, data) => qcalls.push([service, data]);
  q._render = () => {};
  q._giveMenu = "list|person.sam|device:fs:xbox";
  assert.match(menuOf(q._page()), /data-action="menu-give" data-person="person.sam" data-group="all" data-device="fs:xbox" data-minutes="30"/);
  await q._act("menu-give", { dataset: { person: "person.sam", group: "all", device: "fs:xbox", minutes: "30" } });
  assert.deepEqual(ws, [{ type: "call_service", domain: "hearth", service: "add_bonus", service_data: { person: "person.sam", minutes: 30, group: "all", device: "fs:xbox" }, return_response: true }]);
  assert.equal(q._undo.text, "Gave Sam 30 min on Xbox");
  await q._act("undo", { dataset: {} });
  assert.deepEqual(qcalls, [["allow_end", { id: "dx_1" }]]);
  clearTimeout(p._undoTimer);
  clearTimeout(q._undoTimer);
});

test("Unlock: a category gets no limit today, daily time goes Unlimited, a device is allowed; each with Undo", async () => {
  const p = today(16, { sam: { suggestions: [GAMES_OUT] } });
  const ws = [];
  const calls = [];
  p._hass.callWS = async (m) => (ws.push(m), { response: { id: "al_7", until: { "person.sam": "2026-11-14T23:59:59" } } });
  p._hass.callService = async (domain, service, data) => calls.push([service, data]);
  p._render = () => {};
  p._giveMenu = "list|person.sam|more:games";
  await p._act("menu-unlock", { dataset: { person: "person.sam", group: "games" } });
  assert.equal(p._giveMenu, null);
  assert.deepEqual(calls, [["raise_cap", { person: "person.sam", category: "games", no_cap: true }]]);
  assert.equal(p._undo.text, "No Games limit for Sam today");
  await p._act("undo", { dataset: {} });
  assert.deepEqual(calls.at(-1), ["raise_cap_end", { person: "person.sam", category: "games" }]);
  // Daily time: Unlimited until midnight
  await p._act("menu-unlock", { dataset: { person: "person.sam", group: "all" } });
  assert.deepEqual(calls.at(-1), ["unlimited", { people: ["person.sam"], until: "end_of_day", include_bedtime: false }]);
  assert.equal(p._undo.text, "Unlimited for Sam until midnight");
  await p._act("undo", { dataset: {} });
  assert.deepEqual(calls.at(-1), ["unlimited_end", { people: ["person.sam"] }]);
  // A device: an allow on that device until midnight, ended by its id
  await p._act("menu-unlock", { dataset: { person: "person.sam", group: "all", device: "fs:xbox" } });
  assert.deepEqual(ws[0].service_data, { people: ["person.sam"], group: "all", until: "end_of_day", device: "fs:xbox" });
  assert.equal(p._undo.text, "Unlocked Xbox for Sam until midnight");
  // A failure says so, with no Undo
  p._hass.callService = async () => {
    throw new Error("No category games");
  };
  p._undo = null;
  await p._act("menu-unlock", { dataset: { person: "person.sam", group: "games" } });
  assert.equal(p._undo, null);
  assert.equal(p._toast, "No category games");
  clearTimeout(p._undoTimer);
  clearTimeout(p._toastTimer);
});

test("the sheet's actions: Bonus time (no category), Raise limit, Unlimited with its end and bedtime, Pause screens", async () => {
  const p = today(16);
  const calls = [];
  p._hass.callService = async (domain, service, data) => calls.push([service, data]);
  p._hass.callWS = async (m) => (calls.push([m.service, m.service_data]), { response: { ended: ["person.sam"], text: { "person.sam": "Limits back on · 31 min left today" } } });
  p._render = () => {};
  p._sel = "person.sam";
  p._sheetOpen = true;
  let sheet = p._page().split('class="detail on"')[1];
  assert.match(sheet, />Bonus time<\/button>/);
  assert.match(sheet, /data-action="raise-open"[^>]*>[^]*?Raise limit<\/button>/);
  assert.match(sheet, /data-action="unlimited-open"[^>]*>Unlimited<\/button>/);
  assert.match(sheet, /data-action="kid-pause" data-person="person.sam" data-minutes="30">[^]*?Pause screens 30 min/);
  // Bonus time: amounts only, no category to pick
  p._giveOpen = true;
  sheet = p._page().split('class="detail on"')[1];
  assert.doesNotMatch(sheet, /data-action="give-pool"/);
  assert.match(sheet, /data-action="give" data-person="person.sam" data-minutes="15">Give 15 min bonus/);
  // Raise limit: a category (Games first: it's at its limit) and how much
  p._giveOpen = false;
  await p._act("raise-open", { dataset: {} });
  sheet = p._page().split('class="detail on"')[1];
  assert.match(sheet, /data-action="raise-cat" data-group="games" aria-pressed="true">Games/);
  assert.match(sheet, /Games: 2 h limit\. Daily time stays the same\./);
  await p._act("raise-how", { dataset: { how: "60" } });
  await p._act("raise", { dataset: { person: "person.sam", group: "games", how: "60" } });
  assert.deepEqual(calls.at(-1), ["raise_cap", { person: "person.sam", category: "games", minutes: 60 }]);
  // Unlimited: until turned off, with bedtime
  await p._act("unlimited-open", { dataset: {} });
  await p._act("unlimited-until", { dataset: { until: "turned_off" } });
  await p._act("unlimited-bed", { dataset: {} });
  sheet = p._page().split('class="detail on"')[1];
  assert.match(sheet, /data-action="unlimited-until" data-until="turned_off" aria-pressed="true">Until turned off/);
  assert.match(sheet, /type="checkbox" data-change="unlimited-bed" checked>Include bedtime/);
  await p._act("unlimited", { dataset: { person: "person.sam" } });
  assert.deepEqual(calls.at(-1), ["unlimited", { people: ["person.sam"], until: "turned_off", include_bedtime: true }]);
  // While it's on: its line and End unlimited
  p._summary.people[0].time = { ...p._summary.people[0].time, unlimited: { until: iso(23, 59), open: true, include_bedtime: true, text: "Unlimited (until turned off)" } };
  const html = p._page();
  assert.match(html.split('class="card kid')[1], /<b>Unlimited \(until turned off\)<\/b>/);
  sheet = html.split('class="detail on"')[1];
  assert.match(sheet, /data-action="unlimited-end" data-person="person.sam">End unlimited/);
  await p._act("unlimited-end", { dataset: { person: "person.sam" } });
  assert.deepEqual(calls.at(-1), ["unlimited_end", { people: ["person.sam"] }]);
  assert.equal(p._toast, "Limits back on · 31 min left today");
  // The "?" shows where today's statuses came from
  await p._act("origin", { dataset: { key: "sheet|person.sam" } });
  assert.match(p._page(), /<div class="origins" role="note"><div>Bonus \+30 · added by Robin in Hearth · 3:05 PM<\/div><\/div>/);
  clearTimeout(p._undoTimer);
  clearTimeout(p._toastTimer);
});

test("the kid's sheet has the same + box beside Bonus time, for the category that stops them", () => {
  const p = today(16, {
    sam: {
      groups: [
        { id: "all", name: "All screen time", used_minutes: 155, minutes_left: 25, budget: 180, bonus: 0, state: "ok" },
        { id: "games", name: "Games", used_minutes: 131, minutes_left: 0, budget: 120, bonus: 0, state: "out" },
      ],
    },
  });
  p._sel = "person.sam";
  p._sheetOpen = true;
  let sheet = p._page().split('class="detail on"')[1];
  assert.match(sheet, /Bonus time<\/button><span class="givebox"><button class="b sq" data-action="give-menu" data-menu="bar\|person.sam"/);
  p._giveMenu = "bar|person.sam";
  sheet = p._page().split('class="detail on"')[1];
  const menu = menuOf(sheet);
  assert.match(menu, /data-action="menu-give" data-person="person.sam" data-group="games" data-minutes="15">\+15 min/);
  assert.match(menu, /data-action="menu-unlock" data-person="person.sam" data-group="games"/);
  // 11 past the 2 h: 15 over (rounded up to 5, as the server counts it)
  assert.match(menu, /15 min over: \+30 leaves 15/);
  // In bedtime: no Bonus time, no box
  const q = today(23);
  q._sel = "person.alex";
  q._sheetOpen = true;
  assert.doesNotMatch(q._page().split('class="detail on"')[1], /data-action="give-menu"/);
});

test("a tap outside the menu or Esc closes it; a tap inside doesn't", () => {
  const p = today(16, { sam: { suggestions: [GAMES_OUT] } });
  let renders = 0;
  p._render = () => renders++;
  const listeners = {};
  p.shadowRoot.addEventListener = (type, fn) => (listeners[type] = fn);
  p.connectedCallback();
  const el = (inside, action = null) => ({ closest: (sel) => (sel === ".givebox" ? (inside ? {} : null) : action ? { dataset: { action } } : null) });
  p._giveMenu = "list|person.sam|more:games";
  listeners.click({ target: el(true), preventDefault() {} });
  assert.equal(p._giveMenu, "list|person.sam|more:games");
  listeners.click({ target: el(false), preventDefault() {} });
  assert.equal(p._giveMenu, null);
  assert.equal(renders, 1);
  p._giveMenu = "list|person.sam|more:games";
  p._sheetOpen = true;
  listeners.keydown({ key: "Escape", target: { dataset: {}, getAttribute: () => null } });
  assert.equal(p._giveMenu, null);
  // Esc closed only the menu, not the sheet under it
  assert.equal(p._sheetOpen, true);
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
  assert.match(html, /Mon to Fri · by 07:30 · \+15 min bonus/);
  // No category to pick for a reward
  assert.doesNotMatch(html, /todo-pool/);
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

const CATEGORIES = {
  lookup: true, ai: "default", ai_entity: null, ai_default: null, starter: 400, waiting: 1,
  sources: { override: 1, starter: 5, store: 2, ai: 1, unknown: 3 },
  values: ["game", "youtube", "companion"], pools: { game: "games", companion: "other" }, own_pools: { companion: "games" },
  labels: { game: "Games", video: "Video", youtube: "YouTube", productivity: "Productivity", companion: "Companion apps", interface: "System screens", messaging: "Messaging" },
  category_choices: ["game", "video", "productivity", "messaging", "interface"],
  detail_choices: { youtube: "video", companion: "productivity" },
  ai_entities: ["ai_task.ollama"],
};

test("Check these: guesses (an AI's, a store's) and disagreements, kept with Right or moved", () => {
  const p = panel();
  p._config.groups.push({ id: "games", name: "Games", builtin: true, in_all: true, apps: [], added_apps: [] });
  p._config.check_these = [
    { package: "com.example.maybe", name: "Maybe Game", group: "games", why: "an AI guessed game", suggested: true },
    { package: "x:xboxplt:0123456789abcdef", name: "Hub", group: "other", why: "Hearth says companion, the device says game", suggested: false },
  ];
  p._config.apps = [{ package: "com.example.moved", name: "Moved", group: "games", moved: true, category_says: "companion", source: "starter", category: "productivity", detail: "companion" }];
  p._config.categories = CATEGORIES;
  const html = p._appsTab();
  assert.match(html, /<h3><ha-icon icon="mdi:help-circle-outline"><\/ha-icon>Check these<\/h3>/);
  assert.match(html, /data-action="app-confirm" data-app="com.example.maybe" data-group="games">Right/);
  assert.match(html, /data-change="app-group" data-app="com.example.maybe" data-idx="0"/);
  assert.match(html, /an AI guessed game/);
  // Nothing is shared anywhere: no tick
  assert.doesNotMatch(html, /suggest|catalog/i);
  assert.match(html, /Hearth now knows it as Companion apps/);
  // Nothing to check: no card
  p._config.check_these = [];
  assert.doesNotMatch(p._appsTab(), /Check these/);
});

test("Every app shows what each app is and where that came from, and an adult can say what it is", () => {
  const p = panel();
  p._config.groups.push({ id: "games", name: "Games", builtin: true, in_all: true, apps: [], added_apps: [] });
  p._config.categories = CATEGORIES;
  p._config.apps = [
    { package: "com.example.tube", name: "Tube", group: "other", source: "starter", category: "video", detail: "youtube", confirmed: true },
    { package: "com.example.guess", name: "Guess", group: "games", source: "ai", category: "game", detail: null, confirmed: false },
    { package: "com.example.new", name: "New", group: "other", source: "unknown", category: null, detail: null, waiting: true },
    { package: "com.example.mine", name: "Mine", group: "games", source: "override", category: "game", detail: null, confirmed: true },
    { package: "com.example.shop", name: "Shop", group: "other", source: "store", category: null, detail: null, genre: "SHOPPING" },
    { package: "com.example.web", name: "Web", group: "other", source: "override", category: null, detail: null },
  ];
  let html = p._appsTab();
  assert.match(html, /YouTube \(Hearth&#39;s list\)/);
  assert.match(html, /Games \(AI guess\)/);
  assert.match(html, /<span class="chip small warn">AI guess<\/span>/);
  assert.match(html, /kind not known \(not known yet, looking it up\)/);
  assert.match(html, /Games \(set by you\)/);
  assert.match(html, /none of Hearth&#39;s kinds \(store: SHOPPING\)/);
  // The select: Hearth's answer first, the adult's own choice selected when there is one
  assert.match(html, /data-change="app-category" data-app="com.example.tube"[^>]*>\s*<option value="auto" selected>Hearth: YouTube<\/option>/);
  assert.match(html, /<option value="video\/youtube" >Video: YouTube<\/option>/);
  assert.match(html, /data-change="app-category" data-app="com.example.mine"[\s\S]*?<option value="game" selected>Games<\/option>/);
  assert.match(html, /data-change="app-category" data-app="com.example.web"[\s\S]*?<option value="none" selected>None of these<\/option>/);
  assert.match(html, /<option value="interface" >System screens<\/option>/);
  // Review the guesses and the unknown ones
  p._appSource = "ai";
  html = p._appsTab();
  assert.match(html, /title="com.example.guess"/);
  assert.doesNotMatch(html, /title="com.example.tube"/);
  assert.match(html, /<option value="ai" selected>AI guesses<\/option>/);
  p._appSource = "unknown";
  html = p._appsTab();
  assert.match(html, /title="com.example.new"/);
  assert.doesNotMatch(html, /title="com.example.guess"/);
});

test("saying what an app is calls hearth/apps/category, and auto takes it back", async () => {
  const p = panel();
  p._config.categories = CATEGORIES;
  const calls = [];
  p._hass = { states: {}, callWS: async (m) => { calls.push(m); return null; } };
  p._loadConfig = async () => {};
  p._render = () => {};
  const realTimeout = globalThis.setTimeout;
  globalThis.setTimeout = (fn) => { fn(); return 0; };
  try {
    await p._act("app-category", { value: "video/youtube", dataset: { app: "com.example.tube" }, checked: false });
    await p._act("app-category", { value: "none", dataset: { app: "com.example.web" }, checked: false });
    await p._act("app-category", { value: "auto", dataset: { app: "com.example.web" }, checked: false });
  } finally {
    globalThis.setTimeout = realTimeout;
  }
  assert.deepEqual(calls, [
    { type: "hearth/apps/category", app: "com.example.tube", category: "video", detail: "youtube" },
    { type: "hearth/apps/category", app: "com.example.web", category: "none" },
    { type: "hearth/apps/category", app: "com.example.web", category: "auto" },
  ]);
});

test("the App categories card: counts by source, store lookups, the AI Task entity and the group map", () => {
  const p = panel();
  p._config.groups.push({ id: "games", name: "Games", builtin: true, in_all: true, apps: [], added_apps: [] });
  p._config.categories = CATEGORIES;
  let html = p._categoriesCard();
  assert.match(html, /App categories<\/h3>/);
  assert.match(html, /Hearth knows 400 apps from its own list/);
  assert.match(html, /sends the app's public store id/);
  assert.match(html, /1 set by you, 5 from Hearth&#39;s list, 2 from their store, 1 AI guesses, 3 not known · 1 waiting to be looked up/);
  assert.match(html, /data-change="category-lookup" checked/);
  // The default: Home Assistant's default AI Task, here none set
  assert.match(html, /<option value="default" selected>Home Assistant's default AI Task \(none set\)<\/option>/);
  assert.match(html, /<option value="off" >Off<\/option>/);
  assert.match(html, /<option value="ai_task.ollama" >ai_task.ollama<\/option>/);
  assert.match(html, /No default AI Task in Home Assistant/);
  assert.match(html, /never puts an app in Messaging, Accessibility or System screens/);
  assert.match(html, /Hearth's default \(Other\)/);
  assert.match(html, /<option value="games" selected>Games<\/option>/);
  assert.match(html, /<div class="grow">Companion apps<\/div>/);
  // Home Assistant's default set: named as what AI guesses use
  p._hass = { states: { "ai_task.ollama": { attributes: { friendly_name: "Ollama AI Task" } } } };
  p._config.categories = { ...CATEGORIES, lookup: false, ai_entity: "ai_task.ollama", ai_default: "ai_task.ollama" };
  html = p._categoriesCard();
  assert.match(html, /data-change="category-lookup" >/);
  assert.match(html, /Home Assistant's default AI Task \(Ollama AI Task\)/);
  assert.match(html, /AI guesses use Ollama AI Task\./);
  // A specific entity, and off
  p._config.categories = { ...CATEGORIES, ai: "ai_task.ollama", ai_entity: "ai_task.ollama" };
  assert.match(p._categoriesCard(), /<option value="ai_task.ollama" selected>Ollama AI Task<\/option>/);
  p._config.categories = { ...CATEGORIES, ai: "off", ai_entity: null, ai_default: "ai_task.ollama" };
  html = p._categoriesCard();
  assert.match(html, /<option value="off" selected>Off<\/option>/);
  assert.match(html, /No AI is asked\./);
  // The card sits on the Apps tab, and nothing names the retired catalog
  assert.match(p._appsTab(), /App categories<\/h3>/);
  assert.doesNotMatch(html, /App facts|catalog|Glint|tile/i);
});

test("Sharing app data says what it does without naming an app", () => {
  const p = panel();
  p._config.share_app_data = ["person.sam"];
  const sharing = p._sharingCard();
  assert.match(sharing, /Sharing app data<\/h3>/);
  assert.match(sharing, /Off here turns it off on their devices/);
  assert.match(sharing, /data-change="share-app-data" data-person="person.sam" checked/);
  assert.doesNotMatch(sharing, /Glint|tile/i);
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

test("Parental controls: what Hearth does with less on the installed Family Safety, not a problem", () => {
  const fs = {
    domain: "microsoft_family_safety",
    name: "Microsoft Family Safety",
    entries: [{ entry_id: "e1", title: "Family Safety", state: "loaded" }],
    connection: { entity_id: "sensor.microsoft_family_safety_connection", state: "connected", reauth_required: false },
    reduced: ["Hearth's locks last whole hours, so they end up to an hour after midnight."],
  };
  const p = panel({ controls: [fs] });
  const html = p._parentalControlsCard();
  assert.match(html, /Works with less on this version \(1\)/);
  assert.match(html, /end up to an hour after midnight/);
  assert.match(html, /dot on/);
  assert.deepEqual(p._controlProblems(), []);
  // A version with everything: nothing said
  const full = panel({ controls: [{ ...fs, reduced: [] }] });
  assert.doesNotMatch(full._parentalControlsCard(), /Works with less/);
});

const APP_BLOCKS = {
  rule: true,
  supported: [
    { name: "Chrome", platform: "Android", package: "com.android.chrome", filtered_by: "Family Link" },
    { name: "Microsoft Edge", platform: "Windows", package: null, filtered_by: "Family Safety" },
    { name: "Microsoft Edge", platform: "Xbox", package: null, filtered_by: "Family Safety" },
  ],
  browsers: { "org.mozilla.firefox": "Firefox" },
  app_stores: { "com.sec.android.app.samsungapps": "Galaxy Store" },
  kids: [
    {
      person: "person.sam",
      name: "Sam",
      family_link: true,
      blocks: [
        { app: "org.mozilla.firefox", name: "Firefox", why: ["browser"], state: "blocked" },
        { app: "com.example.chat", name: "Chat", why: ["adult"], state: "parent" },
      ],
      exempt: [],
      web_filter: { entity_id: "switch.sam_web_filtering", on: true },
    },
    { person: "person.robin", name: "Robin", family_link: false, blocks: [], exempt: [], web_filter: { entity_id: "switch.robin_web_filtering", on: false } },
  ],
};

test("Blocked by Hearth: the browser rule, where Hearth filters sites, each kid's blocks with Unblock, and Windows and Xbox", () => {
  const p = panel();
  p._config.app_blocks = APP_BLOCKS;
  p._config.apps = [
    { package: "org.mozilla.firefox", name: "Firefox", group: "other" },
    { package: "com.example.game", name: "Game", group: "other" },
    { package: "x:9NBLGGH4R315", name: "Xbox game", group: "other" },
  ];
  const html = p._appsTab();
  assert.match(html, /Blocked by Hearth<\/h3>/);
  assert.match(html, /data-change="block-browsers" checked> Block browsers Hearth doesn't support/);
  assert.match(html, /Hearth filters sites in: Chrome on Android, Microsoft Edge on Windows, Microsoft Edge on Xbox/);
  assert.match(html, /Galaxy Store/);
  assert.match(html, /a browser Hearth doesn&#39;t support · blocked/);
  assert.match(html, /by an adult · blocked by a parent in Family Link/);
  assert.match(html, /data-action="app-unblock" data-app="org.mozilla.firefox" data-name="Firefox" data-person="person.sam">Unblock/);
  assert.match(html, /covered by Family Safety web filtering: on/);
  assert.match(html, /Family Safety web filtering is off/);
  assert.match(html, /Robin[\s\S]*No Family Link set up/);
  // Rows: blocked ones say so; others get Block, but not an Xbox app
  assert.match(html, /Firefox <span class="chip small out">blocked<\/span>/);
  assert.match(html, /data-action="app-block" data-app="com.example.game"/);
  assert.doesNotMatch(html, /data-action="app-block" data-app="org.mozilla.firefox"/);
  assert.doesNotMatch(html, /data-action="app-block" data-app="x:9NBLGGH4R315"/);
});

test("Block and Unblock go through hearth.block_app and hearth.unblock_app; the rule through the option", async () => {
  const p = panel();
  p._config.app_blocks = APP_BLOCKS;
  const services = [];
  const ws = [];
  p._hass = { states: {}, callService: async (d, s, data) => { services.push([d, s, data]); }, callWS: async (m) => { ws.push(m); return null; } };
  p._loadConfig = async () => {};
  p._render = () => {};
  p._notify = () => {};
  const realTimeout = globalThis.setTimeout;
  globalThis.setTimeout = (fn) => { fn(); return 0; };
  try {
    await p._act("app-block", { dataset: { app: "com.example.game", name: "Game" } });
    await p._act("app-unblock", { dataset: { app: "org.mozilla.firefox", name: "Firefox", person: "person.sam" } });
    await p._act("block-browsers", { checked: false, dataset: {} });
  } finally {
    globalThis.setTimeout = realTimeout;
  }
  assert.deepEqual(services, [
    ["hearth", "block_app", { app: "com.example.game" }],
    ["hearth", "unblock_app", { app: "org.mozilla.firefox", people: ["person.sam"] }],
  ]);
  assert.deepEqual(ws, [{ type: "hearth/config/set", key: "block_unsupported_browsers", value: false }]);
});
