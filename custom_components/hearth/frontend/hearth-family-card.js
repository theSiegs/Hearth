// Hearth's family card: the household for a TV's dashboard (a `hearth-tv` view), read from the couch with a remote.
// It draws the dashboard spec's sections 2.1 to 2.6 from the household summary (hearth/household/subscribe), the same
// one the panel and Glint read: the headline with requests and suggestions and their buttons, the family pause, one
// tile per kid (today line, All bar, what's on, the last 7 days, one give button), and each pool today. Text, order,
// levels and buttons all come from the summary (glance.py); the card only arranges and colors them, and draws the
// server's lower-case text as it comes. Pools without a budget today are left out (decision 6). The summary answers
// administrators and adults only, so a kid's sign-in sees a note instead. Plain custom element, no build step; the
// integration serves it and adds it to every dashboard (panel.py).
//
//   type: custom:hearth-family-card
//   title: Family          # optional
//   autofocus: true        # optional: focus the first button when the card opens (default true)

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

// The one time format (glance.duration, noiwid's hm()): "45 min", "2 h 10"; amount() is the short form ("10 left")
const duration = (minutes) => {
  const m = Math.max(0, Math.round(minutes || 0));
  if (m < 60) return `${m} min`;
  const r = m % 60;
  return r ? `${Math.floor(m / 60)} h ${String(r).padStart(2, "0")}` : `${Math.floor(m / 60)} h`;
};
const amount = (minutes) => {
  const m = Math.max(0, Math.round(minutes || 0));
  return m < 60 ? String(m) : duration(m);
};

const ROLES = ["ok", "low", "out", "allowed", "paused", "locked", "held", "none"];
const role = (state) => (ROLES.includes(state) ? state : "none");
const limited = (g) => Boolean(g) && g.limited !== false && g.minutes_left !== null && g.minutes_left !== undefined;

