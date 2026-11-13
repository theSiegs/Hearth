// Hearth's page in Home Assistant's sidebar: the family today, each kid's rules, devices, apps and the household's
// settings, plus a guided setup. It talks to the integration over Home Assistant's WebSocket (panel.py, websocket.py)
// and calls Hearth's services for extra time and YouTube blocks. Plain custom element, no build step; Home Assistant's
// theme variables do the colors, so it follows light and dark themes.

const TABS = [
  { id: "today", label: "Today", icon: "mdi:home-heart" },
  { id: "kids", label: "Kids", icon: "mdi:account-child" },
  { id: "devices", label: "Devices", icon: "mdi:television" },
  { id: "apps", label: "Apps", icon: "mdi:apps" },
  { id: "family", label: "Family", icon: "mdi:account-group" },
];

const SETUP_STEPS = [
  { id: "welcome", title: "Welcome" },
  { id: "people", title: "Who's who" },
  { id: "pins", title: "Parent PINs" },
  { id: "devices", title: "TVs and phones" },
  { id: "screen", title: "Screen time" },
  { id: "limits", title: "Daily limits" },
  { id: "done", title: "Done" },
];

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

// One time format everywhere (noiwid's hm(), glance.duration): "45 min", "2 h 10", "1 h 05", "3 h"
const fmtMinutes = (minutes) => {
  if (minutes === null || minutes === undefined) return "No limit";
  const m = Math.max(0, Math.round(minutes));
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r ? `${h} h ${String(r).padStart(2, "0")}` : `${h} h`;
};

// Before "left" and "of", after "+": the bare number under an hour ("10 left", "+15"), else as above ("1 h 20 left")
const amount = (minutes) => {
  const m = Math.max(0, Math.round(minutes || 0));
  return m < 60 ? String(m) : fmtMinutes(m);
};

// A time of day as the glance writes it: "6:30" (local, 12-hour, no am/pm), "midnight", "noon"
const clock = (iso) => {
  const t = iso ? new Date(iso) : null;
  if (!t || Number.isNaN(t.getTime())) return "";
  if (t.getMinutes() === 0 && t.getHours() % 12 === 0) return t.getHours() === 0 ? "midnight" : "noon";
  return `${t.getHours() % 12 || 12}:${String(t.getMinutes()).padStart(2, "0")}`;
};

// The server's text is lower case: the panel capitalizes the first letter only
const cap = (text) => {
  const s = String(text ?? "");
  return s.charAt(0).toUpperCase() + s.slice(1);
};

// "a", "a and b", "a, b and c"
const listWords = (words) => (words.length <= 1 ? words.join("") : `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}`);

// A pool's short name, as the glance writes it: "screen time" for All, else the group's name in lower case
const shortGroup = (id, name) => (id === "all" ? "screen time" : String(name || id).toLowerCase());

// The summary's state for a group or person, as a color role (spec section 4); unknown: neutral
const ROLES = ["ok", "low", "out", "allowed", "paused", "locked", "held", "none"];
const role = (state) => (ROLES.includes(state) ? state : "none");

// noiwid's hourly chart (parental-screen-time.js): 24 bars in minutes, steps of 15 min up to an hour, 30 above
const hourChart = (values) => {
  const peak = Math.max(...values);
  const top = peak <= 60 ? 60 : Math.ceil(peak / 30) * 30;
  const steps = top <= 60 ? 4 : top / 30;
  const grid = Array.from({ length: steps + 1 }, (_, i) => top - (i * top) / steps);
  return `<div class="plot">
    <div class="hy">${grid.map((v) => `<span>${Math.round(v)} min</span>`).join("")}</div>
    <div class="harea">${grid.map((_, i) => `<i style="top:${(i * 100) / steps}%"></i>`).join("")}
      <div class="hcols">${values.map((v) => `<div class="hcol"><div style="height:${Math.min(100, (v / top) * 100)}%" title="${esc(fmtMinutes(v))}"></div></div>`).join("")}</div>
    </div>
    <div></div><div class="hx">${values.map((_, i) => `<span>${i % 2 ? "" : `${i}h`}</span>`).join("")}</div>
  </div>`;
};

// Minutes in each hour today from the hourly statistics of a sensor that counts up through the day (noiwid's
// _hours): an hour's use is its growth, or its whole value right after the midnight reset; `live` is the value now
const hourBars = (rows, midnight, live) => {
  const at = (t) => (typeof t === "number" ? t : Date.parse(t));
  const list = (rows || []).map((r) => ({ t: at(r.start), v: r.state ?? r.max })).filter((r) => r.v !== null && r.v !== undefined);
  if (!Number.isNaN(live)) list.push({ t: Date.now(), v: live });
  const bars = new Array(24).fill(0);
  let prev = list.length && list[0].t < midnight ? list[0].v : 0;
  for (const r of list) {
    if (r.t < midnight) continue;
    bars[new Date(r.t).getHours()] += Math.max(0, r.v >= prev ? r.v - prev : r.v);
    prev = r.v;
  }
  // Sources report in bursts: no hour holds more than 60 min, the rest belongs to the hours before
  for (let h = 23; h > 0; h--) if (bars[h] > 60) { bars[h - 1] += bars[h] - 60; bars[h] = 60; }
  return bars.map((v) => Math.min(60, v));
};

const slug = (text) =>
  String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 64);

