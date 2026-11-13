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