class HearthFamilyCard extends HTMLElement {
  setConfig(config) {
    this._config = config || {};
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const button = e.target.closest("button[data-act]");
        if (button) this._run(button.dataset.act, button.dataset.person || null);
      });
      this.shadowRoot.addEventListener("keydown", (e) => this._arrow(e));
    }
    this._draw();
  }

  set hass(hass) {
    this._hass = hass;
    this._subscribe();
  }

  connectedCallback() {
    this._refused = false;
    this._subscribe();
  }

  disconnectedCallback() {
    if (this._unsub) {
      this._unsub.then((unsub) => unsub()).catch(() => {});
      this._unsub = null;
    }
    this._focused = false;
  }

  getCardSize() {
    return 8;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6, rows: "auto" };
  }

  static getStubConfig() {
    return {};
  }

  _subscribe() {
    // Not again after a refusal (hass is set on every state change): only when the card is shown again
    if (!this._hass || !this.isConnected || this._unsub || this._refused) return;
    this._unsub = this._hass.connection
      .subscribeMessage((summary) => {
        this._error = null;
        this._summary = summary;
        this._draw();
      }, { type: "hearth/household/subscribe" })
      .catch((err) => {
        this._unsub = null;
        this._refused = true;
        this._error =
          err && err.code === "unauthorized"
            ? "Hearth's family card is for adults."
            : err && (err.code === "not_set_up" || err.code === "unknown_command")
              ? "Hearth isn't set up yet."
              : (err && err.message) || "Hearth didn't answer.";
        this._draw();
      });
  }

  // An action of the summary by its id: a person's own and their suggestions', else the household's
  _action(id, person) {
    const s = this._summary || {};
    const h = s.household || {};
    const lists = [];
    if (person) {
      const p = (s.people || []).find((x) => x.id === person) || {};
      lists.push(p.actions || [], ...(p.suggestions || []).map((x) => x.actions || []));
      lists.push(...(h.suggestions || []).filter((x) => x.person === person).map((x) => x.actions || []));
    } else lists.push(h.actions || []);
    for (const list of lists) {
      const found = list.find((a) => a.id === id);
      if (found) return found;
    }
    return null;
  }

  // An action calls its service with exactly its data, as the signed-in adult, after its confirm
  async _run(id, person) {
    const a = this._action(id, person);
    if (!a || this._busy) return;
    if (a.confirm && !window.confirm(a.confirm)) return;
    const [domain, service] = a.service.split(".");
    this._busy = true;
    try {
      await this._hass.callService(domain, service, a.data || {});
      this._say(`${a.label}: done`);
    } catch (err) {
      this._say((err && err.message) || "that didn't work");
    } finally {
      this._busy = false;
    }
  }

  _say(text) {
    this._toast = text;
    this._draw();
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => {
      this._toast = null;
      this._draw();
    }, 3000);
  }

  _button(a, person, extra = "") {
    const fid = `${person || "house"}|${a.id}`;
    return `<button class="btn ${a.primary ? "primary" : ""} ${extra}" data-act="${esc(a.id)}" ${person ? `data-person="${esc(person)}"` : ""} data-fid="${esc(fid)}">${esc(a.label)}</button>`;
  }

  // Redrawn whole on each summary: a remote's focus stays on the same button (by its id), and an unchanged summary
  // draws nothing
  _draw() {
    if (!this.shadowRoot || !this._config) return;
    const body = this._error
      ? `<div class="note">${esc(this._error)}</div>`
      : !this._summary
        ? `<div class="note">loading…</div>`
        : this._top() + this._kids() + this._pools();
    const html = `<style>${STYLE}</style><ha-card>${this._config.title ? `<h1>${esc(this._config.title)}</h1>` : ""}${body}${this._toast ? `<div class="toast" role="status">${esc(this._toast)}</div>` : ""}</ha-card>`;
    if (html === this._last) return;
    this._last = html;
    const active = this.shadowRoot.activeElement;
    const fid = active && active.dataset ? active.dataset.fid : null;
    this.shadowRoot.innerHTML = html;
    const again = fid && [...this.shadowRoot.querySelectorAll("[data-fid]")].find((el) => el.dataset.fid === fid);
    if (again) again.focus();
    else if (!this._focused && this._summary && this._config.autofocus !== false) {
      // The top row is focused by default (spec 2.1), once
      const first = this.shadowRoot.querySelector("button");
      if (first) {
        first.focus({ preventScroll: true });
        this._focused = true;
      }
    }
  }

  // Spec 2.1 and 2.2: the headline, then requests waiting, then suggestions, then the family pause at the row's end.
  // A fixed slot: it keeps its height, so the tiles below don't jump
  _top() {
    const s = this._summary;
    const h = s.household || {};
    const actions = h.actions || [];
    const people = s.people || [];
    const items = [];
    for (const ask of (s.approvals || []).filter((a) => a.type === "more_time")) {
      const p = people.find((x) => x.id === ask.person) || {};
      const said = [p.headline, ...(p.lines || [])].find((x) => x && x.key === `ask:${ask.id}`);
      const buttons = actions.filter((a) => a.id === `ask_yes:${ask.id}` || a.id === `ask_no:${ask.id}`);
      items.push(`<div class="item ask"><div class="what">${esc(ask.person_name || p.name || "")} ${esc(said ? said.text : "asks for more time")}</div>
        <div class="buttons">${buttons.map((a) => this._button(a, null)).join("")}</div></div>`);
    }
    for (const sug of h.suggestions || [])
      items.push(`<div class="item"><div class="what">${esc(sug.person_name)} · ${esc(sug.text)}</div>
        <div class="buttons">${(sug.actions || []).map((a) => this._button(a, sug.person)).join("")}</div></div>`);
    const pause = actions.filter((a) => a.id === "pause_all" || a.id === "pause_end");
    const headline = h.headline || { text: "all clear", level: "calm" };
    return `<section class="top lvl-${esc(headline.level)}">
      <div class="headline">${esc(headline.text)}</div>
      ${items.length ? `<div class="items">${items.join("")}</div>` : ""}
      ${pause.length ? `<div class="buttons house">${pause.map((a) => this._button(a, null)).join("")}</div>` : ""}
    </section>`;
  }

  // Spec 2.3, 2.4 and 2.6: one tile per kid in a row. Name, the All bar, the today line, what's on, the last 7 days
  // and one give button (the pool that binds), two presses away at most
  _kids() {
    const kids = (this._summary.people || []).filter((p) => p.kind === "kid");
    if (!kids.length) return "";
    return `<section class="kids">${kids.map((p) => this._tile(p)).join("")}</section>`;
  }

  _tile(p) {
    const all = p.all;
    const total = limited(all) ? (all.budget !== null && all.budget !== undefined ? all.budget + (all.bonus || 0) : (all.used_minutes || 0) + all.minutes_left) : null;
    const give = p.binding ? (p.actions || []).find((a) => a.id === `bonus:${p.binding.group}`) : null;
    const playing = (p.playing || [])[0];
    const line = p.day_line;
    return `<div class="tile role-${role(p.state)}">
      <div class="name"><span class="dot"></span>${esc(p.name)}</div>
      ${total !== null ? `<div class="bar role-${role(all.state)}"><div style="width:${total ? Math.min(100, ((all.used_minutes || 0) / total) * 100) : 100}%"></div></div>` : ""}
      ${line ? `<div class="line lvl-${esc(line.level)}">${esc(line.text)}</div>` : ""}
      ${playing ? `<div class="playing">${esc([playing.text || playing.title || playing.app, (playing.device || "").toLowerCase()].filter(Boolean).join(" · "))}</div>` : ""}
      ${this._week(p)}
      ${give ? `<div class="buttons">${this._button({ ...give, primary: true }, p.id)}</div>` : ""}
    </div>`;
  }

  // Seven bars of All screen time, oldest on the left, each against its day's budget, a dot under a day something ran
  // out, a hatched day with no record; no axis labels at this distance
  _week(p) {
    const week = [...(p.week || [])].reverse();
    if (!week.length) return "";
    const days = week.map((d) => {
      const known = Boolean(d.minutes && Object.keys(d.minutes).length);
      const budget = d.budget && d.budget.all !== null && d.budget.all !== undefined ? d.budget.all + ((d.bonus || {}).all || 0) : null;
      return { known, used: known ? d.minutes.all || 0 : 0, budget, out: (d.out || []).length > 0 };
    });
    const top = Math.max(60, ...days.map((x) => Math.max(x.used, x.budget || 0)));
    return `<div class="week" aria-label="last 7 days">${days
      .map(
        (x) => `<div class="day"><div class="area">${x.known ? `<div class="fill" style="height:${(x.used / top) * 100}%"></div>` : `<div class="fill none"></div>`}
          ${x.known && x.budget !== null ? `<div class="tick" style="bottom:${(x.budget / top) * 100}%"></div>` : ""}</div>
          <div class="out ${x.out ? "on" : ""}"></div></div>`
      )
      .join("")}</div>`;
  }

  // Spec 2.5: each pool with a budget, every kid's state in it ("games: alex 10 left · sam out"), a short bar per kid
  _pools() {
    const kids = (this._summary.people || []).filter((p) => p.kind === "kid");
    const rows = (this._summary.groups || [])
      .map((g) => ({ g, cells: kids.map((p) => ({ p, pool: (p.groups || []).find((x) => x.id === g.id) })).filter((c) => limited(c.pool)) }))
      .filter((r) => r.cells.length);
    if (!rows.length) return "";
    const value = (pool) => ({ out: "out", allowed: "allowed", paused: "paused" })[pool.state] || `${amount(pool.minutes_left)} left`;
    return `<section class="pools">${rows
      .map(
        (r) => `<div class="pool"><div class="pool-name">${esc(r.g.id === "all" ? "screen time" : String(r.g.name || r.g.id).toLowerCase())}</div>
          ${r.cells
            .map(({ p, pool }) => {
              const total = pool.budget !== null && pool.budget !== undefined ? pool.budget + (pool.bonus || 0) : (pool.used_minutes || 0) + pool.minutes_left;
              return `<div class="cell role-${role(pool.state)}"><span>${esc(p.name)} ${esc(value(pool))}</span>
                <div class="bar"><div style="width:${total ? Math.min(100, ((pool.used_minutes || 0) / total) * 100) : 100}%"></div></div></div>`;
            })
            .join("")}</div>`
      )
      .join("")}</section>`;
  }

  // A remote's arrows move the focus to the nearest button that way (a TV's browser doesn't always do it itself)
  _arrow(e) {
    const dirs = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    const dir = dirs[e.key];
    const from = this.shadowRoot.activeElement;
    if (!dir || !from) return;
    const a = from.getBoundingClientRect();
    const ax = a.left + a.width / 2;
    const ay = a.top + a.height / 2;
    let best = null;
    let bestScore = Infinity;
    for (const el of this.shadowRoot.querySelectorAll("button")) {
      if (el === from) continue;
      const b = el.getBoundingClientRect();
      const dx = b.left + b.width / 2 - ax;
      const dy = b.top + b.height / 2 - ay;
      const along = dx * dir[0] + dy * dir[1];
      if (along <= 1) continue;
      const across = Math.abs(dx * dir[1]) + Math.abs(dy * dir[0]);
      const score = along + across * 2;
      if (score < bestScore) {
        bestScore = score;
        best = el;
      }
    }
    if (best) {
      e.preventDefault();
      best.focus();
      best.scrollIntoView({ block: "nearest", inline: "nearest" });
    }
  }
}