class HearthPanel extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._tab = "today";
    this._kid = null;
    this._summary = null;
    this._config = null;
    this._error = null;
    this._toast = null;
    this._setupStep = null;
    this._watch = {};
    this._busy = false;
    this._drafts = {};
    this._open = new Set();
    // Today's kid cards: the pool each 7-day chart shows, the day tapped, and the hourly statistics read
    this._weekGroup = {};
    this._weekDay = {};
    this._hours = {};
    this._hoursBusy = new Set();
  }

  set hass(hass) {
    const first = !this._hass;
    this._hass = hass;
    if (first) this._start();
  }

  get hass() {
    return this._hass;
  }

  set narrow(value) {
    this._narrow = value;
    if (this._config) this._render();
  }

  set panel(value) {
    this._panel = value;
  }

  connectedCallback() {
    this.shadowRoot.addEventListener("click", (e) => this._onClick(e));
    this.shadowRoot.addEventListener("change", (e) => this._onChange(e));
    this.shadowRoot.addEventListener("input", (e) => {
      const t = e.target;
      if (t.id === "app-filter") {
        this._appFilter = t.value.trim().toLowerCase();
        clearTimeout(this._filterTimer);
        this._filterTimer = setTimeout(() => this._render(), 250);
      }
      if (t.id && !t.dataset.change) this._drafts[t.id] = t.type === "checkbox" ? t.checked : t.value;
    });
    this.shadowRoot.addEventListener(
      "toggle",
      (e) => {
        if (e.target.tagName === "DETAILS" && e.target.id) {
          if (e.target.open) this._open.add(e.target.id);
          else this._open.delete(e.target.id);
          // The hourly chart reads Home Assistant's statistics only once someone opens it
          if (e.target.open && e.target.dataset.hours) this._loadHours(e.target.dataset.hours);
        }
      },
      true
    );
    this.shadowRoot.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && e.target.dataset && e.target.dataset.enter) {
        e.preventDefault();
        this._act(e.target.dataset.enter, e.target);
      }
    });
    try {
      const saved = window.localStorage.getItem("hearth-panel-tab");
      if (saved && TABS.some((t) => t.id === saved)) this._tab = saved;
    } catch (_err) {
      // A private window: the first tab
    }
    // A link to a tab (/hearth#kids); #approvals is Today, where requests and pairings wait
    const hash = (window.location.hash || "").replace("#", "");
    if (hash === "approvals") this._tab = "today";
    else if (TABS.some((t) => t.id === hash)) this._tab = hash;
    // A request's notification opens /hearth?ask=<id>: Today, scrolled to that request
    try {
      const ask = new URLSearchParams(window.location.search).get("ask");
      if (ask) {
        this._askFocus = ask;
        this._askShown = false;
        this._tab = "today";
      }
    } catch (_err) {
      // No query string to read
    }
    if (this._hass && !this._unsub) this._start();
  }

  disconnectedCallback() {
    if (this._unsub) {
      this._unsub.then((unsub) => unsub()).catch(() => {});
      this._unsub = null;
    }
  }

  async _start() {
    if (!this.isConnected || this._unsub) return;
    this._render();
    await this._loadConfig();
    this._unsub = this._hass.connection
      .subscribeMessage((summary) => {
        const before = this._summary;
        this._summary = summary;
        // Devices waiting to pair, or a new one: the settings side shows them too
        if (before && JSON.stringify(before.approvals) !== JSON.stringify(summary.approvals)) this._loadConfig();
        // Only Today shows live numbers: the other tabs aren't redrawn under someone typing
        else if (this._tab === "today" && this._setupStep === null) this._render();
      }, { type: "hearth/household/subscribe" })
      .catch((err) => {
        this._error = this._message(err);
        this._render();
      });
  }

  async _loadConfig(retries = 0) {
    try {
      this._config = await this._hass.callWS({ type: "hearth/config" });
      this._error = null;
      if (this._setupStep === null && !Object.keys(this._config.roles || {}).length) this._setupStep = 0;
      const kids = this._kids();
      if (!this._kid || !kids.some((k) => k.id === this._kid)) this._kid = kids.length ? kids[0].id : null;
    } catch (err) {
      // The entry reloads after a setting changes: it answers again in a moment
      if (retries < 8) {
        await new Promise((r) => setTimeout(r, 700));
        return this._loadConfig(retries + 1);
      }
      this._error = this._message(err);
    }
    this._render();
  }

  _message(err) {
    if (!err) return "Something went wrong";
    if (err.code === "not_set_up" || err.code === "unknown_command")
      return "Hearth isn't set up yet. Add it in Settings → Devices & services → Add integration → Hearth.";
    return err.message || String(err);
  }

  _notify(text) {
    this._toast = text;
    this._render();
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => {
      this._toast = null;
      this._render();
    }, 3500);
  }

  // Helpers over the config

  _personName(id) {
    const p = (this._config?.persons || []).find((x) => x.id === id);
    if (p) return p.name;
    const state = this._hass.states[id];
    return state?.attributes?.friendly_name || (id || "").replace(/^person\./, "");
  }

  _picture(id) {
    return this._hass.states[id]?.attributes?.entity_picture || null;
  }

  _kids() {
    const roles = this._config?.roles || {};
    return Object.keys(roles)
      .filter((p) => roles[p] === "kid")
      .map((id) => ({ id, name: this._personName(id) }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  _adults() {
    const roles = this._config?.roles || {};
    return Object.keys(roles)
      .filter((p) => roles[p] === "adult")
      .map((id) => ({ id, name: this._personName(id) }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  _summaryPerson(id) {
    return (this._summary?.people || []).find((p) => p.id === id) || null;
  }

  _groupName(id) {
    return (this._config?.groups || []).find((g) => g.id === id)?.name || id;
  }

  _entityName(entityId) {
    const state = this._hass.states[entityId];
    return state?.attributes?.friendly_name || entityId;
  }

  // Writes

  async _ws(message, done) {
    if (this._busy) return;
    this._busy = true;
    try {
      await this._hass.callWS(message);
      this._drafts = {};
      if (done) this._notify(done);
    } catch (err) {
      this._notify(this._message(err));
    } finally {
      this._busy = false;
    }
  }

  async _setOption(key, value, done) {
    await this._ws({ type: "hearth/config/set", key, value }, done);
    // The entry reloads with the new options
    await new Promise((r) => setTimeout(r, 900));
    await this._loadConfig();
  }

  async _service(service, data, done) {
    try {
      await this._hass.callService("hearth", service, data);
      this._drafts = {};
      if (done) this._notify(done);
    } catch (err) {
      this._notify(this._message(err));
    }
  }

  // Events

  _onClick(e) {
    const target = e.target.closest("[data-action]");
    if (!target) return;
    e.preventDefault();
    this._act(target.dataset.action, target);
  }

  _onChange(e) {
    const target = e.target.closest("[data-change]");
    if (!target) return;
    this._act(target.dataset.change, target);
  }

  _value(selector) {
    const el = this.shadowRoot.querySelector(selector);
    return el ? el.value.trim() : "";
  }

  async _act(action, el) {
    const d = el.dataset;
    const cfg = this._config;
    switch (action) {
      case "menu":
        this.dispatchEvent(new Event("hass-toggle-menu", { bubbles: true, composed: true }));
        return;
      case "tab":
        this._tab = d.tab;
        this._setupStep = null;
        try {
          window.localStorage.setItem("hearth-panel-tab", d.tab);
        } catch (_err) {
          // Not kept
        }
        this._render();
        if (d.tab === "kids" && this._kid) this._loadWatch(this._kid);
        return;
      case "kid-open":
        // A kid's row on Today: their full card opens under the rows (tap again to close)
        this._todayKid = this._todayKid === d.kid ? null : d.kid;
        this._render();
        if (this._todayKid) this._loadHours(this._todayKid);
        return;
      case "kid":
        this._kid = d.kid;
        if (d.go) this._tab = d.go;
        this._render();
        this._loadWatch(d.kid);
        return;
      case "grant-end":
        if (!window.confirm("End what the parent gave in their app? Hearth's hold comes back.")) return;
        await this._service("allow_end", { id: d.grant }, "Ended");
        return;
      case "bonus":
        this._open.delete(`more-${d.person}`);
        await this._service(
          "add_bonus",
          { person: d.person, minutes: Number(d.minutes), group: d.group || "all" },
          `${Number(d.minutes) > 0 ? "Added" : "Took"} ${Math.abs(Number(d.minutes))} min ${Number(d.minutes) > 0 ? "for" : "from"} ${this._personName(d.person)}`
        );
        return;
      case "glance": {
        // One of the summary's actions (contract 2): its service with exactly its data, after its confirm
        const a = this._glanceAction(d.id, d.person);
        if (!a) return this._notify("That's no longer on offer");
        if (a.confirm && !window.confirm(cap(a.confirm))) return;
        const [domain, service] = a.service.split(".");
        try {
          await this._hass.callService(domain, service, a.data || {});
          this._notify(`${cap(a.label)}: done`);
        } catch (err) {
          this._notify(this._message(err));
        }
        return;
      }
      case "week-group":
        this._weekGroup[d.person] = d.group;
        this._render();
        return;
      case "week-day":
        this._weekDay[d.person] = this._weekDay[d.person] === d.date ? null : d.date;
        this._render();
        return;
      case "answer":
        await this._ws(
          d.deny ? { type: "hearth/approvals/answer", request_id: d.request, deny: true } : { type: "hearth/approvals/answer", request_id: d.request, minutes: Number(d.minutes) },
          d.deny ? "Not now, then" : `Gave ${d.minutes} more minutes`
        );
        return;
      case "pause-start": {
        const minutes = Number(this._value("#pause-minutes")) || 45;
        const reason = this._value("#pause-reason");
        await this._service("pause", reason ? { minutes, reason } : { minutes }, `Paused for ${fmtMinutes(minutes)}`);
        return;
      }
      case "pause-end":
        await this._service("pause_end", {}, "Pause ended");
        return;
      case "bonus-custom": {
        const minutes = Number(this._value(`#custom-${CSS.escape(d.person)}`));
        const group = this._value(`#custom-group-${CSS.escape(d.person)}`) || "all";
        if (!minutes) return this._notify("Give a number of minutes (negative takes time away)");
        await this._service("add_bonus", { person: d.person, minutes, group }, `Done: ${minutes > 0 ? "+" : ""}${minutes} min`);
        return;
      }
      case "budget": {
        const raw = el.value.trim();
        const minutes = raw === "" ? null : Math.max(0, Math.min(1440, Math.round(Number(raw))));
        if (raw !== "" && Number.isNaN(Number(raw))) return this._notify("Minutes, or empty for no limit");
        await this._ws(
          { type: "hearth/budget", person: d.person, group: d.group, days: d.days, minutes },
          `${this._groupName(d.group)}: ${minutes === null ? "no limit" : fmtMinutes(minutes)} on ${d.days === "school_days" ? "school days" : d.days === "other_days" ? "other days" : "every day"}`
        );
        await this._loadConfig();
        return;
      }
      case "budget-preset":
        await this._ws(
          { type: "hearth/budget", person: d.person, group: "all", days: d.days, minutes: Number(d.minutes) },
          `All screen time: ${fmtMinutes(Number(d.minutes))}`
        );
        await this._loadConfig();
        return;
      case "role": {
        const roles = { ...(cfg.roles || {}) };
        if (d.role) roles[d.person] = d.role;
        else delete roles[d.person];
        await this._setOption("roles", roles, `${this._personName(d.person)}: ${d.role || "not in Hearth"}`);
        return;
      }
      case "approve":
      case "deny": {
        const person = this._value(`#pair-person-${CSS.escape(d.pairing)}`) || null;
        if (action === "approve" && d.kind === "mobile" && !person) return this._notify("Pick whose phone it is first");
        await this._ws(
          { type: "hearth/pairing", pairing_id: d.pairing, answer: action, person },
          action === "approve" ? "Paired" : "Turned away"
        );
        await this._loadConfig();
        return;
      }
      case "profile": {
        const profiles = { ...(cfg.profiles || {}) };
        if (el.value) profiles[d.profile] = el.value;
        else delete profiles[d.profile];
        await this._setOption("profiles", profiles, "Profile saved");
        return;
      }
      case "profile-add": {
        const id = this._value("#new-profile-id");
        const person = this._value("#new-profile-person");
        if (!/^user:\d+(:[a-z0-9._-]+)?$/.test(id) || !person) return this._notify("Give an id like user:11, and its person");
        await this._setOption("profiles", { ...(cfg.profiles || {}), [id]: person }, "Profile added");
        return;
      }
      case "source-add": {
        const entityId = this._value(`#source-entity-${CSS.escape(d.person)}`);
        if (!entityId) return this._notify("Pick a sensor");
        if ((cfg.sources || []).some((s) => s.entity_id === entityId)) return this._notify("That sensor is a source already");
        const name = this._value(`#source-name-${CSS.escape(d.person)}`) || this._entityName(entityId);
        let id = slug(name) || "source";
        const taken = new Set((cfg.sources || []).map((s) => s.id));
        for (let n = 2; taken.has(id); n++) id = `${slug(name)}_${n}`;
        const source = { id, entity_id: entityId, person: d.person, name };
        const group = this._value(`#source-group-${CSS.escape(d.person)}`);
        if (group) source.group = group;
        const same = this._value(`#source-same-${CSS.escape(d.person)}`);
        if (same) source.same_as = same;
        if (this.shadowRoot.querySelector(`#source-live-${CSS.escape(d.person)}`)?.checked) source.live = true;
        await this._setOption("sources", [...(cfg.sources || []), source], "Source added");
        return;
      }
      case "source-remove":
        await this._setOption("sources", (cfg.sources || []).filter((s) => s.id !== d.id), "Source removed");
        return;
      case "place-save": {
        const places = this._placesOption();
        const school = this._value(`#place-school-${CSS.escape(d.person)}`);
        const tracker = this._value(`#place-tracker-${CSS.escape(d.person)}`);
        delete places.school[d.person];
        delete places.trackers[d.person];
        if (school) places.school[d.person] = school;
        if (tracker) places.trackers[d.person] = tracker;
        await this._setOption("places", places, "Places saved");
        return;
      }
      case "place-fav-add": {
        const zone = this._value("#place-fav-zone");
        if (!zone) return this._notify("Pick the place's zone");
        const name = this._value("#place-fav-name") || this._entityName(zone);
        const places = this._placesOption();
        const taken = new Set(places.favorites.map((f) => f.key));
        let base = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 32) || "place";
        if (["home", "school", "away", "unknown"].includes(base)) base = `${base}_place`;
        let key = base;
        for (let n = 2; taken.has(key); n++) key = `${base}_${n}`;
        places.favorites.push({ key, zone, name: name.slice(0, 40) });
        await this._setOption("places", places, "Place added");
        return;
      }
      case "place-fav-remove": {
        const places = this._placesOption();
        places.favorites = places.favorites.filter((f) => f.key !== d.key);
        await this._setOption("places", places, "Place removed");
        return;
      }
      case "lock-add": {
        const entityId = this._value(`#lock-entity-${CSS.escape(d.person)}`);
        if (!entityId) return this._notify("Pick a sensor");
        await this._setOption("locks", [...(cfg.locks || []), { entity_id: entityId, person: d.person }], "Lock added");
        return;
      }
      case "lock-remove":
        await this._setOption(
          "locks",
          (cfg.locks || []).filter((l) => !(l.person === d.person && l.entity_id === d.entity)),
          "Lock removed"
        );
        return;
      case "enforce-save": {
        const person = d.person;
        const kept = (cfg.enforce || []).filter((e) => e.person !== person);
        const fl = this._value(`#enf-fl-${CSS.escape(person)}`);
        const schoolApps = (this._value(`#enf-fl-school-${CSS.escape(person)}`) || "")
          .split(/[\s,]+/)
          .filter((p) => p.includes("."));
        if (fl) kept.push({ kind: "family_link", person, entity_id: fl, school_time_apps: schoolApps });
        const fs = this._value(`#enf-fs-${CSS.escape(person)}`);
        if (fs) {
          const platforms = [...this.shadowRoot.querySelectorAll(`[data-fs-platform="${person}"]:checked`)].map((x) => x.value);
          const groups = [...this.shadowRoot.querySelectorAll(`[data-fs-group="${person}"]:checked`)].map((x) => x.value);
          kept.push({ kind: "family_safety", person, entity_id: fs, platforms: platforms.length ? platforms : ["Xbox"], groups });
        }
        const nin = this._value(`#enf-nin-${CSS.escape(person)}`);
        if (nin) {
          const groups = [...this.shadowRoot.querySelectorAll(`[data-nin-group="${person}"]:checked`)].map((x) => x.value);
          const playing = this._value(`#enf-nin-playing-${CSS.escape(person)}`);
          kept.push({ kind: "nintendo", person, entity_id: nin, groups, ...(playing ? { playing: [playing] } : {}) });
        }
        await this._setOption("enforce", kept, "Parental controls saved");
        return;
      }
      case "voice-assistants":
        await this._setOption("voice_assistants", el.checked, el.checked ? "Voice assistants on" : "Voice assistants off");
        return;
      case "tile-share": {
        const set = new Set(cfg.tile_exchange || []);
        if (el.checked) set.add(d.person);
        else set.delete(d.person);
        await this._setOption("tile_exchange_share", [...set], el.checked ? "Sharing allowed" : "Sharing off");
        return;
      }
      case "outside-all": {
        const outside = new Set(cfg.outside_all || []);
        const inside = new Set(cfg.inside_all || []);
        if (el.checked) {
          outside.delete(d.group);
          if ((cfg.default_outside_all || []).includes(d.group)) inside.add(d.group);
        } else {
          outside.add(d.group);
          inside.delete(d.group);
        }
        await this._ws({ type: "hearth/config/set", key: "inside_all", value: [...inside] });
        await this._setOption("outside_all", [...outside], el.checked ? "Counts as screen time" : "Not screen time now");
        return;
      }
      case "app-group": {
        const moved = { ...(cfg.app_groups || {}) };
        moved[d.app] = el.value;
        await this._setOption("app_groups", moved, `Moved to ${el.value === "other" ? "Other" : this._groupName(el.value)}`);
        return;
      }
      case "app-filter":
        this._appFilter = el.value.trim().toLowerCase();
        this._render();
        return;
      case "push-save":
        await this._setOption("push_server", this._value("#push-server") || null, this._value("#push-server") ? "Phones get pings" : "Pings off");
        return;
      case "media-player": {
        const players = { ...(cfg.media_players || {}) };
        if (el.value) players[d.device] = el.value;
        else delete players[d.device];
        await this._setOption("media_players", players, "Saved");
        return;
      }
      case "app-add": {
        const pkg = this._value(`#app-new-${CSS.escape(d.group)}`);
        if (!pkg) return this._notify("Pick or type an app's package");
        const pkgId = this._packageOf(pkg);
        await this._changeGroupApps(d.group, (apps) => [...new Set([...apps, pkgId])], `Added to ${this._groupName(d.group)}`);
        return;
      }
      case "app-remove":
        await this._changeGroupApps(d.group, (apps) => apps.filter((a) => a !== d.app), "Removed");
        return;
      case "group-add": {
        const name = this._value("#group-new-name");
        if (!name) return this._notify("Give the group a name");
        const taken = new Set((cfg.groups || []).map((g) => g.id));
        let id = slug(name) || "group";
        for (let n = 2; taken.has(id); n++) id = `${slug(name)}_${n}`;
        const custom = (cfg.groups || []).filter((g) => !g.builtin).map((g) => ({ id: g.id, name: g.name, apps: g.added_apps.length ? g.added_apps : g.apps }));
        await this._setOption("groups", [...custom, { id, name, apps: [] }], `Group ${name} added`);
        return;
      }
      case "group-remove": {
        if (!window.confirm(`Remove the group ${this._groupName(d.group)}? Its budgets go with it.`)) return;
        const custom = (cfg.groups || [])
          .filter((g) => !g.builtin && g.id !== d.group)
          .map((g) => ({ id: g.id, name: g.name, apps: g.apps }));
        await this._setOption("groups", custom, "Group removed");
        return;
      }
      case "pin-save": {
        const pin = this._value(`#pin-${CSS.escape(d.person)}`);
        const again = this._value(`#pin-again-${CSS.escape(d.person)}`);
        if (!/^\d{4}$/.test(pin)) return this._notify("A parent PIN is 4 digits");
        if (pin !== again) return this._notify("The two PINs differ");
        await this._ws({ type: "hearth/parent_pin", person: d.person, pin }, `Parent PIN set for ${this._personName(d.person)}`);
        await new Promise((r) => setTimeout(r, 900));
        await this._loadConfig();
        return;
      }
      case "pin-remove":
        if (!window.confirm(`Remove ${this._personName(d.person)}'s parent PIN?`)) return;
        await this._ws({ type: "hearth/parent_pin", person: d.person, pin: null }, "Parent PIN removed");
        await new Promise((r) => setTimeout(r, 900));
        await this._loadConfig();
        return;
      case "school-save": {
        const fields = ["entity", "school_states", "calendar", "calendar_mode", "keywords", "year_start", "year_end", "days_off", "extra_school_days", "half_days", "half_states", "half_keywords", "half_day_budget"];
        const value = {};
        for (const f of fields) {
          const v = this._value(`#school-${f}`);
          value[f] = v || null;
        }
        await this._setOption("school_days", value, "School days saved");
        return;
      }
      case "ask-on":
      case "ask-link": {
        const key = action === "ask-on" ? "ask_notify_off" : "ask_deep_link";
        const byAdult = cfg.ask_phones || {};
        const set = new Set(Object.keys(byAdult).filter((p) => (action === "ask-on" ? !byAdult[p].on : byAdult[p].deep_link)));
        // ask_notify_off lists who is off: a ticked "Requests" takes them out
        if ((action === "ask-on") !== el.checked) set.add(d.person);
        else set.delete(d.person);
        await this._setOption(key, [...set], `${this._personName(d.person)}: ${action === "ask-on" ? (el.checked ? "gets requests" : "no requests") : el.checked ? "opens in their app" : "opens Hearth's page"}`);
        return;
      }
      case "suggest-on":
      case "suggest-minutes": {
        const all = cfg.suggest_push || [];
        const mine = all.find((p) => p.person === d.person && p.group === d.group);
        const kept = all.filter((p) => p !== mine);
        const row = el.closest("li");
        const minutes = Number(row?.querySelector("select")?.value) || 15;
        const on = action === "suggest-on" ? el.checked : Boolean(mine);
        if (on) kept.push({ person: d.person, group: d.group, minutes });
        const what = d.group === "all" ? "All screen time" : this._groupName(d.group);
        await this._setOption("suggest_push", kept, on ? `${what}: suggested to phones (+${minutes} min)` : `${what}: not suggested to phones`);
        return;
      }
      case "new-apps-save": {
        const entities = [...this.shadowRoot.querySelectorAll("[data-app-watch]:checked")].map((x) => x.value);
        await this._ws({ type: "hearth/config/set", key: "app_watch", value: entities });
        await this._setOption("ask_notify", this._value("#ask-notify") || null, "Saved");
        return;
      }
      case "block": {
        const kind = d.kind;
        const value = d.item || this._value(`#block-${kind}-${CSS.escape(d.person)}`);
        if (!value) return;
        const data = { person: d.person, [kind]: value };
        if (d.label && kind !== "word") data.label = d.label;
        await this._service(`block_${kind}`, data, "Blocked");
        this._loadWatch(d.person);
        return;
      }
      case "unblock":
        await this._service(`unblock_${d.kind}`, { person: d.person, [d.kind]: d.item }, "Unblocked");
        this._loadWatch(d.person);
        return;
      case "kid-pause": {
        const minutes = Number(this._value(`#kid-pause-${CSS.escape(d.person)}`)) || 30;
        await this._service("pause", { people: [d.person], minutes }, `${this._personName(d.person)} paused for ${fmtMinutes(minutes)}`);
        return;
      }
      case "kid-pause-end":
        await this._service("pause_end", { people: [d.person] }, `${this._personName(d.person)}'s pause ended`);
        return;
      case "app-pause-end":
        await this._service(
          "pause_end",
          { people: [d.person], ...(d.app ? { app: d.app } : { group: d.group }) },
          "Pause ended"
        );
        return;
      case "device-bonus":
        await this._service(
          "add_bonus",
          { person: d.person, minutes: Number(d.minutes), group: "all", device: d.target },
          `+${d.minutes} min on ${d.name || "that device"}`
        );
        return;
      case "school-off":
        await this._service("school_time_off", { people: [d.person] }, "No School time today");
        return;
      case "school-off-cancel":
        await this._service("school_time_off_cancel", { people: [d.person] }, "School time is back today");
        return;
      case "nin-bonus": {
        const minutes = Number(d.minutes);
        await this._ws(
          { type: "hearth/nintendo/bonus", person: d.person, device_id: d.device, minutes },
          minutes === -1 ? "Unlimited on the Switch for the rest of today" : `Nintendo: +${minutes} min on the Switch`
        );
        return;
      }
      case "nin-bonus-cancel":
        if (!window.confirm("Cancel the Switch's extra playing time for today?")) return;
        await this._ws({ type: "hearth/nintendo/bonus_cancel", person: d.person, device_id: d.device }, "Extra playing time cancelled");
        return;
      case "nin-apps":
        await this._loadSwitchApps(d.person, d.device);
        return;
      case "nin-allow": {
        const allowed = el.checked;
        if (allowed && !window.confirm("An allowed game starts even past the Switch's age rating restriction. Allow it?")) {
          el.checked = false;
          return;
        }
        await this._ws(
          { type: "hearth/nintendo/app_allowed", person: d.person, device_id: d.device, application_id: d.app, allowed },
          allowed ? "Allowed on the Switch" : "Off the allow list"
        );
        await this._loadSwitchApps(d.person, d.device);
        return;
      }
      case "setup-open":
        this._setupStep = 0;
        this._render();
        return;
      case "setup-close":
        this._setupStep = null;
        this._render();
        return;
      case "setup-next":
        this._setupStep = Math.min(SETUP_STEPS.length - 1, (this._setupStep || 0) + 1);
        this._render();
        return;
      case "setup-back":
        this._setupStep = Math.max(0, (this._setupStep || 0) - 1);
        this._render();
        return;
      case "advanced":
        history.pushState(null, "", "/config/integrations/integration/hearth");
        window.dispatchEvent(new CustomEvent("location-changed"));
        return;
      default:
    }
  }

  _packageOf(text) {
    const known = this._config?.known_apps || {};
    if (known[text]) return text;
    const byName = Object.entries(known).find(([, name]) => name.toLowerCase() === text.toLowerCase());
    return byName ? byName[0] : text;
  }

  async _changeGroupApps(groupId, change, done) {
    const cfg = this._config;
    const group = (cfg.groups || []).find((g) => g.id === groupId);
    if (!group) return;
    if (group.builtin) {
      const added = { ...(Object.fromEntries((cfg.groups || []).filter((g) => g.builtin && g.added_apps.length).map((g) => [g.id, g.added_apps]))) };
      added[groupId] = change(group.added_apps || []);
      await this._setOption("group_apps", added, done);
    } else {
      const custom = (cfg.groups || [])
        .filter((g) => !g.builtin)
        .map((g) => ({ id: g.id, name: g.name, apps: g.id === groupId ? change(g.apps) : g.apps }));
      await this._setOption("groups", custom, done);
    }
  }

  // An action of the summary by its id: a person's own (and their suggestions'), else the household's
  _glanceAction(id, person) {
    const h = this._summary?.household || {};
    const lists = [];
    if (person) {
      const p = this._summaryPerson(person);
      lists.push(p?.actions || [], ...(p?.suggestions || []).map((s) => s.actions || []));
      lists.push(...(h.suggestions || []).filter((s) => s.person === person).map((s) => s.actions || []));
    } else lists.push(h.actions || []);
    for (const list of lists) {
      const found = list.find((a) => a.id === id);
      if (found) return found;
    }
    return null;
  }

  // The hourly statistics of a person's Screen time today sensor (spec 3.4, decision 3b): finished hours read once an
  // hour, the current one from the live state at each draw
  async _loadHours(person) {
    const entity = this._config?.screen_time_sensors?.[person];
    const now = new Date();
    const midnight = new Date(now);
    midnight.setHours(0, 0, 0, 0);
    const key = `${midnight.getTime()}|${now.getHours()}`;
    if (!entity || this._hours[person]?.key === key || this._hoursBusy.has(person)) return;
    this._hoursBusy.add(person);
    try {
      const rows = await this._hass.callWS({
        type: "recorder/statistics_during_period",
        start_time: new Date(midnight.getTime() - 3600000).toISOString(),
        statistic_ids: [entity],
        period: "hour",
        types: ["state"],
      });
      this._hours[person] = { key, rows: rows[entity] || [] };
    } catch (err) {
      this._hours[person] = { key, error: this._message(err) };
    } finally {
      this._hoursBusy.delete(person);
    }
    this._render();
  }

  async _loadWatch(person) {
    if (!person) return;
    try {
      const result = await this._hass.callWS({
        type: "call_service",
        domain: "hearth",
        service: "get_watch_log",
        service_data: { person, days: 7, limit: 30 },
        return_response: true,
      });
      this._watch[person] = result.response || null;
    } catch (_err) {
      // No TV profile: no YouTube log
      this._watch[person] = null;
    }
    this._render();
  }

  // The games on a kid's Switch and its allow list (a patched Nintendo integration's list_applications)
  async _loadSwitchApps(person, device) {
    this._switchApps = this._switchApps || {};
    try {
      const result = await this._hass.callWS({ type: "hearth/nintendo/apps", person, device_id: device });
      this._switchApps[device] = result.applications || [];
    } catch (err) {
      this._switchApps[device] = null;
      this._notify(this._message(err));
    }
    this._render();
  }

  // Rendering

  _render() {
    const root = this.shadowRoot;
    const focused = root.activeElement;
    const focusId = focused && focused.id;
    const focusValue = focused && "value" in focused ? focused.value : null;
    root.innerHTML = `<style>${STYLE}</style>${this._page()}`;
    for (const [id, value] of Object.entries(this._drafts)) {
      const el = root.getElementById(id);
      if (!el) continue;
      if (el.type === "checkbox") el.checked = value;
      else el.value = value;
    }
    for (const id of this._open) {
      const el = root.getElementById(id);
      if (el) el.open = true;
      // An hourly chart left open reads the hour just finished
      if (el && el.dataset.hours) this._loadHours(el.dataset.hours);
    }
    // The open kid's day strip shows the minutes used each hour once their statistics are read
    if (this._tab === "today" && this._config && this._summary && this._setupStep === null) {
      const kids = this._kids();
      const open = kids.length === 1 ? kids[0].id : this._todayKid;
      if (open) this._loadHours(open);
    }
    if (focusId) {
      const again = root.getElementById(focusId);
      if (again) {
        again.focus();
        if (focusValue !== null && again.value !== focusValue && again.tagName === "INPUT") again.value = focusValue;
      }
    }
    this._showAsk();
  }

  // Once, after opening /hearth?ask=<id>: scroll to that request, or say it's already been answered
  _showAsk() {
    if (!this._askFocus || this._askShown || !this._summary || !this._config || this._setupStep !== null || this._tab !== "today") return;
    this._askShown = true;
    const card = this.shadowRoot.getElementById(`ask-${this._askFocus}`);
    if (card) {
      card.scrollIntoView({ block: "center", behavior: "smooth" });
      return;
    }
    this._askFocus = null;
    setTimeout(() => this._notify("That request has already been answered"), 0);
  }

  _page() {
    const toolbar = `
      <header class="toolbar">
        ${this._narrow ? `<button class="icon-btn" data-action="menu" aria-label="Menu"><ha-icon icon="mdi:menu"></ha-icon></button>` : ""}
        <ha-icon class="logo" icon="mdi:fireplace"></ha-icon>
        <div class="title">Hearth${this._config?.title ? ` <span class="sub">${esc(this._config.title)}</span>` : ""}</div>
        <div class="spacer"></div>
        ${this._config ? `<button class="text-btn" data-action="setup-open"><ha-icon icon="mdi:wizard-hat"></ha-icon><span>Guided setup</span></button>` : ""}
      </header>
      <nav class="tabs" role="tablist">
        ${TABS.map(
          (t) => `<button role="tab" aria-selected="${t.id === this._tab}" class="tab ${t.id === this._tab ? "on" : ""}" data-action="tab" data-tab="${t.id}">
            <ha-icon icon="${t.icon}"></ha-icon><span>${t.label}</span>${t.id === "devices" && this._pendingCount() ? `<span class="badge">${this._pendingCount()}</span>` : ""}</button>`
        ).join("")}
      </nav>`;
    let body;
    if (this._error && !this._config) body = `<div class="card empty"><ha-icon icon="mdi:alert-circle-outline"></ha-icon><p>${esc(this._error)}</p></div>`;
    else if (!this._config) body = `<div class="loading">Loading Hearth…</div>`;
    else if (this._setupStep !== null) body = this._setup();
    else body = { today: () => this._today(), kids: () => this._kidsTab(), devices: () => this._devicesTab(), apps: () => this._appsTab(), family: () => this._familyTab() }[this._tab]();
    return `${toolbar}<main class="content">${body}</main>${this._toast ? `<div class="toast" role="status">${esc(this._toast)}</div>` : ""}`;
  }

  _pendingCount() {
    return (this._config?.pairings || []).length;
  }

  _avatar(id, size = 44) {
    const pic = this._picture(id);
    const name = this._personName(id);
    return pic
      ? `<img class="avatar" style="width:${size}px;height:${size}px" src="${esc(pic)}" alt="">`
      : `<div class="avatar initials" style="width:${size}px;height:${size}px">${esc(name.slice(0, 1).toUpperCase())}</div>`;
  }

  _pairingCards() {
    const pairings = this._config.pairings || [];
    if (!pairings.length) return "";
    const persons = this._config.persons || [];
    return pairings
      .map(
        (p) => `<div class="card attention">
          <div class="row">
            <ha-icon icon="${p.kind === "tv" ? "mdi:television" : "mdi:cellphone"}"></ha-icon>
            <div class="grow"><div class="strong">${esc(p.name)} wants to join</div>
              <div class="muted">Check the ${p.kind === "tv" ? "TV" : "phone"} shows this code: <span class="code">${esc(p.code)}</span></div></div>
          </div>
          ${p.kind === "mobile" ? `<label class="field">Whose phone is it?
            <select id="pair-person-${esc(p.pairing_id)}"><option value="">Choose…</option>${persons.map((x) => `<option value="${esc(x.id)}">${esc(x.name)}</option>`).join("")}</select></label>` : ""}
          <div class="actions">
            <button class="btn" data-action="deny" data-pairing="${esc(p.pairing_id)}" data-kind="${esc(p.kind)}">Turn away</button>
            <button class="btn primary" data-action="approve" data-pairing="${esc(p.pairing_id)}" data-kind="${esc(p.kind)}">The code matches: pair</button>
          </div>
        </div>`
      )
      .join("");
  }

  // Today, in the spec's order (section 2): the Suggested now strip, the pause, problems, the kids, what's on, the
  // family by pool
  _today() {
    const kids = this._kids();
    const devices = this._summary?.devices || [];
    const parts = [this._suggestedNow(), this._pauseBar(), this._pairingCards(), this._controlsAttention()];
    if (!kids.length) {
      parts.push(`<div class="card empty"><ha-icon icon="mdi:account-child-outline"></ha-icon>
        <p>No kids in Hearth yet. The guided setup takes a few minutes.</p>
        <button class="btn primary" data-action="setup-open">Start the guided setup</button></div>`);
    }
    // Time-use decision 4a: a compact row per kid, the full card of the one tapped (with one kid, theirs at once)
    if (kids.length > 1) parts.push(`<div class="card kid-rows">${kids.map((k) => this._kidRow(k)).join("")}</div>`);
    const open = kids.length === 1 ? kids[0] : kids.find((k) => k.id === this._todayKid);
    if (open) parts.push(this._kidCard(open));
    if (devices.length) {
      parts.push(`<h2>TVs and phones</h2><div class="grid devices">${devices.map((dv) => this._deviceCard(dv)).join("")}</div>`);
    }
    parts.push(this._familyPools(kids));
    return parts.join("");
  }

  // Spec 2.1, a fixed slot at the top: the household's headline, then requests waiting (with +15 to +60), then
  // suggestions with their own buttons, urgent first as the summary orders them. It keeps a minimum height so the
  // cards below don't jump when one comes or goes
  _suggestedNow() {
    const h = this._summary?.household;
    const items = this._askCards() + (h?.suggestions || []).map((s) => this._suggestionRow(s)).join("");
    const headline = h?.headline;
    return `<section class="card suggested ${headline ? `lvl-${esc(headline.level)}` : ""}">
      <h3><ha-icon icon="mdi:lightbulb-on-outline"></ha-icon>Suggested now</h3>
      <div class="headline">${esc(cap(headline ? headline.text : "all clear"))}</div>
      ${items ? `<div class="suggested-items">${items}</div>` : ""}
    </section>`;
  }

  _suggestionRow(s) {
    return `<div class="item sugg" data-key="${esc(s.key)}"><div class="grow"><span class="strong">${esc(s.person_name)}</span> · ${esc(s.text)}</div>
      <div class="actions wrap">${(s.actions || []).map((a) => this._actionButton(a, s.person)).join("")}</div></div>`;
  }

  _actionButton(a, person) {
    return `<button class="btn ${a.primary ? "primary" : ""}" data-action="glance" data-id="${esc(a.id)}" ${person ? `data-person="${esc(person)}"` : ""}>${esc(cap(a.label))}</button>`;
  }

  // A request's text as the glance writes it for that kid ("sam asks for 30 more · games"), else built here
  _askText(a) {
    const p = this._summaryPerson(a.person);
    const item = [p?.headline, ...(p?.lines || [])].find((x) => x && x.key === `ask:${a.id}`);
    if (item) return `${a.person_name} ${item.text}`;
    if (a.source === "family_safety")
      return `${a.person_name} asks for more time${a.platform ? ` on ${a.platform}` : ""}${a.app_name ? ` for ${a.app_name}` : ""} (Family Safety)`;
    return `${a.person_name} asks for ${amount(a.minutes)} more${a.group && a.group !== "all" ? ` · ${shortGroup(a.group, this._groupName(a.group))}` : ""}`;
  }

  _askCards() {
    const asks = (this._summary?.approvals || []).filter((a) => a.type === "more_time");
    return asks
      .map(
        (a) => `<div class="item ask ${a.id === this._askFocus ? "focus" : ""}" id="ask-${esc(a.id)}">
        <div class="row">${this._avatar(a.person, 36)}<div class="grow">
          <div class="strong">${esc(cap(this._askText(a)))}</div>
          ${a.note ? `<div class="muted">“${esc(a.note)}”</div>` : ""}
          ${a.via === "home_assistant" ? `<div class="muted small">From their Home Assistant app${a.app ? ` · ${esc(a.app)}` : ""}</div>` : ""}</div></div>
        <div class="actions wrap">
          <button class="btn" data-action="answer" data-request="${esc(a.id)}" data-deny="1">No</button>
          ${[15, 30, 45, 60]
            .map((m) => `<button class="btn ${m === a.minutes ? "primary" : ""}" data-action="answer" data-request="${esc(a.id)}" data-minutes="${m}">+${esc(amount(m))}</button>`)
            .join("")}
        </div></div>`
      )
      .join("");
  }

  _pauseBar() {
    const paused = (this._summary?.people || []).filter((p) => p.pause);
    if (paused.length) {
      const p = paused[0].pause;
      return `<div class="card pause on"><div class="row"><ha-icon icon="mdi:silverware-fork-knife"></ha-icon>
        <div class="grow"><div class="strong">${esc(cap(p.reason || "paused"))} till ${esc(clock(p.until))}${p.ends_on ? ` or ${esc(this._endsOn(p.ends_on))}` : ""}</div>
        <div class="muted small">${esc(paused.map((x) => x.name).join(", "))}: their Hearth TVs and phones are on hold.</div></div>
        <button class="btn primary" data-action="pause-end">End pause</button></div></div>`;
    }
    return `<div class="card pause"><div class="row wrap"><ha-icon icon="mdi:pause-circle-outline"></ha-icon>
      <div class="grow strong">Pause everyone</div>
      <select id="pause-minutes" aria-label="How long">${[15, 30, 45, 60, 90].map((m) => `<option value="${m}" ${m === 45 ? "selected" : ""}>${fmtMinutes(m)}</option>`).join("")}</select>
      <input id="pause-reason" placeholder="Reason, e.g. Dinner" value="" data-enter="pause-start">
      <button class="btn" data-action="pause-start">Pause</button></div></div>`;
  }

  // A kid on Today (spec 2.3 and section 3): the server's today line and state color, the ring for All, one bar per
  // pool, the give button for the pool that binds (All in an overflow), the last 7 days and, opened, the day by hour,
  // device and app
  _kidCard(kid) {
    const s = this._summaryPerson(kid.id);
    const left = s?.all?.minutes_left ?? null;
    const playing = (s?.playing || [])[0];
    const chips = [];
    // The kind of lock and when it ends, as the day line says it ("School time till 3:00"); what locks them (the
    // School time and bedtime entities) only in the tooltip
    if (s?.locked && !s.pause) {
      const kind = s.lock?.kind;
      const word = { bedtime: "Bedtime", school_time: "School time" }[kind] || "Locked";
      const icon = { bedtime: "weather-night", school_time: "school-outline" }[kind] || "lock";
      const by = (s.locked_by || []).filter((e) => e !== "pause").map((e) => this._entityName(e));
      chips.push(`<span class="chip warn"${by.length ? ` title="${esc(`Locked by ${by.join(", ")}`)}"` : ""}><ha-icon icon="mdi:${icon}"></ha-icon>${esc(word)}${s.lock?.until ? ` till ${esc(clock(s.lock.until))}` : ""}</span>`);
    }
    if (s?.pause) chips.push(`<span class="chip warn"><ha-icon icon="mdi:pause"></ha-icon>${esc(cap(s.pause.reason || "paused"))}</span>`);
    const place = s?.place;
    if (place) {
      const now = this._config.places_now?.[kid.id] || {};
      const source = { family_link: "Family Link", person: "Home Assistant" }[now.source] || "";
      const title = place.fresh ? `From ${source || "its source"}` : place.name === "No location" ? "No Family Link location and no person location" : "No fresh reading";
      chips.push(`<span class="chip ${place.fresh ? "" : "dim"}" title="${esc(title)}"><ha-icon icon="mdi:map-marker${place.fresh ? "" : "-question"}-outline"></ha-icon>${esc(place.name === "No location" ? "no location" : place.name)}${place.fresh && source ? ` · ${esc(source)}` : ""}</span>`);
    }
    // Now playing: the summary's own short text ("bluey · s2e4 · 8 min left"), and where
    if (playing)
      chips.push(`<span class="chip play"><ha-icon icon="mdi:play-circle"></ha-icon>${esc(cap(playing.text || playing.title || playing.app || "playing"))}${playing.device ? ` · ${esc(playing.device)}` : ""}</span>`);
    if (s?.next_lock) {
      const mins = Math.round((new Date(s.next_lock.at) - Date.now()) / 60000);
      const what = s.next_lock.kind === "bedtime" ? "Bedtime" : "School time";
      if (mins >= 0 && mins <= 120)
        chips.push(`<span class="chip"><ha-icon icon="mdi:${s.next_lock.kind === "bedtime" ? "weather-night" : "school-outline"}"></ha-icon>${what} ${mins <= 15 ? `in ${mins} min` : `at ${esc(clock(s.next_lock.at))}`}</span>`);
    }
    const line = s?.day_line;
    return `<div class="card kid role-${role(s?.state)}" id="kid-${esc(kid.id)}">
      <div class="kid-head">
        ${this._avatar(kid.id)}
        <div class="grow"><div class="name">${esc(kid.name)}</div><div class="chips">${chips.join("")}</div></div>
        <div class="left-now">${left === null ? `<span class="muted">No limit</span>` : left === 0 ? "Out" : `${esc(amount(left))} left`}</div>
      </div>
      <div class="kid-main">
        ${line ? `<div class="day-line lvl-${esc(line.level)}"><span class="dot-role"></span>${esc(cap(line.text))}</div>` : ""}
        ${this._allBar(s)}
        ${this._dayStrip(kid, s)}
        ${this._deviceTiles(s)}
      </div>
      ${this._exceptionsAndApps(kid, s)}
      ${this._weekChart(kid, s)}
      ${this._hoursCard(kid)}
      ${this._todayDetail(kid, s)}
      ${this._kidControls(kid, s)}
      ${this._giveButtons(kid, s)}
    </div>`;
  }

  // Time-use decision 4a: one kid in a row (tap for the full card), with a button only when there's something to answer:
  // their waiting request ("Yes 30") or a suggestion for them ("+15 youtube", the pool named)
  _kidRow(kid) {
    const s = this._summaryPerson(kid.id);
    const all = s?.all;
    const used = all?.used_minutes || 0;
    const total = all && all.minutes_left !== null && all.minutes_left !== undefined ? used + Math.max(0, all.minutes_left) : null;
    const text = s?.day_line?.text || s?.headline?.text || (total === null ? "no limit" : `${amount(all.minutes_left)} left`);
    const open = this._todayKid === kid.id;
    return `<div class="kid-row role-${role(s?.state)}${open ? " on" : ""}" data-action="kid-open" data-enter="kid-open" data-kid="${esc(kid.id)}" role="button" tabindex="0" aria-expanded="${open}">
      ${this._avatar(kid.id, 32)}
      <div class="grow"><div class="strong">${esc(kid.name)}</div><div class="muted small">${esc(cap(text))}</div></div>
      <div class="row-bar">${total === null ? "" : `<div class="bar"><div style="width:${total ? Math.min(100, (used / total) * 100) : 100}%"></div></div>`}</div>
      ${this._rowButton(kid)}
    </div>`;
  }

  _rowButton(kid) {
    const ask = (this._summary?.approvals || []).find((a) => a.type === "more_time" && a.person === kid.id && a.minutes);
    if (ask)
      return `<button class="btn primary" data-action="answer" data-request="${esc(ask.id)}" data-minutes="${esc(ask.minutes)}" title="${esc(cap(this._askText(ask)))}">Yes ${esc(amount(ask.minutes))}</button>`;
    const sugg = (this._summary?.household?.suggestions || []).find((x) => x.person === kid.id && (x.actions || []).length);
    if (sugg) {
      const a = sugg.actions.find((x) => x.primary) || sugg.actions[0];
      return this._actionButton({ ...a, primary: true }, kid.id);
    }
    return "";
  }

  // A pool's color on the All bar and its lane: by the household's order of groups, "other" grey
  _poolColor(id) {
    if (id === "other") return "other";
    const order = (this._summary?.groups || []).map((g) => g.id).filter((g) => g !== "all");
    const i = order.indexOf(id);
    return `p${(i < 0 ? order.length : i) % 6}`;
  }

  // Time-use decisions 1a and 2c: All screen time as one bar split by pool plus "other" (an app is in one pool, so the
  // parts add up), the limit as a mark, today's extra time as a hatched end, then each pool with a budget as a thin
  // lane on the same minute scale (which cap comes first), and the pools without a budget in one muted line
  _allBar(s) {
    const all = s?.all;
    if (!all) return "";
    const used = all.used_minutes || 0;
    const bonus = Math.max(0, all.bonus || 0);
    const limited = (g) => g.limited !== false && g.minutes_left !== null && g.minutes_left !== undefined;
    const capOf = (g) => (g.budget !== null && g.budget !== undefined ? g.budget + Math.max(0, g.bonus || 0) : (g.used_minutes || 0) + Math.max(0, g.minutes_left));
    const budget = limited(all) ? capOf(all) - bonus : null;
    const pools = (s.groups || []).filter((g) => g.id !== "all");
    const lanes = pools.filter(limited).sort((a, b) => a.minutes_left - b.minutes_left);
    const free = pools.filter((g) => !limited(g) && (g.used_minutes || 0) > 0);
    const top = Math.max(1, used, budget === null ? 0 : budget + bonus, ...lanes.map((g) => Math.max(capOf(g), g.used_minutes || 0)));
    const x = (m) => `${Math.max(0, Math.min(100, (m / top) * 100)).toFixed(2)}%`;
    const parts = s.all_by_pool?.length ? s.all_by_pool : used ? [{ id: "all", name: "All screen time", minutes: used }] : [];
    let at = 0;
    const segs = parts
      .map((p) => {
        const html = `<span class="seg ${p.id === "all" ? "whole" : this._poolColor(p.id)}" style="left:${x(at)};width:${x(p.minutes)}" title="${esc(`${p.name}: ${fmtMinutes(p.minutes)}`)}"></span>`;
        at += p.minutes;
        return html;
      })
      .join("");
    const marks = budget === null ? "" : `${bonus ? `<span class="bonus" style="left:${x(budget)};width:${x(bonus)}"></span>` : ""}<span class="limit" style="left:${x(budget)}"></span>`;
    const head = budget === null ? `${fmtMinutes(used)} today · no limit` : `${amount(used)} of ${fmtMinutes(budget + bonus)}`;
    const legend = parts.filter((p) => p.id !== "all" && p.minutes > 0);
    const lane = (g) => {
      const value = { out: "Out", allowed: "Allowed", paused: "Paused" }[g.state] || `${amount(g.minutes_left)} left`;
      return `<div class="lane role-${role(g.state)}"><span class="bar-label">${esc(g.name)}</span>
        <div class="lane-track"><span class="lane-fill ${this._poolColor(g.id)}" style="width:${x(g.used_minutes || 0)}"></span><span class="limit" style="left:${x(capOf(g))}"></span></div>
        <span class="bar-value">${g.bonus > 0 ? `<span class="tag">+${esc(amount(g.bonus))}</span>` : ""}${esc(value)}</span></div>`;
    };
    return `<div class="allbar role-${role(all.state)}">
      <div class="allbar-head"><span class="strong">All screen time</span><span class="grow"></span><span class="muted small">${esc(head)}</span>${bonus ? `<span class="tag">+${esc(amount(bonus))}</span>` : ""}</div>
      <div class="all-track">${segs}${marks}</div>
      ${legend.length ? `<div class="legend small">${legend.map((p) => `<span><i class="dot ${this._poolColor(p.id)}"></i>${esc(p.id === "other" ? "other" : p.name)} ${esc(amount(p.minutes))}</span>`).join("")}</div>` : ""}
      ${lanes.map(lane).join("")}
      ${free.length ? `<div class="muted small">No limit: ${esc(free.map((g) => `${String(g.name).toLowerCase()} ${fmtMinutes(g.used_minutes)}`).join(" · "))}</div>` : ""}
    </div>`;
  }

  // Time-use decision 3a: the kid's waking day, from this morning's wake to tonight's bedtime (the summary's bedtime,
  // from their lock entities; else 6:00 to 22:00): bedtime shaded at the ends, School time striped, a line at now, and
  // the minutes used each hour once the hourly statistics are read
  _dayStrip(kid, s) {
    const midnight = new Date();
    midnight.setHours(0, 0, 0, 0);
    const hourOf = (iso) => (new Date(iso).getTime() - midnight.getTime()) / 3600000;
    const wake = s?.bedtime ? hourOf(s.bedtime.end) : 6;
    const bed = s?.bedtime ? hourOf(s.bedtime.start) : 22;
    if (!(bed > wake) || Number.isNaN(bed) || Number.isNaN(wake)) return "";
    const from = Math.max(0, Math.floor(wake));
    const to = Math.min(24, Math.ceil(bed));
    const span = to - from;
    const pos = (h) => ((Math.min(to, Math.max(from, h)) - from) / span) * 100;
    const block = (a, b, cls) => (pos(b) > pos(a) ? `<span class="${cls}" style="left:${pos(a).toFixed(2)}%;width:${(pos(b) - pos(a)).toFixed(2)}%"></span>` : "");
    const parts = [block(from, wake, "night"), block(bed, to, "night")];
    const words = [];
    if (s?.school_time) {
      parts.push(block(hourOf(s.school_time.start), hourOf(s.school_time.end), "school"));
      words.push(`School time ${clock(s.school_time.start)}–${clock(s.school_time.end)}`);
    }
    if (s?.bedtime) words.push(`bedtime at ${clock(s.bedtime.start)}`);
    const entity = this._config?.screen_time_sensors?.[kid.id];
    const read = this._hours[kid.id];
    if (read?.rows) {
      const bars = hourBars(read.rows, midnight.getTime(), parseFloat(this._hass?.states?.[entity]?.state));
      for (let h = from; h < to; h++)
        if (bars[h] > 0)
          parts.push(`<span class="use" style="left:${pos(h).toFixed(2)}%;width:${(100 / span).toFixed(2)}%;height:${Math.min(100, (bars[h] / 60) * 100).toFixed(0)}%" title="${esc(`${fmtMinutes(bars[h])} at ${h % 12 || 12}`)}"></span>`);
    }
    const now = (Date.now() - midnight.getTime()) / 3600000;
    if (now >= from && now <= to) parts.push(`<span class="now" style="left:${pos(now).toFixed(2)}%"></span>`);
    const step = span > 16 ? 3 : 2;
    const hours = [];
    for (let h = from; h <= to; h += step) hours.push(h);
    if (hours[hours.length - 1] !== to) hours.push(to);
    const ticks = hours.map((h) => `<span style="left:${pos(h).toFixed(2)}%">${h % 12 || 12}</span>`);
    return `<div class="strip" aria-label="Today from wake to bedtime">
      <div class="strip-track">${parts.join("")}</div>
      <div class="strip-x">${ticks.join("")}</div>
      ${words.length ? `<div class="muted small">${esc(cap(words.join(" · ")))}</div>` : ""}
    </div>`;
  }

  // Time-use decision 5a: each device with the time actually left there, as the server works it out (targets'
  // left, left_by, locked): "1 h 43 left · by google", "2 h left · games, by hearth", "Locked · school time"
  _deviceTiles(s) {
    const tiles = (s?.targets || []).filter((t) => !t.same_as && "left" in t);
    if (!tiles.length) return "";
    const icons = { tv: "mdi:television", phone: "mdi:cellphone", xbox: "mdi:microsoft-xbox", windows: "mdi:microsoft-windows", switch: "mdi:nintendo-switch" };
    const why = { bedtime: "bedtime", school_time: "school time", pause: "paused", other: "locked", out: "out of time", device_limit: "its own limit", parent_lock: "a parent's lock" };
    return `<div class="tiles">${tiles
      .map((t) => {
        const big = t.locked ? (t.locked_kind === "out" ? "Out" : "Locked") : t.left === null || t.left === undefined ? "No limit" : `${fmtMinutes(t.left)} left`;
        const pool = t.left_by === "hearth" && t.left_pool && t.left_pool !== "all" ? `${shortGroup(t.left_pool, this._groupName(t.left_pool))}, ` : "";
        const sub = t.locked ? why[t.locked_kind] || "" : t.left_by ? `${pool}by ${t.left_by}` : "";
        return `<div class="tile${t.locked ? " locked" : ""}"><ha-icon icon="${icons[t.kind] || "mdi:devices"}"></ha-icon>
          <div class="grow"><div class="small">${esc(t.name)}</div><div class="strong">${esc(big)}</div>${sub ? `<div class="muted small">${esc(sub)}</div>` : ""}</div></div>`;
      })
      .join("")}</div>`;
  }

  // One pool today (spec 3.3): fill used / (budget + bonus), the state's color, "40 left", "out", or muted
  // "no limit · 25 min" for a pool without a budget today
  _poolRow(g) {
    const name = g.id === "all" ? "All screen time" : g.name;
    const bonus = g.bonus > 0 ? `<span class="tag">+${esc(amount(g.bonus))}</span>` : "";
    if (g.limited === false || g.minutes_left === null || g.minutes_left === undefined)
      return `<div class="bar-row unlimited role-none"><span class="bar-label">${esc(name)}</span><div class="bar"><div style="width:0"></div></div>
        <span class="bar-value">No limit · ${esc(fmtMinutes(g.used_minutes || 0))}</span></div>`;
    const total = g.budget !== null && g.budget !== undefined ? g.budget + (g.bonus || 0) : (g.used_minutes || 0) + g.minutes_left;
    const pct = total ? Math.min(100, ((g.used_minutes || 0) / total) * 100) : 100;
    const value = { out: "Out", allowed: "Allowed", paused: "Paused" }[g.state] || `${amount(g.minutes_left)} left`;
    return `<div class="bar-row role-${role(g.state)}"><span class="bar-label">${esc(name)}</span>
      <div class="bar"><div style="width:${pct}%"></div></div><span class="bar-value">${bonus}${esc(value)}</span></div>`;
  }

  // Spec principle 6 (round 2, 3b): one button gives to the pool that stops them first and names it ("+15 games");
  // more of it, All screen time and taking time back are in the overflow
  _giveButtons(kid, s) {
    const groups = s?.groups || [];
    if (!groups.some((g) => g.limited !== false && g.minutes_left !== null && g.minutes_left !== undefined))
      return `<div class="actions"><button class="link" data-action="kid" data-kid="${esc(kid.id)}" data-go="kids">Change limits</button><span class="grow"></span>
        <button class="btn" data-action="kid" data-kid="${esc(kid.id)}" data-go="kids">Set limits</button></div>`;
    const binding = s.binding?.group || null;
    const give = binding ? (s.actions || []).find((a) => a.id === `bonus:${binding}`) : null;
    const name = (id) => shortGroup(id, groups.find((g) => g.id === id)?.name || this._groupName(id));
    const more = (minutes, group) =>
      `<button class="chip-btn" data-action="bonus" data-person="${esc(kid.id)}" data-minutes="${minutes}" data-group="${esc(group)}">${minutes > 0 ? "+" : "−"}${esc(amount(Math.abs(minutes)))} ${esc(name(group))}</button>`;
    const overflow = [];
    if (binding && binding !== "all") overflow.push(more(30, binding), more(-15, binding));
    overflow.push(more(15, "all"), more(30, "all"), more(60, "all"), more(-15, "all"));
    return `<div class="actions wrap">
      <button class="link" data-action="kid" data-kid="${esc(kid.id)}" data-go="kids">Change limits</button><span class="grow"></span>
      <details class="more" id="more-${esc(kid.id)}"><summary aria-label="More extra time">More</summary><div class="more-menu">${overflow.join("")}</div></details>
      ${give ? this._actionButton({ ...give, primary: true }, kid.id) : ""}
    </div>`;
  }

  // Spec 2.6 and 3.7, noiwid's daily bars from the summary's `week` (decision 4a): oldest on the left, All (or the
  // chosen pool) per day with the day's budget tick, "+30" over a day with extra time, a dot under a day something ran
  // out, a hatched placeholder for a day with no record. A tap shows the day: "tue · 2 h 40 of 3 h · games ran out ·
  // +30 given · 1 ask"
  _weekChart(kid, s) {
    const week = [...(s?.week || [])].reverse();
    if (!week.length) return "";
    const names = new Map((s.groups || []).map((g) => [g.id, g.name]));
    const short = (id) => shortGroup(id, names.get(id) || this._groupName(id));
    const budgeted = new Set();
    for (const d of week) for (const [id, n] of Object.entries(d.budget || {})) if (n !== null && id !== "all") budgeted.add(id);
    const chipIds = ["all", ...(s.groups || []).map((g) => g.id).filter((id) => budgeted.has(id))];
    const group = chipIds.includes(this._weekGroup[kid.id]) ? this._weekGroup[kid.id] : "all";
    const today = week[week.length - 1].date;
    const days = week.map((d) => {
      const known = Boolean(d.minutes && Object.keys(d.minutes).length);
      const bonus = group === "all" ? Object.values(d.bonus || {}).reduce((a, b) => a + b, 0) : (d.bonus || {})[group] || 0;
      const budget = d.budget && d.budget[group] !== null && d.budget[group] !== undefined ? d.budget[group] + ((d.bonus || {})[group] || 0) : null;
      const out = (d.out || []).filter((id) => group === "all" || id === group);
      const label = d.date === today ? "today" : new Date(`${d.date}T12:00:00`).toLocaleDateString("en-US", { weekday: "short" });
      return { d, known, used: known ? d.minutes[group] || 0 : 0, budget, bonus, out, label };
    });
    const peak = Math.max(60, ...days.map((x) => Math.max(x.used, x.budget || 0)));
    const step = peak > 480 ? 240 : 60;
    const top = Math.ceil(peak / step) * step;
    const steps = top / step;
    const pick = days.find((x) => x.d.date === this._weekDay[kid.id]);
    let detail = "";
    if (pick) {
      const parts = [pick.label.toLowerCase()];
      if (!pick.known) parts.push("no record");
      else {
        parts.push(pick.budget === null ? fmtMinutes(pick.used) : `${amount(pick.used)} of ${fmtMinutes(pick.budget)}`);
        if (pick.out.length) parts.push(pick.out.includes("all") && group === "all" ? "out of time" : `${pick.out.map(short).join(" and ")} ran out`);
        if (pick.bonus > 0) parts.push(`+${amount(pick.bonus)} given`);
        if (pick.d.asks) parts.push(`${pick.d.asks} ask${pick.d.asks === 1 ? "" : "s"}`);
      }
      detail = cap(parts.join(" · "));
    }
    return `<div class="week">
      <div class="week-head"><span class="strong">Last 7 days</span><span class="grow"></span>${chipIds.length > 1 ? chipIds
        .map((id) => `<button class="chip-btn ${id === group ? "on" : ""}" data-action="week-group" data-person="${esc(kid.id)}" data-group="${esc(id)}">${esc(short(id))}</button>`)
        .join("") : ""}</div>
      <div class="wk-plot">
        <div class="wk-y">${Array.from({ length: steps + 1 }, (_, i) => `<span>${Math.round((top - i * step) / 60)} h</span>`).join("")}</div>
        <div class="wk-cols">
          ${days
            .map((x) => `<button class="wk-col ${pick === x ? "on" : ""}" data-action="week-day" data-person="${esc(kid.id)}" data-date="${esc(x.d.date)}" aria-label="${esc(x.label)}">
              <span class="wk-tag">${x.bonus > 0 ? `+${esc(amount(x.bonus))}` : ""}</span>
              <span class="wk-area">${Array.from({ length: steps + 1 }, (_, i) => `<i style="top:${(i * 100) / steps}%"></i>`).join("")}
                ${x.known ? `<span class="wk-bar" style="height:${Math.min(100, (x.used / top) * 100)}%" title="${esc(fmtMinutes(x.used))}"></span>` : `<span class="wk-bar none" title="No record"></span>`}
                ${x.known && x.budget !== null ? `<span class="wk-tick" style="bottom:${Math.min(100, (x.budget / top) * 100)}%"></span>` : ""}</span>
              <span class="wk-dot ${x.out.length ? "out" : ""}"></span>
              <span class="wk-x">${esc(x.label === "today" ? "Today" : x.label)}</span>
            </button>`)
            .join("")}
        </div>
      </div>
      ${detail ? `<div class="small wk-detail">${esc(detail)}</div>` : ""}
    </div>`;
  }

  // Spec 3.4: All minutes per hour today, from Home Assistant's statistics of the kid's Screen time today sensor
  // (decision 3b; read when opened)
  _hoursCard(kid) {
    const entity = this._config?.screen_time_sensors?.[kid.id];
    if (!entity) return "";
    const read = this._hours[kid.id];
    let body = `<div class="muted small">Loading…</div>`;
    if (read?.error) body = `<div class="small error-text">${esc(read.error)}</div>`;
    else if (read) {
      const midnight = new Date();
      midnight.setHours(0, 0, 0, 0);
      body = hourChart(hourBars(read.rows, midnight.getTime(), parseFloat(this._hass.states[entity]?.state)));
    }
    return `<details id="hours-${esc(kid.id)}" data-hours="${esc(kid.id)}" class="today-detail"><summary>Today, hour by hour</summary>${body}</details>`;
  }

  // Spec 2.5: each pool with a budget, every kid's state in it, one short bar per kid (never stacked). Pools without
  // a budget for anyone are left out
  _familyPools(kids) {
    const people = kids.map((k) => this._summaryPerson(k.id)).filter(Boolean);
    const rows = (this._summary?.groups || [])
      .map((g) => ({
        g,
        cells: people
          .map((p) => ({ p, pool: (p.groups || []).find((x) => x.id === g.id) }))
          .filter((c) => c.pool && c.pool.limited !== false && c.pool.minutes_left !== null && c.pool.minutes_left !== undefined),
      }))
      .filter((r) => r.cells.length);
    if (people.length < 2 || !rows.length) return "";
    return `<h2>Family today, by pool</h2><div class="card pools">${rows
      .map(
        (r) => `<div class="pool"><div class="strong">${esc(r.g.id === "all" ? "All screen time" : r.g.name)}</div>${r.cells
          .map(({ p, pool }) => {
            const total = pool.budget !== null && pool.budget !== undefined ? pool.budget + (pool.bonus || 0) : (pool.used_minutes || 0) + pool.minutes_left;
            const value = { out: "out", allowed: "allowed", paused: "paused" }[pool.state] || `${amount(pool.minutes_left)} left`;
            return `<div class="bar-row role-${role(pool.state)}"><span class="bar-label">${esc(p.name)}</span>
              <div class="bar"><div style="width:${total ? Math.min(100, ((pool.used_minutes || 0) / total) * 100) : 100}%"></div></div><span class="bar-value">${esc(value)}</span></div>`;
          })
          .join("")}</div>`
      )
      .join("")}</div>`;
  }

  // One kid's own pause, their app and group pauses, and School time today: what the integrations' dashboards do with
  // a lock switch, done through Hearth so every device of theirs (TVs, phones, Xbox, Switch) follows
  _kidControls(kid, s) {
    if (!s) return "";
    const time = clock;
    const chips = [];
    for (const p of s.pauses || [])
      chips.push(`<span class="chip warn"><ha-icon icon="mdi:pause"></ha-icon>${esc(p.name)} paused till ${esc(time(p.until))}<button class="x" data-action="app-pause-end" data-person="${esc(kid.id)}" ${p.app ? `data-app="${esc(p.app)}"` : `data-group="${esc(p.group)}"`} title="End this pause">×</button></span>`);
    const off = (s.school_time_off || [])[0];
    if (off)
      chips.push(`<span class="chip"><ha-icon icon="mdi:school-outline"></ha-icon>No School time today${off.from ? ` from ${esc(off.from)}` : ""}${off.reason ? ` · ${esc(off.reason)}` : ""}<button class="x" data-action="school-off-cancel" data-person="${esc(kid.id)}" title="School time is back today">×</button></span>`);
    const buttons = [];
    if (s.pause) buttons.push(`<button class="chip-btn" data-action="kid-pause-end" data-person="${esc(kid.id)}">End ${esc(kid.name)}'s pause</button>`);
    else
      buttons.push(`<select id="kid-pause-${esc(kid.id)}" aria-label="How long">${[15, 30, 60, 120].map((m) => `<option value="${m}" ${m === 30 ? "selected" : ""}>${fmtMinutes(m)}</option>`).join("")}</select>
        <button class="chip-btn" data-action="kid-pause" data-person="${esc(kid.id)}" title="Holds their TVs, phones, Xbox and Switch">Pause ${esc(kid.name)}</button>`);
    if (s.school_time && !off)
      buttons.push(`<button class="chip-btn" data-action="school-off" data-person="${esc(kid.id)}" title="${esc(`School time ${time(s.school_time.start)}–${time(s.school_time.end)}`)}">No School time today</button>`);
    return `<div class="native">${chips.length ? `<div class="chips">${chips.join("")}</div>` : ""}<div class="inline small-controls">${buttons.join("")}</div></div>`;
  }

  // Today's minutes by device (with extra time on one device) and the apps used most, as the Family Link and Family
  // Safety dashboards show them, across every device Hearth counts
  _todayDetail(kid, s) {
    const devices = s?.devices_today || [];
    const apps = s?.apps_today || [];
    if (!devices.length && !apps.length) return "";
    const targets = new Map((s.targets || []).map((t) => [t.id, t]));
    const extras = new Map((s.device_extras || []).map((x) => [x.target, x]));
    const groupNames = new Map((s.groups || []).map((g) => [g.id, g.name]));
    const most = Math.max(1, ...apps.map((a) => a.minutes));
    const icons = { tv: "mdi:television", phone: "mdi:cellphone", xbox: "mdi:microsoft-xbox", windows: "mdi:microsoft-windows", switch: "mdi:nintendo-switch" };
    return `<details id="today-${esc(kid.id)}" class="today-detail"><summary>Today by device and app</summary>
      ${devices.length ? `<ul class="list compact">${devices
        .map((dv) => {
          const extra = extras.get(dv.target);
          const target = targets.get(dv.target);
          // Spec 3.5: "48 min today", "25 left there", "open there till 7:00"
          const there = !extra ? "" : extra.kind === "allow" ? ` · open there${extra.until ? ` till ${clock(extra.until)}` : ""}` : ` · ${amount(extra.minutes_left || 0)} left there`;
          return `<li><ha-icon icon="${icons[target?.kind || dv.kind] || "mdi:devices"}"></ha-icon>
            <div class="grow"><div>${esc(dv.name)}</div><div class="muted small">${esc(fmtMinutes(dv.minutes))} today${esc(there)}</div></div>
            ${target ? `<button class="chip-btn" data-action="device-bonus" data-person="${esc(kid.id)}" data-target="${esc(target.id)}" data-name="${esc(dv.name)}" data-minutes="15" title="Only there, today">+15 there</button>` : ""}</li>`;
        })
        .join("")}</ul>` : ""}
      <div class="muted small">Apps today</div>
      ${apps.length ? apps
        .slice(0, 8)
        // Spec 3.6: "Minecraft · 35 min · games", the pools it counts in
        .map((a) => `<div class="bar-row"><span class="bar-label" title="${esc(a.package)}">${esc(a.name || a.package)}</span><div class="bar"><div style="width:${(a.minutes / most) * 100}%"></div></div><span class="bar-value">${esc([fmtMinutes(a.minutes), ...(a.groups || []).map((g) => shortGroup(g, groupNames.get(g) || this._groupName(g)))].join(" · "))}</span></div>`)
        .join("") : `<div class="muted small">No apps used today</div>`}
    </details>`;
  }

  // Hearth's allows next to what a parent opened in their own apps (grants), requests answered in a parent's app, and,
  // folded under "Device limits", Google's, Microsoft's and Nintendo's own limits and what Hearth last did through
  // each parental control (apps by name, never their packages)
  _exceptionsAndApps(kid, s) {
    if (!s) return "";
    const time = clock;
    const chips = [];
    for (const a of s.allows || [])
      chips.push(`<span class="chip"><ha-icon icon="mdi:check-circle-outline"></ha-icon>${esc(a.group === "all" ? "All screen time" : a.group || a.app)} allowed${a.ends_on ? ` until ${esc(this._endsOn(a.ends_on))}${a.until ? ` or ${esc(time(a.until))}` : ""}` : a.until ? ` till ${esc(time(a.until))}` : ""}</span>`);
    chips.push(...this._grantChips(s.grants || []));
    for (const a of s.answered_elsewhere || [])
      chips.push(`<span class="chip"><ha-icon icon="mdi:message-reply-text-outline"></ha-icon>Request ${esc(a.text)}</span>`);
    const rows = [];
    let stopping = 0;
    let failed = 0;
    for (const d of s.first_party?.family_link || []) {
      const limit = d.daily_limit === null || d.daily_limit === undefined ? "no daily limit" : `limit ${fmtMinutes(d.daily_limit)}`;
      const left = d.minutes_left === null || d.minutes_left === undefined ? "" : ` · ${fmtMinutes(d.minutes_left)} left`;
      const bonus = d.bonus_left > 0 ? ` · bonus ${fmtMinutes(d.bonus_left)}` : "";
      if (d.blocking) stopping++;
      rows.push(`<div class="small ${d.blocking ? "warn-text" : "muted"}">${esc(d.device)} · Google: ${esc(limit + left + bonus)}${d.blocking ? " · its own limit stops it" : ""}</div>`);
    }
    for (const p of s.first_party?.family_safety || []) {
      const allowance = p.allowance_minutes === null || p.allowance_minutes === undefined ? "" : `allowance ${fmtMinutes(p.allowance_minutes)}`;
      const left = p.minutes_left === null || p.minutes_left === undefined ? "" : ` · ${fmtMinutes(p.minutes_left)} left`;
      const why = p.parent_lock ? ` · locked by a parent${p.override_until ? ` till ${time(p.override_until)}` : ""}` : p.blocking ? " · its own limit stops it" : "";
      if (p.parent_lock || p.blocking) stopping++;
      rows.push(`<div class="small ${p.parent_lock || p.blocking ? "warn-text" : "muted"}">${esc(p.platform)} · Microsoft: ${esc(allowance + left + why)}</div>`);
    }
    for (const n of s.first_party?.nintendo || []) {
      if (n.blocking) stopping++;
      rows.push(`<div class="small ${n.blocking ? "warn-text" : "muted"}">${esc(n.name)} · Nintendo: ${esc(this._switchLine(n))}</div>`);
    }
    const services = { family_link: "Family Link", family_safety: "Family Safety", nintendo: "Nintendo" };
    for (const [kind, st] of Object.entries(s.sync || {})) {
      const last = st.last || {};
      const error = st.error || last.error;
      const names = st.names || {};
      const did = [];
      const held = this._heldWords(st.held || [], st.why || {}, names);
      if (held) did.push(`holding ${held}`);
      const outcomes = Object.entries(last.outcomes || {});
      const back = outcomes.filter(([, o]) => o === "restored").map(([item]) => this._itemName(item, names));
      const kept = outcomes.filter(([, o]) => o === "kept_current").map(([item]) => this._itemName(item, names));
      if (back.length) did.push(`put back ${listWords(back)}`);
      if (kept.length) did.push(`kept the parent's setting for ${listWords(kept)}`);
      if (last.bonus_added && Object.keys(last.bonus_added).length) did.push(`bonus ${Object.entries(last.bonus_added).map(([d, m]) => `${d} +${m} min`).join(", ")}`);
      if (last.extra_time && Object.keys(last.extra_time).length) did.push(`extra time on ${Object.keys(last.extra_time).join(", ")}`);
      if (last.parent_grant) did.push(`let go: ${last.reason || "a parent's change"}`);
      if (!did.length && !error) continue;
      if (error) failed++;
      rows.push(`<div class="small ${error ? "error-text" : "muted"}">${esc(services[kind] || kind)}: ${esc(did.join(" · ") || "nothing held")}${error ? ` · didn't take: ${esc(error)}` : ""}</div>`);
    }
    if (!chips.length && !rows.length) return "";
    // Folded: the summary says only what needs a look (a control that didn't take, a device's own limit stopping it)
    const flags = [failed ? `${failed} didn't take` : "", stopping ? `${stopping} stopping them` : ""].filter(Boolean).join(" · ");
    const limits = rows.length
      ? `<details id="device-limits-${esc(kid.id)}" class="device-limits"><summary>Device limits${flags ? ` <span class="${failed ? "error-text" : "warn-text"}">· ${esc(flags)}</span>` : ""}</summary>${rows.join("")}</details>`
      : "";
    return `<div class="native">${chips.length ? `<div class="chips">${chips.join("")}</div>` : ""}${limits}</div>`;
  }

  // A parent's grants as chips, as the glance puts them: one per device lock, Switch or platform; an app's put together
  // by where they came from and when they end, by name ("Spotify and Pandora open", then "9 apps open"), every name in
  // the tooltip
  _grantChips(grants) {
    const where = { family_link: "Family Link", family_safety: "Family Safety", nintendo: "the Nintendo app" };
    const tail = (g) => `${where[g.via] || g.source || "their app"}${g.until ? ` till ${clock(g.until)}` : ""}`;
    const appName = (g) => g.name || g.target?.value || "an app";
    const chips = [];
    const together = new Map();
    for (const g of grants) {
      if (g.target?.kind === "app" && !g.endable) {
        const key = `${g.via}|${g.until}`;
        together.set(key, [...(together.get(key) || []), g]);
        continue;
      }
      const what = { device: "Devices", switch: "Switch", app: appName(g) }[g.target?.kind] || g.target?.value;
      chips.push(`<span class="chip warn" title="${esc(g.reason || "")}"><ha-icon icon="mdi:account-key"></ha-icon>${esc(what)} open · ${esc(tail(g))}${
        g.endable ? `<button class="x" data-action="grant-end" data-grant="${esc(g.id)}" title="End it in the parent's app">×</button>` : ""
      }</span>`);
    }
    for (const group of together.values()) {
      const names = [...new Set(group.map(appName))].sort((a, b) => a.localeCompare(b));
      const what = group.length <= 3 ? listWords(names) : `${group.length} apps`;
      const title = `${names.join(", ")}: ${group[0].reason || "changed in the parent's app"}`;
      chips.push(`<span class="chip warn" title="${esc(title)}"><ha-icon icon="mdi:account-key"></ha-icon>${esc(what)} open · ${esc(tail(group[0]))}</span>`);
    }
    return chips;
  }

  // An item a parental control holds, by name: an app's (never its package), "their devices", "the Switch"
  _itemName(item, names) {
    if (item === "Devices") return "their devices";
    if (item === "Switch") return "the Switch";
    return names[item] || item;
  }

  // What a parental control holds and why: "Google Messages for School time", "Spotify, YouTube and 3 more for the
  // budget"
  _heldWords(items, why, names) {
    const reasons = { school_time: "School time", pause: "a pause", budget: "the budget" };
    const byWhy = new Map();
    for (const item of items) byWhy.set(why[item] || "", [...(byWhy.get(why[item] || "") || []), this._itemName(item, names)]);
    return [...byWhy.entries()]
      .map(([r, list]) => {
        const sorted = list.sort((a, b) => a.localeCompare(b));
        const what = sorted.length <= 3 ? listWords(sorted) : `${sorted.slice(0, 2).join(", ")} and ${sorted.length - 2} more`;
        return reasons[r] ? `${what} for ${reasons[r]}` : what;
      })
      .join("; ");
  }

  // One line of a Switch's day: "played 1 h 15 min (theirs 50 min) · limit 2 h · 45 min left · +30 extra"
  _switchLine(n) {
    if (!n.available) return "no recent word from the Switch";
    const parts = [];
    if (n.played_minutes !== null && n.played_minutes !== undefined)
      parts.push(`played ${fmtMinutes(n.played_minutes)}${n.player_minutes !== null && n.player_minutes !== undefined ? ` (theirs ${fmtMinutes(n.player_minutes)})` : ""}`);
    parts.push(n.limit_minutes === null || n.limit_minutes === undefined ? "no daily limit" : `limit ${fmtMinutes(n.limit_minutes)}`);
    if (n.minutes_left !== null && n.minutes_left !== undefined) parts.push(`${fmtMinutes(n.minutes_left)} left`);
    if (n.extra_minutes === -1) parts.push("unlimited extra today");
    else if (n.extra_minutes > 0) parts.push(`+${fmtMinutes(n.extra_minutes)} extra`);
    if (n.held_by_hearth) parts.push("held by Hearth");
    else if (n.blocking) parts.push("its own limit stops it");
    if (n.playing) parts.push("playing now");
    return parts.join(" · ");
  }

  _deviceCard(dv) {
    const icon = dv.kind === "tv" ? "mdi:television" : "mdi:cellphone";
    const on = dv.screen === "on";
    // Now playing: the summary's short text for what's on there ("bluey · s2e4 · 8 min left"), else the device's own
    const play = (this._summary?.playing || []).find((p) => p.target === `hearth:${dv.id}` && p.text);
    const what = play
      ? cap(`${play.name ? `${play.name} · ` : ""}${play.text}`)
      : dv.media_title ? `${dv.media_title}${dv.media_app ? ` · ${dv.media_app}` : ""}` : dv.app || (on ? "Home" : dv.connected ? "Asleep" : "Not connected");
    return `<div class="card device ${dv.connected ? "" : "dim"}">
      <div class="row"><ha-icon icon="${icon}"></ha-icon><div class="grow"><div class="strong">${esc(dv.name || dv.id)}</div>
      <div class="muted small">${esc(what)}</div></div>
      ${dv.person ? `<span class="chip">${esc(this._personName(dv.person))}</span>` : dv.profile ? `<span class="chip">${esc(dv.profile)}</span>` : ""}
      <span class="dot ${dv.connected ? (on ? "on" : "idle") : "off"}" title="${dv.connected ? "Connected" : "Not connected"}"></span></div></div>`;
  }

  _kidPicker() {
    const kids = this._kids();
    return `<div class="pills">${kids
      .map((k) => `<button class="pill ${k.id === this._kid ? "on" : ""}" data-action="kid" data-kid="${esc(k.id)}">${this._avatar(k.id, 24)}<span>${esc(k.name)}</span></button>`)
      .join("")}</div>`;
  }

  _options(items, selected, placeholder = "Choose…") {
    return `<option value="">${esc(placeholder)}</option>${items
      .map((i) => `<option value="${esc(i.value)}" ${i.value === selected ? "selected" : ""}>${esc(i.label)}</option>`)
      .join("")}`;
  }

  _entityOptions(list, selected, placeholder) {
    const items = (list || []).map((e) => ({ value: e.entity_id, label: `${e.name} (${e.entity_id})` }));
    if (selected && !items.some((i) => i.value === selected)) items.unshift({ value: selected, label: `${this._entityName(selected)} (${selected})` });
    return this._options(items, selected, placeholder);
  }

  _kidsTab() {
    const kids = this._kids();
    if (!kids.length)
      return `<div class="card empty"><p>Mark who's a kid in the Family tab, or run the guided setup.</p><button class="btn primary" data-action="setup-open">Guided setup</button></div>`;
    const kid = kids.find((k) => k.id === this._kid) || kids[0];
    return `${this._kidPicker()}
      ${this._limitsCard(kid)}
      ${this._suggestCard(kid)}
      ${this._sourcesCard(kid)}
      ${this._locksCard(kid)}
      ${this._enforceCard(kid)}
      ${this._switchCard(kid)}
      ${this._youtubeCard(kid)}
      ${this._extraTimeCard(kid)}`;
  }

  _limitsCard(kid) {
    const groups = this._config.groups || [];
    const b = this._config.budgets?.[kid.id] || {};
    return `<section class="card">
      <h3><ha-icon icon="mdi:timer-sand"></ha-icon>Daily limits</h3>
      <p class="muted">Minutes a day. Empty means no limit. <b>All screen time</b> counts every device together; the others count only their apps.</p>
      <div class="presets">Quick All screen time:
        ${[60, 90, 120, 180].map((m) => `<button class="chip-btn" data-action="budget-preset" data-person="${esc(kid.id)}" data-days="both" data-minutes="${m}">${fmtMinutes(m)}</button>`).join("")}
      </div>
      <table class="limits"><thead><tr><th>Group</th><th>School days</th><th>Other days</th></tr></thead><tbody>
      ${groups
        .map((g) => {
          const v = b[g.id] || {};
          const input = (days, value) =>
            `<span class="minutes"><input type="number" min="0" max="1440" step="5" inputmode="numeric" placeholder="No limit" value="${value ?? ""}"
              data-change="budget" data-person="${esc(kid.id)}" data-group="${esc(g.id)}" data-days="${days}" aria-label="${esc(g.name)} ${days}">
              <span class="muted small">${value === null || value === undefined ? "" : value >= 60 ? `min · ${esc(fmtMinutes(value))}` : "min"}</span></span>`;
          return `<tr><td>${esc(g.name)}${g.in_all ? "" : ` <span class="chip small">not screen time</span>`}</td><td>${input("school_days", v.school)}</td><td>${input("other_days", v.other)}</td></tr>`;
        })
        .join("")}
      </tbody></table>
    </section>`;
  }

  // Which of the kid's suggestions ("games ran out · give 15?") also go to the adults' phones, once a day, and how much
  // each offers: All screen time and every group with a limit (option suggest_push; off by default)
  _suggestCard(kid) {
    const cfg = this._config;
    const b = cfg.budgets?.[kid.id] || {};
    const limited = (g) => g.id === "all" || [b[g.id]?.school, b[g.id]?.other].some((v) => v !== null && v !== undefined);
    const groups = (cfg.groups || []).filter(limited);
    const pairs = (cfg.suggest_push || []).filter((p) => p.person === kid.id && p.group);
    const rows = groups
      .map((g) => {
        const pair = pairs.find((p) => p.group === g.id);
        const minutes = pair?.minutes || (g.id === "all" ? 30 : 15);
        const data = `data-person="${esc(kid.id)}" data-group="${esc(g.id)}"`;
        return `<li><div class="grow">${esc(g.id === "all" ? "All screen time" : g.name)}</div>
          <label class="check"><input type="checkbox" data-change="suggest-on" ${data} ${pair ? "checked" : ""}> When it runs out</label>
          <select data-change="suggest-minutes" ${data} aria-label="${esc(g.name)}: minutes offered" ${pair ? "" : "disabled"}>
            ${[15, 30, 45, 60].map((m) => `<option value="${m}" ${m === minutes ? "selected" : ""}>+${m} min</option>`).join("")}</select></li>`;
      })
      .join("");
    return `<section class="card">
      <h3><ha-icon icon="mdi:cellphone-message"></ha-icon>Suggest to phones</h3>
      <p class="muted small">When one runs out, the adults' phones get "give more?" with two amounts and Not today, once a day. Off: it still shows here and in the adults' apps.</p>
      <ul class="list compact small-controls">${rows}</ul>
    </section>`;
  }

  _extraTimeCard(kid) {
    const groups = this._config.groups || [];
    return `<section class="card">
      <h3><ha-icon icon="mdi:plus-circle-outline"></ha-icon>Extra time today</h3>
      <div class="inline">
        <input id="custom-${esc(kid.id)}" type="number" step="5" placeholder="Minutes (−15 takes away)" data-enter="bonus-custom" data-person="${esc(kid.id)}">
        <select id="custom-group-${esc(kid.id)}">${groups.map((g) => `<option value="${esc(g.id)}">${esc(g.name)}</option>`).join("")}</select>
        <button class="btn primary" data-action="bonus-custom" data-person="${esc(kid.id)}">Give</button>
      </div>
    </section>`;
  }

  _sourcesCard(kid) {
    const cfg = this._config;
    const mine = (cfg.sources || []).filter((s) => s.person === kid.id);
    const groups = cfg.groups || [];
    const devices = cfg.devices || [];
    const sameChoices = [
      ...devices.map((dv) => ({ value: `hearth:${dv.id}`, label: `Hearth: ${dv.name || dv.id}` })),
      ...(cfg.sources || []).map((s) => ({ value: s.id, label: s.name || s.entity_id })),
    ];
    return `<section class="card">
      <h3><ha-icon icon="mdi:chart-timeline-variant"></ha-icon>Screen time from other places</h3>
      <p class="muted">Hearth's own TVs and phones count by themselves. Add Family Link, Xbox, Switch or other sensors so ${esc(kid.name)}'s time adds up everywhere.</p>
      ${mine.length ? `<ul class="list">${mine
        .map((s) => `<li><ha-icon icon="mdi:counter"></ha-icon><div class="grow"><div>${esc(s.name || s.entity_id)}</div><div class="muted small">${esc(s.entity_id)}${s.group ? ` · counts in ${esc(this._groupName(s.group))}` : ""}${s.same_as ? " · same device as another" : ""}${s.live ? " · live" : ""}</div></div>
          <button class="icon-btn" data-action="source-remove" data-id="${esc(s.id)}" aria-label="Remove"><ha-icon icon="mdi:close"></ha-icon></button></li>`)
        .join("")}</ul>` : `<p class="muted small">None yet.</p>`}
      <details id="add-source-${esc(kid.id)}"><summary>Add a source</summary>
        <div class="form">
          <label class="field">Sensor<select id="source-entity-${esc(kid.id)}">${this._entityOptions(cfg.choices?.screen_time, "", "Choose a sensor…")}</select></label>
          <label class="field">Name (optional)<input id="source-name-${esc(kid.id)}" placeholder="Phone, Xbox…"></label>
          <label class="field">Time it can't put on an app counts in<select id="source-group-${esc(kid.id)}">${this._options(groups.filter((g) => g.id !== "all").map((g) => ({ value: g.id, label: g.name })), "", "All screen time only")}</select></label>
          <label class="field">The same device as (counted once)<select id="source-same-${esc(kid.id)}">${this._options(sameChoices, "", "A device of its own")}</select></label>
          <label class="check"><input type="checkbox" id="source-live-${esc(kid.id)}"> It says what's playing now (not a total)</label>
          <div class="actions"><button class="btn primary" data-action="source-add" data-person="${esc(kid.id)}">Add</button></div>
        </div>
      </details>
    </section>`;
  }

  _locksCard(kid) {
    const cfg = this._config;
    const mine = (cfg.locks || []).filter((l) => l.person === kid.id);
    return `<section class="card">
      <h3><ha-icon icon="mdi:bed-clock"></ha-icon>Bedtime and school time</h3>
      <p class="muted">While any of these is on, ${esc(kid.name)}'s Hearth devices hold their apps. Family Link's bedtime and school time sensors, or Family Safety's Downtime Active, are typical.</p>
      ${mine.length ? `<ul class="list">${mine
        .map((l) => `<li><ha-icon icon="mdi:lock-clock"></ha-icon><div class="grow">${esc(this._entityName(l.entity_id))}<div class="muted small">${esc(l.entity_id)} · now ${esc(this._hass.states[l.entity_id]?.state ?? "unknown")}</div></div>
          <button class="icon-btn" data-action="lock-remove" data-person="${esc(kid.id)}" data-entity="${esc(l.entity_id)}" aria-label="Remove"><ha-icon icon="mdi:close"></ha-icon></button></li>`)
        .join("")}</ul>` : ""}
      <div class="inline"><select id="lock-entity-${esc(kid.id)}">${this._entityOptions(cfg.choices?.locks, "", "Choose a sensor…")}</select>
        <button class="btn" data-action="lock-add" data-person="${esc(kid.id)}">Add</button></div>
    </section>`;
  }

  _enforceCard(kid) {
    const cfg = this._config;
    const mine = (cfg.enforce || []).filter((e) => e.person === kid.id);
    const fl = mine.find((e) => e.kind === "family_link");
    const fs = mine.find((e) => e.kind === "family_safety");
    const nin = mine.find((e) => e.kind === "nintendo");
    const groups = cfg.groups || [];
    const groupBoxes = (attr, chosen) =>
      groups.map((g) => `<label class="check"><input type="checkbox" ${attr}="${esc(kid.id)}" value="${esc(g.id)}" ${chosen.includes(g.id) ? "checked" : ""}> ${esc(g.name)}</label>`).join("");
    return `<section class="card">
      <h3><ha-icon icon="mdi:shield-account"></ha-icon>When time runs out elsewhere</h3>
      <p class="muted">Hearth's own devices stop by themselves. These parental controls can hold ${esc(kid.name)}'s other devices too, until there's time again.</p>
      <div class="form">
        <label class="field">Family Link (phones and tablets lock; unlimited apps keep working)
          <select id="enf-fl-${esc(kid.id)}">${this._entityOptions(cfg.choices?.family_link, fl?.entity_id || "", "Not used")}</select></label>
        <label class="field">Family Link: during School time, pause these apps (package names)
          <input id="enf-fl-school-${esc(kid.id)}" type="text" value="${esc((fl ? fl.school_time_apps || [] : ["com.google.android.apps.messaging"]).join(", "))}" placeholder="com.google.android.apps.messaging"></label>
        <label class="field">Microsoft Family Safety
          <select id="enf-fs-${esc(kid.id)}">${this._entityOptions(cfg.choices?.family_safety, fs?.entity_id || "", "Not used")}</select></label>
        <div class="checks">${(cfg.platforms || []).map((p) => `<label class="check"><input type="checkbox" data-fs-platform="${esc(kid.id)}" value="${esc(p)}" ${(fs?.platforms || ["Xbox"]).includes(p) ? "checked" : ""}> ${esc(p)}</label>`).join("")}</div>
        <div class="muted small">Locks those while any of these groups is out:</div><div class="checks">${groupBoxes("data-fs-group", fs?.groups || ["all", "games"])}</div>
        <label class="field">Nintendo Switch
          <select id="enf-nin-${esc(kid.id)}">${this._entityOptions(cfg.choices?.nintendo, nin?.entity_id || "", "Not used")}</select></label>
        <div class="muted small">Suspends the game while any of these groups is out:</div><div class="checks">${groupBoxes("data-nin-group", nin?.groups || ["all", "games"])}</div>
        <label class="field">A shared Switch: hold it only while ${esc(kid.name)} is the one playing (their "playing" sensor)
          <select id="enf-nin-playing-${esc(kid.id)}">${this._entityOptions(cfg.choices?.nintendo_playing, (nin?.playing || [])[0] || "", "Hold the whole Switch")}</select></label>
        <div class="muted small">Nintendo reports play about every 10 minutes, so the hold can start that late and end that late.</div>
        <div class="actions"><button class="btn primary" data-action="enforce-save" data-person="${esc(kid.id)}">Save</button></div>
      </div>
    </section>`;
  }

  // A kid's Nintendo Switch: today's play and its own limit, Hearth's extra time on it, Nintendo's own extra time and
  // its cancel, and the allow list, each only when the installed Nintendo integration has it (config.capabilities)
  _switchCard(kid) {
    const caps = this._config.capabilities?.nintendo || {};
    if (!caps.installed) return "";
    const switches = this._summaryPerson(kid.id)?.first_party?.nintendo || [];
    const head = `<h3><ha-icon icon="mdi:nintendo-switch"></ha-icon>Nintendo Switch</h3>`;
    if (!switches.length)
      return `<section class="card">${head}<p class="muted">Pick ${esc(kid.name)}'s Switch under <b>When time runs out elsewhere</b> (or add its played-time sensor as a source) to see it here.</p></section>`;
    return switches.map((n) => this._oneSwitch(kid, n, caps, head)).join("");
  }

  _oneSwitch(kid, n, caps, head) {
    const p = esc(kid.id);
    const dev = esc(n.device_id);
    const sections = [];
    const facts = [
      ["Played today", n.played_minutes === null || n.played_minutes === undefined ? "–" : fmtMinutes(n.played_minutes)],
      ...(n.player_minutes !== null && n.player_minutes !== undefined ? [[`${kid.name}'s player`, fmtMinutes(n.player_minutes)]] : []),
      ["Switch's own limit", n.limit_minutes === null || n.limit_minutes === undefined ? "None" : fmtMinutes(n.limit_minutes)],
      ["Left on it", n.minutes_left === null || n.minutes_left === undefined ? "–" : fmtMinutes(n.minutes_left)],
      ["Extra today", n.extra_minutes === -1 ? "Unlimited" : n.extra_minutes ? fmtMinutes(n.extra_minutes) : "None"],
      ...(n.bedtime ? [["Bedtime alarm", n.bedtime]] : []),
    ];
    const status = [];
    if (!n.available) status.push(`<span class="chip dim"><ha-icon icon="mdi:cloud-off-outline"></ha-icon>No recent word from it</span>`);
    if (n.playing) status.push(`<span class="chip play"><ha-icon icon="mdi:gamepad-variant"></ha-icon>Playing now</span>`);
    if (n.held_by_hearth) status.push(`<span class="chip warn"><ha-icon icon="mdi:lock"></ha-icon>Held by Hearth</span>`);
    else if (n.blocking) status.push(`<span class="chip out"><ha-icon icon="mdi:timer-off"></ha-icon>Its own limit stops it</span>`);
    if (n.suspended && !n.held_by_hearth) status.push(`<span class="chip warn"><ha-icon icon="mdi:pause"></ha-icon>Software suspended</span>`);
    if (n.last_synced) status.push(`<span class="chip dim" title="When the Switch last took its settings"><ha-icon icon="mdi:sync"></ha-icon>Synced ${esc(new Date(n.last_synced).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }))}</span>`);
    sections.push(`<div class="chips">${status.join("")}</div>
      <div class="facts">${facts.map(([k, v]) => `<div><div class="muted small">${esc(k)}</div><div class="strong">${esc(v)}</div></div>`).join("")}</div>`);
    // Hearth's extra time on this Switch alone: lets Hearth's hold go there (its own limit still applies)
    if (n.target)
      sections.push(`<div class="row wrap"><div class="grow muted small">Hearth's extra time on this Switch only (lets Hearth's hold go there, today)</div>
        ${[15, 30, 60].map((m) => `<button class="btn" data-action="device-bonus" data-person="${p}" data-target="${esc(n.target)}" data-name="${esc(n.name)}" data-minutes="${m}">+${m}</button>`).join("")}</div>`);
    // Nintendo's own extra playing time: past the Switch's own limit
    if (caps.add_bonus) {
      if (n.held_by_hearth) sections.push(`<p class="muted small">Nintendo's own extra time waits while Hearth holds the Switch: give Hearth's extra time above instead.</p>`);
      else {
        const amounts = [15, 30, 60, 120].filter((m) => m >= (caps.bonus_min || 5) && m <= (caps.bonus_max || 30));
        sections.push(`<div class="row wrap"><div class="grow muted small">Nintendo's own extra playing time today (past the Switch's own limit${n.bedtime ? "; with a bedtime alarm it moves bedtime later" : ""})</div>
          ${amounts.map((m) => `<button class="btn" data-action="nin-bonus" data-person="${p}" data-device="${dev}" data-minutes="${m}">+${m}</button>`).join("")}
          ${caps.unlimited ? `<button class="btn" data-action="nin-bonus" data-person="${p}" data-device="${dev}" data-minutes="-1">Rest of today</button>` : ""}
          ${caps.cancel_bonus && n.extra_minutes ? `<button class="btn" data-action="nin-bonus-cancel" data-person="${p}" data-device="${dev}">Cancel extra</button>` : ""}</div>`);
      }
    }
    if (caps.list_apps) {
      const apps = (this._switchApps || {})[n.device_id];
      const list = apps
        ? apps.length
          ? `<ul class="list compact">${apps
              .map((a) => `<li><div class="grow">${esc(a.name || a.application_id)}</div>${caps.set_app_allowed
                ? `<label class="check"><input type="checkbox" data-change="nin-allow" data-person="${p}" data-device="${dev}" data-app="${esc(a.application_id)}" ${a.allowed ? "checked" : ""}> Allowed</label>`
                : `<span class="muted small">${a.allowed ? "Allowed" : ""}</span>`}</li>`)
              .join("")}</ul>`
          : `<p class="muted small">No games reported.</p>`
        : "";
      sections.push(`<details id="nin-apps-${dev}"><summary>Games and the allow list</summary>
        <p class="muted small">An allowed game starts even past the Switch's age rating restriction. Nintendo's own setting; Hearth's limits still count its time.</p>
        ${list}<div class="actions"><button class="btn" data-action="nin-apps" data-person="${p}" data-device="${dev}">${apps ? "Read again" : "Show the games"}</button></div></details>`);
    }
    return `<section class="card">${head.replace("Nintendo Switch", () => esc(n.name))}${sections.join("")}</section>`;
  }

  _youtubeCard(kid) {
    const watch = this._watch[kid.id];
    if (watch === undefined) return `<section class="card"><h3><ha-icon icon="mdi:youtube"></ha-icon>YouTube in HearthTube</h3><p class="muted">Loading…</p></section>`;
    if (watch === null)
      return `<section class="card"><h3><ha-icon icon="mdi:youtube"></ha-icon>YouTube in HearthTube</h3><p class="muted">${esc(kid.name)} has no TV profile in Hearth yet. Map one in Devices.</p></section>`;
    const blocked = watch.blocked || {};
    const list = (kind, field, items) =>
      (items || [])
        .map((b) => `<span class="chip">${esc(b.label || b.id || b.word || "")}<button class="x" data-action="unblock" data-kind="${field}" data-person="${esc(kid.id)}" data-item="${esc(b.id || b.word || "")}" aria-label="Unblock">×</button></span>`)
        .join("");
    return `<section class="card">
      <h3><ha-icon icon="mdi:youtube"></ha-icon>YouTube in HearthTube</h3>
      <div class="cols">
        <div><div class="muted small">Watched this week</div>
          <ul class="list compact">${(watch.entries || [])
            .slice(0, 12)
            .map((e) => `<li><div class="grow"><div>${esc(e.title || e.video_id)}</div><div class="muted small">${esc(e.channel || "")}${e.device ? ` · ${esc(e.device)}` : ""}</div></div>
              <button class="chip-btn" data-action="block" data-kind="video" data-person="${esc(kid.id)}" data-item="${esc(e.video_id)}" data-label="${esc(e.title || "")}" title="Block this video">Block video</button>
              ${e.channel_id ? `<button class="chip-btn" data-action="block" data-kind="channel" data-person="${esc(kid.id)}" data-item="${esc(e.channel_id)}" data-label="${esc(e.channel || "")}" title="Block this channel">Block channel</button>` : ""}</li>`)
            .join("") || `<li class="muted small">Nothing yet.</li>`}</ul></div>
        <div>
          ${["video", "channel", "word"]
            .map(
              (field) => `<div class="muted small">Blocked ${field}s</div><div class="chips">${list(field + "s", field, blocked[field + "s"]) || `<span class="muted small">None</span>`}</div>
              <div class="inline"><input id="block-${field}-${esc(kid.id)}" placeholder="${field === "word" ? "A word" : `A ${field} link or id`}" data-enter="block" data-kind="${field}" data-person="${esc(kid.id)}">
              <button class="btn" data-action="block" data-kind="${field}" data-person="${esc(kid.id)}">Block</button></div>`
            )
            .join("")}
        </div>
      </div>
    </section>`;
  }

  _devicesTab() {
    const cfg = this._config;
    const persons = (cfg.persons || []).map((p) => ({ value: p.id, label: p.name }));
    const seen = cfg.seen_profiles || {};
    const profiles = cfg.profiles || {};
    // seen_profiles: option key -> label ("Sam · Kitchen, Playroom"); old bare keys ("user:10") need picking again
    const ids = [...new Set([...Object.keys(seen), ...Object.keys(profiles)])].sort((a, b) =>
      (seen[a] || a).localeCompare(seen[b] || b));
    const old = (id) => /^user:\d+/.test(id);
    return `${this._pairingCards()}
      ${this._parentalControlsCard()}
      <section class="card">
        <h3><ha-icon icon="mdi:link-variant"></ha-icon>Pair a TV or phone</h3>
        <ol class="steps">
          <li>On the TV, open Hearth's <b>Settings → Home Assistant → Pair with Home Assistant</b>. On a phone, Glint's Home Assistant pairing.</li>
          <li>It shows a code, and the request appears at the top of this page.</li>
          <li>Check the codes match, then pair. A phone also asks whose it is.</li>
        </ol>
      </section>
      <section class="card">
        <h3><ha-icon icon="mdi:devices"></ha-icon>Paired</h3>
        ${(cfg.devices || []).length ? `<ul class="list">${cfg.devices
          .map((dv) => `<li><ha-icon icon="${dv.kind === "tv" ? "mdi:television" : "mdi:cellphone"}"></ha-icon><div class="grow"><div>${esc(dv.name || dv.id)}</div>
            <div class="muted small">${dv.kind === "tv" ? "TV" : `Phone${dv.person ? ` · ${esc(this._personName(dv.person))}'s` : ""}`} · ${dv.connected ? "connected" : "not heard from lately"}</div></div>
            ${dv.kind === "tv" ? `<select data-change="media-player" data-device="${esc(dv.id)}" aria-label="Its media player">${this._entityOptions(cfg.choices?.media_player, (cfg.media_players || {})[dv.id] || "", "Its media player…")}</select>` : ""}
            <span class="dot ${dv.connected ? "on" : "off"}"></span></li>`)
          .join("")}</ul>` : `<p class="muted">Nothing paired yet.</p>`}
        <p class="muted small">To remove a device, delete it in Settings → Devices & services → Hearth.</p>
      </section>
      <section class="card">
        <h3><ha-icon icon="mdi:bell-ring-outline"></ha-icon>Push to phones</h3>
        <p class="muted">An ntfy server (ntfy.sh, or your own) through which Home Assistant tells a paired phone that something changed, so it updates at once. Each phone listens on its own random topic, and the ping only says "changed". Empty: no pings; phones still update at their next check.</p>
        <div class="inline"><input id="push-server" type="url" value="${esc(cfg.push_server || "")}" placeholder="https://ntfy.example.com" data-enter="push-save">
          <button class="btn primary" data-action="push-save">Save</button></div>
      </section>
      <section class="card">
        <h3><ha-icon icon="mdi:account-switch"></ha-icon>TV profiles</h3>
        <p class="muted">Each Google TV profile the TVs have reported, by name, and whose it is: one choice covers every TV that has the profile. A guest or shared profile belongs to nobody.</p>
        ${ids.some(old) ? `<p class="warn">Mappings by number (user:10) no longer count: each TV numbers its profiles itself. Pick the profiles by name below, then set the old ones to Nobody.</p>` : ""}
        ${ids.length ? `<table class="limits"><tbody>${ids
          .map((id) => `<tr><td>${esc(seen[id] || id)}</td>
            <td><select data-change="profile" data-profile="${esc(id)}">${this._options(persons, profiles[id] || "", "Nobody")}</select></td></tr>`)
          .join("")}</tbody></table>` : `<p class="muted small">No profiles reported yet: they appear once a paired TV has been used.</p>`}
        <details id="add-profile"><summary>Add a profile no TV has reported yet</summary>
          <div class="inline"><input id="new-profile-id" placeholder="name:sam"><select id="new-profile-person">${this._options(persons, "", "Whose?")}</select>
          <button class="btn" data-action="profile-add">Add</button></div>
        </details>
      </section>`;
  }

  // Whether each parental control works now: its entries, and Family Safety's connection (the integrations' own
  // dashboards show the same as a status pill). What's not right, for the Today tab and the dots below
  _controlProblems() {
    const problems = [];
    for (const c of this._config?.parental_controls || []) {
      for (const e of c.entries || [])
        if (e.state !== "loaded") problems.push({ name: c.name, text: `${e.title || c.name}: ${e.state.replace(/_/g, " ")}${e.reason ? ` (${e.reason})` : ""}` });
      if (c.connection && c.connection.state !== "connected")
        problems.push({ name: c.name, text: `${c.name}: ${c.connection.reauth_required ? "needs you to sign in again" : `connection ${c.connection.state}`}` });
    }
    return problems;
  }

  _controlsAttention() {
    const problems = this._controlProblems();
    if (!problems.length) return "";
    return `<div class="card attention"><div class="row"><ha-icon icon="mdi:alert-outline"></ha-icon><div class="grow">
      <div class="strong">A parental control needs a look</div>${problems.map((p) => `<div class="muted small">${esc(p.text)}</div>`).join("")}
      <div class="muted small">Until it's fixed, Hearth can't read or hold what goes through it. Open it in Settings → Devices & services.</div></div></div></div>`;
  }

  _parentalControlsCard() {
    const controls = this._config.parental_controls || [];
    const problems = new Set(this._controlProblems().map((p) => p.name));
    return `<section class="card">
      <h3><ha-icon icon="mdi:shield-check-outline"></ha-icon>Parental controls Hearth works through</h3>
      ${controls.length ? `<ul class="list">${controls
        .map((c) => `<li><span class="dot ${problems.has(c.name) ? "idle" : "on"}"></span><div class="grow"><div>${esc(c.name)}</div>
          <div class="muted small">${esc((c.entries || []).map((e) => `${e.title}: ${e.state.replace(/_/g, " ")}`).join(", "))}${c.connection ? ` · connection ${esc(c.connection.state)}` : ""}</div></div></li>`)
        .join("")}</ul>` : `<p class="muted">None installed. Family Link (phones and tablets), Microsoft Family Safety (Windows and Xbox) and Nintendo Switch Parental Controls each add their devices.</p>`}
    </section>`;
  }

  _groupSelect(app, group) {
    const groups = (this._config.groups || []).filter((g) => g.id !== "all");
    return `<select data-change="app-group" data-app="${esc(app)}" aria-label="Group">
      ${groups.map((g) => `<option value="${esc(g.id)}" ${g.id === group ? "selected" : ""}>${esc(g.name)}</option>`).join("")}
      <option value="other" ${group === "other" ? "selected" : ""}>Other</option></select>`;
  }

  _appRow(a, extra = "") {
    return `<li><div class="grow"><div>${esc(a.name || a.package)}${a.moved ? ` <span class="chip small">moved by you</span>` : ""}</div>
      <div class="muted small">${esc(a.package)}${extra}</div></div>${this._groupSelect(a.package, a.group)}</li>`;
  }

  _appsTab() {
    const cfg = this._config;
    const known = cfg.known_apps || {};
    const filter = this._appFilter || "";
    const all = (cfg.apps || []).filter((a) => !filter || a.name.toLowerCase().includes(filter) || a.package.includes(filter));
    const recent = cfg.recent || [];
    const appsCards = `
      <section class="card">
        <h3><ha-icon icon="mdi:new-box"></ha-icon>Sorted lately</h3>
        <p class="muted">New apps go to a group on their own: one that lists them, else their kind (games, video, social, messaging…), else Other. If one landed wrong, move it; your choice always wins.</p>
        ${recent.length ? `<ul class="list compact">${recent.map((a) => this._appRow(a, `${a.who ? ` · ${esc(a.who)}` : ""} · ${esc(new Date(a.seen).toLocaleDateString())}`)).join("")}</ul>` : `<p class="muted small">Nothing new lately.</p>`}
      </section>
      <section class="card">
        <h3><ha-icon icon="mdi:apps"></ha-icon>Every app</h3>
        <input id="app-filter" class="filter" placeholder="Find an app" value="${esc(this._appFilter || "")}">
        <ul class="list compact">${all.slice(0, 200).map((a) => this._appRow(a)).join("") || `<li class="muted small">No apps match.</li>`}</ul>
        ${all.length > 200 ? `<p class="muted small">Showing 200 of ${all.length}: narrow it down above.</p>` : ""}
      </section>`;
    const datalist = `<datalist id="known-apps">${Object.entries(known)
      .map(([pkg, name]) => `<option value="${esc(pkg)}">${esc(name)}</option>`)
      .join("")}</datalist>`;
    const groups = (cfg.groups || []).filter((g) => g.id !== "all");
    return `${datalist}${appsCards}
      <section class="card">
        <h3><ha-icon icon="mdi:shape-plus"></ha-icon>Groups</h3>
        <p class="muted">A group gets its own daily limit (Kids tab). Untick <b>Screen time</b> for things like music: their minutes don't count toward All screen time, and they keep working when it runs out.</p>
        <div class="inline"><input id="group-new-name" placeholder="New group, e.g. Homework" data-enter="group-add"><button class="btn" data-action="group-add">Add group</button></div>
      </section>
      ${groups
        .map(
          (g) => `<section class="card">
          <div class="row"><h3 class="grow">${esc(g.name)}</h3>
            <label class="check"><input type="checkbox" data-change="outside-all" data-group="${esc(g.id)}" ${g.in_all ? "checked" : ""}> Screen time</label>
            ${g.builtin ? "" : `<button class="icon-btn" data-action="group-remove" data-group="${esc(g.id)}" aria-label="Remove group"><ha-icon icon="mdi:delete-outline"></ha-icon></button>`}</div>
          <div class="chips">${g.apps
            .map((a) => {
              const removable = !g.builtin || (g.added_apps || []).includes(a);
              return `<span class="chip">${esc(known[a] || a)}${removable ? `<button class="x" data-action="app-remove" data-group="${esc(g.id)}" data-app="${esc(a)}" aria-label="Remove">×</button>` : ""}</span>`;
            })
            .join("") || `<span class="muted small">No apps yet.</span>`}</div>
          <div class="inline"><input id="app-new-${esc(g.id)}" list="known-apps" placeholder="Add an app (name or package)" data-enter="app-add" data-group="${esc(g.id)}">
            <button class="btn" data-action="app-add" data-group="${esc(g.id)}">Add</button></div>
        </section>`
        )
        .join("")}
      <section class="card">
        <h3><ha-icon icon="mdi:bell-badge-outline"></ha-icon>Where new apps are noticed, and requests</h3>
        <p class="muted">Hearth's TVs and phones report their apps. These lists of a kid's apps (Family Link's) add the rest. Requests for more time, offers and chores go to every adult's Home Assistant app; tapping one opens it here.</p>
        <div class="muted small">Watch these lists of a kid's apps:</div>
        <div class="checks">${(cfg.choices?.app_lists || [])
          .map((e) => `<label class="check"><input type="checkbox" data-app-watch value="${esc(e.entity_id)}" ${(cfg.app_watch || []).includes(e.entity_id) ? "checked" : ""}> ${esc(e.name)}</label>`)
          .join("") || `<span class="muted small">No Family Link app lists found.</span>`}</div>
        ${this._askPhones()}
        <label class="field">Another phone that gets them too<select id="ask-notify">${this._options((cfg.notify_services || []).map((n) => ({ value: n, label: n.replace("notify.mobile_app_", "") })), cfg.ask_notify || "", "None")}</select></label>
        <div class="actions"><button class="btn primary" data-action="new-apps-save">Save</button></div>
      </section>`;
  }

  // Each adult on Hearth's page, their companion apps, and whether requests reach them
  _askPhones() {
    const byAdult = this._config.ask_phones || {};
    const adults = Object.keys(byAdult);
    if (!adults.length) return `<div class="muted small">No adults yet: mark them in Family.</div>`;
    return `<ul class="list">${adults
      .map((p) => {
        const a = byAdult[p];
        const found = (a.phones || []).map((x) => `${x.service.replace("notify.mobile_app_", "")}${x.os ? ` (${x.os === "ios" ? "iOS" : "Android"})` : ""}`);
        return `<li>${this._avatar(p, 32)}<div class="grow">${esc(this._personName(p))}
          <div class="muted small">${found.length ? esc(found.join(", ")) : "No Home Assistant app found for them"}</div></div>
          <label class="check"><input type="checkbox" data-change="ask-on" data-person="${esc(p)}" ${a.on ? "checked" : ""}> Requests</label>
          <label class="check" title="Android: a tap opens hearth://ask/&lt;id&gt; (their own app) instead of this page"><input type="checkbox" data-change="ask-link" data-person="${esc(p)}" ${a.deep_link ? "checked" : ""}> Open in their app</label></li>`;
      })
      .join("")}</ul>`;
  }

  _familyTab() {
    const cfg = this._config;
    const roles = cfg.roles || {};
    return `<section class="card">
        <h3><ha-icon icon="mdi:account-group"></ha-icon>Who's who</h3>
        <p class="muted">Kids get limits and rules. Adults get a parent PIN and see everything here.</p>
        <ul class="list">${(cfg.persons || [])
          .map((p) => `<li>${this._avatar(p.id, 32)}<div class="grow">${esc(p.name)}</div>
            <div class="segmented" role="group" aria-label="${esc(p.name)}">
              ${[["kid", "Kid"], ["adult", "Adult"], ["", "Not in Hearth"]]
                .map(([v, label]) => `<button class="${(roles[p.id] || "") === v ? "on" : ""}" data-action="role" data-person="${esc(p.id)}" data-role="${v}">${label}</button>`)
                .join("")}
            </div></li>`)
          .join("")}</ul>
      </section>
      ${this._pinsCard()}
      ${this._sharingCard()}
      ${this._voiceCard()}
      ${this._schoolCard()}
      ${this._placesCard()}
      <section class="card">
        <h3><ha-icon icon="mdi:cog-outline"></ha-icon>More settings</h3>
        <p class="muted">Titles with a limit of their own are still in the integration's Configure menu.</p>
        <button class="btn" data-action="advanced">Open Hearth in Devices & services</button>
      </section>`;
  }

  _pinsCard() {
    const adults = this._adults();
    const set = new Set(this._config.parent_pins || []);
    return `<section class="card">
      <h3><ha-icon icon="mdi:dialpad"></ha-icon>Parent PINs</h3>
      <p class="muted">Each adult's own 4 digits. Any of them unlocks a parent's settings on the TVs and kids' phones. TVs keep them, so they work while Home Assistant is down. Make it the same as your Google TV profile PIN if you like.</p>
      ${adults.length ? `<ul class="list">${adults
        .map((a) => `<li class="pin-row">${this._avatar(a.id, 32)}<div class="grow"><div>${esc(a.name)}</div><div class="muted small">${set.has(a.id) ? "Set" : "Not set"}</div></div>
          <input id="pin-${esc(a.id)}" type="password" inputmode="numeric" maxlength="4" pattern="[0-9]*" placeholder="PIN" autocomplete="off">
          <input id="pin-again-${esc(a.id)}" type="password" inputmode="numeric" maxlength="4" pattern="[0-9]*" placeholder="Again" autocomplete="off" data-enter="pin-save" data-person="${esc(a.id)}">
          <button class="btn primary" data-action="pin-save" data-person="${esc(a.id)}">${set.has(a.id) ? "Change" : "Set"}</button>
          ${set.has(a.id) ? `<button class="icon-btn" data-action="pin-remove" data-person="${esc(a.id)}" aria-label="Remove"><ha-icon icon="mdi:delete-outline"></ha-icon></button>` : ""}</li>`)
        .join("")}</ul>` : `<p class="muted small">Mark the adults above first.</p>`}
    </section>`;
  }

  _voiceCard() {
    const on = !!this._config.voice_assistants;
    return `<section class="card">
      <h3><ha-icon icon="mdi:microphone-outline"></ha-icon>Voice assistants</h3>
      <p class="muted">Lets an Assist voice pipeline with Hearth among its LLM APIs answer questions about screen time. Anything it would change (more time, a pause, an allow) goes to the adults' phones first and runs only when one of you taps Allow. Off: voice gets nothing from Hearth.</p>
      <label class="check"><input type="checkbox" data-change="voice-assistants" ${on ? "checked" : ""}> Let voice assistants use Hearth</label>
    </section>`;
  }

  _sharingCard() {
    const kids = this._kids();
    const on = new Set(this._config.tile_exchange || []);
    return `<section class="card">
      <h3><ha-icon icon="mdi:share-variant-outline"></ha-icon>Glint tile sharing</h3>
      <p class="muted">Lets a kid's phone share the layout of notifications from apps with no tile yet, every word and number blanked out (never chats, health or payments), so Glint can learn new tiles.</p>
      <div class="checks">${kids
        .map((k) => `<label class="check"><input type="checkbox" data-change="tile-share" data-person="${esc(k.id)}" ${on.has(k.id) ? "checked" : ""}> ${esc(k.name)}</label>`)
        .join("") || `<span class="muted small">No kids yet.</span>`}</div>
    </section>`;
  }

  _placesOption() {
    const p = this._config.places || {};
    return { school: { ...(p.school || {}) }, trackers: { ...(p.trackers || {}) }, favorites: [...(p.favorites || [])] };
  }

  // How an exception that ends on a place reads: "until arriving home", "until leaving school"
  _endsOn(e) {
    if (!e) return "";
    const place = e.place && !["Home", "School"].includes(e.place) ? e.place : (e.place || "").toLowerCase();
    return e.arrive ? `arriving ${e.arrive === "home" ? "home" : `at ${place}`}` : `leaving ${place}`;
  }

  _placesCard() {
    const p = this._config.places || {};
    const zones = (this._config.zones || []).map((z) => ({ value: z.entity_id, label: `${z.name} (${z.entity_id})` }));
    const trackers = this._config.choices?.location || [];
    const kids = this._kids();
    return `<section class="card">
      <h3><ha-icon icon="mdi:map-marker-outline"></ha-icon>Places</h3>
      <p class="muted">Places are Home Assistant zones. Hearth keeps no coordinates and shows only the place's name, from each kid's Family Link location (or their person in Home Assistant when it's older than 20 minutes). Home is always your home zone. A Wi-Fi or router tracker is never used.</p>
      ${kids.length ? `<ul class="list">${kids
        .map((k) => `<li class="wrap">${this._avatar(k.id, 32)}<div class="grow">${esc(k.name)}</div>
          <select id="place-school-${esc(k.id)}" aria-label="${esc(k.name)}'s school">${this._options(zones, p.school?.[k.id], "School: none")}</select>
          <select id="place-tracker-${esc(k.id)}" aria-label="${esc(k.name)}'s Family Link location">${this._entityOptions(trackers, p.trackers?.[k.id], "Family Link location: found by Hearth")}</select>
          <button class="btn" data-action="place-save" data-person="${esc(k.id)}">Save</button></li>`)
        .join("")}</ul>` : `<p class="muted small">No kids yet.</p>`}
      <div class="strong">Favorite places</div>
      ${(p.favorites || []).length ? `<ul class="list">${p.favorites
        .map((f) => `<li><div class="grow">${esc(f.name)} <span class="muted small">${esc(f.key)} · ${esc(this._entityName(f.zone))}</span></div>
          <button class="icon-btn" data-action="place-fav-remove" data-key="${esc(f.key)}" aria-label="Remove"><ha-icon icon="mdi:delete-outline"></ha-icon></button></li>`)
        .join("")}</ul>` : `<p class="muted small">None yet.</p>`}
      <div class="row wrap">
        <select id="place-fav-zone" aria-label="Zone">${this._options(zones, "", "Zone")}</select>
        <input id="place-fav-name" placeholder="Name, e.g. Practice" maxlength="40">
        <button class="btn primary" data-action="place-fav-add">Add</button>
      </div>
    </section>`;
  }

  _schoolCard() {
    const s = this._config.school_days || {};
    const input = (f, label, placeholder = "", type = "text") =>
      `<label class="field">${label}<input id="school-${f}" type="${type}" value="${esc(s[f] || "")}" placeholder="${esc(placeholder)}"></label>`;
    const area = (f, label, placeholder) =>
      `<label class="field">${label}<textarea id="school-${f}" rows="3" placeholder="${esc(placeholder)}">${esc(s[f] || "")}</textarea></label>`;
    return `<section class="card">
      <h3><ha-icon icon="mdi:school-outline"></ha-icon>School days</h3>
      <p class="muted">Which budget applies today. The first that answers decides: the dates below, then the entity, then the calendar, then Monday to Friday within the school year.</p>
      <div class="form two">
        ${input("year_start", "School year starts", "", "date")}
        ${input("year_end", "School year ends", "", "date")}
        ${area("days_off", "Days off (one per line, or a range like 2026-12-21..2027-01-02)", "2026-11-26")}
        ${area("extra_school_days", "Extra school days", "")}
        ${area("half_days", "Half days (school ends early)", "2026-11-25")}
        <label class="field">A half day takes<select id="school-half_day_budget">
          <option value="other_days" ${s.half_day_budget !== "school_days" ? "selected" : ""}>The other-day budget</option>
          <option value="school_days" ${s.half_day_budget === "school_days" ? "selected" : ""}>The school-day budget</option></select></label>
        ${input("entity", "An entity that says it's a school day (optional)", "input_boolean.school_day")}
        ${input("school_states", "Its school-day states", "on, school")}
        ${input("half_states", "Its half-day states", "half, half_day")}
        ${input("calendar", "A calendar (optional)", "calendar.school")}
        <label class="field">Its events are<select id="school-calendar_mode">
          <option value="off_days" ${s.calendar_mode !== "school_days" ? "selected" : ""}>Days off</option>
          <option value="school_days" ${s.calendar_mode === "school_days" ? "selected" : ""}>School days</option></select></label>
        ${input("keywords", "Only events with these words (days off)", "closed, break, holiday")}
        ${input("half_keywords", "Events with these words are half days", "early dismissal, half day")}
      </div>
      <div class="actions"><button class="btn primary" data-action="school-save">Save</button></div>
    </section>`;
  }

  // Guided setup

  _setup() {
    const step = SETUP_STEPS[this._setupStep] || SETUP_STEPS[0];
    const nav = `<ol class="stepper">${SETUP_STEPS.map(
      (s, i) => `<li class="${i === this._setupStep ? "on" : i < this._setupStep ? "done" : ""}"><span>${i < this._setupStep ? "✓" : i + 1}</span>${esc(s.title)}</li>`
    ).join("")}</ol>`;
    const body = {
      welcome: () => `<h2>Set up Hearth</h2>
        <p>Hearth keeps the family's screen time in one place, across TVs, phones, consoles and computers. This takes a few minutes, and everything can be changed later in the tabs.</p>
        <div class="features">
          <div class="feature"><ha-icon icon="mdi:timer-sand"></ha-icon><div class="strong">One daily limit everywhere</div><div class="muted small">Time on every device adds up; music and the like can stay outside it.</div></div>
          <div class="feature"><ha-icon icon="mdi:lock-clock"></ha-icon><div class="strong">Holds apps when time's up</div><div class="muted small">On Hearth's TVs and phones, and through Family Link, Family Safety and Nintendo.</div></div>
          <div class="feature"><ha-icon icon="mdi:plus-circle-outline"></ha-icon><div class="strong">More time in a tap</div><div class="muted small">From here, a dashboard, an automation or your voice.</div></div>
          <div class="feature"><ha-icon icon="mdi:dialpad"></ha-icon><div class="strong">A parent PIN each</div><div class="muted small">Works on every TV, even when Home Assistant is down.</div></div>
        </div>`,
      people: () => `<h2>Who's who</h2><p class="muted">Kids get limits. Adults get a parent PIN.</p>${this._familyTab().split("</section>")[0]}</section>`,
      pins: () => `<h2>Parent PINs</h2>${this._pinsCard()}`,
      devices: () => `<h2>TVs and phones</h2>${this._devicesTab()}`,
      screen: () => {
        const kids = this._kids();
        const kid = kids.find((k) => k.id === this._kid) || kids[0];
        return `<h2>Where screen time comes from</h2>${kid ? `${this._kidPicker()}${this._sourcesCard(kid)}${this._locksCard(kid)}` : `<p class="muted">Mark a kid first.</p>`}`;
      },
      limits: () => {
        const kids = this._kids();
        const kid = kids.find((k) => k.id === this._kid) || kids[0];
        return `<h2>Daily limits</h2>${kid ? `${this._kidPicker()}${this._limitsCard(kid)}${this._enforceCard(kid)}` : `<p class="muted">Mark a kid first.</p>`}`;
      },
      done: () => `<h2>All set</h2><p>The Today tab shows each kid's time left, what's playing and anything waiting for you, with buttons for extra time.</p>
        <p class="muted">Tip: Hearth's entities (Hearth: <i>name</i>) work on any dashboard and in automations too, and the time-left sensors are good for a voice assistant.</p>`,
    }[step.id]();
    const last = this._setupStep === SETUP_STEPS.length - 1;
    return `<div class="setup">${nav}<div class="setup-body">${body}</div>
      <div class="actions sticky">
        <button class="btn" data-action="setup-close">${last ? "Close" : "Skip setup"}</button>
        <div class="spacer"></div>
        ${this._setupStep > 0 ? `<button class="btn" data-action="setup-back">Back</button>` : ""}
        ${last ? `<button class="btn primary" data-action="setup-close">Go to Today</button>` : `<button class="btn primary" data-action="setup-next">${this._setupStep === 0 ? "Start" : "Next"}</button>`}
      </div></div>`;
  }
}

const STYLE = `
:host { display: block; min-height: 100vh; background: var(--primary-background-color); color: var(--primary-text-color);
  font-family: var(--paper-font-body1_-_font-family, Roboto, system-ui, sans-serif); --gap: 16px; --radius: var(--ha-card-border-radius, 12px); }
* { box-sizing: border-box; }
.toolbar { display: flex; align-items: center; gap: 12px; height: 56px; padding: 0 16px; background: var(--app-header-background-color, var(--primary-color));
  color: var(--app-header-text-color, var(--text-primary-color, #fff)); position: sticky; top: 0; z-index: 3; }
.toolbar .title { font-size: 20px; font-weight: 400; }
.toolbar .sub { opacity: .75; font-size: 14px; margin-left: 6px; }
.toolbar .logo { --mdc-icon-size: 26px; }
.toolbar .text-btn { color: inherit; }
.spacer, .grow { flex: 1; min-width: 0; }
.tabs { display: flex; gap: 4px; padding: 0 12px; background: var(--app-header-background-color, var(--primary-color)); overflow-x: auto; position: sticky; top: 56px; z-index: 2; scrollbar-width: none; }
.tab { display: flex; align-items: center; gap: 6px; padding: 10px 14px; border: 0; background: none; color: var(--app-header-text-color, #fff); opacity: .72;
  font: inherit; font-size: 14px; cursor: pointer; border-bottom: 3px solid transparent; white-space: nowrap; position: relative; }
.tab.on { opacity: 1; border-bottom-color: var(--app-header-text-color, #fff); }
.tab ha-icon { --mdc-icon-size: 20px; }
.badge { background: var(--error-color, #db4437); color: #fff; border-radius: 10px; font-size: 11px; padding: 1px 6px; }
.content { max-width: 1100px; margin: 0 auto; padding: var(--gap); }
.loading { padding: 48px; text-align: center; color: var(--secondary-text-color); }
h2 { font-size: 18px; font-weight: 500; margin: 20px 4px 10px; }
h3 { display: flex; align-items: center; gap: 8px; font-size: 16px; font-weight: 500; margin: 0 0 8px; }
h3 ha-icon { color: var(--primary-color); --mdc-icon-size: 22px; }
p { margin: 6px 0 12px; line-height: 1.45; }
.muted { color: var(--secondary-text-color); }
.small { font-size: 12px; }
.strong { font-weight: 500; }
.card { background: var(--ha-card-background, var(--card-background-color, #fff)); border-radius: var(--radius); padding: 16px;
  box-shadow: var(--ha-card-box-shadow, 0 1px 3px rgba(0,0,0,.12)); border: var(--ha-card-border-width, 1px) solid var(--ha-card-border-color, var(--divider-color, transparent));
  margin-bottom: var(--gap); }
.card.attention { border-color: var(--warning-color, #ffa600); border-width: 2px; }
.card.ask.focus { box-shadow: 0 0 0 3px var(--primary-color, #03a9f4); }
.card.pause { padding: 12px 16px; }
.card.pause.on { border-color: var(--primary-color); border-width: 2px; }
.card.pause ha-icon { color: var(--primary-color); }
.card.pause input { min-width: 160px; flex: 1; }
.row.wrap { flex-wrap: wrap; }
.card.empty { text-align: center; padding: 32px 16px; }
.card.empty ha-icon { --mdc-icon-size: 48px; color: var(--secondary-text-color); }
.card.dim { opacity: .6; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: var(--gap); }
.grid .card { margin: 0; }
.grid.devices { grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); }
.row { display: flex; align-items: center; gap: 12px; }
.kid-head { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
.kid .name { font-size: 18px; font-weight: 500; }
.avatar { border-radius: 50%; object-fit: cover; flex: none; }
.avatar.initials { display: flex; align-items: center; justify-content: center; background: var(--primary-color); color: var(--text-primary-color, #fff); font-weight: 500; }
.kid-main { display: flex; flex-direction: column; gap: 10px; }
.left-now { font-size: 17px; font-weight: 500; white-space: nowrap; }
.kid-rows { padding: 4px 8px; }
.kid-row { display: flex; align-items: center; gap: 10px; padding: 8px; border-radius: 10px; cursor: pointer; border-left: 4px solid var(--role); }
.kid-row + .kid-row { margin-top: 2px; }
.kid-row:hover, .kid-row.on { background: rgba(var(--rgb-primary-color, 3, 169, 244), .08); }
.kid-row:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
.kid-row .row-bar { width: 96px; flex: none; }
.kid-row .grow { min-width: 0; }
.kid-row .grow > div { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.p0 { --pool: #0f6b74; } .p1 { --pool: #b85c00; } .p2 { --pool: #6a4c93; } .p3 { --pool: #2d7a3e; } .p4 { --pool: #c2185b; } .p5 { --pool: #1565c0; }
.other { --pool: var(--disabled-text-color, #9e9e9e); }
.allbar-head { display: flex; align-items: baseline; gap: 6px; }
.all-track { position: relative; height: 16px; margin: 6px 0 4px; border-radius: 4px; background: var(--divider-color, #e0e0e0); }
.all-track .seg { position: absolute; top: 0; bottom: 0; background: var(--pool, var(--role)); }
.all-track .seg.whole { background: var(--role, var(--primary-color)); }
.all-track .bonus { position: absolute; top: 0; bottom: 0; background: repeating-linear-gradient(45deg, transparent 0 3px, var(--role, var(--primary-color)) 3px 5px); opacity: .6; }
.limit { position: absolute; top: -4px; bottom: -4px; width: 2px; margin-left: -1px; background: var(--primary-text-color); }
.legend { display: flex; flex-wrap: wrap; gap: 4px 12px; color: var(--secondary-text-color); }
.legend .dot { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 4px; background: var(--pool); }
.lane { display: grid; grid-template-columns: 80px 1fr auto; gap: 8px; align-items: center; margin: 6px 0; font-size: 13px; }
.lane-track { position: relative; height: 6px; border-radius: 3px; background: var(--divider-color, #e0e0e0); }
.lane-fill { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px; background: var(--pool); }
.lane.role-out .lane-fill { background: var(--error-color, #db4437); }
.lane .limit { top: -3px; bottom: -3px; }
.strip-track { position: relative; height: 34px; border-radius: 6px; background: var(--divider-color, #e0e0e0); overflow: hidden; }
.strip-track .night { position: absolute; top: 0; bottom: 0; background: var(--primary-text-color); opacity: .7; }
.strip-track .school { position: absolute; top: 0; bottom: 0; background: repeating-linear-gradient(45deg, transparent 0 4px, rgba(var(--rgb-primary-text-color, 128, 128, 128), .35) 4px 6px); }
.strip-track .use { position: absolute; bottom: 0; background: var(--accent-color, var(--primary-color)); border-radius: 2px 2px 0 0; box-shadow: inset 1px 0 0 var(--card-background-color, #fff); }
.strip-track .now { position: absolute; top: 0; bottom: 0; width: 2px; margin-left: -1px; background: var(--error-color, #db4437); }
.strip-x { position: relative; height: 16px; font-size: 10px; color: var(--secondary-text-color); }
.strip-x span { position: absolute; transform: translateX(-50%); }
.strip-x span:first-child { transform: none; }
.strip-x span:last-child { transform: translateX(-100%); }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 8px; }
.tile { display: flex; gap: 8px; align-items: flex-start; padding: 8px 10px; border: 1px solid var(--divider-color, #e0e0e0); border-radius: 10px; min-width: 0; }
.tile .grow { min-width: 0; }
.tile.locked { border-color: var(--warning-color, #ffa600); }
.tile ha-icon { --mdc-icon-size: 20px; color: var(--secondary-text-color); }
.bar-row { display: grid; grid-template-columns: 80px 1fr auto; gap: 8px; align-items: center; margin: 6px 0; font-size: 13px; }
.bar-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.bar { height: 6px; border-radius: 3px; background: var(--divider-color, #e0e0e0); overflow: hidden; }
.bar > div { height: 100%; background: var(--role, var(--primary-color)); border-radius: 3px; }
.bar.out > div { background: var(--error-color, #db4437); }
.bar-value { color: var(--secondary-text-color); font-size: 12px; white-space: nowrap; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0; }
.chip { display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; border-radius: 14px; font-size: 12px;
  background: var(--secondary-background-color, #eee); color: var(--primary-text-color); }
.chip ha-icon { --mdc-icon-size: 14px; }
p.warn { color: var(--warning-color, #ffa600); }
.chip.warn { background: color-mix(in srgb, var(--warning-color, #ffa600) 22%, transparent); }
.chip.out { background: color-mix(in srgb, var(--error-color, #db4437) 20%, transparent); }
.chip.play { background: color-mix(in srgb, var(--success-color, #43a047) 20%, transparent); }
.chip.small { padding: 1px 6px; font-size: 11px; }
.chip.dim { opacity: .6; }
.native { margin-top: 8px; display: flex; flex-direction: column; gap: 2px; }
.device-limits summary { font-size: 13px; margin-top: 4px; }
.device-limits > div { padding-left: 16px; }
.small-controls { margin-top: 4px; }
.small-controls select { min-height: 30px; padding: 3px 8px; font-size: 12px; }
.today-detail .bar-row { grid-template-columns: 120px 1fr auto; }
.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 10px; margin: 10px 0; }
.card .row.wrap + .row.wrap { margin-top: 8px; }
.warn-text { color: var(--warning-color, #b26a00); }
.error-text { color: var(--error-color, #db4437); }
.chip .x { border: 0; background: none; color: var(--secondary-text-color); cursor: pointer; font-size: 15px; padding: 0 0 0 4px; line-height: 1; }
.actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 12px; align-items: center; }
.actions.wrap { flex-wrap: wrap; }
.btn { font: inherit; font-size: 14px; font-weight: 500; padding: 8px 16px; border-radius: 18px; cursor: pointer; min-height: 36px;
  border: 1px solid var(--divider-color, #ccc); background: transparent; color: var(--primary-color); }
.btn.primary { background: var(--primary-color); color: var(--text-primary-color, #fff); border-color: var(--primary-color); }
.btn:hover { filter: brightness(1.08); }
.btn:focus-visible, .icon-btn:focus-visible, .tab:focus-visible, .pill:focus-visible, .chip-btn:focus-visible, .segmented button:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
.icon-btn { border: 0; background: none; color: inherit; cursor: pointer; padding: 6px; border-radius: 50%; display: inline-flex; }
.icon-btn:hover { background: var(--secondary-background-color, rgba(0,0,0,.06)); }
.text-btn { display: inline-flex; align-items: center; gap: 6px; border: 0; background: none; cursor: pointer; font: inherit; font-size: 14px; padding: 6px 10px; border-radius: 16px; }
.text-btn:hover { background: rgba(255,255,255,.12); }
.link { border: 0; background: none; color: var(--primary-color); cursor: pointer; font: inherit; font-size: 13px; padding: 4px 0; }
.chip-btn { border: 1px solid var(--divider-color, #ccc); background: none; color: var(--primary-text-color); border-radius: 14px; padding: 3px 10px; font: inherit; font-size: 12px; cursor: pointer; }
.chip-btn:hover { border-color: var(--primary-color); color: var(--primary-color); }
.presets { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin-bottom: 10px; font-size: 13px; color: var(--secondary-text-color); }
.pills { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: var(--gap); }
.pill { display: inline-flex; align-items: center; gap: 8px; padding: 4px 14px 4px 4px; border-radius: 20px; border: 1px solid var(--divider-color, #ccc);
  background: var(--card-background-color, #fff); color: var(--primary-text-color); font: inherit; cursor: pointer; }
.pill.on { border-color: var(--primary-color); box-shadow: inset 0 0 0 1px var(--primary-color); }
table.limits { width: 100%; border-collapse: collapse; }
table.limits th { text-align: left; font-weight: 500; font-size: 12px; color: var(--secondary-text-color); padding: 6px 4px; }
table.limits td { padding: 6px 4px; border-top: 1px solid var(--divider-color, #eee); }
input, select, textarea { font: inherit; font-size: 14px; color: var(--primary-text-color); background: var(--input-fill-color, var(--secondary-background-color, #f5f5f5));
  border: 1px solid var(--input-idle-line-color, var(--divider-color, #ccc)); border-radius: 8px; padding: 8px 10px; min-height: 38px; max-width: 100%; }
input:focus, select:focus, textarea:focus { outline: none; border-color: var(--primary-color); box-shadow: 0 0 0 1px var(--primary-color); }
table.limits input { width: 96px; }
.minutes { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }
.filter { width: 100%; margin-bottom: 8px; }
ul.list select { max-width: 45%; }
.inline { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-top: 8px; }
.inline input { flex: 1; min-width: 160px; }
.form { display: grid; gap: 12px; margin-top: 10px; }
.form.two { grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); align-items: start; }
.field { display: grid; gap: 4px; font-size: 13px; color: var(--secondary-text-color); }
.field select, .field input, .field textarea { color: var(--primary-text-color); width: 100%; }
.check { display: inline-flex; align-items: center; gap: 6px; font-size: 14px; cursor: pointer; }
.checks { display: flex; flex-wrap: wrap; gap: 6px 16px; }
details summary { cursor: pointer; color: var(--primary-color); font-size: 14px; margin-top: 8px; }
ul.list { list-style: none; margin: 0; padding: 0; }
ul.list li { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid var(--divider-color, #eee); }
ul.list li:first-child { border-top: 0; }
ul.list.compact li { padding: 6px 0; }
ul.list ha-icon { color: var(--secondary-text-color); }
.pin-row input { width: 76px; text-align: center; letter-spacing: 4px; }
.segmented { display: inline-flex; border: 1px solid var(--divider-color, #ccc); border-radius: 18px; overflow: hidden; }
.segmented button { border: 0; background: none; font: inherit; font-size: 13px; padding: 6px 12px; cursor: pointer; color: var(--primary-text-color); }
.segmented button + button { border-left: 1px solid var(--divider-color, #ccc); }
.segmented button.on { background: var(--primary-color); color: var(--text-primary-color, #fff); }
.dot { width: 10px; height: 10px; border-radius: 50%; flex: none; background: var(--disabled-text-color, #bbb); }
.dot.on { background: var(--success-color, #43a047); }
.dot.idle { background: var(--warning-color, #ffa600); }
.code { font-family: var(--code-font-family, monospace); font-size: 18px; letter-spacing: 3px; font-weight: 600; color: var(--primary-text-color); }
.cols { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; }
ol.steps { margin: 0; padding-left: 20px; line-height: 1.7; }
.toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); background: var(--primary-text-color, #222); color: var(--primary-background-color, #fff);
  padding: 10px 18px; border-radius: 8px; font-size: 14px; box-shadow: 0 4px 12px rgba(0,0,0,.3); z-index: 10; max-width: calc(100% - 32px); }
.setup { max-width: 860px; margin: 0 auto; }
.stepper { display: flex; gap: 4px; list-style: none; padding: 0; margin: 4px 0 16px; overflow-x: auto; }
.stepper li { display: flex; align-items: center; gap: 6px; font-size: 13px; color: var(--secondary-text-color); white-space: nowrap; padding: 6px 10px; border-radius: 16px; }
.stepper li span { display: inline-flex; width: 22px; height: 22px; border-radius: 50%; align-items: center; justify-content: center; font-size: 12px;
  background: var(--divider-color, #ddd); color: var(--primary-text-color); }
.stepper li.on { color: var(--primary-text-color); background: var(--secondary-background-color, #eee); font-weight: 500; }
.stepper li.on span, .stepper li.done span { background: var(--primary-color); color: var(--text-primary-color, #fff); }
.setup-body { min-height: 300px; }
.features { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 12px; margin-top: 16px; }
.feature { background: var(--ha-card-background, var(--card-background-color, #fff)); border-radius: var(--radius); padding: 16px; display: grid; gap: 6px;
  border: 1px solid var(--divider-color, #e0e0e0); }
.feature ha-icon { color: var(--primary-color); --mdc-icon-size: 28px; }
.actions.sticky { position: sticky; bottom: 0; background: var(--primary-background-color); padding: 12px 0; border-top: 1px solid var(--divider-color, #eee); }
/* Color roles (spec section 4): the summary's state picks the role, the theme picks the hue */
.role-ok { --role: var(--success-color, #43a047); }
.role-low { --role: var(--warning-color, #ffa600); }
.role-out { --role: var(--error-color, #db4437); }
.role-allowed { --role: var(--info-color, #039be5); }
.role-paused { --role: var(--primary-color, #03a9f4); }
.role-locked { --role: var(--state-icon-color, #44739e); }
.role-held { --role: var(--purple-color, #926bc7); }
.role-none { --role: var(--disabled-text-color, #9e9e9e); }
.card.kid { border-left: 4px solid var(--role); }
.used { display: flex; align-items: baseline; gap: 4px; flex-wrap: wrap; }
.big-num { font-size: 26px; font-weight: 600; letter-spacing: -.5px; }
.day-line { display: flex; align-items: center; gap: 6px; font-size: 14px; margin: 2px 0 8px; }
.dot-role { width: 8px; height: 8px; border-radius: 50%; background: var(--role); flex: none; }
.lvl-notice { font-weight: 500; }
.lvl-urgent { font-weight: 700; }
.bar-row.unlimited { opacity: .55; }
.tag { display: inline-block; font-size: 11px; font-weight: 600; padding: 0 5px; margin-right: 4px; border-radius: 8px;
  background: color-mix(in srgb, var(--success-color, #43a047) 22%, transparent); color: var(--primary-text-color); }
.card.suggested { min-height: 112px; }
.card.suggested.lvl-urgent { border-color: var(--warning-color, #ffa600); border-width: 2px; }
.suggested .headline { font-size: 16px; margin-bottom: 4px; }
.suggested.lvl-urgent .headline { font-weight: 600; }
.suggested-items .item { padding: 10px 0; border-top: 1px solid var(--divider-color, #eee); }
.suggested-items .item .actions { margin-top: 8px; }
.item.ask.focus { box-shadow: 0 0 0 3px var(--primary-color, #03a9f4); border-radius: 8px; padding: 10px; }
.item.sugg { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.item.sugg .actions { margin-top: 0; }
details.more { position: relative; }
details.more summary { list-style: none; margin: 0; padding: 8px 12px; border: 1px solid var(--divider-color, #ccc); border-radius: 18px; font-size: 14px; }
details.more summary::-webkit-details-marker { display: none; }
.more-menu { position: absolute; right: 0; bottom: calc(100% + 6px); z-index: 2; display: flex; flex-direction: column; gap: 6px; padding: 8px; min-width: 170px;
  background: var(--ha-card-background, var(--card-background-color, #fff)); border: 1px solid var(--divider-color, #ccc); border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,.2); }
.chip-btn.on { border-color: var(--primary-color); background: var(--primary-color); color: var(--text-primary-color, #fff); }
.week { margin-top: 12px; }
.week-head { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; font-size: 14px; margin-bottom: 6px; }
.wk-plot { display: grid; grid-template-columns: auto 1fr; column-gap: 6px; }
.wk-y { display: flex; flex-direction: column; justify-content: space-between; font-size: 10px; font-weight: 600; text-align: right; height: 96px; margin-top: 14px; }
.wk-y span { line-height: 0; }
.wk-cols { display: flex; gap: 3px; }
.wk-col { flex: 1; display: flex; flex-direction: column; align-items: stretch; border: 0; background: none; padding: 0; font: inherit; color: inherit; cursor: pointer; border-radius: 6px; }
.wk-col:hover .wk-bar, .wk-col.on .wk-bar { filter: brightness(1.2); }
.wk-col.on { background: var(--secondary-background-color, rgba(0,0,0,.05)); }
.wk-col:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 1px; }
.wk-tag { display: block; height: 14px; font-size: 10px; font-weight: 600; text-align: center; color: var(--success-color, #43a047); }
.wk-area { display: block; position: relative; height: 96px; }
.wk-area i { position: absolute; left: 0; right: 0; border-top: 1px dashed rgba(var(--rgb-primary-text-color, 128, 128, 128), .2); }
.wk-bar { position: absolute; bottom: 0; left: 12%; right: 12%; border-radius: 4px 4px 0 0; background: var(--accent-color, var(--primary-color)); }
.wk-bar.none { height: 100%; opacity: .5; background: repeating-linear-gradient(45deg, var(--divider-color, #ccc) 0 3px, transparent 3px 7px); }
.wk-tick { position: absolute; left: 0; right: 0; border-top: 2px solid var(--primary-text-color); opacity: .55; }
.wk-dot { display: block; width: 6px; height: 6px; border-radius: 50%; margin: 4px auto 2px; }
.wk-dot.out { background: var(--error-color, #db4437); }
.wk-x { display: block; font-size: 10px; font-weight: 600; text-align: center; white-space: nowrap; }
.wk-detail { margin-top: 6px; }
.plot { display: grid; grid-template-columns: auto 1fr; grid-template-rows: 120px auto; column-gap: 6px; margin-top: 8px; }
.hy { display: flex; flex-direction: column; justify-content: space-between; white-space: nowrap; font-size: 10px; font-weight: 600; text-align: right; margin: -6px 0; }
.harea { position: relative; }
.harea i { position: absolute; left: 0; right: 0; border-top: 1px dashed rgba(var(--rgb-primary-text-color, 128, 128, 128), .2); }
.hcols { position: absolute; inset: 0; display: flex; gap: 3px; align-items: flex-end; }
.hcol { flex: 1; height: 100%; display: flex; align-items: flex-end; }
.hcol div { width: 100%; border-radius: 4px 4px 0 0; background: var(--accent-color, var(--primary-color)); }
.hx { display: flex; gap: 3px; font-size: 10px; font-weight: 600; margin-top: 6px; }
.hx span { flex: 1; text-align: center; white-space: nowrap; }
.card.pools .pool + .pool { margin-top: 12px; }
@media (max-width: 600px) {
  .content { padding: 12px; }
  .grid { grid-template-columns: 1fr; }
  .kid-row .row-bar { width: 56px; }
  .tab span:not(.badge) { display: none; }
  .tab { padding: 10px 12px; }
  table.limits input { width: 92px; }
  .pin-row { flex-wrap: wrap; }
  .toolbar .text-btn span { display: none; }
}
`;

customElements.define("hearth-panel", HearthPanel);
