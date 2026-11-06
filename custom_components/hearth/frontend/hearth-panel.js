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

const fmtMinutes = (minutes) => {
  if (minutes === null || minutes === undefined) return "No limit";
  const m = Math.max(0, Math.round(minutes));
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r ? `${h} h ${r} min` : `${h} h`;
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
      case "kid":
        this._kid = d.kid;
        if (d.go) this._tab = d.go;
        this._render();
        this._loadWatch(d.kid);
        return;
      case "bonus":
        await this._service(
          "add_bonus",
          { person: d.person, minutes: Number(d.minutes), group: d.group || "all" },
          `${Number(d.minutes) > 0 ? "Added" : "Took"} ${Math.abs(Number(d.minutes))} min ${Number(d.minutes) > 0 ? "for" : "from"} ${this._personName(d.person)}`
        );
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
        if (fl) kept.push({ kind: "family_link", person, entity_id: fl });
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
        const fields = ["entity", "school_states", "calendar", "calendar_mode", "keywords", "year_start", "year_end", "days_off", "extra_school_days"];
        const value = {};
        for (const f of fields) {
          const v = this._value(`#school-${f}`);
          value[f] = v || null;
        }
        await this._setOption("school_days", value, "School days saved");
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
    }
    if (focusId) {
      const again = root.getElementById(focusId);
      if (again) {
        again.focus();
        if (focusValue !== null && again.value !== focusValue && again.tagName === "INPUT") again.value = focusValue;
      }
    }
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

  _ring(left, budget) {
    const pct = budget ? Math.max(0, Math.min(1, left / budget)) : 1;
    const r = 34;
    const c = 2 * Math.PI * r;
    const tone = budget === null || budget === undefined ? "none" : left <= 0 ? "out" : left <= 15 ? "low" : "ok";
    return `<svg class="ring ${tone}" viewBox="0 0 80 80" aria-hidden="true">
      <circle class="track" cx="40" cy="40" r="${r}"></circle>
      <circle class="fill" cx="40" cy="40" r="${r}" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - pct)}"></circle>
    </svg>`;
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

  _today() {
    const kids = this._kids();
    const devices = this._summary?.devices || [];
    const parts = [this._pauseBar(), this._askCards(), this._pairingCards()];
    if (!kids.length) {
      parts.push(`<div class="card empty"><ha-icon icon="mdi:account-child-outline"></ha-icon>
        <p>No kids in Hearth yet. The guided setup takes a few minutes.</p>
        <button class="btn primary" data-action="setup-open">Start the guided setup</button></div>`);
    }
    parts.push(`<div class="grid">${kids.map((k) => this._kidCard(k)).join("")}</div>`);
    if (devices.length) {
      parts.push(`<h2>TVs and phones</h2><div class="grid devices">${devices.map((dv) => this._deviceCard(dv)).join("")}</div>`);
    }
    return parts.join("");
  }

  _askCards() {
    const asks = (this._summary?.approvals || []).filter((a) => a.type === "more_time");
    return asks
      .map(
        (a) => `<div class="card attention ask">
        <div class="row">${this._avatar(a.person, 36)}<div class="grow">
          <div class="strong">${esc(a.person_name)} asks for ${a.minutes} more minutes${a.group && a.group !== "all" ? ` of ${esc(this._groupName(a.group))}` : ""}</div>
          ${a.note ? `<div class="muted">“${esc(a.note)}”</div>` : ""}</div></div>
        <div class="actions wrap">
          <button class="btn" data-action="answer" data-request="${esc(a.id)}" data-deny="1">Not now</button>
          ${[15, 30, 45, 60]
            .map((m) => `<button class="btn ${m === a.minutes ? "primary" : ""}" data-action="answer" data-request="${esc(a.id)}" data-minutes="${m}">+${m} min</button>`)
            .join("")}
        </div></div>`
      )
      .join("");
  }

  _pauseBar() {
    const paused = (this._summary?.people || []).filter((p) => p.pause);
    if (paused.length) {
      const p = paused[0].pause;
      const until = new Date(p.until).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      return `<div class="card pause on"><div class="row"><ha-icon icon="mdi:silverware-fork-knife"></ha-icon>
        <div class="grow"><div class="strong">${esc(p.reason || "Paused")} until ${esc(until)}</div>
        <div class="muted small">${esc(paused.map((x) => x.name).join(", "))}: their Hearth TVs and phones are on hold.</div></div>
        <button class="btn primary" data-action="pause-end">End pause</button></div></div>`;
    }
    return `<div class="card pause"><div class="row wrap"><ha-icon icon="mdi:pause-circle-outline"></ha-icon>
      <div class="grow strong">Pause everyone</div>
      <select id="pause-minutes" aria-label="How long">${[15, 30, 45, 60, 90].map((m) => `<option value="${m}" ${m === 45 ? "selected" : ""}>${fmtMinutes(m)}</option>`).join("")}</select>
      <input id="pause-reason" placeholder="Reason, e.g. Dinner" value="" data-enter="pause-start">
      <button class="btn" data-action="pause-start">Pause</button></div></div>`;
  }

  _kidCard(kid) {
    const s = this._summaryPerson(kid.id);
    const all = s?.all;
    const budgets = this._config.budgets?.[kid.id]?.all || {};
    const budget = all && all.minutes_left !== null ? (all.used_minutes || 0) + all.minutes_left : null;
    const left = all?.minutes_left ?? null;
    const groups = (s?.groups || []).filter((g) => g.id !== "all");
    const playing = (s?.playing || [])[0];
    const chips = [];
    if (s?.locked && !s.pause)
      chips.push(`<span class="chip warn"><ha-icon icon="mdi:lock"></ha-icon>Locked${s.locked_by?.length ? `: ${esc(s.locked_by.filter((e) => e !== "pause").map((e) => this._entityName(e)).join(", "))}` : ""}${s.lock?.until ? ` until ${esc(new Date(s.lock.until).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }))}` : ""}</span>`);
    if (s?.pause) chips.push(`<span class="chip warn"><ha-icon icon="mdi:pause"></ha-icon>${esc(s.pause.reason || "Paused")}</span>`);
    if (playing) chips.push(`<span class="chip play"><ha-icon icon="mdi:play-circle"></ha-icon>${esc(playing.app || playing.package || "Playing")}${playing.device ? ` · ${esc(playing.device)}` : ""}</span>`);
    if (left === 0) chips.push(`<span class="chip out"><ha-icon icon="mdi:timer-off"></ha-icon>Out of time</span>`);
    if (s?.next_lock) {
      const at = new Date(s.next_lock.at);
      const mins = Math.round((at - Date.now()) / 60000);
      if (mins >= 0 && mins <= 120)
        chips.push(`<span class="chip"><ha-icon icon="mdi:${s.next_lock.kind === "bedtime" ? "weather-night" : "school-outline"}"></ha-icon>${s.next_lock.kind === "bedtime" ? "Bedtime" : "School time"} ${mins <= 60 ? `in ${mins} min` : `at ${esc(at.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }))}`}</span>`);
    }
    const noBudget = budgets.school === null && budgets.other === null;
    return `<div class="card kid">
      <div class="kid-head">
        ${this._avatar(kid.id)}
        <div class="grow"><div class="name">${esc(kid.name)}</div><div class="chips">${chips.join("")}</div></div>
      </div>
      <div class="kid-main">
        <div class="ring-wrap">${this._ring(left ?? 0, budget)}
          <div class="ring-text"><div class="big">${left === null ? "∞" : esc(fmtMinutes(left))}</div><div class="muted small">${left === null ? "no limit" : "left today"}</div></div>
        </div>
        <div class="grow">
          <div class="muted small">Used today: ${esc(fmtMinutes(all?.used_minutes || 0))}</div>
          ${groups
            .map((g) => {
              const total = g.minutes_left === null ? null : g.used_minutes + g.minutes_left;
              const pct = total ? Math.min(100, (g.used_minutes / total) * 100) : 0;
              return `<div class="bar-row"><span class="bar-label">${esc(g.name)}</span>
                <div class="bar ${g.minutes_left === 0 ? "out" : ""}"><div style="width:${total ? pct : 0}%"></div></div>
                <span class="bar-value">${g.minutes_left === null ? esc(fmtMinutes(g.used_minutes)) : `${esc(fmtMinutes(g.minutes_left))} left`}</span></div>`;
            })
            .join("")}
          ${noBudget ? `<div class="muted small">No daily limit yet.</div>` : ""}
        </div>
      </div>
      ${left === null && !groups.some((g) => g.minutes_left !== null) ? `<div class="actions"><button class="btn" data-action="kid" data-kid="${esc(kid.id)}" data-go="kids">Set limits</button></div>` : `<div class="actions wrap">
        <button class="btn" data-action="bonus" data-person="${esc(kid.id)}" data-minutes="-15">−15</button>
        <button class="btn primary" data-action="bonus" data-person="${esc(kid.id)}" data-minutes="15">+15 min</button>
        <button class="btn primary" data-action="bonus" data-person="${esc(kid.id)}" data-minutes="30">+30</button>
        <button class="btn primary" data-action="bonus" data-person="${esc(kid.id)}" data-minutes="60">+1 h</button>
      </div>`}
    </div>`;
  }

  _deviceCard(dv) {
    const icon = dv.kind === "tv" ? "mdi:television" : "mdi:cellphone";
    const on = dv.screen === "on";
    const what = dv.media_title ? `${dv.media_title}${dv.media_app ? ` · ${dv.media_app}` : ""}` : dv.app || (on ? "Home" : dv.connected ? "Asleep" : "Not connected");
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
      ${this._sourcesCard(kid)}
      ${this._locksCard(kid)}
      ${this._enforceCard(kid)}
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
      <p class="muted">While any of these is on, ${esc(kid.name)}'s Hearth devices hold their apps. Family Link's bedtime and school time sensors are typical.</p>
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
    const ids = [...new Set([...Object.keys(seen), ...Object.keys(profiles)])].sort();
    return `${this._pairingCards()}
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
        <p class="muted">Each Google TV profile the TVs have reported, and whose it is. A guest or shared profile belongs to nobody.</p>
        ${ids.length ? `<table class="limits"><tbody>${ids
          .map((id) => `<tr><td>${esc(seen[id] || "Profile")} <span class="muted small">${esc(id)}</span></td>
            <td><select data-change="profile" data-profile="${esc(id)}">${this._options(persons, profiles[id] || "", "Nobody")}</select></td></tr>`)
          .join("")}</tbody></table>` : `<p class="muted small">No profiles reported yet: they appear once a paired TV has been used.</p>`}
        <details id="add-profile"><summary>Add a profile no TV has reported yet</summary>
          <div class="inline"><input id="new-profile-id" placeholder="user:11"><select id="new-profile-person">${this._options(persons, "", "Whose?")}</select>
          <button class="btn" data-action="profile-add">Add</button></div>
        </details>
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
        <p class="muted">Hearth's TVs and phones report their apps. These lists of a kid's apps (Family Link's) add the rest. Requests for more time go to the phone below.</p>
        <div class="muted small">Watch these lists of a kid's apps:</div>
        <div class="checks">${(cfg.choices?.app_lists || [])
          .map((e) => `<label class="check"><input type="checkbox" data-app-watch value="${esc(e.entity_id)}" ${(cfg.app_watch || []).includes(e.entity_id) ? "checked" : ""}> ${esc(e.name)}</label>`)
          .join("") || `<span class="muted small">No Family Link app lists found.</span>`}</div>
        <label class="field">Phone that gets requests for more time<select id="ask-notify">${this._options((cfg.notify_services || []).map((n) => ({ value: n, label: n.replace("notify.mobile_app_", "") })), cfg.ask_notify || "", "Only in Home Assistant")}</select></label>
        <div class="actions"><button class="btn primary" data-action="new-apps-save">Save</button></div>
      </section>`;
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
      ${this._schoolCard()}
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
        ${input("entity", "An entity that says it's a school day (optional)", "input_boolean.school_day")}
        ${input("school_states", "Its school-day states", "on, school")}
        ${input("calendar", "A calendar (optional)", "calendar.school")}
        <label class="field">Its events are<select id="school-calendar_mode">
          <option value="off_days" ${s.calendar_mode !== "school_days" ? "selected" : ""}>Days off</option>
          <option value="school_days" ${s.calendar_mode === "school_days" ? "selected" : ""}>School days</option></select></label>
        ${input("keywords", "Only events with these words (days off)", "closed, break, holiday")}
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
.kid-main { display: flex; gap: 16px; align-items: center; }
.ring-wrap { position: relative; width: 112px; height: 112px; flex: none; }
.ring { width: 112px; height: 112px; transform: rotate(-90deg); }
.ring circle { fill: none; stroke-width: 7; }
.ring .track { stroke: var(--divider-color, #e0e0e0); }
.ring .fill { stroke: var(--success-color, #43a047); stroke-linecap: round; transition: stroke-dashoffset .6s ease; }
.ring.low .fill { stroke: var(--warning-color, #ffa600); }
.ring.out .fill { stroke: var(--error-color, #db4437); }
.ring.none .fill { stroke: var(--primary-color); opacity: .35; }
.ring-text { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; }
.ring-text .big { font-size: 17px; font-weight: 500; line-height: 1.1; }
.bar-row { display: grid; grid-template-columns: 80px 1fr auto; gap: 8px; align-items: center; margin: 6px 0; font-size: 13px; }
.bar-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.bar { height: 6px; border-radius: 3px; background: var(--divider-color, #e0e0e0); overflow: hidden; }
.bar > div { height: 100%; background: var(--primary-color); border-radius: 3px; }
.bar.out > div { background: var(--error-color, #db4437); }
.bar-value { color: var(--secondary-text-color); font-size: 12px; white-space: nowrap; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; margin: 6px 0; }
.chip { display: inline-flex; align-items: center; gap: 4px; padding: 3px 10px; border-radius: 14px; font-size: 12px;
  background: var(--secondary-background-color, #eee); color: var(--primary-text-color); }
.chip ha-icon { --mdc-icon-size: 14px; }
.chip.warn { background: color-mix(in srgb, var(--warning-color, #ffa600) 22%, transparent); }
.chip.out { background: color-mix(in srgb, var(--error-color, #db4437) 20%, transparent); }
.chip.play { background: color-mix(in srgb, var(--success-color, #43a047) 20%, transparent); }
.chip.small { padding: 1px 6px; font-size: 11px; }
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
@media (max-width: 600px) {
  .content { padding: 12px; }
  .grid { grid-template-columns: 1fr; }
  .kid-main { flex-direction: column; align-items: stretch; }
  .ring-wrap { margin: 0 auto; }
  .tab span:not(.badge) { display: none; }
  .tab { padding: 10px 12px; }
  table.limits input { width: 92px; }
  .pin-row { flex-wrap: wrap; }
  .toolbar .text-btn span { display: none; }
}
`;

customElements.define("hearth-panel", HearthPanel);