const STYLE = `
:host { display: block; }
ha-card { padding: 20px 24px 24px; font-size: 22px; line-height: 1.3; position: relative; overflow: hidden; }
h1 { font-size: 28px; font-weight: 500; margin: 0 0 12px; }
.note { font-size: 22px; color: var(--secondary-text-color); padding: 12px 0; }
.role-ok { --role: var(--success-color, #43a047); }
.role-low { --role: var(--warning-color, #ffa600); }
.role-out { --role: var(--error-color, #db4437); }
.role-allowed { --role: var(--info-color, #039be5); }
.role-paused { --role: var(--primary-color, #03a9f4); }
.role-locked { --role: var(--state-icon-color, #44739e); }
.role-held { --role: var(--purple-color, #926bc7); }
.role-none { --role: var(--disabled-text-color, #9e9e9e); }
.top { min-height: 150px; padding-bottom: 16px; border-bottom: 1px solid var(--divider-color, #444); }
.headline { font-size: 32px; font-weight: 500; margin-bottom: 8px; }
.lvl-urgent .headline, .line.lvl-urgent { font-weight: 700; }
.top.lvl-urgent .headline { color: var(--warning-color, #ffa600); }
.items { display: flex; flex-direction: column; gap: 10px; }
.item { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
.item .what { flex: 1; min-width: 240px; }
.buttons { display: flex; gap: 10px; flex-wrap: wrap; }
.buttons.house { margin-top: 12px; }
.btn { font: inherit; font-size: 22px; font-weight: 500; min-height: 56px; padding: 8px 22px; border-radius: 28px; cursor: pointer;
  border: 2px solid var(--divider-color, #666); background: transparent; color: var(--primary-text-color); }
.btn.primary { background: var(--primary-color); border-color: var(--primary-color); color: var(--text-primary-color, #fff); }
.btn:focus, .btn:focus-visible { outline: 4px solid var(--accent-color, #ff9800); outline-offset: 3px; transform: scale(1.05); }
.kids { display: flex; gap: 16px; overflow-x: auto; padding: 18px 4px 8px; scroll-snap-type: x proximity; }
.tile { flex: 0 0 300px; scroll-snap-align: start; display: flex; flex-direction: column; gap: 8px; padding: 16px; border-radius: 16px;
  background: rgba(var(--rgb-primary-text-color, 128, 128, 128), .06); border-top: 6px solid var(--role); }
.name { font-size: 28px; font-weight: 600; display: flex; align-items: center; gap: 10px; }
.dot { width: 14px; height: 14px; border-radius: 50%; background: var(--role); flex: none; }
.bar { height: 14px; border-radius: 7px; background: var(--divider-color, #555); overflow: hidden; }
.bar > div { height: 100%; border-radius: 7px; background: var(--role); }
.line { font-size: 22px; }
.line.lvl-notice { font-weight: 600; }
.playing { font-size: 20px; color: var(--secondary-text-color); }
.week { display: flex; gap: 6px; height: 64px; margin-top: 4px; }
.day { flex: 1; display: flex; flex-direction: column; }
.area { position: relative; flex: 1; }
.fill { position: absolute; bottom: 0; left: 10%; right: 10%; border-radius: 4px 4px 0 0; background: var(--accent-color, var(--primary-color)); }
.fill.none { height: 100%; opacity: .5; background: repeating-linear-gradient(45deg, var(--divider-color, #777) 0 4px, transparent 4px 9px); }
.tick { position: absolute; left: 0; right: 0; border-top: 3px solid var(--primary-text-color); opacity: .6; }
.out { width: 10px; height: 10px; border-radius: 50%; margin: 4px auto 0; }
.out.on { background: var(--error-color, #db4437); }
.pools { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 12px 24px; padding-top: 16px; border-top: 1px solid var(--divider-color, #444); margin-top: 8px; }
.pool-name { font-weight: 600; margin-bottom: 4px; }
.cell { display: grid; grid-template-columns: 1fr 120px; align-items: center; gap: 12px; font-size: 20px; margin: 4px 0; }
.cell .bar { height: 10px; }
.toast { position: absolute; left: 50%; bottom: 12px; transform: translateX(-50%); background: var(--primary-text-color, #222); color: var(--primary-background-color, #fff);
  padding: 10px 20px; border-radius: 10px; font-size: 20px; }
`;

if (!customElements.get("hearth-family-card")) {
  customElements.define("hearth-family-card", HearthFamilyCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "hearth-family-card",
    name: "Hearth family",
    preview: false,
    description: "The family at TV distance: requests, suggestions, each kid's day and the pools today, from Hearth.",
  });
}
