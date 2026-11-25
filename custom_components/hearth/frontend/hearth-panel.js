// Hearth's page in Home Assistant's sidebar: the family today, each kid's rules, devices, apps and the household's
// settings, plus a guided setup. It talks to the integration over Home Assistant's WebSocket (panel.py, websocket.py)
// and calls Hearth's services for extra time and YouTube blocks. Plain custom element, no build step; Home Assistant's
// theme variables do the colors, so it follows light and dark themes.

const TABS = [
  { id: "today", label: "Today", icon: "mdi:home-heart" },
  { id: "kids", label: "Kids", icon: "mdi:account-child" },
  { id: "schedule", label: "Schedule", icon: "mdi:calendar-clock" },
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

// In a sentence or a big number, with its unit: "45 min", "1 h 10 min", "2 h"
const longMinutes = (minutes) => {
  const m = Math.max(0, Math.round(minutes || 0));
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r ? `${h} h ${r} min` : `${h} h`;
};

// On a button: "+15 min", "+30 min", "+1 h"
const plusLabel = (minutes) => (minutes % 60 === 0 ? `+${minutes / 60} h` : `+${minutes} min`);

// "19:00" (a time input's value) as people read it: "7:00 pm"
const hhmmWords = (value) => {
  const [h, m] = String(value || "").split(":").map(Number);
  if (!Number.isFinite(h)) return String(value || "");
  return `${h % 12 || 12}:${String(m || 0).padStart(2, "0")} ${h < 12 ? "am" : "pm"}`;
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

// The summary's state for a group or person, as a color role (spec section 4); unknown: neutral
const ROLES = ["ok", "low", "out", "allowed", "paused", "locked", "held", "none"];
const role = (state) => (ROLES.includes(state) ? state : "none");

// "11:00 pm": the header's time of day
const clockAmPm = (date) => {
  const h = date.getHours();
  return `${h % 12 || 12}:${String(date.getMinutes()).padStart(2, "0")} ${h < 12 ? "am" : "pm"}`;
};

// The words people see for today's time (docs/contracts/time-model.md): one table, so a rename is one edit. Daily time
// is the one total (group id "all"), categories may have a limit inside it, and more time is only bonus time (no
// category), a raised limit (one category, today) or Unlimited. Hearth's family pause is "Pause screens".
// Messages apps: blocking one (unlike pausing it) makes it miss incoming texts, so the Block action asks first
const MESSAGES_APPS = ["com.google.android.apps.messaging", "com.samsung.android.messaging"];

const WORDS = {
  daily: "Daily time",
  dailyLower: "daily time",
  category: "category",
  categories: "Categories",
  bonus: "Bonus time",
  bonusShort: "bonus",
  raise: "Raise limit",
  raiseEnd: "End raised limit",
  noLimit: "No limit",
  unlimited: "Unlimited",
  unlimitedEnd: "End unlimited",
  includeBedtime: "Include bedtime",
  untilEndOfDay: "End of day",
  untilTurnedOff: "Until turned off",
  limitsBack: "Limits back on",
  pauseScreens: "Pause screens",
  screensPaused: "Screens paused",
  endPause: "End pause screens",
  origin: "Where this came from",
  noOrigin: "Set by Hearth's rules",
  outOfTime: "No time left today",
  activity: "Activity",
  activityHint: "What Hearth did: its calls to Family Link, Family Safety and the Switch, the holds it started and ended, TV commands and Glint requests. Kept 14 days.",
  activityAll: "Everyone",
  activityNone: "Nothing yet",
  holdStarted: "hold started",
  holdEnded: "hold ended",
  tvCommand: "TV command",
  glintInbox: "Glint request",
  ruleOpened: "Messages when away: open",
  ruleClosed: "Messages when away: back to normal",
  awayMessages: "Messages when away from adults",
  awayMessagesHint:
    "While a kid is out, away from home and apart from every adult for 5 minutes, their text app isn't held by daily time or Messaging's limit, so they can arrange a ride. It goes back after 10 minutes with an adult or at home. School time, the schedule, bedtime, a pause and a block still hold it. Calls always work.",
  backstop: "Keep Family Link's daily limit as a backstop",
  backstopMargin: "Backstop margin (minutes)",
  backstopHint:
    "Each kid's Family Link daily limit today follows their daily time, plus bonus time left and the margin, and a whole day while Unlimited is on. Hearth's own holds stay the real limit. Google TVs are never written.",
};
const limitWord = (minutes) => (minutes === null || minutes === undefined ? "no limit" : `${fmtMinutes(minutes)} limit`);

const LOCK_WORDS = { bedtime: "Bedtime", school_time: "School time", paused: WORDS.screensPaused, other: "Locked" };

// Today's own icons, drawn inline (crisp at any size, and the same in every theme)
const ICONS = {
  tv: '<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8"/>',
  tablet: '<rect x="5" y="2.5" width="14" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
  phone: '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
  xbox: '<path d="M6 9h12a3 3 0 0 1 3 3l-1 5a2 2 0 0 1-3.4 1L15 16H9l-1.6 2A2 2 0 0 1 4 17l-1-5a3 3 0 0 1 3-3z"/><path d="M8 12v2M7 13h2M16 12.5h.01M17.5 14h.01"/>',
  windows: '<rect x="3" y="4" width="18" height="12" rx="1.5"/><path d="M9 20h6M12 16v4"/>',
  switch: '<rect x="2.5" y="6" width="19" height="12" rx="3"/><path d="M7 6v12M17 6v12"/>',
  moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  school: '<path d="M2 9l10-5 10 5-10 5z"/><path d="M6 11v5c3 2.5 9 2.5 12 0v-5"/>',
  pause: '<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chev: '<path d="M9 6l6 6-6 6"/>',
  down: '<path d="M6 9l6 6 6-6"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
  more: '<circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
  edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>',
  book: '<path d="M3 6.5C5.5 5 8.5 5 12 7c3.5-2 6.5-2 9-.5V19c-2.5-1.5-5.5-1.5-9 .5-3.5-2-6.5-2-9-.5z"/><path d="M12 7v12.5"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
};
const icon = (name, cls = "") => `<svg class="svg ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ""}</svg>`;

// How long an Undo stays on offer: long enough for a phone in one hand while talking to a kid
const UNDO_MS = 9000;

const money = (cents) => `${cents < 0 ? "−" : ""}$${(Math.abs(cents) / 100).toFixed(2)}`;
const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const repeatWords = (task) => {
  const r = task.repeat || {};
  if (r.kind === "daily") return "every day";
  if (r.kind === "weekdays") return r.days.join() === "0,1,2,3,4" ? "Mon to Fri" : r.days.join() === "5,6" ? "Sat and Sun" : r.days.map((d) => DAY_NAMES[d]).join(", ");
  if (r.kind === "every_n") return `every ${r.n} days`;
  if (r.kind === "after_done") return `${r.n} days after done`;
  return task.due_date ? `once, by ${task.due_date}` : "once";
};
// A chore's minutes are bonus time whatever category the reward names (time_model.py)
const rewardWords = (reward, _groups) => (reward.cents !== undefined ? `+${money(reward.cents)}` : `+${reward.minutes} min ${WORDS.bonusShort}`);

const slug = (text) =>
  String(text || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 64);

// The weekly schedule's days and times (weekly.py): minutes since midnight, snapped to 15 minutes
const SCH_DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
const SCH_SHORT = { mon: "Mon", tue: "Tue", wed: "Wed", thu: "Thu", fri: "Fri", sat: "Sat", sun: "Sun", day_off: "Day off", half_day: "Half day" };
const SCH_LONG = {
  mon: "Monday", tue: "Tuesday", wed: "Wednesday", thu: "Thursday", fri: "Friday", sat: "Saturday", sun: "Sunday", day_off: "Day off", half_day: "Half day",
};
const schMin = (hhmm) => {
  const [h, m] = String(hhmm || "0:0").split(":").map(Number);
  return Math.max(0, Math.min(1425, Math.round(((h || 0) * 60 + (m || 0)) / 15) * 15));
};
const schHhmm = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
// "9:30 PM", "7 AM", "noon", "midnight"
const schClock = (m) => {
  m = ((m % 1440) + 1440) % 1440;
  if (m === 0) return "midnight";
  if (m === 720) return "noon";
  const h = Math.floor(m / 60);
  const mm = m % 60;
  return `${h % 12 || 12}${mm ? `:${String(mm).padStart(2, "0")}` : ""} ${h < 12 ? "AM" : "PM"}`;
};
// "9:30p", "7a"
const schShort = (m) => {
  m = ((m % 1440) + 1440) % 1440;
  const h = Math.floor(m / 60);
  const mm = m % 60;
  return `${h % 12 || 12}${mm ? `:${String(mm).padStart(2, "0")}` : ""}${h < 12 ? "a" : "p"}`;
};
const schIsoClock = (iso) => {
  const t = new Date(iso);
  return Number.isNaN(t.getTime()) ? "" : schClock(t.getHours() * 60 + t.getMinutes());
};
const schPct = (m) => `${(m / 1440) * 100}%`;
const schDur = (m) => (m === null || m === undefined ? "No limit" : m === 0 ? "None" : fmtMinutes(m));
const schDayMonth = (iso) => {
  const d = new Date(`${iso}T12:00:00`);
  return `${d.getDate()} ${d.toLocaleDateString("en", { month: "short" })}`;
};
// Sorted, one per time, neighbours with the same mode merged
const schMerge = (changes) => {
  const out = [];
  for (const [m, mode] of [...changes].sort((a, b) => a[0] - b[0])) {
    if (out.length && out[out.length - 1][0] === m) out[out.length - 1] = [m, mode];
    else if (!out.length || out[out.length - 1][1] !== mode) out.push([m, mode]);
  }
  return out.filter((c, i, a) => i === 0 || a[i - 1][1] !== c[1]);
};
// A half day: the weekday's changes with its first School ending at [ends] (or [early] minutes before the weekday's)
const schHalfChanges = (base, modes, ends, early) => {
  const i = base.findIndex(([, m]) => modes[m]?.allows === "school");
  if (i < 0) return base;
  const after = base[i + 1];
  let end;
  if (early) {
    if (!after) return base;
    end = Math.round((after[0] - early) / 15) * 15;
  } else end = ends ?? 720;
  if (end <= base[i][0] || (after && end >= after[0])) return base;
  const rest = after ? base.slice(i + 2).filter(([m]) => m > end) : [];
  return schMerge([...base.slice(0, i + 1), [end, after ? after[1] : "free"], ...rest]);
};

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
    // A kid's to-do list, as hearth/todo/list answers (null: couldn't be read)
    this._todo = {};
    this._todoBusy = new Set();
    this._busy = false;
    this._drafts = {};
    this._open = new Set();
    // Today: the kid whose sheet shows (and whether it's open on a phone), what's unfolded, the open choosers
    this._sel = null;
    this._sheetOpen = false;
    this._exp = new Set();
    this._wide = false;
    // Undo: the toast on offer, and what waits its turn (a "Not today" or a "No" runs once the Undo is gone)
    this._undo = null;
    this._deferred = new Map();
    this._hidden = new Set();
    // The "+" box's menu that's open (15, 30, 1 h, Unlock for today): which one, by its key
    this._giveMenu = null;
  }

  set hass(hass) {
    const first = !this._hass;
    this._hass = hass;
    // Hearth's own accent follows Home Assistant's dark mode
    if (hass?.themes && typeof this.toggleAttribute === "function") this.toggleAttribute("dark", Boolean(hass.themes.darkMode));
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
      // Allow an app: the kid's apps, filtered as it's typed
      if (t.id === "allow-q") {
        this._allowQ = t.value.trim().toLowerCase();
        clearTimeout(this._filterTimer);
        this._filterTimer = setTimeout(() => this._render(), 200);
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
      if ((e.key === "Enter" || (e.key === " " && e.target.getAttribute?.("role") === "button")) && e.target.dataset && e.target.dataset.enter) {
        e.preventDefault();
        this._act(e.target.dataset.enter, e.target);
      }
      // Esc closes the "+" box's menu first, back to its box
      if (e.key === "Escape" && this._giveMenu) {
        const key = this._giveMenu;
        this._giveMenu = null;
        this._render();
        [...(this.shadowRoot.querySelectorAll?.('[data-action="give-menu"]') || [])].find((b) => b.dataset.menu === key)?.focus();
        return;
      }
      // Esc closes the More time sheet, back to the kid's sheet
      if (e.key === "Escape" && this._mt) {
        this._act("mt-close", e.target);
        return;
      }
      // Esc closes a kid's sheet on a phone
      if (e.key === "Escape" && this._sheetOpen) this._act("sheet-close", e.target);
      // and the schedule's dialog, then its day sheet
      if (e.key === "Escape" && this._tab === "schedule" && (this._schDlg || this._schSheet)) {
        if (this._schDlg) this._schDlg = null;
        else this._schSheet = false;
        this._render();
      }
    });
    // A tap outside the page (Home Assistant's sidebar) closes the "+" box's menu too
    if (typeof document !== "undefined" && !this._docClick) {
      this._docClick = (e) => {
        if (this._giveMenu && !e.composedPath().includes(this)) {
          this._giveMenu = null;
          this._render();
        }
      };
      document.addEventListener("click", this._docClick);
    }
    // Swiped down from its top, the sheet closes
    let swipeFrom = null;
    this.shadowRoot.addEventListener("touchstart", (e) => {
      // Only from the sheet's handle or head: a drag on its buttons doesn't close it
      const sheet = e.target.closest?.(".handle, .dhead") ? e.target.closest?.(".detail.on") : null;
      swipeFrom = sheet && sheet.scrollTop <= 0 && !this._wide ? e.touches[0].clientY : null;
    }, { passive: true });
    this.shadowRoot.addEventListener("touchend", (e) => {
      if (swipeFrom !== null && e.changedTouches[0].clientY - swipeFrom > 80) this._act("sheet-close", e.target);
      swipeFrom = null;
    }, { passive: true });
    // Side by side from 900 px of the page's own width (Home Assistant's sidebar takes the rest)
    if (typeof ResizeObserver !== "undefined" && !this._resize) {
      this._resize = new ResizeObserver(() => {
        const wide = this.clientWidth >= 900;
        if (wide !== this._wide) {
          this._wide = wide;
          if (this._config) this._render();
        }
      });
      this._resize.observe(this);
    }
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
    // Leaving the page: a "Not today" or "No" still waiting for its Undo runs now
    for (const key of [...this._deferred.keys()]) this._runDeferred(key);
    if (this._docClick) {
      document.removeEventListener("click", this._docClick);
      this._docClick = null;
    }
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
        // The same summary again (it's pushed up to every 2 s): nothing to redraw, unless the minute moved (the header's
        // clock, "bedtime in 20 min")
        const json = JSON.stringify(summary);
        const minute = Math.floor(Date.now() / 60000);
        if (json === this._summaryJson && minute === this._summaryMinute) return;
        this._summaryJson = json;
        this._summaryMinute = minute;
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
    // A message takes the toast's place: what waited for its Undo runs now
    if (this._undo?.key) this._runDeferred(this._undo.key);
    this._undo = null;
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
    // As named; a group only the summary knows by its name there; never a lower-case id
    const named = (this._config?.groups || []).find((g) => g.id === id)?.name || (this._summary?.groups || []).find((g) => g.id === id)?.name;
    if (named) return named;
    for (const p of this._summary?.people || []) {
      const g = (p.groups || []).find((x) => x.id === id);
      if (g?.name) return g.name;
    }
    return cap(String(id || ""));
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

  // A Hearth service, raising on failure (for Undo's own calls)
  async _call(service, data) {
    await this._hass.callService("hearth", service, data);
  }

  // Undo instead of confirm: the service runs at once, and the toast offers [undo] for UNDO_MS
  async _undoable(service, data, text, undo) {
    try {
      await this._call(service, data);
    } catch (err) {
      this._notify(this._message(err));
      return;
    }
    this._drafts = {};
    this._offerUndo(text, undo);
  }

  _offerUndo(text, undo, key = null) {
    // A toast already on offer for a "Not today" or "No": it runs now, as the new one takes its place
    if (this._undo?.key && this._undo.key !== key) this._runDeferred(this._undo.key);
    this._toast = null;
    this._undo = { text, undo, key, at: Date.now() };
    clearTimeout(this._undoTimer);
    this._undoTimer = setTimeout(() => {
      this._undo = null;
      this._render();
    }, UNDO_MS);
    this._render();
  }

  // A "Not today" or a "No": its row goes at once, and it runs once its Undo is gone (or the page closes)
  _defer(key, text, run) {
    this._hidden.add(key);
    const timer = setTimeout(() => this._runDeferred(key), UNDO_MS);
    this._deferred.set(key, { run, timer });
    this._offerUndo(text, null, key);
  }

  async _runDeferred(key) {
    const waiting = this._deferred.get(key);
    if (!waiting) return;
    clearTimeout(waiting.timer);
    this._deferred.delete(key);
    try {
      await waiting.run();
    } catch (err) {
      this._hidden.delete(key);
      this._notify(this._message(err));
      return;
    }
    // Gone from the summary by now; a new one with the same key (another day) shows again
    setTimeout(() => this._hidden.delete(key), 15000);
  }

  // A device of the kid's, as the toasts name it
  _targetName(person, device) {
    const t = (this._summaryPerson(person)?.targets || []).find((x) => x.id === device);
    return t ? t.display_name || t.name : null;
  }

  // Extra time now, with Undo: of a group (Undo takes back just that), or on one device (it answers with its id, and
  // Undo ends just that one)
  async _giveNow(person, data) {
    const minutes = Number(data.minutes) || 0;
    const where = data.device ? this._targetName(person, data.device) : null;
    const what = data.device ? `on ${where || "that device"}` : WORDS.bonusShort;
    const text = `Gave ${this._personName(person)} ${minutes} min ${what}`;
    if (data.device) {
      let id = null;
      try {
        const r = await this._hass.callWS({ type: "call_service", domain: "hearth", service: "add_bonus", service_data: data, return_response: true });
        id = r?.response?.id || null;
      } catch (err) {
        this._notify(this._message(err));
        return;
      }
      this._offerUndo(text, id ? () => this._call("allow_end", { id }) : null);
      return;
    }
    // Bonus time has no category: whatever group a suggestion named, it's hearth.add_time
    const who = data.person || person;
    await this._undoable("add_time", { person: who, minutes }, text, () => this._call("remove_time", { person: who, minutes }));
  }

  // Unlimited until a time (hearth.unlimited); Undo ends it
  async _unlimited(person, until, includeBedtime) {
    const data = { people: [person], until, include_bedtime: Boolean(includeBedtime) };
    const when = until === "turned_off" ? "until turned off" : until === "end_of_day" ? "until midnight" : `until ${until}`;
    await this._undoable("unlimited", data, `${WORDS.unlimited} for ${this._personName(person)} ${when}`, () => this._call("unlimited_end", { people: [person] }));
  }

  // A category's limit raised today (hearth.raise_cap): by minutes, or no limit; Undo ends the raise
  async _raise(person, category, how) {
    const data = { person, category, ...(how === "none" ? { no_cap: true } : { minutes: Number(how) }) };
    const name = this._groupName(category);
    const text = how === "none" ? `No ${name} limit for ${this._personName(person)} today` : `Raised ${this._personName(person)}'s ${name} limit by ${fmtMinutes(Number(how))}`;
    await this._undoable("raise_cap", data, text, () => this._call("raise_cap_end", { person, category }));
  }

  // Unlock for today: an allow of the group (or of the device) that ends at midnight; Undo ends that allow by its id
  async _unlock(person, group, device) {
    // Daily time: Unlimited for the rest of today; a category: no limit today (a raised limit). Only a device is an allow
    if (!device && group === "all") return this._unlimited(person, "end_of_day", false);
    if (!device) return this._raise(person, group, "none");
    const data = { people: [person], group, until: "end_of_day", ...(device ? { device } : {}) };
    let id = null;
    try {
      const r = await this._hass.callWS({ type: "call_service", domain: "hearth", service: "allow", service_data: data, return_response: true });
      id = r?.response?.id || null;
      if (Array.isArray(id)) id = id[0] || null;
    } catch (err) {
      this._notify(this._message(err));
      return;
    }
    const name = this._personName(person);
    const what = device ? this._targetName(person, device) || "that device" : group === "all" ? "screen time" : this._groupName(group);
    const fallback = { people: [person], ...(device ? { device } : { group }) };
    this._offerUndo(`Unlocked ${what} for ${name} until midnight`, () => this._call("allow_end", id ? { id } : fallback));
  }

  // How much more bonus time it takes before a group opens again, as glance.py's _over: the bonus already given
  // (All's row) pays what's past daily time or, all together, past the category limits; rounded up to 5 minutes,
  // 0 under 10
  _overOf(row, rows) {
    const budget = row?.budget;
    if (budget === null || budget === undefined || budget < 0) return 0;
    rows = rows && rows.length ? rows : [row];
    const whole = rows.find((r) => r.id === "all");
    const given = Math.max(0, whole?.bonus || 0);
    const day = whole && whole.budget !== null && whole.budget !== undefined && whole.budget >= 0
      ? (whole.used_minutes || 0) - whole.budget : 0;
    let past;
    if (row.id === "all") past = day - given;
    else {
      const caps = rows
        .filter((r) => r.id !== "all" && r.budget !== null && r.budget !== undefined && r.budget > 0)
        .reduce((sum, r) => sum + Math.max(0, (r.used_minutes || 0) - r.budget - Math.max(0, r.bonus || 0)), 0);
      past = Math.max(day, caps) - given;
    }
    return past < 10 ? 0 : Math.ceil(Math.floor(past) / 5) * 5;
  }

  // The "+" box: a square button whose menu gives 15, 30 or 60 more minutes, or unlocks the group (or device) until
  // midnight; with a line under it when the kid is already over ("10 min over: +15 leaves 5")
  _giveBox(key, { person, group = "all", device = null, over = 0 }) {
    const open = this._giveMenu === key;
    const data = `data-person="${esc(person)}" data-group="${esc(group)}"${device ? ` data-device="${esc(device)}"` : ""}`;
    let menu = "";
    if (open) {
      const items = [[15, "+15 min"], [30, "+30 min"], [60, "+1 h"]]
        .map(([m, label]) => `<button role="menuitem" data-action="menu-give" ${data} data-minutes="${m}">${label}</button>`)
        .join("");
      let note = "";
      if (over > 0) {
        const enough = [15, 30, 60].find((m) => m > over);
        note = `<div class="gnote">${esc(fmtMinutes(over))} over: ${enough ? `+${esc(amount(enough))} leaves ${esc(amount(enough - over))}` : "+1 h won't cover it"}</div>`;
      }
      // The amounts are bonus time (no category); the last line opens daily time (Unlimited), the category (no limit
      // today) or the device for the rest of today
      const unlockLabel = device
        ? `Unlock for today<small>Ends at midnight</small>`
        : group === "all"
          ? `${WORDS.unlimited} today<small>Not counted, ends at midnight</small>`
          : `No ${esc(this._groupName(group))} limit today<small>A raised limit, ends at midnight</small>`;
      menu = `<div class="givemenu" role="menu" aria-label="${esc(WORDS.bonus)}">${items}<button role="menuitem" data-action="menu-unlock" ${data}>${icon("lock", "sm")}${unlockLabel}</button>${note}</div>`;
    }
    return `<span class="givebox"><button class="b sq" data-action="give-menu" data-menu="${esc(key)}" aria-label="More choices" aria-haspopup="menu" aria-expanded="${open}">${icon("plus")}</button>${menu}</span>`;
  }

  _resetChoosers() {
    this._giveMenu = null;
    this._allowOpen = false;
    this._moreOpen = false;
    this._allowPick = null;
    this._allowLen = 30;
    this._allowQ = "";
    this._unlimitedUntil = "end_of_day";
    this._unlimitedBed = false;
    this._originOpen = null;
    // The More time sheet: {kid, for: a category's id or "all", view: "main" or "free"} while it's open
    this._mt = null;
  }

  // More time (the kid's sheet's one button for more time): what's stopping the kid, the categories it can be for, and
  // what a choice does. The page works out which service helps now (no new server work):
  //   Anything +N                       hearth.add_time (bonus time, any app)
  //   a category +N, daily time left    hearth.raise_cap by N (its limit, inside daily time)
  //   a category +N, daily time is out  hearth.add_time with the category (its own bonus, past daily time)
  //   a category, rest of today         hearth.raise_cap no_cap; daily time out: free play (a raise wouldn't help)
  //   Anything, rest of today           hearth.unlimited until the end of the day (free play, not counted)
  //   Take 15 min away                  hearth.remove_time (takes back extra time given today, never more)
  _mtState(s) {
    const t = s?.time || {};
    const all = s?.all || {};
    const dailyLimited = all.minutes_left !== null && all.minutes_left !== undefined;
    const dailyOut = dailyLimited && (all.minutes_left <= 0 || all.state === "out");
    const cats = (t.categories || []).filter((c) => c.limit_today !== null && c.limit_today !== undefined);
    const b = this._binding(s);
    // The category that's stopping them, else the one closest to its limit
    const stopping = cats.find((c) => b && c.id === b.id) || cats.find((c) => c.left === 0) || null;
    const closest = [...cats].sort((x, y) => (x.left ?? 1e9) - (y.left ?? 1e9))[0] || null;
    return { t, all, dailyLimited, dailyOut, cats, stopping, closest };
  }

  // The category (or "all") the More time sheet is for now: the one picked, else the one that's stopping them
  _mtFor(s) {
    const { cats, stopping } = this._mtState(s);
    const picked = this._mt?.for;
    if (picked === "all" || cats.some((c) => c.id === picked)) return picked;
    return stopping ? stopping.id : "all";
  }

  // What a More time choice does: {service, data, text, undo, note}. [how]: minutes, or "rest" (the rest of today)
  _mtPlan(person, forId, how) {
    const s = this._summaryPerson(person);
    const name = s?.name || this._personName(person);
    const { dailyOut } = this._mtState(s);
    const rest = how === "rest";
    const minutes = rest ? 0 : Number(how) || 0;
    if (forId === "all" || (rest && dailyOut)) {
      if (rest)
        return {
          service: "unlimited",
          data: { people: [person], until: "end_of_day", include_bedtime: false },
          text: `Free play for ${name} till midnight (not counted)`,
          undo: () => this._call("unlimited_end", { people: [person] }),
        };
      return {
        service: "add_time",
        data: { person, minutes },
        text: `${plusLabel(minutes)} for ${name}`,
        undo: () => this._call("remove_time", { person, minutes }),
      };
    }
    const cat = this._groupName(forId);
    if (rest)
      return { service: "raise_cap", data: { person, category: forId, no_cap: true }, text: `No ${cat} limit for ${name} till midnight`, raise: true };
    if (dailyOut)
      return {
        service: "add_time",
        data: { person, minutes, category: forId },
        text: `${plusLabel(minutes)} of ${cat} for ${name} (past daily time)`,
        undo: () => this._call("remove_time", { person, minutes, category: forId }),
      };
    return { service: "raise_cap", data: { person, category: forId, minutes }, text: `${plusLabel(minutes)} of ${cat} for ${name}`, raise: true };
  }

  // One tap gives, with Undo. A raise's Undo ends just that raise (its origin), else every raise of the category
  async _mtGive(person, forId, how) {
    const plan = this._mtPlan(person, forId, how);
    let response = null;
    try {
      const r = await this._hass.callWS({ type: "call_service", domain: "hearth", service: plan.service, service_data: plan.data, return_response: true });
      response = r?.response || null;
    } catch (err) {
      this._notify(this._message(err));
      return;
    }
    this._mt = null;
    this._drafts = {};
    let undo = plan.undo;
    if (plan.raise) {
      const origin = response?.origin_id || response?.origin_ids?.[person] || null;
      undo = origin ? () => this._call("end_grant", { origin_id: origin }) : () => this._call("raise_cap_end", { person, category: plan.data.category });
    }
    this._offerUndo(plan.text, undo);
  }

  // Take 15 min away: takes back extra time given today (hearth.remove_time never cuts daily time itself)
  async _mtTake(person, minutes = 15) {
    const name = this._personName(person);
    let removed = minutes;
    try {
      const r = await this._hass.callWS({ type: "call_service", domain: "hearth", service: "remove_time", service_data: { person, minutes }, return_response: true });
      const said = r?.response?.removed?.[person];
      if (typeof said === "number") removed = said;
    } catch (err) {
      this._notify(this._message(err));
      return;
    }
    this._mt = null;
    if (!removed) {
      this._notify(`No extra time to take back from ${name} today`);
      return;
    }
    this._offerUndo(`−${longMinutes(removed)} for ${name}`, () => this._call("add_time", { person, minutes: removed }));
  }

  // Events

  _onClick(e) {
    const target = e.target.closest("[data-action]");
    // A tap outside the "+" box's menu closes it (and still does what it tapped)
    if (this._giveMenu && !e.target.closest(".givebox")) {
      this._giveMenu = null;
      if (!target) this._render();
    }
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
    if (action.startsWith("sch-")) return this._schAct(action, el);
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
        if (d.tab === "kids") this._loadTodo(this._kid || this._kids()[0]?.id);
        if (d.tab === "schedule") this._loadSchedule();
        return;
      case "kid-sheet":
        // A kid's row on Today: their sheet opens (a bottom sheet on a phone, the column beside on a wide page)
        if (this._sel !== d.kid) this._resetChoosers();
        this._sel = d.kid;
        this._sheetOpen = true;
        this._render();
        this.shadowRoot.querySelector?.(".detail")?.scrollTo?.(0, 0);
        // On a phone the sheet is a dialog: focus goes into it
        if (!this._wide) this.shadowRoot.querySelector?.(".detail .closebtn")?.focus?.({ preventScroll: true });
        return;
      case "sheet-close": {
        const was = this._sel;
        this._sheetOpen = false;
        if (!this._wide) this._sel = null;
        this._resetChoosers();
        this._render();
        // and back to the kid's row
        if (was) [...(this.shadowRoot.querySelectorAll?.('[data-action="kid-sheet"]') || [])].find((b) => b.dataset.kid === was)?.focus?.({ preventScroll: true });
        return;
      }
      case "mt-open":
        // The More time sheet over the kid's sheet; [view] "free" opens on Free play until a time
        this._mt = { kid: d.person, for: null, view: d.view || "main" };
        this._moreOpen = false;
        this._allowOpen = false;
        this._render();
        this.shadowRoot.querySelector?.(".mt button")?.focus?.({ preventScroll: true });
        return;
      case "mt-close":
        this._mt = null;
        this._render();
        this.shadowRoot.querySelector?.('[data-action="mt-open"]')?.focus?.({ preventScroll: true });
        return;
      case "mt-for":
        if (this._mt) this._mt.for = d.group;
        this._render();
        return;
      case "mt-view":
        if (this._mt) this._mt.view = d.view;
        this._render();
        return;
      case "mt-give":
        await this._mtGive(d.person, d.group, d.how);
        return;
      case "mt-take":
        await this._mtTake(d.person, Number(d.minutes) || 15);
        return;
      case "pause-quick":
        // The header's Pause: everyone, 30 minutes, at once, with Undo (its caret opens the length and reason)
        this._pauseOpen = false;
        await this._undoable("pause", { minutes: 30 }, "Paused everyone for 30 min", () => this._call("pause_end", {}));
        return;
      case "extra-end": {
        // One of Today's extras ends (hearth.end_grant by its origin), with Undo when it can be given again
        const s = this._summaryPerson(d.person);
        const o = (s?.time?.origins || []).find((x) => x.id === d.origin);
        await this._undoable("end_grant", { origin_id: d.origin }, `Ended: ${this._extraText(o || {}, s)}`, this._extraUndo(d.person, o, s));
        return;
      }
      case "exp":
        if (this._exp.has(d.key)) this._exp.delete(d.key);
        else this._exp.add(d.key);
        this._render();
        return;
      case "pause-open":
        this._pauseOpen = !this._pauseOpen;
        this._render();
        return;
      case "pause-len":
        this._pauseMinutes = d.minutes === "until" ? "until" : Number(d.minutes);
        this._render();
        return;
      case "pause-go": {
        const reason = this._value("#pause-reason");
        if (this._pauseMinutes === "until") {
          const until = this._value("#pause-until");
          if (!until) return this._notify("Pick a time");
          this._pauseOpen = false;
          await this._undoable("pause", reason ? { until, reason } : { until }, `Paused everyone till ${hhmmWords(until)}`, () => this._call("pause_end", {}));
          return;
        }
        const minutes = this._pauseMinutes || 30;
        this._pauseOpen = false;
        await this._undoable("pause", reason ? { minutes, reason } : { minutes }, `Paused everyone's screens for ${fmtMinutes(minutes)}`, () => this._call("pause_end", {}));
        return;
      }
      case "pause-end-all": {
        const was = (this._summary?.people || []).find((p) => p.pause)?.pause;
        await this._undoable(
          "pause_end",
          {},
          "Screens back on",
          was?.until ? () => this._call("pause", { until: was.until, ...(was.reason ? { reason: was.reason } : {}) }) : null
        );
        return;
      }
      case "allow-open":
        this._allowOpen = !this._allowOpen;
        this._moreOpen = false;
        this._mt = null;
        this._render();
        if (this._allowOpen) this.shadowRoot.getElementById?.("allow-q")?.focus?.({ preventScroll: true });
        return;
      case "allow-pick":
        this._allowPick = d.pick;
        this._render();
        return;
      case "allow-len":
        this._allowLen = Number(d.minutes);
        this._render();
        return;
      case "more-open":
        this._moreOpen = !this._moreOpen;
        this._render();
        return;
      case "screens-toggle":
        this._screensOpen = !this._screensOpen;
        this._render();
        return;
      case "give": {
        // Bonus time now (no category); Undo takes back just that (hearth.remove_time)
        const minutes = Number(d.minutes);
        await this._undoable(
          "add_time",
          { person: d.person, minutes },
          `Gave ${this._personName(d.person)} ${minutes} min ${WORDS.bonusShort}`,
          () => this._call("remove_time", { person: d.person, minutes })
        );
        return;
      }
      case "raise":
        await this._raise(d.person, d.group, d.how);
        return;
      case "activity-who":
        this._activityWho = el.value || "";
        await this._loadActivity();
        return;
      case "activity-open":
        this._activityOpen = !this._activityOpen;
        if (this._activityOpen) await this._loadActivity();
        else this._render();
        return;
      case "raise-end":
        await this._service("raise_cap_end", { person: d.person, category: d.group }, `${this._groupName(d.group)} limit back as set`);
        return;
      case "unlimited-until":
        this._unlimitedUntil = d.until;
        this._render();
        return;
      case "unlimited-bed":
        this._unlimitedBed = !this._unlimitedBed;
        this._render();
        return;
      case "unlimited": {
        // Free play until a time (the More time sheet's own view): not counted, ends at midnight at the latest
        let until = this._unlimitedUntil || "end_of_day";
        if (until === "time") until = this._value(`#unlimited-time`) || "end_of_day";
        const bed = Boolean(this._unlimitedBed);
        this._mt = null;
        const name = this._personName(d.person);
        const when = until === "turned_off" ? "until turned off" : until === "end_of_day" ? "till midnight" : `till ${hhmmWords(until)}`;
        await this._undoable(
          "unlimited",
          { people: [d.person], until, include_bedtime: bed },
          `Free play for ${name} ${when} (not counted)`,
          () => this._call("unlimited_end", { people: [d.person] })
        );
        return;
      }
      case "unlimited-end": {
        let ended = null;
        try {
          const r = await this._hass.callWS({ type: "call_service", domain: "hearth", service: "unlimited_end", service_data: { people: [d.person] }, return_response: true });
          ended = r?.response?.text?.[d.person] || null;
        } catch (err) {
          this._notify(this._message(err));
          return;
        }
        const was = this._summaryPerson(d.person)?.time?.unlimited;
        this._offerUndo(ended || WORDS.limitsBack, was ? () => this._call("unlimited", this._unlimitedAgain(d.person, was)) : null);
        return;
      }
      case "origin": {
        // The "?" beside a status line: where it came from, on tap
        const key = d.key || d.person;
        this._originOpen = this._originOpen === key ? null : key;
        this._render();
        return;
      }
      case "ask-give": {
        const minutes = Number(d.minutes);
        try {
          await this._hass.callWS({ type: "hearth/approvals/answer", request_id: d.request, minutes });
        } catch (err) {
          this._notify(this._message(err));
          return;
        }
        // A Family Safety request's time is Microsoft's: nothing of Hearth's to take back
        const undo = d.fs ? null : () => this._call("remove_time", { person: d.person, minutes });
        this._offerUndo(`Gave ${this._personName(d.person)} ${minutes} min${d.fs ? "" : ` ${WORDS.bonusShort}`}`, undo);
        return;
      }
      case "ask-no":
        this._defer(`ask|${d.request}`, `Told ${this._personName(d.person)} no`, () =>
          this._hass.callWS({ type: "hearth/approvals/answer", request_id: d.request, deny: true })
        );
        return;
      case "sugg-give": {
        const a = this._glanceAction(d.id, d.person);
        if (!a) {
          this._notify("That's no longer on offer");
          return;
        }
        await this._giveNow(d.person, a.data || {});
        return;
      }
      case "give-menu":
        this._giveMenu = this._giveMenu === d.menu ? null : d.menu;
        this._render();
        if (this._giveMenu) this.shadowRoot.querySelector?.(".givemenu button")?.focus();
        return;
      case "menu-give":
        this._giveMenu = null;
        await this._giveNow(d.person, { person: d.person, minutes: Number(d.minutes), ...(d.device ? { group: "all", device: d.device } : {}) });
        return;
      case "menu-unlock":
        this._giveMenu = null;
        await this._unlock(d.person, d.group || "all", d.device || null);
        return;
      case "sugg-dismiss": {
        const a = this._glanceAction(d.id, d.person);
        const data = a?.data || { person: d.person, key: d.key };
        this._defer(`${d.person}|${d.key}`, `Not today for ${this._personName(d.person)}`, () => this._call("dismiss_suggestion", data));
        return;
      }
      case "allow": {
        const at = d.pick.indexOf(":");
        const kind = d.pick.slice(0, at);
        const value = d.pick.slice(at + 1);
        const minutes = Number(d.minutes);
        const until = minutes ? new Date(this._now().getTime() + minutes * 60000).toISOString() : "end_of_day";
        const s = this._summaryPerson(d.person);
        const name = kind === "app" ? (s?.apps_today || []).find((a) => a.package === value)?.name || this._config?.known_apps?.[value] || value : this._groupName(value);
        this._allowOpen = false;
        this._allowQ = "";
        await this._undoable(
          "allow",
          { people: [d.person], [kind]: value, until },
          `Allowed ${name} for ${this._personName(d.person)}${minutes ? ` for ${fmtMinutes(minutes)}` : " for the rest of today"}`,
          () => this._call("allow_end", { people: [d.person], [kind]: value })
        );
        return;
      }
      case "allow-end": {
        // Undo allows it again till the same time
        const a = (this._summaryPerson(d.person)?.allows || []).find((x) => (d.app ? x.app === d.app : x.group === d.group));
        const what = d.app ? { app: d.app } : { group: d.group };
        const again = a && (a.until || a.ends_on) ? () => this._call("allow", { people: [d.person], ...what, ...(a.ends_on ? { ends_on: a.ends_on } : { until: a.until }) }) : null;
        await this._undoable("allow_end", { people: [d.person], ...what }, "Ended the allow", again);
        return;
      }
      case "undo": {
        const u = this._undo;
        this._undo = null;
        clearTimeout(this._undoTimer);
        if (u?.key) {
          // A "Not today" or "No" that hadn't run yet: it never runs, and its row is back
          const waiting = this._deferred.get(u.key);
          if (waiting) clearTimeout(waiting.timer);
          this._deferred.delete(u.key);
          this._hidden.delete(u.key);
        }
        this._render();
        if (u?.undo) {
          try {
            await u.undo();
          } catch (err) {
            this._notify(this._message(err));
          }
        }
        return;
      }
      case "kid":
        this._kid = d.kid;
        if (d.go) {
          this._tab = d.go;
          this._sheetOpen = false;
        }
        this._render();
        this._loadWatch(d.kid);
        this._loadTodo(d.kid);
        return;
      case "grant-end":
        await this._undoable("allow_end", { id: d.grant }, "Ended the extra time from the parent's app: Hearth's hold is back", null);
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
      case "answer":
        await this._ws(
          d.deny ? { type: "hearth/approvals/answer", request_id: d.request, deny: true } : { type: "hearth/approvals/answer", request_id: d.request, minutes: Number(d.minutes) },
          d.deny ? "Not now, then" : `Gave ${d.minutes} more minutes`
        );
        return;
      case "pause-start": {
        const minutes = Number(this._value("#pause-minutes")) || 45;
        const reason = this._value("#pause-reason");
        await this._service("pause", reason ? { minutes, reason } : { minutes }, `Screens paused for ${fmtMinutes(minutes)}`);
        return;
      }
      case "pause-end":
        await this._service("pause_end", {}, "Screens back on");
        return;
      case "todo-add": {
        const id = CSS.escape(d.person);
        const title = this._value(`#todo-title-${id}`);
        if (!title) return this._notify("Give the task a name");
        const kind = this._value(`#todo-repeat-${id}`) || "daily";
        const n = Number(this._value(`#todo-n-${id}`)) || 0;
        const repeat =
          kind === "school" ? { kind: "weekdays", days: [0, 1, 2, 3, 4] } : kind === "weekend" ? { kind: "weekdays", days: [5, 6] } : kind === "every_n" || kind === "after_done" ? { kind, n } : { kind };
        if (repeat.n !== undefined && !(n >= 1 && n <= 365)) return this._notify("Every 1 to 365 days");
        const rewardKind = this._value(`#todo-reward-${id}`);
        const amount = Number(this._value(`#todo-amount-${id}`)) || 0;
        let reward = null;
        // Chore minutes are bonus time (no category): kept as daily time's ("all") for the server's reward shape
        if (rewardKind === "minutes") reward = { pool: "all", minutes: Math.round(amount) };
        if (rewardKind === "money") reward = { cents: Math.round(amount * 100) };
        if (reward && !(amount > 0)) return this._notify("How much is it worth?");
        const due = this._value(`#todo-due-${id}`);
        await this._todoWs({ type: "hearth/todo/task/save", person: d.person, title, repeat, due_time: due || null, reward }, d.person, `Added ${title}`);
        return;
      }
      case "todo-del":
        if (!window.confirm("Remove this task from the list? What it gave stays given.")) return;
        await this._todoWs({ type: "hearth/todo/task/delete", task_id: d.task }, d.person, "Removed");
        return;
      case "todo-check":
        await this._todoWs({ type: "hearth/todo/check", item: d.item, done: el.checked }, d.person);
        return;
      case "todo-give":
        await this._todoWs({ type: "hearth/todo/give", item: d.item }, d.person, "Given");
        return;
      case "todo-undo":
        if (!window.confirm("Take this reward back? Minutes already used are taken too: the group can run out now.")) return;
        await this._todoWs({ type: "hearth/todo/undo", key: d.key }, d.person, "Taken back");
        return;
      case "fl-backstop":
        await this._setOption("fl_backstop", Boolean(el.checked), el.checked ? "Family Link backstop on" : "Family Link backstop off");
        return;
      case "fl-backstop-margin": {
        const margin = Math.max(0, Math.min(240, Math.round(Number(el.value) || 0)));
        await this._setOption("fl_backstop_margin", margin, `Backstop margin: ${fmtMinutes(margin)}`);
        return;
      }
      case "bonus-custom": {
        const minutes = Number(this._value(`#custom-${CSS.escape(d.person)}`));
        if (!minutes) return this._notify("Give a number of minutes (negative takes time away)");
        // Bonus time (no category); a negative number takes bonus time back
        if (minutes > 0) await this._service("add_time", { person: d.person, minutes }, `Done: +${minutes} min ${WORDS.bonusShort}`);
        else await this._service("remove_time", { person: d.person, minutes: -minutes }, `Done: ${minutes} min ${WORDS.bonusShort}`);
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
          `${WORDS.daily}: ${fmtMinutes(Number(d.minutes))}`
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
      case "adult-offer": {
        // Make adult sets the role (the entry reloads with it); Not now: never asked again
        await this._service(
          "adult_offer_answer",
          { person: d.person, answer: d.answer },
          d.answer === "adult" ? `${this._personName(d.person)}: adult` : "Not asked again"
        );
        await new Promise((r) => setTimeout(r, 900));
        await this._loadConfig();
        return;
      }
      case "panel-hello": {
        const area = this._value(`#hello-area-${CSS.escape(d.hello)}`) || null;
        const replaces = this._value(`#hello-replaces-${CSS.escape(d.hello)}`) || null;
        if (d.answer === "approve" && !area) return this._notify("Pick the panel's room first");
        await this._ws(
          { type: "hearth/panel_hello", device_id: d.hello, answer: d.answer, area_id: area, replaces },
          d.answer === "approve" ? "Panel added" : "Refused"
        );
        await this._loadConfig();
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
      case "away-app-add":
      case "away-app-remove": {
        const all = { ...(this._config.away_messages_apps || {}) };
        const mine = [...(all[d.person] || [])];
        const pick = action === "away-app-add" ? this._value(`#away-app-${CSS.escape(d.person)}`) : d.package;
        if (!pick) return this._notify("Pick an app first");
        all[d.person] = action === "away-app-add" ? [...new Set([...mine, pick])] : mine.filter((p) => p !== pick);
        if (!all[d.person].length) delete all[d.person];
        await this._setOption("away_messages_apps", all, action === "away-app-add" ? "App added" : "App removed");
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
          const player = this._value(`#enf-nin-player-${CSS.escape(person)}`);
          kept.push({
            kind: "nintendo", person, entity_id: nin, groups,
            ...(playing ? { playing: [playing] } : {}),
            ...(player ? { player: [player] } : {}),
          });
        }
        await this._setOption("enforce", kept, "Parental controls saved");
        return;
      }
      case "away-messages":
        await this._setOption("away_messages", el.checked, el.checked ? "Messages when away on" : "Messages when away off");
        return;
      case "voice-assistants":
        await this._setOption("voice_assistants", el.checked, el.checked ? "Voice assistants on" : "Voice assistants off");
        return;
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
      case "app-category": {
        // What the app is, said by an adult ("auto": Hearth's answer again); its group then follows what it is
        const [category, detail] = String(el.value).split("/");
        const said = category === "auto" ? "Hearth decides again" : `Now ${this._categoryLabel(category, detail)}`;
        await this._ws({ type: "hearth/apps/category", app: d.app, category, ...(detail ? { detail } : {}) }, said);
        await new Promise((r) => setTimeout(r, 900));
        await this._loadConfig();
        return;
      }
      case "app-source":
        this._appSource = el.value;
        this._render();
        return;
      case "app-confirm": {
        // Right where it is: it stays there whatever Hearth learns about the app later
        const moved = { ...(cfg.app_groups || {}), [d.app]: d.group };
        await this._setOption("app_groups", moved, `Kept in ${d.group === "other" ? "Other" : this._groupName(d.group)}`);
        return;
      }
      case "block-browsers":
        await this._setOption("block_unsupported_browsers", el.checked, el.checked ? "Browsers Hearth doesn't support get blocked" : "Browser rule off: Hearth unblocks what it blocked for it");
        return;
      case "block-ai-companions":
        await this._setOption("block_ai_companions", el.checked, el.checked ? "AI companion apps get blocked" : "AI companion rule off: Hearth unblocks what it blocked for it");
        return;
      case "app-block": {
        // Every kid with Family Link (the service's default); Hearth keeps the block and puts it back when the app returns
        const name = d.name || d.app;
        // A messages app: blocking it (unlike pausing it) makes it miss incoming texts
        if (MESSAGES_APPS.includes(d.app) && !window.confirm(`Blocking ${name} makes it miss incoming texts; pausing it keeps them. Block it anyway?`)) return;
        await this._service("block_app", { app: d.app }, `${name} blocked for every kid`);
        await this._loadConfig();
        return;
      }
      case "app-block-kid": {
        // A block a parent took back in Family Link: blocking it again in Hearth makes it Hearth's again
        const name = d.name || d.app;
        await this._service("block_app", { app: d.app, people: [d.person] }, `${name} blocked for ${this._personName(d.person)}`);
        await this._loadConfig();
        return;
      }
      case "app-unblock": {
        const name = d.name || d.app;
        await this._service("unblock_app", { app: d.app, people: [d.person] }, `${name} unblocked for ${this._personName(d.person)}`);
        await this._loadConfig();
        return;
      }
      case "category-lookup":
        await this._setOption("category_lookup", el.checked, el.checked ? "New apps are looked up in their store" : "No store lookups");
        return;
      case "category-ai":
        await this._setOption("category_ai_task", el.value, el.value === "off" ? "No AI is asked" : "Unclear apps go to the AI");
        return;
      case "client-settings-clear":
        if (!window.confirm(`Remove everything Hearth keeps for ${d.client}? The app's settings on every device go with it.`)) return;
        await this._ws({ type: "hearth/client_settings/clear", client: d.client }, "Removed");
        await this._loadConfig();
        return;
      case "category-pool": {
        const own = { ...(cfg.categories?.own_pools || {}) };
        if (el.value) own[d.value] = el.value;
        else delete own[d.value];
        await this._setOption("catalog_pools", own, "Saved");
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
        if (!window.confirm(`Remove the category ${this._groupName(d.group)}? Its limits go with it.`)) return;
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
        const what = d.group === "all" ? WORDS.daily : this._groupName(d.group);
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
        const minutes = Number(d.minutes) || Number(this._value(`#kid-pause-${CSS.escape(d.person)}`)) || 30;
        await this._undoable("pause", { people: [d.person], minutes }, `Paused ${this._personName(d.person)}'s screens for ${fmtMinutes(minutes)}`, () =>
          this._call("pause_end", { people: [d.person] })
        );
        return;
      }
      case "kid-pause-end": {
        const was = this._summaryPerson(d.person)?.pause;
        await this._undoable("pause_end", { people: [d.person] }, `${this._personName(d.person)}'s screens are back on`, was?.until ? () => this._call("pause", { people: [d.person], until: was.until }) : null);
        return;
      }
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
        this._moreOpen = false;
        await this._undoable("school_time_off", { people: [d.person] }, `No School time today for ${this._personName(d.person)}`, () =>
          this._call("school_time_off_cancel", { people: [d.person] })
        );
        return;
      case "school-off-cancel":
        this._moreOpen = false;
        await this._undoable("school_time_off_cancel", { people: [d.person] }, "School time is back today", () => this._call("school_time_off", { people: [d.person] }));
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
      case "nin-let-play": {
        const minutes = Number(d.minutes);
        await this._ws(
          { type: "hearth/nintendo/let_play", person: d.person, device_id: d.device, minutes },
          minutes ? `The Switch is open for ${minutes < 60 ? `${minutes} min` : `${minutes / 60} h`}` : "The Switch is held again"
        );
        return;
      }
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
      lists.push(p?.actions || [], ...[...(p?.suggestions || []), ...(p?.suggestions_held || [])].map((s) => s.actions || []));
      lists.push(...(h.suggestions || []).filter((s) => s.person === person).map((s) => s.actions || []));
    } else lists.push(h.actions || []);
    for (const list of lists) {
      const found = list.find((a) => a.id === id);
      if (found) return found;
    }
    return null;
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

  // A button's identity across a redraw: its id, else its action and data (the same button draws the same data)
  _focusKey(el) {
    if (!el) return null;
    if (el.id) return `#${el.id}`;
    if (!el.dataset?.action) return null;
    return `${el.dataset.action}|${JSON.stringify({ ...el.dataset })}`;
  }

  // The page is drawn whole, but only when it changed: an unchanged page isn't touched (open menus, focus and a tap in
  // flight stay), and the toast lives outside the redrawn part, so its countdown runs on and it isn't announced again
  _render() {
    const root = this.shadowRoot;
    const html = this._body();
    const toast = this._toastHtml();
    let body = root.querySelector?.(".hp-body");
    let slot = root.querySelector?.(".hp-toast");
    if (!body || !slot) {
      root.innerHTML = `<style>${STYLE}</style><div class="hp-body"></div><div class="hp-toast" aria-live="polite"></div>`;
      body = root.querySelector?.(".hp-body");
      slot = root.querySelector?.(".hp-toast");
      this._lastBody = null;
      this._lastToast = null;
    }
    if (!body || !slot) {
      // No DOM to keep (a test's stand-in): the whole page
      root.innerHTML = `<style>${STYLE}</style>${html}${toast}`;
    } else {
      // By what it says, not its markup (its bar's delay moves with the clock)
      const toastKey = this._undo ? `undo|${this._undo.at}|${this._undo.text}` : this._toast || "";
      if (toastKey !== this._lastToast) {
        slot.innerHTML = toast;
        this._lastToast = toastKey;
      }
      if (html === this._lastBody) {
        this._afterRender(false);
        return;
      }
      this._lastBody = html;
    }
    const focused = root.activeElement;
    const focusKey = this._focusKey(focused);
    const focusValue = focused && "value" in focused ? focused.value : null;
    // The kid's sheet keeps its place when the numbers move under it
    const sheetTop = root.querySelector?.(".detail")?.scrollTop || 0;
    if (body && slot) body.innerHTML = html;
    const sheet = root.querySelector?.(".detail");
    if (sheet && sheetTop) sheet.scrollTop = sheetTop;
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
    if (focusKey) {
      const again = focusKey.startsWith("#")
        ? root.getElementById(focusKey.slice(1))
        : [...(root.querySelectorAll?.("[data-action]") || [])].find((el) => this._focusKey(el) === focusKey);
      if (again) {
        again.focus({ preventScroll: true });
        if (focusValue !== null && again.value !== focusValue && again.tagName === "INPUT") again.value = focusValue;
        // A search box keeps typing at its end
        if (again.tagName === "INPUT" && again.type === "search" && again.setSelectionRange) again.setSelectionRange(again.value.length, again.value.length);
      }
    }
    this._afterRender(true);
  }

  // [drawn]: the page was replaced (the schedule's handles need their listeners again)
  _afterRender(drawn) {
    if (drawn && this._tab === "schedule" && this._sched && this._setupStep === null) this._schBindDrag();
    this._placeGiveMenu();
    this._showAsk();
  }

  // The "+" box's menu opens below its box, left-aligned; it turns to end at the box's right edge when it would run off
  // a phone's screen, and opens above when there's no room below
  _placeGiveMenu() {
    const m = this.shadowRoot.querySelector?.(".givemenu");
    if (!m?.getBoundingClientRect || typeof window.innerWidth !== "number") return;
    const r = m.getBoundingClientRect();
    if (r.right > window.innerWidth - 8) m.classList.add("end");
    const box = m.parentElement.getBoundingClientRect();
    if (r.bottom > window.innerHeight - 8 && box.top - r.height - 6 > 8) m.classList.add("up");
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

  _body() {
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
    else body = { today: () => this._today(), kids: () => this._kidsTab(), schedule: () => this._scheduleTab(), devices: () => this._devicesTab(), apps: () => this._appsTab(), family: () => this._familyTab() }[this._tab]();
    return `${toolbar}<main class="content ${["today", "schedule"].includes(this._tab) && this._setupStep === null ? "wide" : ""}">${body}</main>`;
  }

  // The toast: a message, or what was just done with its Undo and a bar that runs down
  _toastHtml() {
    if (this._undo)
      return `<div class="toast undo" role="status"><span>${esc(this._undo.text)}</span>${this._undo.undo || this._undo.key ? `<button data-action="undo">Undo</button>` : ""}<i class="tbar" style="animation-duration:${UNDO_MS}ms;animation-delay:-${Math.max(0, Date.now() - this._undo.at)}ms"></i></div>`;
    return this._toast ? `<div class="toast" role="status">${esc(this._toast)}</div>` : "";
  }

  // The whole page, the toast included
  _page() {
    return this._body() + this._toastHtml();
  }

  // Schedule (the weekly schedule, weekly.py): each kid's week of modes and limits, the editor with drag, copy,
  // today-only changes and the family's modes. Edits go to hearth/schedule/* and come back as the whole view.

  async _loadSchedule() {
    if (this._schLoading) return;
    this._schLoading = true;
    try {
      const answer = await this._hass.callWS({ type: "hearth/schedule/get" });
      this._sched = answer.schedule;
      this._schError = null;
    } catch (err) {
      this._schError = this._message(err);
    } finally {
      this._schLoading = false;
    }
    this._render();
  }

  // An edit: sent at once, the answer's view replaces the page's; Undo offered with [text]
  async _schSend(message, text) {
    try {
      const answer = await this._hass.callWS(message);
      this._sched = answer.schedule;
      if (text && answer.undo) {
        const token = typeof answer.undo === "string" ? answer.undo : null;
        this._offerUndo(text, token ? async () => this._schUndo(token) : null);
      } else if (text) this._notify(text);
      else this._render();
    } catch (err) {
      this._notify(this._message(err));
      await this._loadSchedule();
    }
  }

  async _schUndo(token) {
    const answer = await this._hass.callWS({ type: "hearth/schedule/undo", token });
    this._sched = answer.schedule;
    this._notify("Undone");
  }

  _schKid() {
    const kids = this._sched?.kids || [];
    if (!kids.some((k) => k.id === this._schKidId)) this._schKidId = kids[0]?.id || null;
    return kids.find((k) => k.id === this._schKidId) || null;
  }

  _schTodayKey() {
    const today = this._sched?.today;
    return (this._sched?.week || []).find((d) => d.date === today)?.key || SCH_DAYS[(new Date().getDay() + 6) % 7];
  }

  _schNowMin() {
    const now = new Date();
    return now.getHours() * 60 + now.getMinutes();
  }

  _schModes() {
    return this._sched?.modes || {};
  }

  _schModeName(id) {
    return this._schModes()[id]?.name || id;
  }

  // A day's changes and limits as shown: the weekly day, today's own copy (Today only), or the half day worked out
  _schDay(kid, key, scope = "weekly") {
    if (key === "half_day") {
      const base = kid.days[this._schHalfBase()] || { changes: [], limits: {} };
      const half = kid.half_day || {};
      const changes = schHalfChanges(base.changes.map(([at, m]) => [schMin(at), m]), this._schModes(), half.school_ends ? schMin(half.school_ends) : null, half.early || null);
      const limits = half.limits === "weekday" ? base.limits : (kid.days.day_off || {}).limits;
      return { changes, limits: { ...(limits || {}) } };
    }
    const own = kid.days[key] || { changes: [], limits: {} };
    const day = { changes: own.changes.map(([at, m]) => [schMin(at), m]), limits: { ...(own.limits || {}) } };
    const today = kid.today;
    if (scope === "today" && key === this._schTodayKey() && today && today.date === this._sched.today) {
      if (today.changes) day.changes = today.changes.map(([at, m]) => [schMin(at), m]);
      if (today.limits) day.limits = { ...day.limits, ...today.limits };
    }
    return day;
  }

  // The weekday the Half day's row draws (the next half day this week, else Monday)
  _schHalfBase() {
    const half = (this._sched?.week || []).find((d) => d.type === "half_day");
    return half ? half.key : "mon";
  }

  _schPrevKey(key) {
    if (key === "day_off" || key === "half_day") return "sun";
    return SCH_DAYS[(SCH_DAYS.indexOf(key) + 6) % 7];
  }

  _schSegments(kid, key, scope = "weekly") {
    const day = this._schDay(kid, key, scope);
    let carry = null;
    let back = this._schPrevKey(key);
    for (let i = 0; i < 8 && carry === null; i++) {
      const prev = this._schDay(kid, back);
      if (prev.changes.length) carry = prev.changes[prev.changes.length - 1][1];
      back = this._schPrevKey(back);
    }
    const out = [];
    let at = 0;
    let mode = carry;
    let carried = true;
    for (const [minute, changed] of day.changes) {
      if (minute > at && mode !== null) out.push({ s: at, e: minute, mode, carried });
      at = minute;
      mode = changed;
      carried = false;
    }
    if (mode !== null) out.push({ s: at, e: 1440, mode, carried });
    return out;
  }

  _schColor(id) {
    const known = { sleep: "var(--h-night)", school: "var(--h-school)", free: "var(--h-ok)", homework: "var(--m-homework)", wind: "var(--m-wind)" };
    if (known[id]) return known[id];
    const ids = Object.keys(this._schModes()).filter((m) => !known[m]);
    return `var(--p-x${Math.max(0, ids.indexOf(id)) % 4})`;
  }

  _schBar(kid, key, { now = false, scope = "weekly", labels = false } = {}) {
    const segs = this._schSegments(kid, key, scope);
    const parts = segs
      .map(
        (s) => `<div class="s-seg ${s.carried ? "carried" : ""}" style="left:${schPct(s.s)};width:${schPct(s.e - s.s)};background:${this._schColor(s.mode)}" title="${esc(this._schModeName(s.mode))} ${schClock(s.s)}–${schClock(s.e)}">${labels && s.e - s.s >= 75 ? `<span>${esc(this._schModeName(s.mode))}</span>` : ""}</div>`
      )
      .join("");
    return `<div class="s-bar">${parts}${now ? `<i class="s-nowl" style="left:${schPct(this._schNowMin())}"></i>` : ""}</div>`;
  }

  _schAxis() {
    return `<div class="s-ticks">${[0, 6, 12, 18, 24].map((h) => `<span style="left:${(h / 24) * 100}%">${h === 0 || h === 24 ? "12a" : h === 12 ? "12p" : h < 12 ? `${h}a` : `${h - 12}p`}</span>`).join("")}</div>`;
  }

  _schIsSleep(mode) {
    return this._schModes()[mode]?.allows === "nothing";
  }

  _schIsSchool(mode) {
    return this._schModes()[mode]?.allows === "school";
  }

  _schBed(day) {
    const last = day.changes[day.changes.length - 1];
    return last && this._schIsSleep(last[1]) ? last[0] : null;
  }

  _schWeekRow(kid, i) {
    const key = SCH_DAYS[i];
    const date = (this._sched.week || [])[i];
    const isToday = date?.date === this._sched.today;
    const changedToday = isToday && kid.today?.date === this._sched.today;
    const day = this._schDay(kid, key, changedToday ? "today" : "weekly");
    const bed = this._schBed(day);
    const sum = [];
    if (changedToday) sum.push(`<span class="s-tag over">Changed for today</span>`);
    if (bed !== null) sum.push(`Bed ${schShort(bed)}`);
    if (day.changes.some(([, m]) => this._schIsSchool(m))) sum.push("School");
    sum.push(`${schDur(day.limits.all)} a day`);
    const uses = (kid.this_week || [])[i]?.uses;
    const dm = date ? schDayMonth(date.date) : "";
    if (uses === "day_off") sum.push(`<span class="s-tag off">${esc(dm)}: day off</span>`);
    else if (uses === "half_day") sum.push(`<span class="s-tag half">${esc(dm)}: half day</span>`);
    else if (date && date.type === "school" && i >= 5) sum.push(`<span class="s-tag half">${esc(dm)}: school day</span>`);
    const label = date ? `<small>${isToday ? '<span class="s-today">Today</span>' : esc(dm)}</small>` : "";
    return `<button class="s-wrow" data-action="sch-day" data-day="${key}" aria-current="${this._schDayKey === key}">
      <span class="s-dl">${SCH_SHORT[key]}${label}</span>${this._schBar(kid, key, { now: isToday, scope: changedToday ? "today" : "weekly" })}
      <span></span><span class="s-sum">${sum.join("<span>·</span>")}</span></button>`;
  }

  _schSpecialRow(kid, key) {
    const day = this._schDay(kid, key);
    const sum = [];
    if (key === "day_off") {
      const bed = this._schBed(day);
      if (bed !== null) sum.push(`Bed ${schShort(bed)}`);
      sum.push(day.changes.some(([, m]) => this._schIsSchool(m)) ? "School" : "No School", `${schDur(day.limits.all)} a day`, "Days off and weekdays with no school");
    } else {
      const half = kid.half_day || {};
      sum.push(half.early ? `School ends ${schDur(half.early)} early` : `School ends ${schShort(schMin(half.school_ends || "12:00"))}`);
      sum.push(half.limits === "weekday" ? "The weekday's limits" : "Day off's limits", "Otherwise the weekday's times");
    }
    return `<button class="s-wrow" data-action="sch-day" data-day="${key}" aria-current="${this._schDayKey === key}">
      <span class="s-dl">${key === "day_off" ? "Day<br>off" : "Half<br>day"}</span>${this._schBar(kid, key)}
      <span></span><span class="s-sum">${sum.join("<span>·</span>")}</span></button>`;
  }

  _schNowCard(kid) {
    const now = kid.now;
    if (!now) {
      return `<div class="card s-nowcard"><span class="s-dot" style="background:var(--h-surface-2)">${icon("info")}</span><div class="s-grow">
        <div class="s-t">${esc(kid.name)} has no times yet</div>
        <div class="s-d">Each day's limits count as set below. Bedtime and School time come from Family Link until you add them here.</div></div></div>`;
    }
    const mode = this._schModes()[now.mode.id] || {};
    const until = now.mode.until ? ` until ${schIsoClock(now.mode.until)}` : "";
    const then = now.next ? `, then ${esc(now.next.name || now.next.mode)}` : "";
    const ic = mode.allows === "nothing" ? "moon" : mode.allows === "school" ? "school" : mode.allows === "some" ? "book" : "sun";
    const color = this._schColor(now.mode.id);
    const changed = now.day?.changed_today;
    return `<div class="card s-nowcard"><span class="s-dot" style="background:color-mix(in srgb, ${color} 16%, transparent);color:${color}">${icon(ic)}</span><div class="s-grow">
      <div class="s-t">${esc(kid.name)}: ${esc(now.mode.name)}${esc(until)}${then}</div>
      <div class="s-d">${esc(mode.description || "")}${now.bedtime?.at ? ` Bedtime at ${esc(schIsoClock(now.bedtime.at))}.` : ""}${changed ? " Changed for today only." : ""}</div></div>
      ${changed ? `<button class="b sm" data-action="sch-resume">Back to the schedule</button>` : ""}</div>`;
  }

  _schComingUp() {
    const rows = this._sched.coming_up || [];
    if (!rows.length) return `<div class="card flat s-up"><div class="s-uprow"><div class="s-grow s-d">No days off or half days in the next three weeks.</div></div></div>`;
    const words = { day_off: "Day off", half_day: "Half day", school: "School day" };
    const src = { typed: "From the dates you typed in", calendar: "From the school calendar", entity: "From your day-type helper", rule: "From the school year", date: "From the dates you typed in" };
    return `<div class="card flat s-up">${rows
      .map((r) => {
        const d = new Date(`${r.date}T12:00:00`);
        const what = r.type === "day_off" ? "the Day off's schedule, no School." : r.type === "half_day" ? "School ends early; the Half day's limits." : "the Friday schedule.";
        return `<div class="s-uprow"><span class="s-cal"><small>${d.toLocaleDateString("en", { weekday: "short" })}</small><b>${d.getDate()}</b></span>
          <div class="s-grow"><div class="s-t">${words[r.type] || r.type}</div><div class="s-d">${cap(what)} ${esc(src[r.source] || "")}.</div></div></div>`;
      })
      .join("")}</div>`;
  }

  _schModesCard() {
    const modes = this._schModes();
    return `<div class="card flat s-modes">${Object.entries(modes)
      .map(([id, m]) => `<button class="s-mrow" data-action="sch-mode" data-mode="${esc(id)}"><span class="s-sw" style="background:${this._schColor(id)}"></span>
        <div class="s-grow"><div class="s-t">${esc(m.name)}</div><div class="s-d">${esc(m.description || "")}</div></div>${icon("edit", "sm muted")}</button>`)
      .join("")}${Object.keys(modes).length < 8 ? `<button class="s-mrow" data-action="sch-mode" data-mode=""><span class="s-sw" style="border:1.5px dashed var(--secondary-text-color)"></span><div class="s-grow"><div class="s-t lnk">Add a mode</div></div></button>` : ""}</div>`;
  }

  _schControls(kid) {
    const has = new Set(kid.controls || []);
    const lines = [{ name: "The TV and Hearth phones", sub: "Hearth", d: "Everything as scheduled, to the minute: locked in Sleep and School, closed groups held." }];
    const syncing = kid.sync?.state === "on";
    if (has.has("family_link")) lines.push({ name: "Family Link", sub: "phones and tablets", d: syncing ? "Hearth keeps its bedtime in step. School time stays Family Link's own. During modes that close groups, Hearth pauses those groups' apps." : "Keeps its own bedtime and School time for now. During modes that close groups, Hearth pauses those groups' apps." });
    if (has.has("family_safety")) lines.push({ name: "Xbox and Windows", sub: "Family Safety", d: `Hearth locks them during Sleep, School and modes that close their groups.${syncing ? " Their allowed hours follow bedtime and wake." : ""}` });
    if (has.has("nintendo")) lines.push({ name: "Switch", sub: "Nintendo", d: "Hearth holds it during Sleep, School and modes that close its groups." });
    return `<div class="s-subh"><span>How Hearth holds it</span><span style="font-weight:500">today</span></div>
      <ul class="s-sync">${lines.map((l) => `<li><span class="s-ic ok">${icon("check", "sm")}</span><div class="s-t">${esc(l.name)} <small>${esc(l.sub)}</small></div><div class="s-d">${esc(l.d)}</div></li>`).join("")}</ul>
      ${has.size ? `<div class="s-hint">${syncing ? "Bedtime and wake are kept in step in Family Link and Family Safety. School time and the Switch's own schedule aren't sent yet." : "Bedtime and wake can be kept in step in Family Link and Family Safety from the Bedtime card. School time and the Switch's own schedule aren't sent yet."}</div>` : ""}`;
  }

  // The Bedtime card (bedtime_sync.py): tonight's bedtime with "Change tonight" (tonight only), each weekday's for good,
  // the apps' sync status, a parent's change made in an app, and the first sync's preview
  _schBedCard(kid) {
    const bed = kid.bedtime;
    if (!bed) return "";
    const sync = kid.sync;
    const days = [...SCH_DAYS, "day_off"];
    const at = (v) => (v ? esc(schClock(schMin(v))) : "–");
    const t = bed.tonight || {};
    const tonight = t.bedtime
      ? `${at(t.bedtime)} → ${t.wake ? `${at(t.wake)} tomorrow` : "morning"}`
      : "No bedtime tonight";
    const banner = t.changed && t.bedtime
      ? `<div class="s-bnr"><span class="s-grow">Tonight only: ${at(t.bedtime)}${t.wake && t.wake !== t.usual_wake ? `, wake ${at(t.wake)}` : ""} (usually ${at(t.usual_bedtime)}${t.wake && t.wake !== t.usual_wake ? `, ${at(t.usual_wake)}` : ""})</span><button class="b sm ghost" data-action="sch-resume">Back to the schedule</button></div>`
      : "";
    const today = this._schTodayKey();
    const chips = days
      .map((k) => {
        const d = bed.days[k] || {};
        return `<button class="s-bchip ${k === today && t.changed ? "marked" : ""}" data-action="sch-bed-open" data-scope="days" data-day="${k}" aria-label="${esc(SCH_LONG[k])}: bedtime ${d.bedtime ? esc(schClock(schMin(d.bedtime))) : "none"}"><small>${esc(SCH_SHORT[k])}</small><b>${d.bedtime ? esc(schShort(schMin(d.bedtime))) : "–"}</b><i>${d.wake ? esc(schShort(schMin(d.wake))) : "–"}</i></button>`;
      })
      .join("");
    const names = { family_link: "Family Link", family_safety: "" };
    const marks = { in_sync: [icon("check", "sm"), "ok", "In step"], writing: [icon("more", "sm"), "wait", "Writing"], waiting: [icon("pause", "sm"), "wait", "Waiting"], failed: ["<b>!</b>", "bad", "Didn't take"], unsupported: ["<b>!</b>", "bad", "Can't be set there"], differs: ["<b>?</b>", "warn", "Changed in the app"], off: ["<b>–</b>", "", "Off"] };
    const pills = (sync?.services || [])
      .map((s, i) => {
        const [mark, cls, word] = marks[s.status] || marks.waiting;
        const name = s.platform || names[s.via] || s.via;
        return `<button class="s-pill ${cls}" data-action="sch-sync-pill" data-i="${i}" aria-label="${esc(name)}: ${esc(word)}" aria-pressed="${this._schPill === i}">${esc(name)} ${mark}</button>`;
      })
      .join("");
    let detail = "";
    const open = sync?.services?.[this._schPill];
    if (open) {
      const rows = Object.entries(open.days || {})
        .map(([day, e]) => {
          const key = open.via === "family_link" ? SCH_DAYS[Number(day) - 1] : SCH_DAYS[(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"].indexOf(day) + 6) % 7];
          const value = e.theirs || e.written || e.want;
          const shown = Array.isArray(value) ? `${esc(schClock(schMin(value[0])))}–${esc(schClock(schMin(value[1])))}` : value === "several" ? "several windows" : "–";
          return `<li><span>${esc(SCH_SHORT[key] || day)}</span><span class="s-grow">${shown}</span><span class="muted">${esc(e.reason || "")}</span></li>`;
        })
        .join("");
      const offer = (sync.offers || []).find((o) => o.via === open.via && (o.platform || null) === (open.platform || null));
      detail = `<div class="s-pilld"><div class="s-d">${esc(open.reason || marks[open.status]?.[2] || "")}${open.next_try ? ` · tried again at ${esc(schIsoClock(open.next_try))}` : ""}</div>
        <ul class="s-pdays">${rows}</ul>
        <div class="s-acts"><button class="b sm" data-action="sch-sync-check">Check now</button>
        ${offer ? `<button class="b sm" data-action="sch-offer" data-offer="${esc(offer.id)}" data-accept="0">Put Hearth's back</button>` : ""}
        ${open.status === "off" && sync.state === "on" ? `<button class="b sm" data-action="sch-fl-on">Turn it back on</button>` : ""}</div></div>`;
    }
    const offers = (sync?.offers || [])
      .map((o) => {
        const app = o.via === "family_link" ? "Family Link" : `Family Safety${o.platform ? ` (${o.platform})` : ""}`;
        if (!o.adoptable) return `<div class="s-bnr warn"><span class="s-grow">${esc(app)} has several windows on ${esc(SCH_LONG[o.day])}, which Hearth can't keep in step.</span><button class="b sm" data-action="sch-offer" data-offer="${esc(o.id)}" data-accept="0">Put Hearth's back</button></div>`;
        return `<div class="s-bnr warn"><span class="s-grow">Changed in ${esc(app)}: ${esc(SCH_LONG[o.day])} bedtime ${at(o.bedtime)} (Hearth has ${at(o.was?.bedtime)})</span>
          <button class="b sm primary" data-action="sch-offer" data-offer="${esc(o.id)}" data-accept="1">Make it every ${esc(SCH_LONG[o.day])}</button>
          <button class="b sm ghost" data-action="sch-offer" data-offer="${esc(o.id)}" data-accept="0">Put ${at(o.was?.bedtime)} back</button></div>`;
      })
      .join("");
    return `<div class="card s-bed"><div class="s-bedh"><h2 class="s-grow">Bedtime</h2>${pills}</div>${detail}
      <div class="s-tonight"><span class="s-t">Tonight</span><span class="s-grow">${tonight}</span><button class="b sm" data-action="sch-bed-open" data-scope="today">Change tonight</button></div>
      ${banner}<div class="s-bchips">${chips}</div>${offers}${this._schReview(kid)}</div>`;
  }

  // Before the first sync: what each app gets, and the one button that starts it
  _schReview(kid) {
    if (kid.sync?.state !== "review") return "";
    const preview = this._schPreview?.[kid.id]?.preview;
    if (!preview) {
      if (!this._schPreviewLoading) setTimeout(() => this._schLoadPreview(), 0);
      return `<div class="s-review"><div class="s-d">Working out what keeping bedtimes in step would change…</div></div>`;
    }
    if (preview.start_from === "none") return `<div class="s-review"><div class="s-d">Nothing to keep in step yet: ${esc(kid.name)} has no bedtime here or in the apps.</div></div>`;
    const from = preview.start_from;
    const where = from === "hearth" ? "Hearth's schedule" : from === "family_link" ? "Family Link's bedtime" : "Family Safety's allowed hours";
    const fl = (preview.family_link || []).filter((r) => r.write);
    const fs = (preview.family_safety || []).filter((r) => r.write);
    const flips = ["hearth", "family_link", "family_safety"].filter((f) => f !== from)
      .map((f) => `<button class="b sm ghost" data-action="sch-sync-flip" data-from="${f}">Start from ${f === "hearth" ? "Hearth's" : f === "family_link" ? "Family Link's" : "Family Safety's"}</button>`)
      .join("");
    const rows = SCH_DAYS.map((k) => {
      const d = preview.days?.[k] || {};
      return `<li><span>${esc(SCH_SHORT[k])}</span><span class="s-grow">${d.bedtime ? esc(schClock(schMin(d.bedtime))) : "–"} → ${d.wake ? esc(schClock(schMin(d.wake))) : "–"}</span></li>`;
    }).join("");
    return `<div class="s-review"><div class="s-t">Bedtimes can now be kept in step</div>
      <div class="s-d">Starting from ${esc(where)}. ${fl.length ? `Family Link gets ${fl.length} night${fl.length === 1 ? "" : "s"}` : "Family Link already matches"}${preview.switch_on ? ", and its bedtime is switched on" : ""}; ${fs.length ? `Family Safety gets ${fs.length} day${fs.length === 1 ? "" : "s"}` : "Family Safety already matches"}.${(preview.unsupported || []).length ? ` ${preview.unsupported.length} can't be set there.` : ""}</div>
      <ul class="s-pdays">${rows}</ul>
      <div class="s-acts">${flips}<button class="b primary" data-action="sch-sync-start">Start keeping bedtimes in step</button></div></div>`;
  }

  async _schLoadPreview() {
    if (this._schPreviewLoading) return;
    this._schPreviewLoading = true;
    try {
      const answer = await this._hass.callWS({ type: "hearth/schedule/sync", ...(this._schFrom ? { start_from: this._schFrom } : {}) });
      this._schPreview = answer.sync;
    } catch (err) {
      this._schPreview = {};
      this._notify(this._message(err));
    } finally {
      this._schPreviewLoading = false;
    }
    this._render();
  }

  _schEditor(kid) {
    const key = this._schDayKey;
    const todayKey = this._schTodayKey();
    const isToday = key === todayKey;
    const scope = isToday ? this._schScope : "weekly";
    const half = key === "half_day";
    const day = this._schDay(kid, key, scope);
    const segs = this._schSegments(kid, key, scope);
    const modes = this._schModes();
    const title = SCH_LONG[key];
    const weekIndex = SCH_DAYS.indexOf(key);
    const date = weekIndex >= 0 ? (this._sched.week || [])[weekIndex] : null;
    const uses = weekIndex >= 0 ? (kid.this_week || [])[weekIndex]?.uses : null;
    const sub = key === "day_off"
      ? "Used on days off from school and on weekdays outside the school year."
      : half
        ? "A school day that ends early: the weekday's times, with School ending at this time."
        : `Every ${title}${uses === "day_off" || uses === "half_day" ? `, except ${schDayMonth(date.date)} (${uses === "day_off" ? "a day off" : "a half day"})` : ""}.`;
    const scopeCtl = isToday
      ? `<div class="s-segc" role="group" aria-label="Which ${esc(title)}"><button data-action="sch-scope" data-scope="weekly" aria-pressed="${scope === "weekly"}">Every ${esc(title)}</button><button data-action="sch-scope" data-scope="today" aria-pressed="${scope === "today"}">Today only</button></div>`
      : "";
    const handles = half
      ? ""
      : day.changes
          .map(([tm], i) => `<button class="s-hnd" data-i="${i}" style="left:${schPct(tm)}" aria-label="Change at ${schClock(tm)}; arrow keys move it 15 minutes"><i></i><span class="s-tip">${schClock(tm)}</span></button>`)
          .join("");
    const big = `<div class="s-big" id="sch-big">${this._schBar(kid, key, { now: isToday, scope, labels: true })}${handles}<div class="s-axis">${this._schAxis()}</div></div>`;
    const first = segs[0];
    const carried = first && first.carried && day.changes.length
      ? `<li class="s-blk"><span class="s-carried">From ${key === "day_off" || half ? "the night before" : SCH_SHORT[this._schPrevKey(key)]}</span><span class="s-chip" style="background:color-mix(in srgb, ${this._schColor(first.mode)} 16%, transparent);color:${this._schColor(first.mode)}">${esc(this._schModeName(first.mode))}</span><span class="s-x"></span></li>`
      : "";
    const options = (m) => Object.entries(modes).map(([id, md]) => `<option value="${esc(id)}" ${id === m ? "selected" : ""}>${esc(md.name)}</option>`).join("");
    const rows = day.changes
      .map(([tm, m], i) => `<li class="s-blk"><input class="s-tm" type="time" step="900" value="${schHhmm(tm)}" data-change="sch-time" data-i="${i}" aria-label="Starts at" ${half ? "disabled" : ""}>
        <select data-change="sch-modesel" data-i="${i}" aria-label="Mode" ${half ? "disabled" : ""}>${options(m)}</select>
        ${half ? '<span class="s-x"></span>' : `<button class="s-x" data-action="sch-del" data-i="${i}" aria-label="Remove">${icon("close", "sm")}</button>`}</li>`)
      .join("");
    const empty = !day.changes.length && !half ? `<li class="s-blk"><span class="s-d">No times yet: the day's limits count, and Family Link's bedtime and School time hold.</span></li>` : "";
    const halfCtl = half
      ? `<div class="s-subh"><span>School ends at</span></div>
        <div class="s-blk" style="border:0"><input class="s-tm" type="time" step="900" value="${esc((kid.half_day || {}).school_ends || "12:00")}" data-change="sch-half" aria-label="School ends at">
        <select data-change="sch-half-limits" aria-label="Limits"><option value="day_off" ${(kid.half_day || {}).limits !== "weekday" ? "selected" : ""}>The Day off's limits</option><option value="weekday" ${(kid.half_day || {}).limits === "weekday" ? "selected" : ""}>The weekday's limits</option></select></div>`
      : "";
    const groups = (this._sched.groups || []).filter((g) => g.in_all || g.id === "all");
    const lim = half
      ? ""
      : `<div class="s-subh"><span>Time each day</span><span style="font-weight:500">${scope === "today" ? "today only" : ""}</span></div>
      ${groups
        .map((g) => `<div class="s-lim"><span class="s-pdot" style="background:var(--p-${esc(g.id)}, var(--p-other))"></span><span class="s-grow">${esc(g.name)}${g.id === "all" ? "<small>Every screen together</small>" : ""}</span>
        <span class="s-step"><button data-action="sch-lim" data-group="${esc(g.id)}" data-v="-15" aria-label="15 minutes less">−</button><output>${schDur(day.limits[g.id])}</output><button data-action="sch-lim" data-group="${esc(g.id)}" data-v="15" aria-label="15 minutes more">+</button></span></div>`)
        .join("")}`;
    const foot = `<div class="s-foot">${half ? "" : `<button class="b" data-action="sch-dlg" data-dlg="copy">${icon("copy", "sm")}Copy this day to…</button>`}
      ${(this._sched.kids || []).length > 1 ? `<button class="b ghost" data-action="sch-dlg" data-dlg="kids">Copy to another kid…</button>` : ""}</div>`;
    return `<div class="card s-ed"><div class="s-edh"><div class="s-grow"><h2>${esc(title)}</h2><div class="s-d">${esc(sub)}</div></div></div>
      ${scopeCtl}${big}
      ${half || !day.changes.length ? "" : `<div class="s-hint">Drag a handle to move a change. Times snap to 15 minutes.</div>`}
      <ul class="s-blocks">${carried}${rows}${empty}</ul>
      ${half ? halfCtl : day.changes.length < 12 ? `<button class="b sm s-add" data-action="sch-add">${icon("plus", "sm")}Add a change</button>` : ""}
      ${lim}${this._schControls(kid)}${foot}</div>`;
  }

  _schDialog(kid) {
    const dlg = this._schDlg;
    if (!dlg) return "";
    const key = this._schDayKey;
    if (dlg === "copy") {
      const to = this._schCopyTo || new Set();
      const what = this._schCopyWhat || { times: true, limits: true };
      return `<div class="s-scrim" data-action="sch-dlg-close"><div class="s-dlg" role="dialog" aria-modal="true" aria-label="Copy ${esc(SCH_LONG[key])}" data-stop="1">
        <h3>Copy ${esc(SCH_LONG[key])} to…</h3><p>${esc(kid.name)}'s ${esc(SCH_LONG[key])} replaces the days you pick. You can undo it.</p>
        <div class="s-quick"><button data-action="sch-q" data-q="school">School days</button><button data-action="sch-q" data-q="weekend">Weekend</button><button data-action="sch-q" data-q="all">Every day</button><button data-action="sch-q" data-q="none">None</button></div>
        <div class="s-daygrid">${[...SCH_DAYS, "day_off"].map((o) => `<button class="s-dbox" data-action="sch-pick" data-day="${o}" aria-pressed="${to.has(o)}" ${o === key ? "disabled" : ""}>${o === "day_off" ? "Day off" : SCH_SHORT[o]}${o === key ? "<small>this day</small>" : ""}</button>`).join("")}</div>
        <label class="s-ck"><input type="checkbox" data-change="sch-what" data-w="times" ${what.times ? "checked" : ""}>The times (Sleep, School, Free time…)</label>
        <label class="s-ck"><input type="checkbox" data-change="sch-what" data-w="limits" ${what.limits ? "checked" : ""}>The time each day (limits)</label>
        <div class="s-acts"><button class="b ghost" data-action="sch-dlg-close">Cancel</button><button class="b primary" data-action="sch-copy" ${to.size && (what.times || what.limits) ? "" : "disabled"}>Copy to ${to.size || "no"} day${to.size === 1 ? "" : "s"}</button></div></div></div>`;
    }
    if (dlg === "kids") {
      const others = (this._sched.kids || []).filter((k) => k.id !== kid.id);
      const to = this._schKidsTo || new Set();
      const whole = this._schKidsWhat !== "day";
      return `<div class="s-scrim" data-action="sch-dlg-close"><div class="s-dlg" role="dialog" aria-modal="true" aria-label="Copy to another kid" data-stop="1">
        <h3>Copy ${esc(kid.name)}'s schedule to…</h3><p>Their schedule is replaced. You can undo it.</p>
        ${others.map((k) => `<label class="s-ck"><input type="checkbox" data-change="sch-kidck" data-kid="${esc(k.id)}" ${to.has(k.id) ? "checked" : ""}>${esc(k.name)}</label>`).join("")}
        <div class="s-subh"><span>What</span></div>
        <label class="s-radio"><input type="radio" name="sch-kw" data-change="sch-kw" value="week" ${whole ? "checked" : ""}><span>The whole week<small>Monday to Sunday, Day off and Half day</small></span></label>
        <label class="s-radio"><input type="radio" name="sch-kw" data-change="sch-kw" value="day" ${whole ? "" : "checked"}><span>Only ${esc(SCH_LONG[key])}<small>The other days stay as they are</small></span></label>
        <label class="s-ck"><input type="checkbox" data-change="sch-kidlim" ${this._schKidsLimits !== false ? "checked" : ""}>With the time each day (limits)</label>
        <div class="s-acts"><button class="b ghost" data-action="sch-dlg-close">Cancel</button><button class="b primary" data-action="sch-copykids" ${to.size ? "" : "disabled"}>Copy</button></div></div></div>`;
    }
    if (dlg === "bed") {
      const b = this._schBedDraft || {};
      const tonight = b.scope === "today";
      const t = kid.bedtime?.tonight || {};
      const d = tonight ? { bedtime: t.bedtime, wake: t.wake } : kid.bedtime?.days?.[b.day] || {};
      const title = tonight ? "Change tonight" : `Every ${SCH_LONG[b.day]} from now on`;
      const apply = b.apply || b.day;
      const sets = b.day === "day_off" ? [] : [[b.day, `Every ${SCH_LONG[b.day]}`], ["school_nights", "School nights"], ["weekend_nights", "Weekend nights"], ["every_day", "Every day"]];
      const usual = t.usual_bedtime ? schClock(schMin(t.usual_bedtime)) : null;
      return `<div class="s-scrim" data-action="sch-dlg-close"><div class="s-dlg" role="dialog" aria-modal="true" aria-label="${esc(title)}" data-stop="1">
        <h3>${esc(title)}</h3><p>${tonight ? `Tonight only.${usual ? ` Back to ${esc(usual)} tomorrow.` : ""}` : `${esc(kid.name)}'s bedtime and wake from now on. Family Link and Family Safety follow when they're kept in step.`}</p>
        <label class="s-ck s-name"><span class="muted">Bedtime${tonight ? " tonight" : ""}</span><input id="sch-bed-bed" type="time" step="900" value="${esc(d.bedtime || "")}"></label>
        <label class="s-ck s-name"><span class="muted">${tonight ? "Wake tomorrow" : "Wake"}</span><input id="sch-bed-wake" type="time" step="900" value="${esc(d.wake || "")}"></label>
        ${sets.length ? `<div class="s-subh"><span>Apply to</span></div><div class="s-quick">${sets.map(([v, label]) => `<button data-action="sch-bed-apply" data-v="${v}" aria-pressed="${apply === v}">${esc(label)}</button>`).join("")}</div>` : ""}
        <div class="s-acts"><button class="b ghost" data-action="sch-dlg-close">Cancel</button><button class="b primary" data-action="sch-bed-save">Save</button></div></div></div>`;
    }
    if (dlg === "mode") {
      const draft = this._schModeDraft;
      const radio = (v, title, sub) => `<label class="s-radio"><input type="radio" name="sch-mk" data-change="sch-mode-kind" value="${v}" ${draft.allows === v ? "checked" : ""} ${draft.builtin && draft.allows !== v ? "disabled" : ""}><span>${title}<small>${sub}</small></span></label>`;
      const pools = (this._sched.groups || []).filter((g) => g.id !== "all");
      return `<div class="s-scrim" data-action="sch-dlg-close"><div class="s-dlg" role="dialog" aria-modal="true" aria-label="Mode" data-stop="1">
        <h3>${draft.id ? esc(draft.name || "Mode") : "New mode"}</h3><p>Modes are the family's: changing one changes it in every kid's schedule.</p>
        <label class="s-ck s-name"><span class="muted">Name</span><input id="sch-mode-name" value="${esc(draft.name || "")}" maxlength="40"></label>
        <div class="s-subh"><span>While it's on</span></div>
        ${radio("everything", "Everything", "Screens are open; the day's limits still count.")}
        ${radio("some", "Some groups closed", "Those groups' apps and games are held; the rest stays open.")}
        ${draft.allows === "some" ? `<div class="s-pchips">${pools.map((p) => `<button class="s-pchip" data-action="sch-pool" data-group="${esc(p.id)}" aria-pressed="${(draft.closed || []).includes(p.id)}">${esc(p.name)}</button>`).join("")}</div>` : ""}
        ${radio("school", "School time", "Only the apps School time allows. The TV and Hearth phones lock.")}
        ${radio("nothing", "Bedtime", "Everything locked.")}
        ${draft.allows === "nothing" ? `<label class="s-ck" style="margin-left:28px"><input type="checkbox" data-change="sch-mode-nst" ${draft.keep_not_screen_time !== false ? "checked" : ""}>Keep apps that aren't screen time (music, audiobooks)</label>` : ""}
        <div class="s-acts">${draft.id && !draft.builtin ? `<button class="b ghost" style="margin-right:auto;color:var(--h-out)" data-action="sch-mode-remove">Remove</button>` : ""}<button class="b ghost" data-action="sch-dlg-close">Cancel</button><button class="b primary" data-action="sch-mode-save">Save</button></div></div></div>`;
    }
    return "";
  }

  _scheduleTab() {
    if (!this._sched) {
      if (!this._schLoading && !this._schError) setTimeout(() => this._loadSchedule(), 0);
      return `<div class="today sched">${this._schError ? `<div class="card empty"><p>${esc(this._schError)}</p></div>` : `<div class="loading">Loading the schedule…</div>`}</div>`;
    }
    const kid = this._schKid();
    const head = `<header class="top"><div class="s-grow"><h1>Schedule</h1>
      <div class="sub">Set up a day, then copy it to other days. Each change runs until the next; the night carries over to the morning.</div></div></header>`;
    if (!kid) return `<div class="today sched">${head}<div class="card empty"><p>Mark who's a kid in the Family tab: each kid gets a week of their own.</p></div></div>`;
    if (!this._schDayKey) this._schDayKey = this._schTodayKey();
    if (!this._schScope) this._schScope = "weekly";
    const kids = `<div class="s-kids" role="group" aria-label="Kid">${(this._sched.kids || [])
      .map((k) => `<button class="s-kidchip" data-action="sch-kid" data-kid="${esc(k.id)}" aria-pressed="${k.id === kid.id}"><span class="s-av">${esc((k.name || "?")[0])}</span>${esc(k.name)}</button>`)
      .join("")}</div>`;
    const week = `<div class="card flat s-week"><div class="s-axisrow"><span></span>${this._schAxis()}</div>${SCH_DAYS.map((_, i) => this._schWeekRow(kid, i)).join("")}</div>`;
    const main = `<div>
      ${this._schBedCard(kid)}
      <div class="sec"><span>${esc(kid.name)}'s week</span>${(this._sched.kids || []).length > 1 ? `<button class="lnk" data-action="sch-dlg" data-dlg="kids" style="font-size:13px">Copy to another kid</button>` : ""}</div>
      ${week}
      <div class="sec"><span>Special days</span><span style="font-weight:500">These replace the weekday</span></div>
      <div class="card flat s-week">${this._schSpecialRow(kid, "day_off")}${this._schSpecialRow(kid, "half_day")}</div>
      <div class="sec"><span>Coming up</span></div>${this._schComingUp()}
      <div class="sec"><span>Modes</span><span style="font-weight:500">The family's</span></div>${this._schModesCard()}
    </div>`;
    const editor = this._schEditor(kid);
    const body = this._wide
      ? `<div class="s-cols">${main}<aside class="s-side">${editor}</aside></div>`
      : `${main}${this._schSheet ? `<div class="s-sheet"><div class="s-shtop"><button class="b ghost" data-action="sch-close" aria-label="Back">${icon("chev", "s-back")}</button><span class="s-t">${esc(kid.name)} · ${esc(SCH_LONG[this._schDayKey])}</span></div>${editor}</div>` : ""}`;
    return `<div class="today sched">${head}${kids}${this._schNowCard(kid)}${body}${this._schDialog(kid)}</div>`;
  }

  // The day being edited, as the editor sends it: [[HH:MM, mode]] and limits
  _schEditable(kid) {
    const key = this._schDayKey;
    const scope = key === this._schTodayKey() ? this._schScope : "weekly";
    return { key, scope, day: this._schDay(kid, key, scope) };
  }

  _schCommit(kid, day, text) {
    const key = this._schDayKey;
    const scope = key === this._schTodayKey() ? this._schScope : "weekly";
    const changes = schMerge(day.changes).map(([m, mode]) => [schHhmm(m), mode]);
    // Shown at once; the answer replaces it
    if (scope === "today") {
      kid.today = { ...(kid.today || {}), date: this._sched.today, changes, limits: day.limits };
      this._render();
      return this._schSend({ type: "hearth/schedule/today", person: kid.id, changes, limits: day.limits }, text || "Changed for today only");
    }
    kid.days[key] = { changes, limits: day.limits };
    kid.set = true;
    this._render();
    return this._schSend({ type: "hearth/schedule/set", person: kid.id, days: [key], changes, limits: day.limits }, text);
  }

  async _schAct(action, el) {
    const d = el.dataset;
    const kid = this._schKid();
    switch (action) {
      case "sch-kid":
        this._schKidId = d.kid;
        this._schScope = "weekly";
        break;
      case "sch-day":
        this._schDayKey = d.day;
        this._schSheet = true;
        if (d.day !== this._schTodayKey()) this._schScope = "weekly";
        break;
      case "sch-close":
        this._schSheet = false;
        break;
      case "sch-scope":
        this._schScope = d.scope;
        break;
      case "sch-resume":
        await this._schSend({ type: "hearth/schedule/resume", person: kid.id }, `${kid.name} is back on the schedule`);
        return;
      // The Bedtime card
      case "sch-bed-open":
        this._schBedDraft = { scope: d.scope, day: d.day || null, apply: d.day || null };
        this._schDlg = "bed";
        break;
      case "sch-bed-apply":
        this._schBedDraft = { ...(this._schBedDraft || {}), apply: d.v };
        break;
      case "sch-bed-save": {
        const b = this._schBedDraft || {};
        const bedtime = this._value("#sch-bed-bed") || null;
        const wake = this._value("#sch-bed-wake") || null;
        if (!bedtime && !wake) {
          this._notify("Give a bedtime or a wake");
          return;
        }
        this._schDlg = null;
        const said = [bedtime ? `bedtime ${schClock(schMin(bedtime))}` : null, wake ? `wake ${schClock(schMin(wake))}` : null].filter(Boolean).join(", ");
        if (b.scope === "today") {
          const usual = kid.bedtime?.tonight?.usual_bedtime;
          await this._schSend(
            { type: "hearth/schedule/bedtime", person: kid.id, scope: "today", bedtime, wake },
            `Tonight only: ${said}.${usual ? ` Back to ${schClock(schMin(usual))} tomorrow.` : ""}`
          );
        } else {
          const apply = b.apply || b.day;
          const words = { school_nights: "School nights", weekend_nights: "Weekend nights", every_day: "Every day" };
          await this._schSend(
            { type: "hearth/schedule/bedtime", person: kid.id, scope: "days", days: [apply], bedtime, wake },
            `${words[apply] || `Every ${SCH_LONG[apply]}`}: ${said}`
          );
        }
        return;
      }
      case "sch-sync-pill":
        this._schPill = this._schPill === Number(d.i) ? null : Number(d.i);
        break;
      case "sch-sync-check":
        await this._schSend({ type: "hearth/schedule/sync/start", people: [kid.id], check: true }, "Checking the apps again");
        return;
      case "sch-fl-on":
        await this._schSend({ type: "hearth/schedule/sync/start", people: [kid.id], family_link_bedtime_on: true }, "Family Link's bedtime is on again");
        return;
      case "sch-sync-flip":
        this._schFrom = d.from;
        this._schPreview = null;
        await this._schLoadPreview();
        return;
      case "sch-sync-start": {
        const from = this._schPreview?.[kid.id]?.preview?.start_from;
        this._schPreview = null;
        await this._schSend(
          { type: "hearth/schedule/sync/start", people: [kid.id], ...(from ? { start_from: { [kid.id]: from } } : {}) },
          `${kid.name}'s bedtime is kept in step from now on`
        );
        this._schFrom = null;
        return;
      }
      case "sch-offer": {
        const accept = d.accept === "1";
        await this._schSend({ type: "hearth/schedule/sync/offer", offer: d.offer, accept }, accept ? "Kept for every week" : "Hearth's bedtime goes back");
        return;
      }
      case "sch-dlg":
        this._schDlg = d.dlg;
        if (d.dlg === "copy") this._schCopyTo = new Set();
        if (d.dlg === "kids") this._schKidsTo = new Set();
        break;
      case "sch-dlg-close":
        // The scrim closes it; a click inside the dialog doesn't
        if (el.classList.contains("s-scrim") && this._schClickInside) {
          this._schClickInside = false;
          return;
        }
        this._schDlg = null;
        break;
      case "sch-q": {
        const sets = { school: SCH_DAYS.slice(0, 5), weekend: SCH_DAYS.slice(5), all: [...SCH_DAYS, "day_off"], none: [] };
        this._schCopyTo = new Set(sets[d.q].filter((x) => x !== this._schDayKey));
        break;
      }
      case "sch-pick": {
        const to = this._schCopyTo || new Set();
        if (to.has(d.day)) to.delete(d.day);
        else to.add(d.day);
        this._schCopyTo = to;
        break;
      }
      case "sch-copy": {
        const what = this._schCopyWhat || { times: true, limits: true };
        const days = [...(this._schCopyTo || [])];
        this._schDlg = null;
        await this._schSend(
          { type: "hearth/schedule/copy", from: kid.id, day: this._schDayKey, to_days: days, times: what.times, limits: what.limits },
          `Copied ${SCH_LONG[this._schDayKey]} to ${days.map((x) => SCH_SHORT[x]).join(", ")}`
        );
        return;
      }
      case "sch-copykids": {
        const to = [...(this._schKidsTo || [])];
        const whole = this._schKidsWhat !== "day";
        this._schDlg = null;
        const names = to.map((id) => (this._sched.kids || []).find((k) => k.id === id)?.name || id);
        await this._schSend(
          { type: "hearth/schedule/copy", from: kid.id, day: whole ? null : this._schDayKey, to_people: to, times: true, limits: this._schKidsLimits !== false },
          `Copied ${kid.name}'s ${whole ? "week" : SCH_LONG[this._schDayKey]} to ${listWords(names)}`
        );
        return;
      }
      case "sch-del": {
        const { day } = this._schEditable(kid);
        day.changes.splice(Number(d.i), 1);
        await this._schCommit(kid, day, "Removed a change");
        return;
      }
      case "sch-add": {
        const { key, scope, day } = this._schEditable(kid);
        const segs = this._schSegments(kid, key, scope).filter((s) => !s.carried);
        const longest = segs.reduce((a, b) => (b.e - b.s > a.e - a.s ? b : a), segs[0] || { s: 0, e: 1440, mode: "sleep" });
        const at = Math.min(1425, Math.round((longest.s + (longest.e - longest.s) / 2) / 15) * 15);
        const modes = this._schModes();
        const other = longest.mode === "free" ? Object.keys(modes).find((m) => modes[m].allows === "some") || "sleep" : "free";
        day.changes.push([day.changes.length ? at : 7 * 60, day.changes.length ? other : "free"]);
        day.changes.sort((a, b) => a[0] - b[0]);
        await this._schCommit(kid, day);
        return;
      }
      case "sch-lim": {
        const { day } = this._schEditable(kid);
        const v = Number(d.v);
        let cur = day.limits[d.group];
        if (cur === null || cur === undefined) cur = v > 0 ? null : 600;
        else cur += v;
        if (cur !== null && cur > 600) cur = null;
        if (cur !== null && cur < 0) cur = 0;
        day.limits[d.group] = cur;
        // Steps come quickly: sent once they stop
        clearTimeout(this._schLimTimer);
        const scope = this._schDayKey === this._schTodayKey() ? this._schScope : "weekly";
        if (scope === "today") kid.today = { ...(kid.today || {}), date: this._sched.today, limits: day.limits, changes: kid.today?.changes || null };
        else kid.days[this._schDayKey] = { ...(kid.days[this._schDayKey] || { changes: [] }), limits: day.limits };
        this._render();
        this._schLimTimer = setTimeout(() => this._schCommit(kid, day), 700);
        return;
      }
      case "sch-mode": {
        const mode = this._schModes()[d.mode];
        this._schModeDraft = mode ? { id: d.mode, ...JSON.parse(JSON.stringify(mode)) } : { id: null, name: "", allows: "some", closed: [] };
        this._schDlg = "mode";
        break;
      }
      case "sch-pool": {
        const draft = this._schModeDraft;
        draft.name = this._value("#sch-mode-name") || draft.name;
        const closed = new Set(draft.closed || []);
        if (closed.has(d.group)) closed.delete(d.group);
        else closed.add(d.group);
        draft.closed = [...closed];
        break;
      }
      case "sch-mode-save": {
        const draft = this._schModeDraft;
        const name = this._value("#sch-mode-name") || draft.name;
        if (!name) {
          this._notify("Give the mode a name");
          return;
        }
        this._schDlg = null;
        await this._schSend(
          { type: "hearth/schedule/mode", mode_id: draft.id, name, allows: draft.allows, closed: draft.closed || [], keep_not_screen_time: draft.keep_not_screen_time !== false },
          `Saved ${name}`
        );
        return;
      }
      case "sch-mode-remove": {
        const draft = this._schModeDraft;
        this._schDlg = null;
        await this._schSend({ type: "hearth/schedule/mode/remove", mode_id: draft.id }, `Removed ${draft.name}`);
        return;
      }
      // Changes (data-change)
      case "sch-time":
      case "sch-modesel": {
        const { day } = this._schEditable(kid);
        const i = Number(d.i);
        if (action === "sch-time") {
          const [h, m] = (el.value || "0:0").split(":").map(Number);
          day.changes[i][0] = Math.min(1425, Math.round((h * 60 + m) / 15) * 15);
        } else day.changes[i][1] = el.value;
        day.changes.sort((a, b) => a[0] - b[0]);
        await this._schCommit(kid, day);
        return;
      }
      case "sch-half":
        await this._schSend({ type: "hearth/schedule/set", person: kid.id, days: [], half_day_ends: el.value || "12:00" }, "The half day changed");
        return;
      case "sch-half-limits":
        await this._schSend({ type: "hearth/schedule/set", person: kid.id, days: [], half_day_limits: el.value }, "The half day changed");
        return;
      case "sch-what":
        this._schCopyWhat = { ...(this._schCopyWhat || { times: true, limits: true }), [d.w]: el.checked };
        break;
      case "sch-kidck": {
        const to = this._schKidsTo || new Set();
        if (el.checked) to.add(d.kid);
        else to.delete(d.kid);
        this._schKidsTo = to;
        break;
      }
      case "sch-kw":
        this._schKidsWhat = el.value;
        break;
      case "sch-kidlim":
        this._schKidsLimits = el.checked;
        break;
      case "sch-mode-kind":
        this._schModeDraft.name = this._value("#sch-mode-name") || this._schModeDraft.name;
        this._schModeDraft.allows = el.value;
        break;
      case "sch-mode-nst":
        this._schModeDraft.keep_not_screen_time = el.checked;
        return;
      default:
        return;
    }
    this._render();
  }

  // The editor's handles: dragged with a pointer (snapping to 15 minutes, the bar redrawn live), or moved with the
  // arrow keys; sent once let go
  _schBindDrag() {
    const big = this.shadowRoot.getElementById?.("sch-big");
    const kid = this._schKid();
    if (!big || !kid || typeof big.querySelectorAll !== "function") return;
    big.querySelectorAll(".s-hnd").forEach((h) => {
      h.addEventListener("pointerdown", (ev) => {
        ev.preventDefault();
        h.setPointerCapture?.(ev.pointerId);
        h.classList.add("drag");
        const { day } = this._schEditable(kid);
        const i = Number(h.dataset.i);
        const lo = i > 0 ? day.changes[i - 1][0] + 15 : 0;
        const hi = i < day.changes.length - 1 ? day.changes[i + 1][0] - 15 : 1425;
        const bar = big.querySelector(".s-bar").getBoundingClientRect();
        const move = (e2) => {
          const m = Math.round((((e2.clientX - bar.left) / bar.width) * 1440) / 15) * 15;
          day.changes[i][0] = Math.max(lo, Math.min(hi, m));
          h.style.left = schPct(day.changes[i][0]);
          h.querySelector(".s-tip").textContent = schClock(day.changes[i][0]);
        };
        const up = () => {
          h.removeEventListener("pointermove", move);
          h.removeEventListener("pointerup", up);
          h.removeEventListener("pointercancel", up);
          this._schCommit(kid, day);
        };
        h.addEventListener("pointermove", move);
        h.addEventListener("pointerup", up);
        h.addEventListener("pointercancel", up);
      });
      h.addEventListener("keydown", (e) => {
        if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
        e.preventDefault();
        e.stopPropagation();
        const { day } = this._schEditable(kid);
        const i = Number(h.dataset.i);
        const lo = i > 0 ? day.changes[i - 1][0] + 15 : 0;
        const hi = i < day.changes.length - 1 ? day.changes[i + 1][0] - 15 : 1425;
        day.changes[i][0] = Math.max(lo, Math.min(hi, day.changes[i][0] + (e.key === "ArrowRight" ? 15 : -15)));
        this._schCommit(kid, day);
        this.shadowRoot.querySelector?.(`.s-hnd[data-i="${i}"]`)?.focus();
      });
    });
    // A click inside a dialog doesn't close it
    this.shadowRoot.querySelectorAll?.(".s-dlg").forEach((dlg) => dlg.addEventListener("click", () => (this._schClickInside = true), true));
  }

  _pendingCount() {
    return (this._config?.pairings || []).length + (this._config?.panel_hellos || []).length;
  }

  _avatar(id, size = 44) {
    const pic = this._picture(id);
    const name = this._personName(id);
    return pic
      ? `<img class="avatar" style="width:${size}px;height:${size}px" src="${esc(pic)}" alt="">`
      : `<div class="avatar initials" style="width:${size}px;height:${size}px">${esc(name.slice(0, 1).toUpperCase())}</div>`;
  }

  // A paired device's app (contract 3): the one locked at pairing with the version it reports, its own checks as
  // given (Hearth knows none of them), and what Hearth keeps for that app, which an adult can remove. Never the contents.
  _deviceClientLines(dv) {
    const lines = [];
    const locked = dv.client;
    const reported = dv.client_reported;
    if (locked) {
      const version = reported && reported.id === locked.id && reported.version ? ` ${reported.version}` : "";
      lines.push(`<div class="muted small">App: ${esc(locked.id)}${esc(version)}</div>`);
    } else if (reported) {
      lines.push(`<div class="muted small">App: ${esc(reported.id)} (not confirmed: pair again to confirm it)</div>`);
    }
    const checks = dv.checks || [];
    if (checks.length) {
      lines.push(`<div class="small">${checks
        .map((c) => `<span class="${c.ok ? "muted" : "warn"}">${c.ok ? "✓" : "✗"} ${esc(c.label)}</span>`)
        .join(" · ")}</div>`);
    }
    const kept = locked ? (this._config.client_settings || {})[locked.id] : null;
    if (kept) {
      const kb = Math.max(1, Math.round(kept.bytes / 1024));
      const what = (kept.labels || []).slice(0, 3).map(esc).join(", ");
      lines.push(`<div class="muted small">Settings kept for ${esc(locked.id)}: ${kept.count} (${kb} KB)${what ? ` · ${what}` : ""} ·
        <button class="link" data-action="client-settings-clear" data-client="${esc(locked.id)}">Remove</button></div>`);
    }
    return lines.join("");
  }

  // Someone who signed in from a phone and could be an adult (adult_offer.py): Make adult or Not now
  _adultOfferCards() {
    return (this._config.adult_offers || [])
      .map(
        (o) => `<div class="card attention">
          <div class="row">
            <ha-icon icon="mdi:account-question-outline"></ha-icon>
            <div class="grow"><div class="strong">${esc(o.name)} signed in from a phone. Make them an adult in Hearth?</div>
              <div class="muted">Adults see the kids' time and can give more.</div></div>
          </div>
          <div class="actions">
            <button class="btn" data-action="adult-offer" data-person="${esc(o.person)}" data-answer="not_now">Not now</button>
            <button class="btn primary" data-action="adult-offer" data-person="${esc(o.person)}" data-answer="adult">Make adult</button>
          </div>
        </div>`
      )
      .join("");
  }

  // A Glint Panel waiting after its hello: its room is required; it is a new panel or takes the place of one that
  // isn't connected. The line under the title tells two waiting panels apart (the id's last four, the login's names)
  _panelHelloCards() {
    const hellos = this._config.panel_hellos || [];
    const areas = this._config.areas || [];
    const offline = this._config.panels_offline || [];
    const since = (t) => (t ? `offline since ${esc(new Date(t).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }))}` : "offline");
    return hellos
      .map((h) => {
        const id = esc(h.device_id);
        const login = h.signed_in_as || {};
        const who = [login.user, login.token ? `(${login.token})` : ""].filter(Boolean).map(esc).join(" ");
        const picked = areas.find((a) => a.id === h.area || a.name.toLowerCase() === String(h.area || "").toLowerCase());
        return `<div class="card attention">
          <div class="row">
            <ha-icon icon="mdi:tablet"></ha-icon>
            <div class="grow"><div class="strong">A panel wants to join</div>
              <div class="muted">${esc(h.model || h.name || "tablet")} · …${esc(h.short_id)}${who ? ` · signed in as ${who}` : ""}</div>
              ${h.panel ? `<div class="muted small">It is ${esc(h.panel.name)} again: approving gives it a new secret.</div>` : ""}</div>
          </div>
          <label class="field">Room
            <select id="hello-area-${id}"><option value="">Choose…</option>${areas.map((a) => `<option value="${esc(a.id)}"${picked && picked.id === a.id ? " selected" : ""}>${esc(a.name)}</option>`).join("")}</select></label>
          ${h.panel ? "" : `<label class="field">This panel is
            <select id="hello-replaces-${id}"><option value="">a new panel</option>${offline.map((p) => `<option value="${esc(p.device_id)}">taking the place of ${esc(p.name)} (${since(p.offline_since)})</option>`).join("")}</select></label>`}
          <div class="actions">
            <button class="btn" data-action="panel-hello" data-answer="deny" data-hello="${id}">Refuse</button>
            <button class="btn primary" data-action="panel-hello" data-answer="approve" data-hello="${id}">Add panel</button>
          </div>
        </div>`;
      })
      .join("");
  }

  _pairingCards() {
    const pairings = this._config.pairings || [];
    if (!pairings.length) return this._panelHelloCards() + this._adultOfferCards();
    const persons = this._config.persons || [];
    return pairings
      .map(
        (p) => `<div class="card attention">
          <div class="row">
            <ha-icon icon="${p.kind === "tv" ? "mdi:television" : "mdi:cellphone"}"></ha-icon>
            <div class="grow"><div class="strong">${esc(p.name)} wants to join${p.for_name ? ` (says it's ${esc(p.for_name)}'s${p.for_role ? `, as ${p.for_role === "adult" ? "an adult" : "a kid"}` : ""})` : ""}</div>
              <div class="muted">Check the ${p.kind === "tv" ? "TV" : "phone"} shows this code: <span class="code">${esc(p.code)}</span></div>
              ${p.client ? `<div class="muted small">App: ${esc(p.client.id)}${(p.client.companions || []).length ? ` (and ${p.client.companions.map(esc).join(", ")})` : ""}. Pairing keeps this app from being paused for its person.</div>` : ""}</div>
          </div>
          ${p.kind === "mobile" ? `<label class="field">Whose phone is it?
            <select id="pair-person-${esc(p.pairing_id)}"><option value="">Choose…</option>${persons.map((x) => `<option value="${esc(x.id)}"${x.id === p.for_person ? " selected" : ""}>${esc(x.name)}</option>`).join("")}</select></label>` : ""}
          <div class="actions">
            <button class="btn" data-action="deny" data-pairing="${esc(p.pairing_id)}" data-kind="${esc(p.kind)}">Turn away</button>
            <button class="btn primary" data-action="approve" data-pairing="${esc(p.pairing_id)}" data-kind="${esc(p.kind)}">The code matches: pair</button>
          </div>
        </div>`
      )
      .join("") + this._panelHelloCards() + this._adultOfferCards();
  }

  // Today (the redesign, docs/home-assistant-integration.md and the design review): does anything need an adult, in one
  // sentence; one row per kid; what's playing; the rest one tap away in the kid's sheet (a bottom sheet on a phone, a
  // column beside the list from 900 px). Every action applies at once with an Undo (UNDO_MS) instead of a confirm.
  _today() {
    const kids = this._kids();
    const parts = [this._pairingCards(), this._controlsAttention()];
    if (!kids.length) {
      parts.push(`<div class="card empty"><ha-icon icon="mdi:account-child-outline"></ha-icon>
        <p>No kids in Hearth yet. The guided setup takes a few minutes.</p>
        <button class="btn primary" data-action="setup-open">Start the guided setup</button></div>`);
      return parts.join("");
    }
    if (!this._summary) return `${parts.join("")}<div class="loading">Loading Hearth…</div>`;
    const sel = this._selectedKid(kids);
    const main = `${this._todayHeader(kids)}${this._pauseBox()}${this._pauseBanner()}${parts.join("")}${this._forYou(kids)}${this._kidList(kids, sel)}${this._screensNow()}${this._adultsLine()}`;
    const sheet = sel ? this._kidSheet(sel) : `<div class="empty-detail">Pick a kid to see their day.</div>`;
    const open = Boolean(sel && this._sheetOpen);
    return `<div class="today ${this._wide ? "wide" : ""}">
      <div class="today-cols">
        <div class="today-main">${main}</div>
        <aside class="detail ${open ? "on" : ""}" role="dialog" aria-modal="${open && !this._wide}" aria-label="${esc(sel ? `${sel.name}'s day` : "A kid's day")}">${sheet}</aside>
      </div>
      <div class="scrim ${open ? "on" : ""}" data-action="sheet-close"></div>
      ${sel && this._mt && this._mt.kid === sel.id ? this._moreTimeSheet() : ""}
    </div>`;
  }

  // The kid the sheet shows: the one tapped, else (side by side) the first one awake
  _selectedKid(kids) {
    const tapped = kids.find((k) => k.id === this._sel);
    if (tapped) return tapped;
    if (!this._wide) return null;
    return kids.find((k) => !this._lockOf(this._summaryPerson(k.id))) || kids[0];
  }

  _now() {
    return new Date();
  }

  // What holds a kid now: a pause (theirs or everyone's), else bedtime, School time or another lock; null when none
  _lockOf(s) {
    if (!s) return null;
    if (s.pause) return { kind: "paused", until: s.pause.until, reason: s.pause.reason || "" };
    const kind = s.lock?.kind;
    if (kind === "bedtime" || kind === "school_time" || kind === "other") return { kind, until: s.lock.until, by: s.lock.by || s.locked_by || [] };
    return null;
  }

  // When suggestions and the row's +15 stop for a kid: their bedtime, else 9:00 pm
  _cutoff(s) {
    const start = s?.bedtime ? new Date(s.bedtime.start) : null;
    if (start && !Number.isNaN(start.getTime())) return start;
    const nine = this._now();
    nine.setHours(21, 0, 0, 0);
    return nine;
  }

  _notCounted() {
    return new Set(this._summary?.not_screen_time || []);
  }

  // A kid's pools with what the redesign needs: limited, counted in All screen time, state
  _pools(s) {
    const outside = this._notCounted();
    return (s?.groups || []).map((g) => ({
      ...g,
      limited: g.limited !== false && g.minutes_left !== null && g.minutes_left !== undefined,
      counted: !outside.has(g.id),
      name: g.id === "all" ? WORDS.daily : g.name,
    }));
  }

  _binding(s) {
    const id = s?.binding?.group;
    return id ? this._pools(s).find((g) => g.id === id) || null : null;
  }

  // The "?" beside a status line, and what it opens: where today's statuses came from (time.origins, newest first:
  // "Bonus +30 · added by Alex in Hearth · 3:05 PM"). [kinds]: only these (bonus, raise, unlimited, pause)
  _originButton(s, key) {
    if (!s?.time) return "";
    return `<button class="qbtn" data-action="origin" data-key="${esc(key)}" aria-label="${esc(WORDS.origin)}" aria-expanded="${this._originOpen === key}">?</button>`;
  }

  _originList(s, key, kinds = null) {
    if (this._originOpen !== key) return "";
    const list = (s?.time?.origins || []).filter((o) => !kinds || kinds.includes(o.kind));
    const lines = list.length ? list.map((o) => `<div>${esc(o.text || o.detail)}</div>`).join("") : `<div>${esc(WORDS.noOrigin)}</div>`;
    return `<div class="origins" role="note">${lines}</div>`;
  }

  // A category's color, the same on every kid: by kind of category, else by the household's order
  _poolVar(id) {
    const known = { games: "games", youtube: "youtube", video: "youtube", streaming: "streaming", social: "social", audible: "audible", music: "audible", other: "other", all: "all" };
    if (known[id]) return `var(--p-${known[id]})`;
    const order = (this._summary?.groups || []).map((g) => g.id).filter((g) => g !== "all" && !known[g]);
    return `var(--p-x${Math.max(0, order.indexOf(id)) % 4})`;
  }

  _ring(s, size = 48) {
    const lock = this._lockOf(s);
    const all = s?.all;
    const binding = this._binding(s);
    const r = size / 2 - 4;
    const c = 2 * Math.PI * r;
    // Daily time today, bonus time included
    const cap = s?.time?.today_minutes ?? (all && all.budget !== null && all.budget !== undefined ? all.budget + Math.max(0, all.bonus || 0) : null);
    const frac = cap ? Math.min(1, (all.used_minutes || 0) / cap) : 0;
    let tone = "accent";
    if (lock?.kind === "bedtime") tone = "night";
    else if (lock?.kind === "school_time") tone = "school";
    else if (all?.state === "out") tone = "out";
    else if (binding && binding.state === "out") tone = "low";
    else if (all?.state === "low" || binding?.state === "low") tone = "low";
    const badgeIcon = lock ? { bedtime: "moon", school_time: "school", paused: "pause", other: "lock" }[lock.kind] : "";
    const badge = badgeIcon ? `<span class="badge tone-${tone === "accent" ? "accent" : tone}">${icon(badgeIcon)}</span>` : "";
    // The person's picture inside the ring, else their initials (two letters when two kids share the first)
    const pic = s?.id && this._hass?.states ? this._picture(s.id) : null;
    const inner = pic
      ? `<img class="ini pic" src="${esc(pic)}" alt="">`
      : `<span class="ini ${lock?.kind === "bedtime" ? "dim" : ""}">${esc(this._initials(s?.id, s?.name || ""))}</span>`;
    return `<span class="ring tone-${tone}" style="width:${size}px;height:${size}px" aria-hidden="true">
      <svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" class="track"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" class="arc" stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${(c * (1 - frac)).toFixed(2)}"/></svg>
      ${inner}${badge}</span>`;
  }

  // A kid's initials: the first letter, or two ("Al", "An") when another kid's name starts the same: the first letter
  // and the first one after it that tells them apart
  _initials(id, name) {
    const mine = String(name || "").trim();
    const first = mine.slice(0, 1).toUpperCase();
    const others = this._kids()
      .filter((k) => k.id !== id)
      .map((k) => String(k.name || "").trim().toLowerCase())
      .filter((n) => n.slice(0, 1).toUpperCase() === first);
    if (!others.length || !first) return first;
    const lower = mine.toLowerCase();
    for (let i = 1; i < lower.length; i++) {
      if (others.every((o) => o[i] !== lower[i]) && /\p{L}/u.test(lower[i])) return first + lower[i];
    }
    return first + (lower[1] || "");
  }

  // A kid's row, line 1: the big number on the right ("1 h 10 left", "12 min left"), or the lock ("Bedtime")
  _rowNumber(s) {
    if (!s) return { text: "", tone: "" };
    const lock = this._lockOf(s);
    if (lock?.kind === "paused") return { text: "Paused", tone: "lock" };
    if (lock) return { text: LOCK_WORDS[lock.kind], tone: "lock" };
    const all = s.all || {};
    if (s.time?.unlimited) return { text: "Free play", tone: "" };
    const limited = all.minutes_left !== null && all.minutes_left !== undefined;
    if (!limited) return { text: `${fmtMinutes(all.used_minutes || 0)} used`, tone: "" };
    if (all.state === "out" || all.minutes_left <= 0) return { text: "No time left", tone: "out" };
    const left = Math.round(all.minutes_left);
    const b = this._binding(s);
    const tone = all.state === "low" || (b && (b.state === "low" || b.state === "out")) ? "low" : "";
    return { text: left < 60 ? `${left} min left` : `${fmtMinutes(left)} left`, tone };
  }

  // A kid's row, line 2: the reason or what's next ("Games done · bedtime 9:00"), never cut off
  _rowReason(s) {
    if (!s) return "No screen time reported yet today";
    const lock = this._lockOf(s);
    if (lock?.kind === "paused") return [lock.reason, lock.until ? `till ${clock(lock.until)}` : ""].filter(Boolean).join(" · ") || WORDS.screensPaused;
    if (lock) return lock.until ? `Till ${clockAmPm(new Date(lock.until))}` : "";
    const t = s.time || {};
    const all = s.all || {};
    const now = this._now();
    const parts = [];
    if (t.unlimited) parts.push(`${t.unlimited.open ? "until turned off" : t.unlimited.until ? `till ${clock(t.unlimited.until)}` : ""}${t.unlimited.open || t.unlimited.until ? " · " : ""}not counted`);
    if (s.bedtime_lifted) parts.push(`Bedtime paused till ${clock(s.bedtime_lifted.until)} for extra time`);
    const play = (this._summary?.playing || []).find((p) => p.person === s.id);
    if (play) {
      const target = (s.targets || []).find((x) => x.id === play.target);
      const where = target ? this._deviceName(target, s.name) : play.device || "";
      parts.push([where ? `On ${where}` : "", cap(play.text || play.item || "")].filter(Boolean).join(" · "));
    }
    const done = t.unlimited ? [] : (t.categories || []).filter((c) => c.left === 0).map((c) => c.name);
    if (done.length) parts.push(`${listWords(done)} done`);
    const b = this._binding(s);
    if (b && b.id !== "all" && b.state === "low" && b.minutes_left !== null && b.minutes_left !== undefined)
      parts.push(`${b.name} ${fmtMinutes(b.minutes_left)} left`);
    const start = s.bedtime ? new Date(s.bedtime.start) : null;
    if (start && start > now) {
      const mins = Math.round((start - now) / 60000);
      parts.push(mins <= 60 ? `bedtime in ${mins} min` : `bedtime ${clock(s.bedtime.start)}`);
    }
    const limited = all.minutes_left !== null && all.minutes_left !== undefined;
    if (!parts.length) parts.push(limited ? (all.used_minutes ? `${fmtMinutes(all.used_minutes)} used today` : "No screen time yet today") : "no limit");
    return cap(parts.join(" · "));
  }

  // The kid's sheet, big: "1 h 10 min left", or the lock
  _bigLeft(s) {
    const lock = this._lockOf(s);
    if (lock?.kind === "paused") return WORDS.screensPaused;
    if (lock) return LOCK_WORDS[lock.kind];
    const all = s?.all || {};
    if (s?.time?.unlimited) return "Free play";
    if (all.minutes_left === null || all.minutes_left === undefined) return "No limit today";
    if (all.state === "out" || all.minutes_left <= 0) return WORDS.outOfTime;
    return `${longMinutes(all.minutes_left)} left`;
  }

  // The kid's sheet, why: what's stopped or soon, in short sentences that wrap ("Games are done for today (2 h used).
  // Other apps still work. Bedtime 9:00.")
  _why(s) {
    if (!s) return "";
    const lock = this._lockOf(s);
    const t = s.time || {};
    const all = s.all || {};
    const now = this._now();
    const out = [];
    if (lock?.kind === "paused") return [lock.reason, lock.until ? `Till ${clockAmPm(new Date(lock.until))}.` : ""].filter(Boolean).join(". ");
    if (lock) return lock.until ? `Till ${clockAmPm(new Date(lock.until))}.` : "";
    if (t.unlimited) out.push(`${t.unlimited.text}. Time used now isn't counted.`);
    const limited = all.minutes_left !== null && all.minutes_left !== undefined;
    const dailyOut = limited && (all.state === "out" || all.minutes_left <= 0);
    if (dailyOut && !t.unlimited) out.push("Daily time is used up for today.");
    const done = t.unlimited ? [] : (t.categories || []).filter((c) => c.left === 0);
    for (const c of done) out.push(`${c.name}: done for today (${longMinutes(c.used || 0)} used).`);
    if (done.length && limited && !dailyOut) out.push("Other apps still work.");
    const b = this._binding(s);
    if (b && b.id !== "all" && b.state === "low" && b.minutes_left !== null && b.minutes_left !== undefined) out.push(`${b.name}: ${longMinutes(b.minutes_left)} left.`);
    // Devices stopped by their own limit or a parent's lock
    for (const x of (s.targets || []).filter((y) => !y.same_as)) {
      const company = { google: "Google", microsoft: "Microsoft", nintendo: "Nintendo" }[x.left_by] || "";
      if (x.locked_kind === "parent_lock") out.push(`${this._deviceName(x, s.name)} is locked in ${company ? `${company}'s` : "a parent's"} app.`);
      else if (x.locked_kind === "device_limit") out.push(`${this._deviceName(x, s.name)}: its own limit reached.`);
    }
    if (s.bedtime_lifted) out.push(`Bedtime paused till ${clock(s.bedtime_lifted.until)} for extra time.`);
    const start = s.bedtime ? new Date(s.bedtime.start) : null;
    if (start && start > now) {
      const mins = Math.round((start - now) / 60000);
      out.push(mins <= 60 ? `Bedtime in ${mins} min.` : `Bedtime ${clock(s.bedtime.start)}.`);
    }
    const school = s.school_time && !(s.school_time_off || []).length ? new Date(s.school_time.start) : null;
    if (school && school > now && school - now < 12 * 3600000) out.push(`School time ${clock(s.school_time.start)} to ${clock(s.school_time.end)}.`);
    return out.join(" ");
  }

  // Where a kid is while they're out, by name only: "Away · apart from adults since 6:47 PM · Messages open" or
  // "Practice · with Alex" (presence.py; nothing while they're home or not known)
  _presenceLine(s, tag = "div") {
    const p = s?.presence;
    if (!p || !p.away) return "";
    const parts = [esc(p.place || "Away")];
    if (p.apart) parts.push(`apart from adults${p.apart_since ? ` since ${esc(clockAmPm(new Date(p.apart_since)))}` : ""}`);
    else if ((p.with_adults || []).length) parts.push(`with ${esc(p.with_adults.join(", "))}`);
    if ((p.open || []).length) parts.push(`${esc(p.open.join(", "))} open`);
    return `<${tag} class="line muted small presence">${parts.join(" · ")}</${tag}>`;
  }

  _todayHeader(kids) {
    const now = this._now();
    const people = kids.map((k) => ({ k, s: this._summaryPerson(k.id) }));
    const night = people.length && people.some(({ s }) => now >= this._cutoff(s)) && now >= new Date(Math.min(...people.map(({ s }) => this._cutoff(s).getTime())));
    const bed = people.filter(({ s }) => this._lockOf(s)?.kind === "bedtime");
    const school = people.filter(({ s }) => this._lockOf(s)?.kind === "school_time");
    const awake = people.filter(({ s }) => !this._lockOf(s));
    const sub = [clockAmPm(now)];
    if (bed.length) sub.push(`${bed.length} of ${people.length} in bedtime`);
    if (school.length) sub.push(`${listWords(school.map(({ k }) => k.name))} in School time`);
    if (night && awake.length && bed.length) sub.push(`${listWords(awake.map(({ k }) => k.name))} still up`);
    if (sub.length === 1) sub.push(awake.length === people.length ? "everyone has time left" : "");
    return `<header class="top"><div class="grow"><h1>${night ? "Tonight" : "Today"}</h1>
      <div class="sub">${esc(sub.filter(Boolean).join(" · "))}</div><div class="live"><i></i>Live</div></div>
      <div class="split"><button class="ibtn sl" data-action="pause-quick" aria-label="Pause every kid's screens for 30 min">${icon("pause", "sm")}Pause 30 min</button><button class="ibtn sr" data-action="pause-open" aria-expanded="${Boolean(this._pauseOpen)}" aria-label="Pause: how long, and why">${icon("down", "sm")}</button></div></header>`;
  }

  _pauseBox() {
    if (!this._pauseOpen) return "";
    const m = this._pauseMinutes || 30;
    const lens = [15, 30, 60, 90].map((x) => `<button class="chip-t" data-action="pause-len" data-minutes="${x}" aria-pressed="${x === m}">${esc(fmtMinutes(x))}</button>`).join("");
    return `<div class="card pausebox"><div class="strong">Pause every kid's screens</div>
      <div class="chips">${lens}<button class="chip-t" data-action="pause-len" data-minutes="until" aria-pressed="${m === "until"}">Until a time</button></div>
      ${m === "until" ? `<label class="field">Until<input id="pause-until" type="time" value="19:00"></label>` : ""}
      <label class="field">Reason they'll see (optional)<input id="pause-reason" placeholder="Dinner" data-enter="pause-go"></label>
      <div class="acts"><button class="b primary" data-action="pause-go">${esc(WORDS.pauseScreens)} now</button><button class="b ghost" data-action="pause-open">Cancel</button></div></div>`;
  }

  _pauseBanner() {
    const paused = (this._summary?.people || []).filter((p) => p.pause);
    if (!paused.length) return "";
    const p = paused[0].pause;
    const kids = this._kids();
    const who = paused.length >= kids.length ? `${WORDS.screensPaused} for everyone` : `${WORDS.screensPaused} for ${listWords(paused.map((x) => x.name))}`;
    return `<div class="banner">${icon("pause")}<div class="grow"><b>${esc(who)}</b>${p.until ? ` till ${esc(clock(p.until))}` : ""}${p.ends_on ? ` or ${esc(this._endsOn(p.ends_on))}` : ""}${p.reason ? ` · ${esc(p.reason)}` : ""}</div>
      <button class="lnk" data-action="pause-end-all">End now</button></div>`;
  }

  // The waiting requests and the suggestions showing, one row per kid (a request first), each with its own buttons
  _needs(kids) {
    const asks = (this._summary?.approvals || []).filter((a) => a.type === "more_time" && !this._hidden.has(`ask|${a.id}`));
    const order = [...new Set([...kids.map((k) => k.id), ...asks.map((a) => a.person)])];
    const rows = [];
    for (const id of order) {
      const s = this._summaryPerson(id);
      const mine = asks.filter((a) => a.person === id).map((a) => ({ type: "ask", person: id, ask: a, key: `ask|${a.id}` }));
      const sugg = (s?.suggestions || [])
        .filter((x) => !this._hidden.has(`${id}|${x.key}`))
        .map((x) => ({ type: "suggestion", person: id, s: x, key: `${id}|${x.key}` }));
      const behind = (s?.suggestions_held || [])
        .filter((x) => x.held === "more" && !this._hidden.has(`${id}|${x.key}`))
        .map((x) => ({ type: "suggestion", person: id, s: x, key: `${id}|${x.key}` }));
      const all = [...mine, ...sugg, ...behind];
      if (!mine.length && !sugg.length) continue;
      rows.push({ person: id, top: all[0], more: all.slice(1) });
    }
    const rank = (r) => (r.top.type === "ask" ? 0 : r.top.s.reason === "group_out" ? 1 : 2);
    rows.sort((a, b) => rank(a) - rank(b));
    const held = (this._summary?.household?.suggestions_held || []).filter((x) => x.held && x.held !== "more");
    return { rows, held };
  }

  _forYou(kids) {
    const { rows, held } = this._needs(kids);
    const now = this._now();
    const night = kids.some((k) => now >= this._cutoff(this._summaryPerson(k.id)));
    if (!rows.length) {
      // One quiet line, with what's held back folded beside it
      return `<div class="quietline"><span>${night ? "Nothing needs you tonight" : "Nothing needs you"}</span>${this._heldFold(held)}</div>`;
    }
    const title = rows.length === 1 ? "1 thing for you" : `${rows.length} things for you`;
    return `<div class="sec"><span>${title}</span></div><div class="card flat needs">${rows
      .map((r) => this._needRow(r.top, { more: r.more.length }))
      .join("")}</div>${held.length ? `<div class="card flat heldcard">${this._heldFold(held)}</div>` : ""}`;
  }

  _heldFold(held) {
    if (!held.length) return "";
    return `<details class="held" id="held-fold"><summary>${icon("info", "sm")}${held.length} suggestion${held.length === 1 ? "" : "s"} held back · why</summary><ul>${held
      .map((x) => `<li><span>${esc(x.sentence || `${x.person_name || this._personName(x.person)}: ${cap(x.text)}`)}</span><span>${esc(x.why || "")}</span></li>`)
      .join("")}</ul></details>`;
  }

  // A request or a suggestion, as one sentence, a detail line and its buttons under the text
  _needRow(item, { more = 0, inSheet = false } = {}) {
    const s = this._summaryPerson(item.person);
    const name = s?.name || this._personName(item.person);
    let title;
    let detail;
    let acts;
    if (item.type === "ask") {
      const a = item.ask;
      const pool = a.group && a.group !== "all" ? this._groupName(a.group) : WORDS.daily;
      const ago = a.asked ? Math.max(0, Math.round((this._now() - new Date(a.asked)) / 60000)) : null;
      const when = ago === null ? "" : ago < 2 ? "just now" : ago < 60 ? `${ago} min ago` : `at ${clock(a.asked)}`;
      const fs = a.source === "family_safety" || !a.minutes;
      title = fs ? `${name} asks for more time${a.platform ? ` on ${a.platform}` : ""}` : `${name} asks for ${a.minutes} more min`;
      detail = [fs ? a.app_name || "Family Safety" : pool, when, a.note ? `“${a.note}”` : ""].filter(Boolean).join(" · ");
      const btn = (m, cls, label) => `<button class="b ${cls}" data-action="ask-give" data-request="${esc(a.id)}" data-person="${esc(item.person)}" data-group="${esc(a.group || "all")}" data-minutes="${m}" data-fs="${fs ? 1 : ""}">${label}</button>`;
      acts = fs
        ? `${btn(15, "primary", "15 min")}${btn(30, "", "30 min")}${btn(60, "", "1 h")}`
        : `${btn(a.minutes, "primary", `Give ${esc(amount(a.minutes))} min`)}${a.minutes !== 15 ? btn(15, "", "15 min") : btn(30, "", "30 min")}`;
      acts += `<button class="b ghost" data-action="ask-no" data-request="${esc(a.id)}" data-person="${esc(item.person)}">No</button>`;
    } else {
      const x = item.s;
      title = x.sentence || `${name}: ${cap(x.text)}`;
      detail = x.detail || "";
      const actions = x.actions || [];
      const gives = actions.filter((a) => a.service === "hearth.add_bonus");
      const dismiss = actions.find((a) => a.service === "hearth.dismiss_suggestion");
      // The suggested amount (a catch-up one, +25, when they're well over), then the "+" box with 15, 30, 1 h and Unlock
      const first = gives.find((a) => a.primary) || gives[0];
      acts = first
        ? `<button class="b primary" data-action="sugg-give" data-person="${esc(item.person)}" data-id="${esc(first.id)}">${icon("plus", "sm")}${esc(amount(first.data?.minutes))} min</button>`
        : "";
      if (first) {
        const group = first.data?.group || x.group || "all";
        const device = first.data?.device || null;
        const row = device ? null : (s?.groups || []).find((g) => g.id === group);
        const over = device ? 0 : typeof x.over === "number" ? x.over : this._overOf(row, s?.groups);
        acts += this._giveBox(`${inSheet ? "sheet" : "list"}|${item.person}|${x.key}`, { person: item.person, group, device, over });
      }
      if (dismiss) acts += `<button class="b ghost" data-action="sugg-dismiss" data-person="${esc(item.person)}" data-key="${esc(x.key)}" data-id="${esc(dismiss.id)}" title="Hides it until tomorrow">Not today</button>`;
    }
    const moreLine = more ? `<div class="more">+${more} more for ${esc(name)} · <button class="lnk" data-action="kid-sheet" data-kid="${esc(item.person)}">See</button></div>` : "";
    return `<div class="need ${item.type === "ask" ? "ask" : ""} ${inSheet ? "insheet" : ""}" ${item.type === "ask" && !inSheet ? `id="ask-${esc(item.ask.id)}"` : ""}>
      ${inSheet ? "" : `<span class="av">${this._ring(s, 40)}</span>`}
      <div class="t">${esc(title)}</div>${detail ? `<div class="d">${esc(detail)}</div>` : ""}
      <div class="acts">${acts}</div>${moreLine}</div>`;
  }

  _kidList(kids, sel) {
    const { rows } = this._needs(kids);
    const covered = new Set(rows.map((r) => r.person));
    const sorted = [...kids].sort((a, b) => (this._lockOf(this._summaryPerson(a.id))?.kind === "bedtime") - (this._lockOf(this._summaryPerson(b.id))?.kind === "bedtime"));
    return `<div class="sec"><span>Kids</span></div><div class="kids">${sorted
      .map((k) => {
        const s = this._summaryPerson(k.id);
        const asleep = this._lockOf(s)?.kind === "bedtime";
        const num = this._rowNumber(s);
        const reason = this._rowReason(s);
        const outish = s && !this._lockOf(s) && !s.time?.unlimited && (s.time?.categories || []).some((c) => c.left === 0);
        // The row opens the sheet; its +15 min is a button beside it, never inside it
        return `<div class="card kid ${asleep ? "asleep" : ""}" aria-current="${Boolean(sel && sel.id === k.id && this._wide)}">
          <button class="kopen" data-action="kid-sheet" data-kid="${esc(k.id)}" aria-label="${esc(`${k.name}: ${num.text}${reason ? `, ${reason}` : ""}`)}">
          ${this._ring(s || { id: k.id, name: k.name })}<span class="grow"><span class="l1"><span class="name">${esc(k.name)}</span><span class="num ${num.tone ? `t-${num.tone}` : ""}">${esc(num.text)}</span></span>
          <span class="line ${outish ? "t-out" : ""}">${esc(reason)}</span>${this._presenceLine(s, "span")}</span></button>
          ${covered.has(k.id) ? "" : this._rowGive(s)}</div>`;
      })
      .join("")}</div>`;
  }

  // The row's +15 min: only when time is what stops them, they're awake and it's before their cutoff
  _rowGive(s) {
    if (!s || this._lockOf(s) || s.time?.unlimited || this._now() >= this._cutoff(s)) return "";
    const b = this._binding(s);
    if (!b || (b.state !== "out" && b.state !== "low")) return "";
    return `<button class="b give" data-action="give" data-person="${esc(s.id)}" data-minutes="15" aria-label="${esc(`Give ${s.name} 15 min ${WORDS.bonusShort}`)}">+15 min</button>`;
  }

  // What's playing in the house: one collapsed row when nothing is
  _screensNow() {
    const devices = this._summary?.devices || [];
    const plays = this._summary?.playing || [];
    const kindIcon = { tv: "tv", phone: "phone", xbox: "xbox", windows: "windows", switch: "switch" };
    const onRows = [];
    for (const dv of devices) {
      if (dv.screen !== "on" || !dv.connected) continue;
      const play = plays.find((p) => p.target === `hearth:${dv.id}`);
      const what = play ? cap(play.text || play.item || "") : dv.media_title || (dv.app === "Hearth TV" || !dv.app ? "Home screen" : dv.app);
      const who = play?.name || (dv.profile ? dv.profile : "");
      onRows.push(`<div class="rowi"><span class="dic on">${icon(kindIcon[dv.kind] || "tv")}</span><div class="grow"><div class="t">${esc(dv.name || dv.id)}</div><div class="d">${esc([what, who].filter(Boolean).join(" · "))}</div></div></div>`);
    }
    for (const p of plays) {
      if (String(p.target || "").startsWith("hearth:")) continue;
      const target = (this._summaryPerson(p.person)?.targets || []).find((t) => t.id === p.target);
      const where = target ? target.display_name || target.name : p.device || "";
      onRows.push(`<div class="rowi"><span class="dic on">${icon(kindIcon[target?.kind] || (p.kind === "game" ? "switch" : "tv"))}</span><div class="grow"><div class="t">${esc(where || p.name)}</div><div class="d">${esc([cap(p.text || p.item || ""), p.name].filter(Boolean).join(" · "))}</div></div></div>`);
    }
    const off = devices.filter((dv) => !(dv.screen === "on" && dv.connected));
    const offRows = off.map((dv) => `<div class="rowi"><span class="dic">${icon(kindIcon[dv.kind] || "tv")}</span><div class="grow"><div class="t">${esc(dv.name || dv.id)}</div><div class="d">${dv.connected ? "Off" : "Not connected"}</div></div></div>`);
    const tvs = off.filter((dv) => dv.kind === "tv").length;
    let body;
    if (!onRows.length) {
      const d = [tvs ? `${tvs} TV${tvs === 1 ? "" : "s"} off` : "", "no console or Switch in use"].filter(Boolean).join(" · ");
      body = `<button class="rowi" data-action="screens-toggle" aria-expanded="${Boolean(this._screensOpen)}"><span class="dic">${icon("tv")}</span><div class="grow"><div class="t">Nothing playing</div><div class="d">${esc(d)}</div></div><span class="chev ${this._screensOpen ? "open" : ""}">${icon("chev")}</span></button>${this._screensOpen ? offRows.join("") : ""}`;
    } else {
      body = onRows.join("") + (offRows.length
        ? `<button class="rowi more-off" data-action="screens-toggle" aria-expanded="${Boolean(this._screensOpen)}"><div class="grow d">${offRows.length} more off</div><span class="chev ${this._screensOpen ? "open" : ""}">${icon("chev")}</span></button>${this._screensOpen ? offRows.join("") : ""}`
        : "");
    }
    return `<div class="sec"><span>Screens now</span></div><div class="card flat rowlist">${body}</div>`;
  }

  _adultsLine() {
    const adults = (this._summary?.people || []).filter((p) => p.kind === "adult");
    if (!adults.length) return "";
    const limited = adults.some((p) => p.all && p.all.minutes_left !== null && p.all.minutes_left !== undefined);
    return `<div class="adults">Adults today: ${esc(adults.map((p) => `${p.name} ${fmtMinutes(p.all?.used_minutes || 0)}`).join(" · "))}${limited ? "" : " · no limits"}</div>`;
  }

  // A device's name in a kid's own sheet: without "<kid>'s"
  _deviceName(t, kid) {
    let n = String(t?.display_name || t?.name || "Unnamed device");
    const pre = `${kid}'s `;
    if (kid && n.toLowerCase().startsWith(pre.toLowerCase())) n = n.slice(pre.length);
    return cap(n);
  }

  _deviceKind(t) {
    if (t.kind !== "phone") return t.kind;
    const words = `${t.display_name || ""} ${t.name || ""}`;
    return /\btab|tablet|ipad|\bSM-[XTP]\d/i.test(words) ? "tablet" : "phone";
  }

  // The kid's sheet: how much is left (or the lock) and why, three actions (More time, Pause, ⋯), today's extras with
  // End, today, devices, holds and notes, the week and their to-do list
  _kidSheet(kid) {
    const s = this._summaryPerson(kid.id);
    if (!s) return `<div class="dinner"><p class="muted">No word from Hearth about ${esc(kid.name)} yet.</p></div>`;
    const lock = this._lockOf(s);
    const locked = lock && lock.kind !== "paused";
    const h = [];
    const why = this._why(s);
    const big = this._bigLeft(s);
    const bigTone = !lock && s.all?.state === "out" ? "t-out" : "";
    h.push(`<div class="handle"><i></i></div><div class="dinner">
      <div class="dhead">${this._ring(s, 60)}<div class="grow"><div class="who">${esc(kid.name)}</div><h2 class="${bigTone}">${esc(big)}</h2>${why ? `<div class="why">${esc(why)}</div>` : ""}${this._presenceLine(s)}</div>
      <button class="closebtn" data-action="sheet-close" aria-label="Close">${icon("close")}</button></div>`);
    if (locked) {
      const word = LOCK_WORDS[lock.kind];
      const from = this._lockSource(lock.by);
      h.push(`<div class="lockbox ${lock.kind === "bedtime" ? "night" : "school"}">${icon(lock.kind === "bedtime" ? "moon" : lock.kind === "school_time" ? "school" : "lock")}<div>
        <div class="strong">${esc(word)}${lock.until ? ` till ${esc(clock(lock.until))}` : ""}</div>
        <div class="d">${esc(`${from ? `Set in ${from}. ` : ""}Every screen is off for ${kid.name} until then${lock.kind === "bedtime" ? ". More time pauses bedtime while it lasts." : ". More time counts after it ends."}${lock.kind === "school_time" ? " School time apps still work." : ""}`)}</div></div></div>`);
    }
    if (!lock && s.bedtime_lifted)
      h.push(`<div class="banner">${icon("moon")}<div class="grow">Bedtime paused until ${esc(clock(s.bedtime_lifted.until))} for extra time</div></div>`);
    if (lock?.kind === "paused")
      h.push(`<div class="banner">${icon("pause")}<div class="grow">${esc(WORDS.screensPaused)}${lock.until ? ` till ${esc(clock(lock.until))}` : ""}${lock.reason ? ` · ${esc(lock.reason)}` : ""}</div><button class="lnk" data-action="kid-pause-end" data-person="${esc(kid.id)}">End</button></div>`);
    // Their request or suggestions
    const mine = this._needs([kid]).rows.find((r) => r.person === kid.id);
    if (mine) for (const item of [mine.top, ...mine.more]) h.push(`<div class="card flat">${this._needRow(item, { inSheet: true })}</div>`);
    h.push(this._actionBar(kid, s, lock));
    h.push(this._extras(kid, s));
    h.push(this._todayBlock(kid, s, locked));
    h.push(this._deviceGroups(kid, s));
    h.push(this._exceptions(kid, s));
    h.push(this._weekBlock(s));
    const td = s.todo || { total: 0 };
    h.push(`<div class="card flat blk todo">${icon("list")}<div class="grow"><div class="strong">${td.total ? `To-do: ${td.done} of ${td.total} done` : "No to-do list yet"}</div>
      <div class="d">${td.total ? "" : "Chores can earn bonus time or money."}${s.balance_cents ? ` Balance ${esc(money(s.balance_cents))}` : ""}</div></div>
      <button class="b ghost" data-action="kid" data-kid="${esc(kid.id)}" data-go="kids">${td.total ? "Open" : "Set up"}</button></div>`);
    h.push(`<div class="foot"><span class="muted">Updated ${esc(clockAmPm(this._now()))}</span></div></div>`);
    return h.join("");
  }

  // Today's extras: every extra still on today, each with its End (or Undo): bonus time given, raised limits, free play,
  // allows and No School time today. Ending one offers Undo where it can be given again
  _extras(kid, s) {
    const p = esc(kid.id);
    const t = s.time || {};
    const rows = [];
    const row = (text, button) => rows.push(`<div class="xrow"><span>${esc(text)}</span>${button}</div>`);
    const origins = (t.origins || []).filter((o) => !o.ended_at && o.endable && ["bonus", "raise", "unlimited"].includes(o.kind) && o.source !== "chore");
    for (const o of origins)
      row(this._extraText(o, s), `<button class="lnk" data-action="extra-end" data-person="${p}" data-origin="${esc(o.id)}">End</button>`);
    // Raised limits and free play the origins don't name (an older Hearth): end them all at once
    for (const c of (t.categories || []).filter((x) => x.raised && !origins.some((o) => o.kind === "raise" && o.group === x.id)))
      row(`${c.limit_text || `${c.name}: limit raised today`}`, `<button class="lnk" data-action="raise-end" data-person="${p}" data-group="${esc(c.id)}">End</button>`);
    if (t.unlimited && !origins.some((o) => o.kind === "unlimited"))
      row(`${t.unlimited.text} (not counted)`, `<button class="lnk" data-action="unlimited-end" data-person="${p}">End</button>`);
    const till = (iso) => (iso ? ` till ${clock(iso)}` : "");
    for (const a of s.allows || []) {
      const what = a.group ? (a.group === "all" ? "Screen time" : this._groupName(a.group)) : a.app_name || this._config?.known_apps?.[a.app] || a.app;
      row(`${cap(what)} allowed${a.ends_on ? ` until ${this._endsOn(a.ends_on)}` : till(a.until)}`, `<button class="lnk" data-action="allow-end" data-person="${p}" ${a.group ? `data-group="${esc(a.group)}"` : `data-app="${esc(a.app)}"`}>End</button>`);
    }
    for (const x of s.device_extras || []) {
      const tg = (s.targets || []).find((y) => y.id === x.target);
      const where = tg ? this._deviceName(tg, kid.name) : x.name || "one device";
      row(x.kind === "bedtime" ? `Bedtime lifted on ${where}${till(x.until)}` : x.kind === "allow" ? `${where} open${till(x.until)}` : `${longMinutes(x.minutes_left || 0)} extra left on ${where}`, "");
    }
    const off = (s.school_time_off || [])[0];
    if (off) row(`No School time today${off.reason ? ` · ${off.reason}` : ""}`, `<button class="lnk" data-action="school-off-cancel" data-person="${p}">Undo</button>`);
    if (!rows.length) return "";
    return `<div class="card flat blk extras"><h3>Today's extras</h3>${rows.join("")}</div>`;
  }

  // An extra in a few words: "+30 min from Alex, 3:05 pm", "Games: limit +30 today", "Free play until 6 PM"
  _extraText(o, s) {
    const at = o.at ? clockAmPm(new Date(o.at)) : "";
    const by = o.by ? ` from ${o.by}` : "";
    if (o.kind === "bonus" && typeof o.minutes === "number")
      return `${plusLabel(o.minutes)}${o.group ? ` of ${this._groupName(o.group)}` : ""}${by}${at ? `, ${at}` : ""}`;
    if (o.kind === "unlimited") return `${String(o.detail || "Unlimited").replace(/^Unlimited/, "Free play")}${by} (not counted)`;
    return `${o.detail || o.text || ""}${by}`;
  }

  // What gives an ended extra back (null when it can't be told exactly)
  _extraUndo(person, o, s) {
    if (!o) return null;
    const t = s?.time || {};
    if (o.kind === "bonus" && typeof o.minutes === "number") {
      // Ending takes the unused part: as much as its minutes and as what's left unused
      const left = o.group ? (t.category_bonuses || []).find((c) => c.id === o.group)?.bonus_left : t.bonus_left;
      const minutes = Math.min(o.minutes, typeof left === "number" ? left : o.minutes);
      if (minutes <= 0) return null;
      return () => this._call("add_time", { person, minutes, ...(o.group ? { category: o.group } : {}) });
    }
    if (o.kind === "raise" && o.group) {
      const d = String(o.detail || "");
      if (/no limit/.test(d)) return () => this._call("raise_cap", { person, category: o.group, no_cap: true });
      const by = d.match(/limit \+(\d+)/);
      if (by) return () => this._call("raise_cap", { person, category: o.group, minutes: Number(by[1]) });
      return null;
    }
    if (o.kind === "unlimited" && t.unlimited) return () => this._call("unlimited", this._unlimitedAgain(person, t.unlimited));
    return null;
  }

  // Free play again as it was: until the same time (or turned off), bedtime as it was
  _unlimitedAgain(person, u) {
    const end = u.until ? new Date(u.until) : null;
    const until = u.open ? "turned_off" : end && !Number.isNaN(end.getTime()) ? `${String(end.getHours()).padStart(2, "0")}:${String(end.getMinutes()).padStart(2, "0")}` : "end_of_day";
    return { people: [person], until, include_bedtime: Boolean(u.include_bedtime) };
  }

  // Which parental control a lock comes from, by its entities' integration
  _lockSource(by) {
    const names = { familylink: "Family Link", microsoft_family_safety: "Family Safety", nintendo_parental_controls: "the Nintendo app" };
    for (const e of by || []) {
      const platform = this._hass?.entities?.[e]?.platform;
      if (names[platform]) return names[platform];
    }
    return (by || []).some((e) => /_(bedtime|school_time)_active/.test(e)) ? "Family Link" : "";
  }

  // The adult's actions on a kid, three buttons: More time (one sheet for every kind of extra time), Pause (one tap, 30
  // minutes, with Undo) and ⋯ (Allow an app…, No School time today, Free play…, Change limits). In bedtime or School
  // time: Allow an app, More time anyway and ⋯
  _actionBar(kid, s, lock) {
    const locked = lock && lock.kind !== "paused";
    const p = esc(kid.id);
    const now = this._now();
    const off = (s.school_time_off || [])[0];
    const schoolAhead = s.school_time && !off && now < new Date(s.school_time.end);
    const more = `<button class="b ${locked ? "" : "primary"} grow" data-action="mt-open" data-person="${p}" aria-haspopup="dialog" aria-label="${esc(`More time for ${kid.name}`)}">${icon("plus", "sm")}${locked ? "More time anyway" : "More time"}</button>`;
    const allow = `<button class="b primary grow" data-action="allow-open" data-person="${p}" aria-expanded="${Boolean(this._allowOpen)}">${icon("shield", "sm")}Allow an app</button>`;
    const pause = lock
      ? ""
      : `<button class="b" data-action="kid-pause" data-person="${p}" data-minutes="30" aria-label="${esc(`Pause ${kid.name}'s screens for 30 min`)}">${icon("pause", "sm")}Pause</button>`;
    const dots = `<button class="b sq2" data-action="more-open" data-person="${p}" aria-expanded="${Boolean(this._moreOpen)}" aria-label="More actions">${icon("more")}</button>`;
    const bar = locked ? [allow, more, dots] : [more, pause, dots];
    const menu = [];
    if (this._moreOpen) {
      if (!locked) menu.push(`<button data-action="allow-open" data-person="${p}">Allow an app…<small>Lets one app through limits for a while</small></button>`);
      if (schoolAhead) menu.push(`<button data-action="school-off" data-person="${p}">No School time today<small>For a sick day or a day off</small></button>`);
      menu.push(`<button data-action="mt-open" data-person="${p}" data-view="free">Free play…<small>Until a time, not counted</small></button>`);
      menu.push(`<button data-action="kid" data-kid="${p}" data-go="kids">Change limits<small>Opens ${esc(kid.name)}'s rules</small></button>`);
    }
    return `<div class="actbar">${bar.join("")}</div>${menu.length ? `<div class="menu">${menu.join("")}</div>` : ""}${this._allowOpen ? this._allowChooser(kid, s) : ""}`;
  }

  // Allow an app: any of the kid's apps (today's first, then every app Hearth knows), found by typing
  _allowChooser(kid, s) {
    const p = esc(kid.id);
    const q = this._allowQ || "";
    const seen = new Set();
    const apps = [];
    for (const a of s.apps_today || []) {
      if (!a.package || seen.has(a.package)) continue;
      seen.add(a.package);
      apps.push({ package: a.package, name: a.name || this._config?.known_apps?.[a.package] || a.package });
    }
    const known = Object.entries(this._config?.known_apps || {})
      .filter(([pkg]) => !seen.has(pkg) && !this._testBuild(pkg))
      .map(([pkg, name]) => ({ package: pkg, name: name || pkg }))
      .sort((a, b) => a.name.localeCompare(b.name));
    apps.push(...known);
    const shown = apps.filter((a) => !q || a.name.toLowerCase().includes(q) || a.package.toLowerCase().includes(q)).slice(0, 12);
    const pick = shown.some((a) => `app:${a.package}` === this._allowPick) ? this._allowPick : shown[0] ? `app:${shown[0].package}` : "";
    const len = this._allowLen ?? 30;
    const label = (shown.find((a) => `app:${a.package}` === pick) || {}).name;
    return `<div class="chooser"><label class="field">App<input id="allow-q" type="search" placeholder="Search ${esc(kid.name)}'s apps" autocomplete="off" value="${esc(q)}"></label>
      <div class="chips">${shown
        .map((a) => `<button class="chip-t" data-action="allow-pick" data-pick="app:${esc(a.package)}" aria-pressed="${pick === `app:${a.package}`}" title="${esc(a.package)}">${esc(a.name)}</button>`)
        .join("")}</div>
      <div class="lab">For</div><div class="chips">${[[30, "30 min"], [60, "1 h"], [0, "Rest of today"]]
        .map(([m, l]) => `<button class="chip-t" data-action="allow-len" data-minutes="${m}" aria-pressed="${m === len}">${l}</button>`)
        .join("")}</div>${pick ? `<button class="b primary" data-action="allow" data-person="${p}" data-pick="${esc(pick)}" data-minutes="${len}">Allow ${esc(label || "it")}</button>` : `<div class="d">No app by that name.</div>`}</div>`;
  }

  // The More time sheet (a second bottom sheet on a phone, a dialog on a wide page): For (what's stopping them, or
  // Anything), +15 / +30 / +1 h and the rest of today, a line saying what it will do, then Take 15 min away and Free play
  // until a time. One tap gives, with Undo
  _moreTimeSheet() {
    const m = this._mt;
    if (!m) return "";
    const s = this._summaryPerson(m.kid);
    if (!s) return "";
    const p = esc(m.kid);
    const name = s.name || this._personName(m.kid);
    const st = this._mtState(s);
    const lock = this._lockOf(s);
    const sub = [this._rowNumber(s).text, ...st.cats.filter((c) => c.left === 0).map((c) => `${c.name} done`)].filter(Boolean);
    const head = `<div class="handle"><i></i></div><div class="mt-head"><div class="grow"><h2 id="mt-title">${m.view === "free" ? `Free play for ${esc(name)}` : `More time for ${esc(name)}`}</h2>
      <div class="d">${esc(sub.join(" · "))}</div></div><button class="closebtn" data-action="mt-close" aria-label="Close">${icon("close")}</button></div>`;
    let body;
    if (m.view === "free") {
      const until = this._unlimitedUntil || "end_of_day";
      const choices = [["end_of_day", "Rest of today"], ["time", "Until a time"], ["turned_off", WORDS.untilTurnedOff]];
      body = `<div class="chips">${choices
        .map(([v, l]) => `<button class="chip-t" data-action="unlimited-until" data-until="${v}" aria-pressed="${v === until}">${esc(l)}</button>`)
        .join("")}</div>${until === "time" ? `<label class="field">Until<input id="unlimited-time" type="time" value="18:00"></label>` : ""}
        <label class="check"><input type="checkbox" data-change="unlimited-bed" ${this._unlimitedBed ? "checked" : ""}>${esc(WORDS.includeBedtime)}</label>
        <p class="mt-note">Time used meanwhile isn't counted: ${esc(WORDS.dailyLower)} and limits pick up where they were. School time and ${esc(WORDS.pauseScreens)} still apply. Always ends at midnight.</p>
        <button class="b primary wide" data-action="unlimited" data-person="${p}">Start free play</button>
        <div class="mt-more"><button data-action="mt-view" data-view="main">‹ Back to more time</button></div>`;
    } else {
      const forId = this._mtFor(s);
      const cat = forId === "all" ? null : st.cats.find((c) => c.id === forId);
      // The two choices: the category (the one picked, else the one stopping them, else the closest to its limit) and
      // Anything; the other limited categories as a quiet line under them
      const focus = cat || st.stopping || st.closest;
      let forRow = "";
      if (focus) {
        const seg = (id, label) =>
          `<button role="radio" data-action="mt-for" data-group="${esc(id)}" aria-checked="${forId === id}">${esc(label)}</button>`;
        const others = st.cats.filter((c) => c.id !== focus.id);
        forRow = `<div class="mt-for"><span class="lab" id="mt-for-l">For</span><div class="seg" role="radiogroup" aria-labelledby="mt-for-l">${seg(focus.id, focus.name)}${seg("all", "Anything")}</div>
          ${others.length ? `<div class="mt-others">Or for: ${others.map((c) => `<button class="lnk" data-action="mt-for" data-group="${esc(c.id)}">${esc(c.name)}</button>`).join(" · ")}</div>` : ""}</div>`;
      }
      const amounts = [15, 30, 60]
        .map((n) => `<button class="b amt" data-action="mt-give" data-person="${p}" data-group="${esc(forId)}" data-how="${n}">${plusLabel(n)}</button>`)
        .join("");
      const restLabel = forId === "all" || st.dailyOut ? "Free play rest of today" : `No ${cat.name} limit rest of today`;
      const rest = `<button class="b wide" data-action="mt-give" data-person="${p}" data-group="${esc(forId)}" data-how="rest">${esc(restLabel)}</button>`;
      const note = this._mtNote(s, forId, st, lock);
      body = `${forRow}<div class="mt-amts">${amounts}</div>${rest}<p class="mt-note">${esc(note)}</p>
        <div class="mt-more"><button data-action="mt-take" data-person="${p}" data-minutes="15">Take 15 min away</button>
        <button data-action="mt-view" data-view="free">Free play until a time (not counted) ›</button></div>`;
    }
    return `<div class="mt-scrim" data-action="mt-close"></div><section class="mt" role="dialog" aria-modal="true" aria-labelledby="mt-title">${head}<div class="mt-body">${body}</div></section>`;
  }

  // What a More time choice will do, in a line, and how far over they are ("25 min over: +30 leaves 5")
  _mtNote(s, forId, st, lock) {
    const name = s.name;
    const leftText = st.dailyLimited && !st.dailyOut ? longMinutes(st.all.minutes_left) : null;
    let note;
    let over = 0;
    if (forId === "all") {
      const b = this._binding(s);
      const stop = st.stopping;
      note = `Adds to ${name}'s daily time, for any app${stop ? `, ${stop.name} too` : ""}.`;
      over = this._overOf(b, s.groups);
      if (lock?.kind === "bedtime") note += " It pauses bedtime while it lasts.";
      else if (lock) note += " It counts after the lock ends.";
    } else {
      const c = st.cats.find((x) => x.id === forId) || {};
      const row = (s.groups || []).find((g) => g.id === forId);
      if (st.dailyOut) {
        note = `Daily time is used up, so this is extra just for ${c.name}, past daily time.`;
        over = this._overOf(row, s.groups);
      } else {
        note = `${c.name} can run longer.${leftText ? ` It still counts toward the ${leftText} left today.` : ""}`;
        const past = (c.used || 0) - (c.limit_today || 0);
        over = past >= 1 ? Math.round(past) : 0;
      }
      if (lock) note += ` ${LOCK_WORDS[lock.kind] || "The lock"} still holds.`;
    }
    if (over > 0) {
      const enough = [15, 30, 60].find((n) => n > over);
      note += ` ${fmtMinutes(over)} over: ${enough ? `+${amount(enough)} leaves ${amount(enough - over)}` : "+1 h won't cover it"}.`;
    }
    return note;
  }

  // Today: one bar for daily time, each category's minutes colored inside it and each category's limit as a marker; then
  // a line per category with a limit ("Games: 25 min left", its limit as a hint) that opens to its apps
  _todayBlock(kid, s, locked) {
    const all = s.all;
    if (!all) return "";
    const t = s.time || {};
    const pools = this._pools(s);
    const used = all.used_minutes || 0;
    const cap = t.today_minutes ?? (all.budget !== null && all.budget !== undefined ? all.budget + Math.max(0, all.bonus || 0) : null);
    const left = all.minutes_left;
    const byPool = (s.all_by_pool || []).filter((x) => x.minutes > 0);
    const total = Math.max(cap || 0, used, 1);
    const stack = byPool.length ? byPool : used ? [{ id: "all", name: WORDS.daily, minutes: used }] : [];
    const cats = t.categories || [];
    const markers = cats
      .filter((c) => c.limit_today !== null && c.limit_today !== undefined && c.limit_today <= total)
      .map((c) => `<b class="mark" style="left:${((c.limit_today / total) * 100).toFixed(2)}%;border-color:${this._poolVar(c.id)}" title="${esc(c.limit_text)}"></b>`)
      .join("");
    // Left first (the parent's question), used of today's daily time small
    const head = t.unlimited ? t.unlimited.text : left !== null && left !== undefined ? `${longMinutes(left)} left` : "No limit today";
    const usedOf = cap ? `${fmtMinutes(used)} of ${fmtMinutes(cap)}` : `${fmtMinutes(used)} used`;
    let h = `<div class="card flat blk"><h3>Today <span>${esc(usedOf)}${t.bonus > 0 ? ` · includes +${esc(amount(t.bonus))} ${esc(WORDS.bonusShort)}` : ""}</span>${this._originButton(s, `today|${kid.id}`)}</h3>
      ${this._originList(s, `today|${kid.id}`)}
      <div class="big">${esc(head)}</div>
      <div class="stack" role="img" aria-label="${esc(`${fmtMinutes(used)} used of ${cap ? fmtMinutes(cap) : "no limit"}`)}">${stack
        .map((x) => `<i style="width:${((x.minutes / total) * 100).toFixed(2)}%;background:${this._poolVar(x.id)}" title="${esc(`${x.name}: ${fmtMinutes(x.minutes)}`)}"></i>`)
        .join("")}${markers}</div>
      ${byPool.length ? `<div class="legend">${byPool.map((x) => `<span><i style="background:${this._poolVar(x.id)}"></i>${esc(x.name)} ${esc(fmtMinutes(x.minutes))}</span>`).join("")}</div>` : ""}<div class="lanes">`;
    for (const c of cats) {
      const key = `${kid.id}|cat|${c.id}`;
      const open = this._exp.has(key);
      const g = pools.find((x) => x.id === c.id) || {};
      const out = c.left === 0;
      // Read-only: the category, how it stands and its limit today ("Done · 2 h limit"); it opens to its apps
      const state = g.state === "allowed" ? "Allowed" : g.state === "paused" ? "Paused" : out ? "Done" : c.left === null || c.left === undefined ? "No limit" : `${fmtMinutes(c.left)} left`;
      const lim = c.raised ? `${(c.limit_text || "").replace(`${c.name}: `, "")}` : limitWord(c.limit_today ?? c.limit);
      h += `<button class="lane" data-action="exp" data-key="${esc(key)}" aria-expanded="${open}"><span class="nm"><i style="background:${this._poolVar(c.id)}"></i>${esc(c.name)}</span>
        <span class="v ${out ? "t-out" : ""}">${esc(`${state} · ${lim}`)}</span><span class="chev ${open ? "open" : ""}">${icon("chev", "sm")}</span></button>`;
      if (open) {
        const apps = (s.apps_today || []).filter((a) => (a.groups || []).includes(c.id)).map((a) => ({ name: a.name || a.package, title: a.package, minutes: a.minutes }));
        // Consoles count by device, not by app: "On Switch 2"
        for (const d of s.devices_today || []) {
          const tg = (s.targets || []).find((x) => x.id === d.target);
          if (tg && tg.left_pool === c.id && tg.via !== "family_link" && tg.via !== "hearth") apps.push({ name: `On ${this._deviceName(tg, kid.name)}`, minutes: d.minutes });
        }
        h += `<div class="expand ${out ? "t-out" : ""}">${esc(fmtMinutes(c.used || 0))} of ${esc(fmtMinutes(c.limit_today))} today${c.raised ? " (raised)" : ""}.
          <div class="apps">${apps.length ? apps.map((a) => `<div><span${a.title ? ` title="${esc(a.title)}"` : ""}>${esc(a.name)}</span><span>${esc(fmtMinutes(a.minutes))}</span></div>`).join("") : `<div><span>No apps in ${esc(c.name)} today</span><span></span></div>`}</div></div>`;
      }
    }
    // Categories with a bonus of their own but no limit
    for (const b of (t.category_bonuses || []).filter((x) => !cats.some((c) => c.id === x.id))) {
      h += `<div class="lane"><span class="nm"><i style="background:${this._poolVar(b.id)}"></i>${esc(b.text || `${b.name}: ${fmtMinutes(b.bonus_left || 0)} bonus left`)}</span></div>`;
    }
    const other = byPool.find((x) => x.id === "other");
    const notCounted = pools.filter((g) => !g.counted && (g.used_minutes || 0) > 0);
    const free = pools.filter((g) => g.id !== "all" && g.counted && !g.limited && (g.used_minutes || 0) > 0 && g.id !== "other");
    // Free play earlier today (ended windows: "Unlimited 2:00–5:10 PM · 3 h 10 min not counted")
    const spans = (t.unlimited_today || []).map((u) => `<div class="notcounted">${esc(u.text)}</div>`).join("");
    h += `</div>${other ? `<div class="notcounted">Other apps: ${esc(fmtMinutes(other.minutes))} (no category)</div>` : ""}${free.length ? `<div class="notcounted">No limit: ${esc(free.map((g) => `${g.name} ${fmtMinutes(g.used_minutes)}`).join(", "))}</div>` : ""}${notCounted.length ? `<div class="notcounted">Not counted: ${esc(notCounted.map((g) => `${g.name} ${fmtMinutes(g.used_minutes)}`).join(", "))}</div>` : ""}${spans}</div>`;
    return h;
  }

  // The action log (hearth/activity): plain lines, a kid filter, failures marked
  _activityCard() {
    const open = Boolean(this._activityOpen);
    const kids = this._kids();
    const who = this._activityWho || "";
    const records = this._activity || [];
    const line = (r) => {
      const at = clockAmPm(new Date(r.at));
      const kid = r.person ? this._personName(r.person) : "";
      const targets = (r.target || []).join(", ");
      let what;
      if (r.kind === "call") {
        what = [r.service, r.why, r.result, r.duration_ms !== undefined ? `${r.duration_ms} ms` : null].filter(Boolean).join(" · ");
      } else if (r.kind === "hold_start" || r.kind === "hold_end") {
        what = [r.kind === "hold_start" ? WORDS.holdStarted : WORDS.holdEnded, targets, r.reason].filter(Boolean).join(" · ");
      } else if (r.kind === "rule") {
        what = [r.result === "opened" ? WORDS.ruleOpened : WORDS.ruleClosed, targets].filter(Boolean).join(" · ");
      } else {
        what = [r.kind === "tv_command" ? WORDS.tvCommand : WORDS.glintInbox, r.service, targets, r.result].filter(Boolean).join(" · ");
      }
      const failed = r.result === "failed";
      return `<li class="activity-row${failed ? " failed" : ""}"><span class="muted small">${esc(at)}</span>${kid ? ` <strong>${esc(kid)}</strong>` : ""} ${esc(what)}${failed && r.error ? ` <span class="chip small warn">${esc(r.error)}</span>` : ""}</li>`;
    };
    return `<section class="card activity">
      <h3><ha-icon icon="mdi:history"></ha-icon>${esc(WORDS.activity)}</h3>
      <p class="muted">${esc(WORDS.activityHint)}</p>
      <button class="btn" data-action="activity-open" aria-expanded="${open}">${open ? "Hide" : "Show"} ${esc(WORDS.activity.toLowerCase())}</button>
      ${open ? `<div><select data-change="activity-who" aria-label="Kid"><option value="">${esc(WORDS.activityAll)}</option>${kids
        .map((k) => `<option value="${esc(k.id)}" ${k.id === who ? "selected" : ""}>${esc(k.name)}</option>`)
        .join("")}</select></div>
      ${records.length ? `<ul class="list compact activity-list">${records.map(line).join("")}</ul>` : `<p class="muted small">${esc(WORDS.activityNone)}</p>`}` : ""}
    </section>`;
  }

  async _loadActivity() {
    try {
      const msg = { type: "hearth/activity", limit: 200 };
      if (this._activityWho) msg.person = this._activityWho;
      const answer = await this._hass.callWS(msg);
      this._activity = answer?.records || [];
    } catch (err) {
      this._activity = [];
      this._notify(this._message(err));
    }
    this._render();
  }

  // A device's state in a kid's sheet, as the server worked it out (targets: left, left_by, left_pool, locked_kind)
  _deviceState(kid, s, t) {
    const lock = this._lockOf(s);
    if (lock) {
      const text = lock.kind === "paused" ? WORDS.screensPaused : `${LOCK_WORDS[lock.kind]}${lock.until ? ` till ${clock(lock.until)}` : ""}`;
      return { key: "lock", tone: lock.kind === "school_time" ? "school" : lock.kind === "paused" ? "low" : "night", text, note: "Everything follows the lock" };
    }
    const pool = t.left_pool || "all";
    const poolName = pool === "all" ? WORDS.dailyLower : (this._pools(s).find((g) => g.id === pool) || {}).name || pool;
    const company = { google: "Google", microsoft: "Microsoft", nintendo: "Nintendo" }[t.left_by] || "";
    if (t.locked_kind === "parent_lock") return { key: `parent:${t.via}`, tone: "out", text: "Locked by a parent", note: `Locked in ${company ? `${company}'s` : "the parent's"} app` };
    if (t.locked_kind === "out") return { key: `out:${pool}`, tone: "out", text: pool === "all" ? WORDS.outOfTime : `${cap(poolName)} ran out`, note: "" };
    if (t.locked_kind === "device_limit")
      return { key: `own:${t.left_by}`, tone: "out", text: t.left_by === "microsoft" && t.left ? "Microsoft's hours" : `${company || "Its own"} limit reached`, note: `${company || "The device"}'s own limit` };
    if (t.left === null || t.left === undefined) return { key: "none", tone: "ok", text: "No limit", note: "" };
    const tone = t.left < 10 ? "low" : "ok";
    if (t.left_by && t.left_by !== "hearth") return { key: `own:${t.left_by}:${t.left}`, tone, text: `${fmtMinutes(t.left)} left`, note: `${company}'s own daily limit on this device` };
    return { key: `left:${pool}:${t.left}`, tone, text: `${fmtMinutes(t.left)} left`, note: pool === "all" ? `Follows ${WORDS.dailyLower}` : `Follows ${cap(poolName)}` };
  }

  // Devices grouped by what they're doing: "3 TVs, 2 tablets · Follows screen time · 31 min left"
  _deviceGroups(kid, s) {
    const targets = (s.targets || []).filter((t) => !t.same_as);
    if (!targets.length) return "";
    const usedOf = new Map((s.devices_today || []).map((d) => [d.target, d.minutes]));
    const groups = new Map();
    for (const t of targets) {
      const st = this._deviceState(kid, s, t);
      if (!groups.has(st.key)) groups.set(st.key, { st, items: [] });
      groups.get(st.key).items.push({ t, kind: this._deviceKind(t), name: this._deviceName(t, kid.name), used: usedOf.get(t.id) || 0 });
    }
    const order = { out: 0, low: 1, ok: 2, night: 3, school: 3 };
    const sorted = [...groups.values()].sort((a, b) => (order[a.st.tone] ?? 5) - (order[b.st.tone] ?? 5));
    const words = { tv: ["TV", "TVs"], tablet: ["tablet", "tablets"], phone: ["phone", "phones"], xbox: ["Xbox", "Xboxes"], windows: ["PC", "PCs"], switch: ["Switch", "Switches"] };
    const label = (items) => {
      if (items.length === 1) return items[0].name;
      const by = new Map();
      for (const i of items) by.set(i.kind, [...(by.get(i.kind) || []), i]);
      if (by.size > 3) return `All ${items.length} screens`;
      return [...by.entries()].map(([k, list]) => (list.length === 1 ? list[0].name : `${list.length} ${(words[k] || [k, `${k}s`])[1]}`)).join(", ");
    };
    const fp = s.first_party || {};
    const facts = (t) => {
      const out = [];
      const fl = t.via === "family_link" ? (fp.family_link || []).find((r) => `fl:${r.device_id}` === t.id) : null;
      const fs = t.via === "family_safety" ? (fp.family_safety || []).find((r) => `fs:${String(r.platform).toLowerCase()}` === t.id) : null;
      const nin = t.via === "nintendo" ? (fp.nintendo || []).find((r) => r.target === t.id) : null;
      if (fl && fl.minutes_left !== null && fl.minutes_left !== undefined) out.push(`Google's limit: ${fmtMinutes(fl.minutes_left)} left`);
      if (fs && fs.blocking && !fs.held_by_hearth) out.push("Microsoft's hours also block it");
      if ((fs && fs.held_by_hearth) || (nin && nin.held_by_hearth)) out.push("Hearth is holding it");
      if (nin && nin.playing) out.push("playing now");
      return out;
    };
    let h = `<div class="card flat blk"><h3>Devices <span>${targets.length} linked</span></h3>`;
    for (const g of sorted) {
      const key = `${kid.id}|dev|${g.st.key}`;
      const open = this._exp.has(key);
      const kinds = new Set(g.items.map((i) => i.kind));
      const kind = kinds.size === 1 ? g.items[0].kind : kinds.has("tv") ? "tv" : g.items[0].kind;
      const usedAll = g.items.reduce((a, i) => a + i.used, 0);
      const d = [g.st.note, usedAll ? `${fmtMinutes(usedAll)} on ${g.items.length > 1 ? "these" : "it"} today` : ""].filter(Boolean).join(" · ");
      h += `<button class="dgroup" data-action="exp" data-key="${esc(key)}" aria-expanded="${open}"><span class="dic tone-${g.st.tone}">${icon(kind === "tablet" ? "tablet" : kind)}</span>
        <div class="grow"><div class="t">${esc(g.items.length > 3 && g.st.key === "lock" ? `All ${g.items.length} screens` : label(g.items))}</div>${d ? `<div class="d">${esc(d)}</div>` : ""}</div>
        <span class="r t-${g.st.tone}">${esc(g.st.text)}</span><span class="chev ${open ? "open" : ""}">${icon("chev", "sm")}</span></button>`;
      if (open)
        h += `<div class="dlist">${g.items
          .map((i) => `<div><span title="${esc(i.t.name && i.t.name !== i.name ? i.t.name : "")}">${esc(i.name)}</span><span>${esc([i.used ? `${fmtMinutes(i.used)} today` : "", ...facts(i.t)].filter(Boolean).join(" · ") || "not used today")}</span></div>`)
          .join("")}</div>`;
    }
    return `${h}</div>`;
  }

  // The rest of what's different today, in plain sentences (what was given is in Today's extras): app pauses, what a
  // parent changed in their own apps, what Hearth is holding and why, and what didn't take
  _exceptions(kid, s) {
    const notes = [];
    const p = esc(kid.id);
    const note = (ic, html) => notes.push(`<div class="note">${icon(ic, "sm")}<div>${html}</div></div>`);
    const till = (iso) => (iso ? ` till ${esc(clock(iso))}` : "");
    for (const x of s.pauses || [])
      note("pause", `${esc(x.name)} is paused${till(x.until)}${x.reason ? ` · ${esc(x.reason)}` : ""}. <button class="lnk" data-action="app-pause-end" data-person="${p}" ${x.app ? `data-app="${esc(x.app)}"` : `data-group="${esc(x.group)}"`}>End</button>`);
    // A parent's changes in their own apps
    const grants = s.grants || [];
    const where = { family_link: "the Family Link app", family_safety: "the Family Safety app", nintendo: "the Nintendo app" };
    const appGrants = grants.filter((g) => g.target?.kind === "app");
    if (appGrants.length) {
      const key = `${kid.id}|grants`;
      const open = this._exp.has(key);
      const names = [...new Set(appGrants.map((g) => g.name || g.target.value))].sort((a, b) => a.localeCompare(b));
      const what = appGrants.length === 1 ? `${esc(names[0])} is` : `${appGrants.length} apps are`;
      note("shield", `${what} allowed without a limit${till(appGrants[0].until)}. Someone changed ${appGrants.length === 1 ? "its" : "their"} limits in ${esc(where[appGrants[0].via] || "a parent's app")}. <button class="lnk" data-action="exp" data-key="${esc(key)}">${open ? "Hide" : "Show"}</button>${open ? `<div class="namelist">${esc(names.join(", "))}</div>` : ""}`);
    }
    for (const g of grants.filter((x) => x.target?.kind !== "app")) {
      const what = { device: "Their devices are", switch: "The Switch is" }[g.target?.kind] || `${esc(g.target?.value || "It")} is`;
      note("shield", `${what} open${till(g.until)}, from ${esc(where[g.via] || "a parent's app")}.${g.endable ? ` <button class="lnk" data-action="grant-end" data-grant="${esc(g.id)}">End</button>` : ""}`);
    }
    // What Hearth holds through each parental control, and what didn't take
    const services = { family_link: "Family Link", family_safety: "Family Safety", nintendo: "Nintendo" };
    const outPool = this._pools(s).find((g) => g.state === "out" && g.id !== "all");
    const reasons = { school_time: "it's School time", pause: "of a pause", schedule: "of the schedule", budget: outPool ? `${outPool.name} ran out` : "time ran out" };
    for (const [kind, st] of Object.entries(s.sync || {})) {
      const held = st.held || [];
      if (held.length) {
        const names = held.map((i) => this._itemName(i, st.names || {}));
        const whys = [...new Set(held.map((i) => (st.why || {})[i]).filter(Boolean))];
        const what = held.length <= 3 ? listWords(names.map((n) => (["Xbox", "Windows"].includes(n) ? `the ${n === "Windows" ? "PC" : n}` : n))) : `${held.length} apps`;
        const why = whys.length === 1 && reasons[whys[0]] ? ` because ${reasons[whys[0]]}` : "";
        const where = kind === "family_link" ? `on ${kid.name}'s Family Link devices` : `through ${services[kind] || kind}`;
        note("lock", `Hearth is blocking ${esc(what)} ${esc(where)}${esc(why)}.`);
      }
      const error = st.error || st.last?.error;
      if (error) note("info", `<span class="t-out">${esc(services[kind] || kind)} didn't take what Hearth asked:</span> ${esc(error)}`);
    }
    for (const a of s.answered_elsewhere || []) note("info", `Request ${esc(a.text)}.`);
    if (!notes.length) return "";
    return `<div class="card flat blk"><h3>Holds and notes</h3>${notes.join("")}</div>`;
  }

  // The week: only the days Hearth recorded, with the day's limit as a dashed line
  _weekBlock(s) {
    const days = [...(s.week || [])].reverse().filter((d) => d.minutes && Object.keys(d.minutes).length);
    if (!days.length) return "";
    const outside = this._notCounted();
    const today = (s.week || [])[0]?.date;
    const max = Math.max(60, ...days.map((d) => Math.max(d.minutes.all || 0, (d.budget && d.budget.all) || 0)));
    const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    const label = (ds) => (ds === today ? "Today" : DOW[new Date(`${ds}T12:00:00`).getDay()]);
    const names = new Map((s.groups || []).map((g) => [g.id, g.name]));
    let h = `<div class="card flat blk"><h3>This week <span>${days.length < 7 ? `${days.length} day${days.length === 1 ? "" : "s"} recorded` : ""}</span></h3><div class="weekc">`;
    for (const d of days) {
      const v = d.minutes.all || 0;
      const capD = d.budget && d.budget.all;
      const segs = Object.entries(d.minutes).filter(([k, m]) => k !== "all" && m > 0 && !outside.has(k));
      const sum = segs.reduce((a, [, m]) => a + m, 0);
      h += `<div class="col"><div class="wb" style="height:${Math.max(3, (v / max) * 92).toFixed(1)}px" title="${esc(`${label(d.date)}: ${fmtMinutes(v)}`)}"><span class="fill">${segs
        .map(([k, m]) => `<i style="height:${((m / Math.max(v, sum)) * 100).toFixed(1)}%;background:${this._poolVar(k)}"></i>`)
        .join("")}</span>${capD ? `<span class="cap" style="bottom:${((capD / max) * 92).toFixed(1)}px"></span>` : ""}</div><span class="lbl">${esc(label(d.date))}</span></div>`;
    }
    if (days.length < 3) h += `<div class="col wide"><div class="d">Hearth started counting ${days[0].date === today ? "today" : "recently"}. Each day adds a bar here.</div></div>`;
    const outs = [...new Set(days.flatMap((d) => d.out || []))].map((id) => (id === "all" ? "screen time" : names.get(id) || this._groupName(id)));
    h += `</div><div class="d">${esc(fmtMinutes(days.reduce((a, d) => a + (d.minutes.all || 0), 0)))} so far${outs.length ? ` · ran out at some point: ${esc(outs.join(", "))}` : ""}. Dashed line: the day's limit.</div></div>`;
    return h;
  }

  // An item a parental control holds, by name: an app's (never its package), "their devices", "the Switch"
  _itemName(item, names) {
    if (item === "Devices") return "their devices";
    if (item === "Switch") return "the Switch";
    return names[item] || item;
  }

  // The family today: one bar per kid for daily time, each category's minutes colored inside it and each category's
  // limit as a marker (no bar per category)
  _familyPools(kids) {
    const people = kids.map((k) => this._summaryPerson(k.id)).filter((p) => p && p.all && p.all.minutes_left !== null && p.all.minutes_left !== undefined);
    if (people.length < 2) return "";
    return `<section class="card pools"><h3><ha-icon icon="mdi:chart-bar"></ha-icon>Family today: ${esc(WORDS.dailyLower)}</h3>${people
      .map((p) => {
        const t = p.time || {};
        const used = p.all.used_minutes || 0;
        const cap = t.today_minutes ?? (p.all.budget ?? 0) + Math.max(0, p.all.bonus || 0);
        const total = Math.max(cap || 0, used, 1);
        const parts = (p.all_by_pool || []).filter((x) => x.minutes > 0);
        const fill = parts.length ? parts : used ? [{ id: "all", name: WORDS.daily, minutes: used }] : [];
        const markers = (t.categories || [])
          .filter((c) => c.limit_today !== null && c.limit_today !== undefined && c.limit_today <= total)
          .map((c) => `<b class="mark" style="left:${((c.limit_today / total) * 100).toFixed(2)}%;border-color:${this._poolVar(c.id)}" title="${esc(c.limit_text)}"></b>`)
          .join("");
        const value = t.unlimited ? WORDS.unlimited : p.all.state === "out" ? "Out" : `${amount(p.all.minutes_left)} left`;
        return `<div class="bar-row role-${role(p.all.state)}"><span class="bar-label">${esc(p.name)}</span>
          <div class="stack" role="img" aria-label="${esc(`${p.name}: ${fmtMinutes(used)} of ${fmtMinutes(cap)}`)}">${fill
            .map((x) => `<i style="width:${((x.minutes / total) * 100).toFixed(2)}%;background:${this._poolVar(x.id)}" title="${esc(`${x.name}: ${fmtMinutes(x.minutes)}`)}"></i>`)
            .join("")}${markers}</div><span class="bar-value">${esc(value)}</span></div>`;
      })
      .join("")}</section>`;
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
      ${this._choresCard(kid)}
      ${this._extraTimeCard(kid)}`;
  }

  _limitsCard(kid) {
    const groups = (this._config.groups || []).filter((g) => !g.never_held);
    const b = this._config.budgets?.[kid.id] || {};
    return `<section class="card">
      <h3><ha-icon icon="mdi:timer-sand"></ha-icon>Daily limits</h3>
      <p class="muted">Minutes a day. Empty means no limit. <b>${esc(WORDS.daily)}</b> is the one total across every device; a category's limit only stops that category from taking all of it, and never adds time.
        School days here are Monday to Friday in the schedule, other days the weekend and the Day off.
        <button class="chip-btn" data-action="tab" data-tab="schedule">Set each day in the Schedule</button></p>
      <div class="presets">Quick ${esc(WORDS.dailyLower)}:
        ${[60, 90, 120, 180].map((m) => `<button class="chip-btn" data-action="budget-preset" data-person="${esc(kid.id)}" data-days="both" data-minutes="${m}">${fmtMinutes(m)}</button>`).join("")}
      </div>
      <table class="limits"><thead><tr><th>${esc(WORDS.daily)} and limits</th><th>School days</th><th>Other days</th></tr></thead><tbody>
      ${groups
        .map((g) => {
          const v = b[g.id] || {};
          const input = (days, value) =>
            `<span class="minutes"><input type="number" min="0" max="1440" step="5" inputmode="numeric" placeholder="No limit" value="${value ?? ""}"
              data-change="budget" data-person="${esc(kid.id)}" data-group="${esc(g.id)}" data-days="${days}" aria-label="${esc(g.name)} ${days}">
              <span class="muted small">${value === null || value === undefined ? "" : value >= 60 ? `min · ${esc(fmtMinutes(value))}` : "min"}</span></span>`;
          return `<tr><td>${esc(g.id === "all" ? WORDS.daily : `${g.name} limit`)}${g.in_all ? "" : ` <span class="chip small">not screen time</span>`}</td><td>${input("school_days", v.school)}</td><td>${input("other_days", v.other)}</td></tr>`;
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
        return `<li><div class="grow">${esc(g.id === "all" ? WORDS.daily : g.name)}</div>
          <label class="check"><input type="checkbox" data-change="suggest-on" ${data} ${pair ? "checked" : ""}> When it runs out</label>
          <select data-change="suggest-minutes" ${data} aria-label="${esc(g.name)}: minutes offered" ${pair ? "" : "disabled"}>
            ${[15, 30, 45, 60].map((m) => `<option value="${m}" ${m === minutes ? "selected" : ""}>+${m} min ${WORDS.bonusShort}</option>`).join("")}</select></li>`;
      })
      .join("");
    return `<section class="card">
      <h3><ha-icon icon="mdi:cellphone-message"></ha-icon>Send suggestions to adults' phones</h3>
      <p class="muted small">When one runs out while ${esc(kid.name)} is awake, the adults' phones ask "give more?" once a day, with two amounts and Not today. Off: the suggestion still shows on Today.</p>
      <ul class="list compact small-controls">${rows}</ul>
    </section>`;
  }

  // A kid's to-do list (todos.py): tasks with how they repeat and their reward, today's items (tick, Give, Undo),
  // what chores gave lately and the money balance. A reward is granted when the item is checked off: no approval step
  _choresCard(kid) {
    const p = esc(kid.id);
    const t = this._todo[kid.id];
    const head = `<h3><ha-icon icon="mdi:checkbox-marked-circle-outline"></ha-icon>Chores</h3>`;
    if (t === undefined) {
      // Opened straight on the Kids tab: read it now
      if (!this._todoBusy.has(kid.id)) setTimeout(() => this._loadTodo(kid.id), 0);
      return `<section class="card">${head}<p class="muted">Loading…</p></section>`;
    }
    if (t === null) return `<section class="card">${head}<p class="muted">The to-do list couldn't be read.</p></section>`;
    const groups = this._config.groups || [];
    const today = (t.today || [])
      .map((i) => {
        const state = i.granted
          ? `<span class="chip small">given</span><button class="btn" data-action="todo-undo" data-person="${p}" data-key="${esc(i.granted)}">Undo</button>`
          : i.done && i.reward
            ? `<span class="chip dim small">no reward given</span><button class="btn" data-action="todo-give" data-person="${p}" data-item="${esc(i.id)}">Give</button>`
            : "";
        return `<li><label class="check grow"><input type="checkbox" data-change="todo-check" data-person="${p}" data-item="${esc(i.id)}" ${i.done ? "checked" : ""}>
          ${esc(i.title)}${i.reward ? ` <span class="muted small">${esc(i.reward)}</span>` : ""}${i.by === "kid" ? ` <span class="chip small">${esc(kid.name)}'s own</span>` : ""}</label>${state}</li>`;
      })
      .join("");
    const tasks = (t.tasks || [])
      .map(
        (task) => `<li><div class="grow">${esc(task.title)} <span class="muted small">${esc(repeatWords(task))}${task.due_time ? ` · by ${esc(task.due_time)}` : ""}${task.reward ? ` · ${esc(rewardWords(task.reward, groups))}` : ""}</span></div>
          <button class="icon-btn" data-action="todo-del" data-task="${esc(task.id)}" data-person="${p}" aria-label="Remove ${esc(task.title)}"><ha-icon icon="mdi:delete-outline"></ha-icon></button></li>`
      )
      .join("");
    const recent = (t.ledger || [])
      .filter((e) => e.kind === "earned")
      .slice(0, 8)
      .map(
        (e) => `<li><div class="grow">${esc(e.title)} <span class="muted small">${esc(e.day)} · ${esc(e.cents !== undefined ? money(e.cents) : `+${e.minutes} min ${this._groupName(e.pool)}`)}${e.reversed_at ? " · taken back" : ""}</span></div>
          ${e.reversed_at ? "" : `<button class="btn" data-action="todo-undo" data-person="${p}" data-key="${esc(e.key)}">Undo</button>`}</li>`
      )
      .join("");
    return `<section class="card">
      ${head}
      <p class="muted small">${esc(kid.name)}'s to-do list (todo.hearth_${esc(kid.id.split(".")[1] || "")} on a tablet or by voice). A reward is given when ${esc(kid.name)} or an adult checks the item off; the adults' phones are told, with Undo. Balance: <b>${esc(money(t.balance_cents || 0))}</b></p>
      <h4>Today</h4>
      ${today ? `<ul class="list compact">${today}</ul>` : `<p class="muted">Nothing on the list today.</p>`}
      <h4>Tasks</h4>
      ${tasks ? `<ul class="list compact">${tasks}</ul>` : `<p class="muted">No tasks yet.</p>`}
      <div class="inline wrap">
        <input id="todo-title-${p}" type="text" maxlength="120" placeholder="Feed the cat" aria-label="Task">
        <select id="todo-repeat-${p}" aria-label="Repeats">
          <option value="daily">Every day</option><option value="school">Mon to Fri</option><option value="weekend">Sat and Sun</option>
          <option value="every_n">Every N days</option><option value="after_done">N days after done</option><option value="once">Once</option></select>
        <input id="todo-n-${p}" type="number" min="1" max="365" placeholder="N" aria-label="N days" style="width:5em">
        <input id="todo-due-${p}" type="time" aria-label="Due by">
        <select id="todo-reward-${p}" aria-label="Reward"><option value="">No reward</option><option value="minutes">Bonus minutes</option><option value="money">Money</option></select>
        <input id="todo-amount-${p}" type="number" min="1" step="1" placeholder="15 min or $" aria-label="Amount" style="width:7em">
        <button class="btn primary" data-action="todo-add" data-person="${p}">Add</button>
      </div>
      ${recent ? `<h4>Lately</h4><ul class="list compact">${recent}</ul>` : ""}
    </section>`;
  }

  async _loadTodo(person) {
    if (!person || this._todoBusy.has(person)) return;
    this._todoBusy.add(person);
    try {
      this._todo[person] = await this._hass.callWS({ type: "hearth/todo/list", person });
    } catch (_err) {
      this._todo[person] = null;
    } finally {
      this._todoBusy.delete(person);
    }
    this._render();
  }

  async _todoWs(message, person, done) {
    await this._ws(message, done);
    await this._loadTodo(person);
  }

  _extraTimeCard(kid) {
    // Bonus time has no category: one amount (a raised limit is on Today, per category)
    return `<section class="card">
      <h3><ha-icon icon="mdi:plus-circle-outline"></ha-icon>${esc(WORDS.bonus)} today</h3>
      <div class="inline">
        <input id="custom-${esc(kid.id)}" type="number" step="5" placeholder="Minutes (−15 takes away)" data-enter="bonus-custom" data-person="${esc(kid.id)}">
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
        .map((s) => `<li><ha-icon icon="mdi:counter"></ha-icon><div class="grow" title="${esc(s.entity_id)}"><div>${esc(s.name || this._entityName(s.entity_id))}</div><div class="muted small">${esc([s.group ? `Counts in ${this._groupName(s.group)}` : "Counts in screen time", s.same_as ? "the same device as another" : "", s.live ? "says what's playing" : ""].filter(Boolean).join(" · "))}</div></div>
          <button class="icon-btn" data-action="source-remove" data-id="${esc(s.id)}" aria-label="Remove"><ha-icon icon="mdi:close"></ha-icon></button></li>`)
        .join("")}</ul>` : `<p class="muted small">None yet.</p>`}
      <details id="add-source-${esc(kid.id)}"><summary>Add a source</summary>
        <div class="form">
          <label class="field">Sensor<select id="source-entity-${esc(kid.id)}">${this._entityOptions(cfg.choices?.screen_time, "", "Choose a sensor…")}</select></label>
          <label class="field">Name (optional)<input id="source-name-${esc(kid.id)}" placeholder="Phone, Xbox…"></label>
          <label class="field">Time it can't put on an app counts in<select id="source-group-${esc(kid.id)}">${this._options(groups.filter((g) => g.id !== "all").map((g) => ({ value: g.id, label: g.name })), "", `${WORDS.daily} only`)}</select></label>
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
        .map((l) => `<li><ha-icon icon="mdi:lock-clock"></ha-icon><div class="grow" title="${esc(l.entity_id)}">${esc(this._entityName(l.entity_id))}<div class="muted small">${esc({ on: "On now", off: "Off now" }[this._hass.states[l.entity_id]?.state] || "Not reporting")}</div></div>
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
        <label class="check"><input type="checkbox" data-change="fl-backstop" ${cfg.fl_backstop !== false ? "checked" : ""}> ${esc(WORDS.backstop)}</label>
        <label class="field">${esc(WORDS.backstopMargin)}
          <input type="number" min="0" max="240" step="5" value="${esc(cfg.fl_backstop_margin ?? 30)}" data-change="fl-backstop-margin" ${cfg.fl_backstop === false ? "disabled" : ""}></label>
        <div class="muted small">${esc(WORDS.backstopHint)} For everyone in the household.</div>
        <label class="field">Family Link: during School time, pause these apps (package names)
          <input id="enf-fl-school-${esc(kid.id)}" type="text" value="${esc((fl ? fl.school_time_apps || [] : ["com.google.android.apps.messaging"]).join(", "))}" placeholder="com.google.android.apps.messaging"></label>
        <label class="field">Microsoft Family Safety
          <select id="enf-fs-${esc(kid.id)}">${this._entityOptions(cfg.choices?.family_safety, fs?.entity_id || "", "Not used")}</select></label>
        <div class="checks">${(cfg.platforms || []).map((p) => `<label class="check"><input type="checkbox" data-fs-platform="${esc(kid.id)}" value="${esc(p)}" ${(fs?.platforms || ["Xbox"]).includes(p) ? "checked" : ""}> ${esc(p)}</label>`).join("")}</div>
        <div class="muted small">Locks those while any of these is out:</div><div class="checks">${groupBoxes("data-fs-group", fs?.groups || ["all", "games"])}</div>
        <label class="field">Nintendo Switch
          <select id="enf-nin-${esc(kid.id)}">${this._entityOptions(cfg.choices?.nintendo, nin?.entity_id || "", "Not used")}</select></label>
        <div class="muted small">Suspends the game while any of these is out:</div><div class="checks">${groupBoxes("data-nin-group", nin?.groups || ["all", "games"])}</div>
        <label class="field">A shared Switch: ${esc(kid.name)}'s player on it (held only once ${esc(kid.name)} is caught playing)
          <select id="enf-nin-player-${esc(kid.id)}">${this._entityOptions(cfg.choices?.nintendo_players, (nin?.playing || []).length && !(nin?.player || []).length ? "" : (nin?.player || [])[0] || this._guessPlayer(kid, nin), "Hold the whole Switch")}</select></label>
        <label class="field">Optional: a playing sensor of ${esc(kid.name)}'s (a patched Nintendo integration's, or friend presence)
          <select id="enf-nin-playing-${esc(kid.id)}">${this._entityOptions(cfg.choices?.nintendo_playing, (nin?.playing || [])[0] || "", "None")}</select></label>
        <div class="muted small">Nintendo reports play about every 10 minutes, so ${esc(kid.name)} can play that long before the hold starts. Once caught, the Switch stays held until ${esc(kid.name)} has time again; the Switch card has Let someone else play.</div>
        <div class="actions"><button class="btn primary" data-action="enforce-save" data-person="${esc(kid.id)}">Save</button></div>
      </div>
    </section>`;
  }

  // The kid's player on their Switch by name, when the Switch has several players and exactly one name matches
  _guessPlayer(kid, nin) {
    if (!nin?.entity_id) return "";
    const players = (this._config.choices?.nintendo_players || []).filter((p) => p.switch === nin.entity_id);
    if (players.length < 2) return "";
    const name = String(kid.name || "").trim().toLowerCase();
    const first = name.split(/\s+/)[0];
    const words = (s) => String(s || "").toLowerCase().split(/[^\p{L}\p{N}_]+/u).filter(Boolean);
    const found = players.filter((p) => p.nickname && (p.nickname.toLowerCase() === name || words(p.nickname).includes(first)));
    return found.length === 1 ? found[0].entity_id : "";
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
    if (n.shared && n.playing_now === null && !n.caught && !n.turn)
      status.push(`<span class="chip dim" title="Nintendo hasn't reported lately, so Hearth can't tell who's playing"><ha-icon icon="mdi:help-circle-outline"></ha-icon>Who's playing: not known</span>`);
    sections.push(`<div class="chips">${status.join("")}</div>
      <div class="facts">${facts.map(([k, v]) => `<div><div class="muted small">${esc(k)}</div><div class="strong">${esc(v)}</div></div>`).join("")}</div>`);
    // A shared Switch held because the kid was caught playing out of time: everyone waits, unless it's someone else's turn
    if (n.caught && n.target)
      sections.push(`<div class="row wrap"><div class="grow muted small">Held for everyone: ${esc(kid.name)} played it with no time left. It stays held until ${esc(kid.name)} has time again.</div>
        ${[30, 60, 120].map((m) => `<button class="btn" data-action="nin-let-play" data-person="${p}" data-device="${dev}" data-minutes="${m}">Let someone else play ${m < 60 ? `${m} min` : `${m / 60} h`}</button>`).join("")}</div>`);
    else if (n.turn && n.target) {
      const until = new Date(n.turn.until).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      const who = n.turn.for_person ? `${this._personName(n.turn.for_person)}'s turn` : "Someone else's turn";
      sections.push(`<div class="row wrap"><div class="grow muted small">${esc(who)} until ${esc(until)}. If ${esc(kid.name)} plays meanwhile, the Switch is held again.</div>
        <button class="btn" data-action="nin-let-play" data-person="${p}" data-device="${dev}" data-minutes="0">Hold again now</button></div>`);
    }
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
          <li>On the TV, open Hearth's <b>Settings → Home Assistant → Pair with Home Assistant</b>. On a phone, pair from an app that works with Hearth (Glint, for example: Settings › Home Assistant).</li>
          <li>It shows a code, and the request appears at the top of this page.</li>
          <li>Check the codes match, then pair. A phone also asks whose it is.</li>
        </ol>
      </section>
      <section class="card">
        <h3><ha-icon icon="mdi:devices"></ha-icon>Paired</h3>
        ${(cfg.devices || []).length ? `<ul class="list">${cfg.devices
          .map((dv) => `<li><ha-icon icon="${dv.kind === "tv" ? "mdi:television" : "mdi:cellphone"}"></ha-icon><div class="grow"><div>${esc(dv.name || dv.id)}</div>
            <div class="muted small">${dv.kind === "tv" ? "TV" : `Phone${dv.person ? ` · ${esc(this._personName(dv.person))}'s` : ""}`} · ${dv.connected ? "connected" : "not heard from lately"}</div>
            ${this._deviceClientLines(dv)}</div>
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
          <div class="muted small">${esc((c.entries || []).map((e) => `${e.title}: ${e.state.replace(/_/g, " ")}`).join(", "))}${c.connection ? ` · connection ${esc(c.connection.state)}` : ""}</div>${this._reducedLines(c)}</div></li>`)
        .join("")}</ul>` : `<p class="muted">None installed. Family Link (phones and tablets), Microsoft Family Safety (Windows and Xbox) and Nintendo Switch Parental Controls each add their devices.</p>`}
    </section>`;
  }

  // What Hearth does with less on the version installed (Family Safety: fs_capabilities.py), not a problem to fix
  _reducedLines(c) {
    const lines = c.reduced || [];
    if (!lines.length) return "";
    return `<details class="reduced"><summary class="muted small">Works with less on this version (${lines.length})</summary>
      ${lines.map((t) => `<div class="muted small">${esc(t)}</div>`).join("")}</details>`;
  }

  _groupSelect(app, group, idx = null) {
    const groups = (this._config.groups || []).filter((g) => g.id !== "all");
    return `<select data-change="app-group" data-app="${esc(app)}"${idx != null ? ` data-idx="${idx}"` : ""} aria-label="Group">
      ${groups.map((g) => `<option value="${esc(g.id)}" ${g.id === group ? "selected" : ""}>${esc(g.name)}</option>`).join("")}
      <option value="other" ${group === "other" ? "selected" : ""}>Other</option></select>`;
  }

  // What an app is, in words: "YouTube", "Games", "System screens"
  _categoryLabel(category, detail) {
    const labels = this._config.categories?.labels || {};
    if (category === "none") return "none of Hearth's kinds";
    return labels[detail] || labels[category] || cap(detail || category || "");
  }

  // Where Hearth's answer of what an app is came from
  _sourceLabel(a) {
    switch (a.source) {
      case "override": return "set by you";
      case "starter": return "Hearth's list";
      case "store": return a.genre ? `store: ${a.genre}` : "store";
      case "ai": return "AI guess";
      default: return a.waiting ? "not known yet, looking it up" : "not known";
    }
  }

  // An adult says what an app is: Hearth's answer (auto), a category, a finer kind, or none of them
  _categorySelect(a) {
    const c = this._config.categories || {};
    const details = c.detail_choices || {};
    const current = a.source === "override" ? (a.category === null ? "none" : a.detail ? `${a.category}/${a.detail}` : a.category) : "auto";
    const auto = a.source && a.source !== "unknown" && a.source !== "override"
      ? `Hearth: ${a.category ? this._categoryLabel(a.category, a.detail) : "none"}` : "Hearth decides";
    const options = [["auto", auto]];
    for (const category of c.category_choices || []) {
      options.push([category, this._categoryLabel(category)]);
      for (const [detail, parent] of Object.entries(details)) if (parent === category) options.push([`${category}/${detail}`, `${this._categoryLabel(category)}: ${this._categoryLabel(category, detail)}`]);
    }
    options.push(["none", "None of these"]);
    return `<select data-change="app-category" data-app="${esc(a.package)}" aria-label="What it is">
      ${options.map(([v, label]) => `<option value="${esc(v)}" ${v === current ? "selected" : ""}>${esc(label)}</option>`).join("")}</select>`;
  }

  _appRow(a, extra = "") {
    const says = a.category_says ? ` · Hearth now knows it as ${esc(this._categoryLabel(a.category_says))}` : "";
    const kind = a.source ? ` · ${esc(a.category ? this._categoryLabel(a.category, a.detail) : a.source === "unknown" ? "kind not known" : "none of Hearth's kinds")} (${esc(this._sourceLabel(a))})` : "";
    const sub = `${extra}${kind}${says}`.replace(/^ · /, "");
    return `<li><div class="grow"><div title="${esc(a.package)}">${esc(this._appName(a))}${a.moved ? ` <span class="chip small">moved by you</span>` : ""}${a.source === "ai" ? ` <span class="chip small warn">AI guess</span>` : ""}${this._blockChip(a.package)}</div>
      ${sub ? `<div class="muted small">${sub}</div>` : ""}</div>${a.source ? this._categorySelect(a) : ""}${this._groupSelect(a.package, a.group)}${this._blockButton(a)}</li>`;
  }

  // Hearth's app blocks (app_blocks.py): the kids with Family Link, and who has [pkg] blocked
  _blockKids() {
    return (this._config?.app_blocks?.kids || []).filter((k) => k.family_link);
  }

  _blockedFor(pkg) {
    return this._blockKids().filter((k) => (k.blocks || []).some((b) => b.app === pkg));
  }

  _androidPackage(pkg) {
    return /^[A-Za-z][\w]*(\.[A-Za-z_][\w]*)+$/.test(String(pkg || ""));
  }

  _blockChip(pkg) {
    const kids = this._blockedFor(pkg);
    if (!kids.length) return "";
    const all = kids.length === this._blockKids().length;
    return ` <span class="chip small out">${all ? "blocked" : `blocked for ${esc(kids.map((k) => k.name).join(", "))}`}</span>`;
  }

  // A block action on an Android app's row: every kid with Family Link
  _blockButton(a) {
    const kids = this._blockKids();
    if (!kids.length || !this._androidPackage(a.package) || this._blockedFor(a.package).length === kids.length) return "";
    return `<button class="btn" data-action="app-block" data-app="${esc(a.package)}" data-name="${esc(this._appName(a))}" title="Block it for every kid through Family Link">Block</button>`;
  }

  _blockStateLabel(b) {
    // "Family Link didn't block <app>" after Hearth's tries; any other error as it came
    if (b.error) return /^Family Link didn't block/.test(b.error) ? b.error : `couldn't block: ${b.error}`;
    return { blocked: "blocked", parent: "blocked by a parent in Family Link", not_installed: "not installed: blocked when it shows up", pending: "blocking…" }[b.state] || b.state;
  }

  _blockWhyLabel(why) {
    return (why || []).map((w) => ({ adult: "by an adult", browser: "a browser Hearth doesn't support", app_store: "another app store", ai_companion: "an AI companion app" }[w] || w)).join(", ");
  }

  // Blocked by Hearth: the browser rule, the browsers Hearth filters sites in, each kid's blocks (Unblock), and Windows
  // and Xbox, covered by Family Safety's web filter
  _blocksCard() {
    const b = this._config.app_blocks;
    if (!b) return "";
    const supported = (b.supported || []).map((s) => `${s.name} on ${s.platform}`).join(", ");
    const kids = b.kids || [];
    const filter = (k) => {
      const w = k.web_filter;
      if (!w) return `<span class="muted small">Windows and Xbox: no Family Safety set up</span>`;
      if (w.on === true) return `<span class="chip small">Windows and Xbox: covered by Family Safety web filtering: on</span>`;
      if (w.on === false) return `<span class="chip small warn">Windows and Xbox: Family Safety web filtering is off, so other browsers aren't blocked</span>`;
      return `<span class="chip small warn">Windows and Xbox: Family Safety's web filtering switch wasn't found</span>`;
    };
    return `<section class="card">
      <h3><ha-icon icon="mdi:web-cancel"></ha-icon>Blocked by Hearth</h3>
      <p class="muted">Apps Hearth blocks through Family Link. Hearth blocks one again when it's installed again, never pauses or resumes a blocked app, and an allow doesn't lift a block. Unblock here: Hearth only ever unblocks what it blocked, so a parent's own block in Family Link stays, and a block a parent takes back in the Family Link app stays unblocked until you block it again here.</p>
      <label class="check"><input type="checkbox" data-change="block-browsers" ${b.rule ? "checked" : ""}> Block browsers Hearth doesn't support</label>
      <div class="muted small">Hearth filters sites in: ${esc(supported)}. With this on, any other browser on a kid's Android devices is blocked as soon as Family Link lists it, and so are other app stores that skip Family Link's approval (${esc(Object.values(b.app_stores || {}).filter((v, i, all) => all.indexOf(v) === i).join(", "))}).</div>
      <label class="check"><input type="checkbox" data-change="block-ai-companions" ${b.ai_companion_rule !== false ? "checked" : ""}> Block AI companion apps</label>
      <div class="muted small">The AI companion and character role-play chat apps Hearth knows (${esc(Object.values(b.ai_companions || {}).join(", "))}) are blocked as soon as Family Link lists them. An app only named like one isn't blocked: the adults get a notice with Block and Not now, once per app and kid. General assistants (Gemini, ChatGPT, Copilot, Claude), messaging and school apps get neither.</div>
      ${kids.length ? `<ul class="list compact">${kids
        .map((k) => `<li><div class="grow"><div>${esc(k.name)}</div>
          ${k.family_link ? "" : `<div class="muted small">No Family Link set up (Kids tab, parental controls): nothing to block on Android</div>`}
          ${(k.blocks || []).length ? `<ul class="list compact">${k.blocks
            .map((x) => `<li><div class="grow"><div title="${esc(x.app)}">${esc(x.name || x.app)}</div><div class="muted small">${esc(this._blockWhyLabel(x.why))} · ${esc(this._blockStateLabel(x))}</div></div>
              <button class="btn" data-action="app-unblock" data-app="${esc(x.app)}" data-name="${esc(x.name || x.app)}" data-person="${esc(k.person)}">Unblock</button></li>`)
            .join("")}</ul>` : k.family_link ? `<div class="muted small">Nothing blocked</div>` : ""}
          ${(k.parent_unblocked || []).length ? `<ul class="list compact">${k.parent_unblocked
            .map((x) => `<li><div class="grow"><div title="${esc(x.app)}">${esc(x.name || x.app)}</div><div class="muted small">unblocked by a parent in Family Link: Hearth leaves it unblocked</div></div>
              <button class="btn" data-action="app-block-kid" data-app="${esc(x.app)}" data-name="${esc(x.name || x.app)}" data-person="${esc(k.person)}">Block again</button></li>`)
            .join("")}</ul>` : ""}
          <div>${filter(k)}</div></div></li>`)
        .join("")}</ul>` : `<p class="muted small">No kids yet.</p>`}
    </section>`;
  }

  // An app's name, never its package: a guess from the package when nothing better is known
  _appName(a) {
    if (a.name && a.name !== a.package) return a.name;
    const parts = String(a.package || "").split(".").filter((x) => x && !["com", "org", "net", "android", "app", "apps", "x:xboxplt:"].includes(x));
    const last = parts[parts.length - 1] || a.package || "";
    return cap(last);
  }

  // A build for testing (Hearth's own .ardtest builds, a debug build): not an app a kid uses
  _testBuild(pkg) {
    return /\.(ardtest|debug|dev|test)$/.test(String(pkg || ""));
  }

  // Apps placed on a guess (a store's loose genre, an AI's), or where Hearth's answer and the device disagree: an
  // adult keeps or moves each
  _checkTheseCard() {
    const rows = this._config.check_these || [];
    if (!rows.length) return "";
    return `<section class="card">
      <h3><ha-icon icon="mdi:help-circle-outline"></ha-icon>Check these</h3>
      <p class="muted">Placed on a guess (an AI's, or a store's), or where what Hearth knows and the device disagree (Hearth goes by what it knows). Keep each where it is, or move it; your choice always wins.</p>
      <ul class="list compact">${rows
        .map((a, i) => `<li><div class="grow"><div title="${esc(a.package)}">${esc(this._appName(a))}</div>
          <div class="muted small">${esc(a.why)}</div></div>
          <button class="btn" data-action="app-confirm" data-app="${esc(a.package)}" data-group="${esc(a.group)}">Right</button>
          ${this._groupSelect(a.package, a.group, i)}</li>`)
        .join("")}</ul>
    </section>`;
  }

  // App categories: how the apps are known, store lookups, the AI Task entity, and which group each kind goes to
  _categoriesCard() {
    const c = this._config.categories;
    if (!c) return "";
    const groups = (this._config.groups || []).filter((g) => g.id !== "all");
    const names = { other: "Other", ...Object.fromEntries(groups.map((g) => [g.id, g.name])) };
    const n = c.sources || {};
    const counts = [["override", "set by you"], ["starter", "from Hearth's list"], ["store", "from their store"], ["ai", "AI guesses"], ["unknown", "not known"]]
      .filter(([k]) => n[k]).map(([k, label]) => `${n[k]} ${label}`).join(", ");
    const ais = c.ai_entities || [];
    const aiName = (e) => this._hass?.states?.[e]?.attributes?.friendly_name || e;
    const choice = c.ai || "default";
    const using = choice === "off" ? "No AI is asked."
      : c.ai_entity ? `AI guesses use ${aiName(c.ai_entity)}.`
      : "No default AI Task in Home Assistant (Settings > AI Task): no AI is asked.";
    return `<section class="card">
      <h3><ha-icon icon="mdi:shape-outline"></ha-icon>App categories</h3>
      <p class="muted">What each app is (a game, YouTube, streaming, a companion app) decides its group unless you moved it. Hearth knows ${c.starter || 0} apps from its own list. When a kid first uses one it doesn't know, it can look the app's genre up in its store: that sends the app's public store id to Google Play, the Microsoft Store or Steam, and nothing else. Your choice always wins.</p>
      ${counts ? `<div class="muted small">Apps here: ${esc(counts)}${c.waiting ? ` · ${c.waiting} waiting to be looked up` : ""}</div>` : ""}
      <label class="check"><input type="checkbox" data-change="category-lookup" ${c.lookup ? "checked" : ""}> Look new apps up in their store</label>
      <label class="field">Ask an AI when the store doesn't say
        <select data-change="category-ai" aria-label="AI Task entity">
          <option value="default" ${choice === "default" ? "selected" : ""}>Home Assistant's default AI Task${c.ai_default ? ` (${esc(aiName(c.ai_default))})` : " (none set)"}</option>
          <option value="off" ${choice === "off" ? "selected" : ""}>Off</option>
          ${ais.map((e) => `<option value="${esc(e)}" ${choice === e ? "selected" : ""}>${esc(aiName(e))}</option>`).join("")}
        </select></label>
      <div class="muted small">${esc(using)} The AI gets the app's name, store id and the store's one-line description, at most 20 apps a day. Its answer is only a guess: it never puts an app in Messaging, Accessibility or System screens.</div>
      <details><summary>Which group each kind of app goes to</summary>
        <ul class="list compact">${(c.values || [])
          .map((v) => `<li><div class="grow">${esc(c.labels?.[v] || v)}</div><select data-change="category-pool" data-value="${esc(v)}" aria-label="${esc(v)}">
            <option value="" ${c.own_pools?.[v] ? "" : "selected"}>Hearth's default (${esc(names[c.pools?.[v]] || "Other")})</option>
            ${groups.map((g) => `<option value="${esc(g.id)}" ${c.own_pools?.[v] === g.id ? "selected" : ""}>${esc(g.name)}</option>`).join("")}
            <option value="other" ${c.own_pools?.[v] === "other" ? "selected" : ""}>Other</option></select></li>`)
          .join("")}</ul>
      </details>
    </section>`;
  }

  _appsTab() {
    const cfg = this._config;
    const known = cfg.known_apps || {};
    const filter = this._appFilter || "";
    const source = this._appSource || "";
    const all = (cfg.apps || []).filter((a) => !this._testBuild(a.package)).filter((a) => !filter || a.name.toLowerCase().includes(filter) || a.package.includes(filter))
      .filter((a) => !source || a.source === source);
    const recent = (cfg.recent || []).filter((a) => !this._testBuild(a.package));
    const appsCards = `${this._checkTheseCard()}
      ${this._blocksCard()}
      <section class="card">
        <h3><ha-icon icon="mdi:new-box"></ha-icon>Sorted lately</h3>
        <p class="muted">New apps go to a group on their own: one that lists them, else what they are (games, video, social…; Messaging and Accessibility only from Hearth's list or your choice, never a guess), else Other. Accessibility apps are never paused. System screens (the home screen, lock screen, keyboards) never count and are never paused; only Hearth's list or your choice puts an app there. If one landed wrong, move it or say what it is; your choice always wins.</p>
        ${recent.length ? `<ul class="list compact">${recent.map((a) => this._appRow(a, `${a.who ? ` · ${esc(a.who)}` : ""} · ${esc(new Date(a.seen).toLocaleDateString())}`)).join("")}</ul>` : `<p class="muted small">Nothing new lately.</p>`}
      </section>
      <section class="card">
        <h3><ha-icon icon="mdi:apps"></ha-icon>Every app</h3>
        <div class="inline"><input id="app-filter" class="filter" placeholder="Find an app" value="${esc(this._appFilter || "")}">
          <select data-change="app-source" aria-label="Show">
            ${[["", "Every app"], ["ai", "AI guesses"], ["unknown", "Not known"], ["store", "From their store"], ["starter", "From Hearth's list"], ["override", "Set by you"]]
              .map(([v, label]) => `<option value="${v}" ${source === v ? "selected" : ""}>${label}</option>`).join("")}
          </select></div>
        <ul class="list compact">${all.slice(0, 200).map((a) => this._appRow(a)).join("") || `<li class="muted small">No apps match.</li>`}</ul>
        ${all.length > 200 ? `<p class="muted small">Showing 200 of ${all.length}: narrow it down above.</p>` : ""}
      </section>
      ${this._categoriesCard()}`;
    const datalist = `<datalist id="known-apps">${Object.entries(known)
      .map(([pkg, name]) => `<option value="${esc(pkg)}">${esc(name)}</option>`)
      .join("")}</datalist>`;
    const groups = (cfg.groups || []).filter((g) => g.id !== "all");
    return `${datalist}${appsCards}
      <section class="card">
        <h3><ha-icon icon="mdi:shape-plus"></ha-icon>${esc(WORDS.categories)}</h3>
        <p class="muted">A category can have its own daily limit (Kids tab). Untick <b>Screen time</b> for things like music: their minutes don't count toward ${esc(WORDS.dailyLower)}, and they keep working when it runs out.</p>
        <div class="inline"><input id="group-new-name" placeholder="New category, e.g. Homework" data-enter="group-add"><button class="btn" data-action="group-add">Add category</button></div>
      </section>
      ${groups
        .map(
          (g) => `<section class="card">
          <div class="row"><h3 class="grow">${esc(g.name)}</h3>
            ${g.never_counted ? `<span class="chip small">never screen time</span>` : `<label class="check"><input type="checkbox" data-change="outside-all" data-group="${esc(g.id)}" ${g.in_all ? "checked" : ""}> Screen time</label>`}
            ${g.builtin ? "" : `<button class="icon-btn" data-action="group-remove" data-group="${esc(g.id)}" aria-label="Remove group"><ha-icon icon="mdi:delete-outline"></ha-icon></button>`}</div>
          <div class="chips">${g.apps
            .map((a) => {
              const removable = !g.builtin || (g.added_apps || []).includes(a);
              return `<span class="chip" title="${esc(a)}">${esc(known[a] || this._appName({ package: a }))}${removable ? `<button class="x" data-action="app-remove" data-group="${esc(g.id)}" data-app="${esc(a)}" aria-label="Remove">×</button>` : ""}</span>`;
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

  // Someone Hearth has something of: a role, a TV profile, a paired device, a source or time counted today. Anyone else
  // (a Home Assistant user an add-on made, say) is folded away
  _inHearth(p) {
    const cfg = this._config;
    if ((cfg.roles || {})[p.id]) return true;
    if (Object.values(cfg.profiles || {}).includes(p.id)) return true;
    if ((cfg.devices || []).some((d) => d.person === p.id) || (cfg.sources || []).some((s) => s.person === p.id)) return true;
    const s = this._summaryPerson(p.id);
    return Boolean(s && ((s.tv_profiles || []).length || (s.all?.used_minutes || 0) > 0));
  }

  _familyTab() {
    const cfg = this._config;
    const roles = cfg.roles || {};
    const row = (p) => `<li>${this._avatar(p.id, 32)}<div class="grow">${esc(p.name)}</div>
            <div class="segmented" role="group" aria-label="${esc(p.name)}">
              ${[["kid", "Kid"], ["adult", "Adult"], ["", "Not in Hearth"]]
                .map(([v, label]) => `<button class="${(roles[p.id] || "") === v ? "on" : ""}" data-action="role" data-person="${esc(p.id)}" data-role="${v}">${label}</button>`)
                .join("")}
            </div></li>`;
    const persons = cfg.persons || [];
    const shown = persons.filter((p) => this._inHearth(p));
    const others = persons.filter((p) => !this._inHearth(p));
    return `<section class="card">
        <h3><ha-icon icon="mdi:account-group"></ha-icon>Who's who</h3>
        <p class="muted">Kids get limits and rules. Adults get a parent PIN and see everything here.</p>
        <ul class="list">${(shown.length ? shown : persons).map(row).join("")}</ul>
        ${shown.length && others.length ? `<details id="family-others"><summary>Others in Home Assistant (${others.length})</summary><ul class="list">${others.map(row).join("")}</ul></details>` : ""}
      </section>
      ${this._summary ? this._familyPools(this._kids()) : ""}
      ${this._activityCard()}
      ${this._pinsCard()}
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
        .map((f) => `<li><div class="grow" title="${esc(`${f.key} · ${f.zone}`)}">${esc(f.name)} <span class="muted small">${esc(this._entityName(f.zone))}</span></div>
          <button class="icon-btn" data-action="place-fav-remove" data-key="${esc(f.key)}" aria-label="Remove"><ha-icon icon="mdi:delete-outline"></ha-icon></button></li>`)
        .join("")}</ul>` : `<p class="muted small">None yet.</p>`}
      <div class="row wrap">
        <select id="place-fav-zone" aria-label="Zone">${this._options(zones, "", "Zone")}</select>
        <input id="place-fav-name" placeholder="Name, e.g. Practice" maxlength="40">
        <button class="btn primary" data-action="place-fav-add">Add</button>
      </div>
      ${this._awayMessagesSetting(kids)}
    </section>`;
  }

  // Messages when away from adults (presence_rules.py): on by default; each kid's text app is found by Hearth, and
  // an adult may add other Messaging apps of theirs
  _awayMessagesSetting(kids) {
    const cfg = this._config;
    const on = cfg.away_messages !== false;
    const added = cfg.away_messages_apps || {};
    const choices = cfg.away_messages_choices || {};
    const rows = on && kids.length
      ? `<ul class="list">${kids
          .map((k) => {
            const mine = added[k.id] || [];
            const named = (choices[k.id] || []).reduce((m, a) => ({ ...m, [a.package]: a.name }), {});
            const offer = (choices[k.id] || []).filter((a) => !mine.includes(a.package)).map((a) => ({ value: a.package, label: a.name }));
            const chips = mine
              .map((p) => `<span class="chip small" title="${esc(p)}">${esc(named[p] || p)} <button class="lnk" data-action="away-app-remove" data-person="${esc(k.id)}" data-package="${esc(p)}" aria-label="Remove">×</button></span>`)
              .join(" ");
            return `<li class="wrap">${this._avatar(k.id, 32)}<div class="grow">${esc(k.name)}<div class="muted small">Their text app${chips ? ` and ${chips}` : ""}</div></div>
              ${offer.length ? `<select id="away-app-${esc(k.id)}" aria-label="${esc(k.name)}'s other app">${this._options(offer, "", "Add an app")}</select>
              <button class="btn" data-action="away-app-add" data-person="${esc(k.id)}">Add</button>` : ""}</li>`;
          })
          .join("")}</ul>`
      : "";
    return `<div class="strong">${esc(WORDS.awayMessages)}</div>
      <p class="muted small">${esc(WORDS.awayMessagesHint)}</p>
      <label class="check"><input type="checkbox" data-change="away-messages" ${on ? "checked" : ""}> ${esc(WORDS.awayMessages)}</label>
      ${rows}`;
  }

  _schoolCard() {
    const s = this._config.school_days || {};
    const input = (f, label, placeholder = "", type = "text") =>
      `<label class="field">${label}<input id="school-${f}" type="${type}" value="${esc(s[f] || "")}" placeholder="${esc(placeholder)}"></label>`;
    const area = (f, label, placeholder) =>
      `<label class="field">${label}<textarea id="school-${f}" rows="3" placeholder="${esc(placeholder)}">${esc(s[f] || "")}</textarea></label>`;
    return `<section class="card">
      <h3><ha-icon icon="mdi:school-outline"></ha-icon>School days</h3>
      <p class="muted">Which daily time applies today (school days or other days). The first that answers decides: the dates below, then the entity, then the calendar, then Monday to Friday within the school year.</p>
      <div class="form two">
        ${input("year_start", "School year starts", "", "date")}
        ${input("year_end", "School year ends", "", "date")}
        ${area("days_off", "Days off (one per line, or a range like 2026-12-21..2027-01-02)", "2026-11-26")}
        ${area("extra_school_days", "Extra school days", "")}
        ${area("half_days", "Half days (school ends early)", "2026-11-25")}
        <label class="field">A half day takes<select id="school-half_day_budget">
          <option value="other_days" ${s.half_day_budget !== "school_days" ? "selected" : ""}>Daily time of other days</option>
          <option value="school_days" ${s.half_day_budget === "school_days" ? "selected" : ""}>Daily time of school days</option></select></label>
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
.row.wrap { flex-wrap: wrap; }
.card.empty { text-align: center; padding: 32px 16px; }
.card.empty ha-icon { --mdc-icon-size: 48px; color: var(--secondary-text-color); }
.card.dim { opacity: .6; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: var(--gap); }
.grid .card { margin: 0; }
.grid.devices { grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); }
.row { display: flex; align-items: center; gap: 12px; }
.avatar { border-radius: 50%; object-fit: cover; flex: none; }
.avatar.initials { display: flex; align-items: center; justify-content: center; background: var(--primary-color); color: var(--text-primary-color, #fff); font-weight: 500; }
.kid-main { display: flex; flex-direction: column; gap: 10px; }
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
.activity-row.failed { color: var(--error-color, #db4437); }
.cat-bonus { flex-wrap: wrap; gap: 6px; align-items: center; }
.chip.warn { background: color-mix(in srgb, var(--warning-color, #ffa600) 22%, transparent); }
.chip.out { background: color-mix(in srgb, var(--error-color, #db4437) 20%, transparent); }
.chip.play { background: color-mix(in srgb, var(--success-color, #43a047) 20%, transparent); }
.chip.small { padding: 1px 6px; font-size: 11px; }
.chip.dim { opacity: .6; }
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
.bar-row.unlimited { opacity: .55; }
.chip-btn.on { border-color: var(--primary-color); background: var(--primary-color); color: var(--text-primary-color, #fff); }
.card.pools .pool + .pool { margin-top: 12px; }
@media (max-width: 600px) {
  .content { padding: 12px; }
  .grid { grid-template-columns: 1fr; }
  .tab span:not(.badge) { display: none; }
  .tab { padding: 10px 12px; }
  table.limits input { width: 92px; }
  .pin-row { flex-wrap: wrap; }
  .toolbar .text-btn span { display: none; }
}
/* Today (the redesign). Hearth's own warm accent for its actions and rings; Home Assistant's theme for the rest */
:host { --h-accent: #b9501c; --h-accent-soft: #fbe6da; --h-on-accent: #fff; --h-ok: #2f7d5b; --h-low: #a86b00; --h-low-soft: #fdf0d5;
  --h-out: #c03a2b; --h-out-soft: #fbe3df; --h-night: #4a4fa3; --h-night-soft: #e7e8f7; --h-school: #2c6f9e; --h-school-soft: #e0eef7;
  --p-all: #7a736b; --p-games: #3466c2; --p-youtube: #d24b43; --p-streaming: #8a52c9; --p-social: #c78a12; --p-audible: #2f8f83; --p-other: #a8a29b;
  --p-x0: #0f6b74; --p-x1: #b85c00; --p-x2: #6a4c93; --p-x3: #2d7a3e;
  --h-line: var(--divider-color, rgba(0,0,0,.12)); --h-track: color-mix(in srgb, var(--primary-text-color, #222) 10%, transparent);
  --h-surface: var(--ha-card-background, var(--card-background-color, #fff)); --h-surface-2: var(--secondary-background-color, #f0ede9);
  --h-btn-line: color-mix(in srgb, var(--primary-text-color, #222) 24%, transparent); }
:host([dark]) { --h-accent: #f08a52; --h-accent-soft: #3a2418; --h-on-accent: #1a0f08; --h-ok: #5cc08f; --h-low: #e7b04a; --h-low-soft: #3a2d12;
  --h-out: #f07a6c; --h-out-soft: #3d1d19; --h-night: #a3a8f0; --h-night-soft: #25264a; --h-school: #7cb8e3; --h-school-soft: #17303f;
  --p-all: #a39b92; --p-games: #6f9cf0; --p-youtube: #f07870; --p-streaming: #b88af0; --p-social: #e9b34a; --p-audible: #5cc0b2; --p-other: #77716b;
  --p-x0: #4fb3bd; --p-x1: #f0a050; --p-x2: #b39ddb; --p-x3: #7bc47f; }
.content.wide { max-width: 1180px; }
.small-controls { margin-top: 4px; }
.small-controls select { min-height: 30px; padding: 3px 8px; font-size: 12px; }
.svg { width: 20px; height: 20px; flex: none; stroke: currentColor; fill: none; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.svg.sm { width: 16px; height: 16px; }
.today { font-size: 15px; line-height: 1.4; }
.today button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; }
.today button:focus-visible, .today [tabindex]:focus-visible { outline: 2px solid var(--h-accent); outline-offset: 2px; border-radius: 10px; }
.today .card { margin-bottom: 0; }
.today .card.flat { padding: 0; }
.today-cols { display: block; }
.top { display: flex; align-items: flex-start; gap: 12px; padding: 6px 0 4px; }
.top h1 { margin: 0; font-size: 24px; font-weight: 600; letter-spacing: -.01em; }
.top .sub { color: var(--secondary-text-color); font-size: 14px; margin-top: 2px; }
.live { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; color: var(--secondary-text-color); margin-top: 6px; }
.live i { width: 7px; height: 7px; border-radius: 50%; background: var(--h-ok); }
.today .ibtn { display: inline-flex; align-items: center; gap: 6px; height: 40px; padding: 0 14px; border-radius: 999px; background: var(--h-surface);
  border: 1px solid var(--h-btn-line); font-weight: 500; font-size: 14px; white-space: nowrap; color: var(--primary-text-color); }
.sec { display: flex; align-items: baseline; justify-content: space-between; margin: 22px 4px 8px; font-size: 13px; font-weight: 600; color: var(--secondary-text-color); letter-spacing: .02em; }
.today .b { height: 36px; padding: 0 14px; border-radius: 999px; font-weight: 600; font-size: 14px; display: inline-flex; align-items: center; gap: 6px;
  border: 1px solid var(--h-btn-line); background: var(--h-surface); color: var(--primary-text-color); white-space: nowrap; }
.today .b:hover { background: var(--h-surface-2); }
.today .b.primary { background: var(--h-accent); color: var(--h-on-accent); border-color: transparent; }
.today .b.primary:hover { filter: brightness(1.06); }
.today .b.ghost { border-color: transparent; background: transparent; color: var(--secondary-text-color); }
.today .b.ghost:hover { background: var(--h-surface-2); color: var(--primary-text-color); }
.today .lnk { color: var(--h-accent); font-weight: 600; }
.givebox { position: relative; display: inline-flex; }
.today .b.sq { width: 36px; padding: 0; justify-content: center; border-radius: 10px; color: var(--h-accent); border-color: var(--h-btn-line); }
.today .b.sq[aria-expanded="true"] { background: var(--h-accent-soft); border-color: var(--h-accent); }
.givemenu { position: absolute; top: calc(100% + 6px); left: 0; z-index: 9; min-width: 200px; display: flex; flex-direction: column; padding: 6px;
  background: var(--h-surface); border: 1px solid var(--h-line); border-radius: 14px; box-shadow: 0 8px 28px rgba(0,0,0,.18); }
.givemenu.end { left: auto; right: 0; }
.givemenu.up { top: auto; bottom: calc(100% + 6px); }
.today .givemenu button { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 10px 12px; border-radius: 10px; font-weight: 600; font-size: 14px; text-align: left; white-space: nowrap; }
.today .givemenu button:hover, .today .givemenu button:focus-visible { background: var(--h-surface-2); outline-offset: -2px; }
.givemenu button[data-action="menu-unlock"] { border-top: 1px solid var(--h-line); border-radius: 0 0 10px 10px; margin-top: 4px; color: var(--h-accent); }
.givemenu button small { flex-basis: 100%; padding-left: 24px; margin-top: -2px; font-weight: 400; font-size: 12px; color: var(--secondary-text-color); }
.givemenu .gnote { padding: 8px 12px 4px; border-top: 1px solid var(--h-line); font-size: 12px; color: var(--secondary-text-color); white-space: nowrap; }
.t-out { color: var(--h-out); font-weight: 600; } .t-low { color: var(--h-low); font-weight: 600; } .t-night { color: var(--h-night); } .t-school { color: var(--h-school); }
.banner { display: flex; align-items: center; gap: 10px; padding: 12px 14px; border-radius: var(--radius); background: var(--h-accent-soft); margin: 10px 0; color: var(--primary-text-color); }
.banner .svg { color: var(--h-accent); }
.pausebox { padding: 16px; margin-top: 10px; }
.pausebox .field input { width: 100%; }
.chips .chip-t, .today .chip-t { padding: 6px 12px; border-radius: 999px; border: 1px solid var(--h-btn-line); background: var(--h-surface); font-size: 13px; font-weight: 500; color: var(--primary-text-color); }
.today .chip-t[aria-pressed="true"] { background: var(--primary-text-color); color: var(--h-surface); border-color: transparent; }
.today .acts { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }
.needs { padding: 4px 0; }
.need { padding: 14px 16px; display: grid; grid-template-columns: auto 1fr; gap: 4px 12px; border-top: 1px solid var(--h-line); }
.need:first-child { border-top: 0; }
.need .av { grid-row: span 2; }
.need .t { font-weight: 600; }
.need .d, .today .d { color: var(--secondary-text-color); font-size: 13px; }
.need .acts, .need .more { grid-column: 2; }
.need.insheet { grid-template-columns: 1fr; padding: 12px 14px; }
.need.insheet .acts, .need.insheet .more { grid-column: 1; }
.need.ask { background: linear-gradient(90deg, var(--h-accent-soft), transparent 70%); }
.need .more { font-size: 13px; color: var(--secondary-text-color); margin-top: 4px; }
.quiet { display: flex; align-items: center; gap: 12px; padding: 16px; }
.qic { width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center; background: var(--h-night-soft); color: var(--h-night); flex: none; }
.quiet.day .qic { background: color-mix(in srgb, var(--h-ok) 15%, transparent); color: var(--h-ok); }
.heldcard { margin-top: 8px; padding-top: 4px !important; }
.held { margin: 0 16px 12px; border-top: 1px dashed var(--h-line); padding-top: 8px; font-size: 13px; color: var(--secondary-text-color); }
.held summary { cursor: pointer; list-style: none; display: flex; align-items: center; gap: 6px; margin: 0; color: var(--secondary-text-color); font-size: 13px; }
.held summary::-webkit-details-marker { display: none; }
.held ul { margin: 8px 0 0; padding: 0; list-style: none; }
.held li { padding: 6px 0; display: flex; gap: 8px; justify-content: space-between; border-top: 1px solid var(--h-line); }
.held li span:last-child { color: var(--secondary-text-color); opacity: .8; text-align: right; }
.kids { display: flex; flex-direction: column; gap: 10px; }
.today .card.kid { display: flex; align-items: center; gap: 8px; padding: 6px 12px 6px 6px; }
.today .card.kid[aria-current="true"] { outline: 2px solid var(--h-accent); outline-offset: -2px; }
.today .kopen { flex: 1; min-width: 0; display: flex; align-items: center; gap: 12px; padding: 8px 6px; min-height: 56px; text-align: left; border-radius: 10px; }
.today .kopen:hover { background: color-mix(in srgb, var(--h-surface-2) 55%, transparent); }
.today .kopen .grow { min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.today .card.kid .l1 { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.today .card.kid .name { font-weight: 600; font-size: 16px; }
.today .card.kid .num { font-weight: 700; font-size: 18px; white-space: nowrap; color: var(--primary-text-color); }
.today .card.kid .num.t-lock { font-size: 16px; font-weight: 600; color: var(--secondary-text-color); }
.today .line { color: var(--secondary-text-color); font-size: 14px; }
.today .card.kid .line { font-size: 13px; overflow-wrap: anywhere; }
.today .card.kid .line.t-out { font-weight: 500; color: var(--h-out); }
.today .card.kid .num.t-low { color: var(--h-low); } .today .card.kid .num.t-out { color: var(--h-out); }
.today .b.give { min-height: 44px; height: 44px; flex: none; padding: 0 14px; }
.quietline { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; margin: 18px 4px 4px; font-size: 13px; color: var(--secondary-text-color); }
.quietline .held { margin: 0; border: 0; padding: 0; }
.split { display: inline-flex; flex: none; }
.today .split .ibtn.sl { border-radius: 999px 0 0 999px; height: 44px; }
.today .split .ibtn.sr { border-radius: 0 999px 999px 0; border-left: 0; height: 44px; width: 40px; padding: 0; justify-content: center; }
.today .line b { font-weight: 600; color: var(--primary-text-color); }
.today .line b.t-out { color: var(--h-out); }
.today .card.kid.asleep .name { color: var(--secondary-text-color); }
.chev { color: var(--secondary-text-color); opacity: .7; display: inline-flex; transition: transform .15s; }
.chev.open { transform: rotate(90deg); }
.ring { position: relative; flex: none; display: inline-block; }
.ring svg { display: block; transform: rotate(-90deg); }
.ring .track { stroke: var(--h-track); stroke-width: 4; fill: none; }
.ring .arc { stroke: var(--ring); stroke-width: 4; fill: none; stroke-linecap: round; transition: stroke-dashoffset .5s; }
.ring .ini { position: absolute; inset: 0; display: grid; place-items: center; font-weight: 600; font-size: 15px; }
.ring .ini.dim { color: var(--secondary-text-color); }
.ring img.ini.pic { position: absolute; inset: 6px; width: calc(100% - 12px); height: calc(100% - 12px); border-radius: 50%; object-fit: cover; }
.ring .badge { position: absolute; right: -3px; bottom: -3px; width: 20px; height: 20px; border-radius: 50%; display: grid; place-items: center; background: var(--h-surface); box-shadow: 0 0 0 2px var(--h-surface); color: var(--ring); padding: 0; font-size: 0; }
.ring .badge .svg { width: 14px; height: 14px; }
.tone-accent { --ring: var(--h-accent); } .tone-night { --ring: var(--h-night); } .tone-school { --ring: var(--h-school); }
.tone-out { --ring: var(--h-out); } .tone-low { --ring: var(--h-low); } .tone-ok { --ring: var(--h-ok); }
.rowlist { padding: 4px 0; }
.today .rowi { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-top: 1px solid var(--h-line); width: 100%; text-align: left; }
.today .rowi:first-child { border-top: 0; }
.rowi .t { font-weight: 500; }
.dic { width: 36px; height: 36px; border-radius: 10px; display: grid; place-items: center; background: var(--h-surface-2); color: var(--secondary-text-color); flex: none; }
.dic.on { background: color-mix(in srgb, var(--h-ok) 16%, transparent); color: var(--h-ok); }
.dic.tone-out { background: var(--h-out-soft); color: var(--h-out); } .dic.tone-night { background: var(--h-night-soft); color: var(--h-night); }
.dic.tone-school { background: var(--h-school-soft); color: var(--h-school); } .dic.tone-low { background: var(--h-low-soft); color: var(--h-low); }
.adults { font-size: 13px; color: var(--secondary-text-color); padding: 12px 4px; }
.scrim { position: fixed; inset: 0; background: rgba(10,8,6,.38); opacity: 0; pointer-events: none; transition: opacity .2s; z-index: 6; }
.scrim.on { opacity: 1; pointer-events: auto; }
.detail { position: fixed; left: 0; right: 0; bottom: 0; z-index: 7; max-height: 90vh; overflow: auto; background: var(--primary-background-color); border-radius: 22px 22px 0 0;
  transform: translateY(105%); transition: transform .28s cubic-bezier(.2,.8,.2,1); box-shadow: 0 -8px 32px rgba(0,0,0,.18); overscroll-behavior: contain; visibility: hidden; }
.detail.on { transform: none; visibility: visible; }
.detail .handle { position: sticky; top: 0; z-index: 2; background: var(--primary-background-color); padding: 8px 0 0; }
.detail .handle i { display: block; width: 40px; height: 4px; border-radius: 2px; background: var(--h-btn-line); margin: 0 auto; }
.dinner { padding: 4px 16px 28px; max-width: 640px; margin: 0 auto; display: flex; flex-direction: column; gap: 12px; }
.dhead { display: flex; align-items: flex-start; gap: 14px; padding: 10px 0 2px; }
.dhead .grow { display: flex; flex-direction: column; gap: 4px; }
.dhead .who { font-size: 15px; font-weight: 600; color: var(--secondary-text-color); }
.dhead h2 { margin: 0; font-size: 26px; font-weight: 700; line-height: 1.15; }
.dhead h2.t-out { color: var(--h-out); }
.dhead .why { font-size: 14px; line-height: 1.4; color: var(--primary-text-color); overflow-wrap: anywhere; }
.closebtn { width: 44px; height: 44px; flex: none; border-radius: 50%; display: grid !important; place-items: center; background: var(--h-surface) !important; border: 1px solid var(--h-line) !important; }
.actbar { display: flex; gap: 8px; }
.today .actbar .b { height: 48px; border-radius: 12px; font-size: 15px; padding: 0 16px; }
.today .actbar .b.grow { flex: 1; justify-content: center; min-width: 0; }
.today .actbar .b.sq2 { width: 48px; padding: 0; justify-content: center; flex: none; }
.extras h3 { margin-bottom: 4px !important; }
.xrow { display: flex; align-items: center; justify-content: space-between; gap: 10px; min-height: 44px; border-top: 1px solid var(--h-line); font-size: 14px; }
.xrow:first-of-type { border-top: 0; }
.xrow span { overflow-wrap: anywhere; }
.today .xrow .lnk { min-height: 44px; padding: 0 8px; flex: none; }
/* More time: a second bottom sheet over the kid's sheet on a phone, a dialog on a wide page */
.mt-scrim { position: fixed; inset: 0; z-index: 8; background: rgba(10,8,6,.38); }
.mt { position: fixed; left: 0; right: 0; bottom: 0; z-index: 9; max-height: 92vh; overflow: auto; background: var(--h-surface); color: var(--primary-text-color);
  border-radius: 20px 20px 0 0; box-shadow: 0 -8px 32px rgba(0,0,0,.25); padding: 0 18px calc(24px + env(safe-area-inset-bottom, 0px)); overscroll-behavior: contain; }
.mt .handle { padding: 10px 0 2px; } .mt .handle i { display: block; width: 40px; height: 4px; border-radius: 2px; background: var(--h-btn-line); margin: 0 auto; }
.mt-head { display: flex; align-items: flex-start; gap: 10px; padding: 6px 0 14px; }
.mt-head h2 { margin: 0; font-size: 22px; font-weight: 700; }
.mt-body { display: flex; flex-direction: column; gap: 14px; max-width: 560px; margin: 0 auto; }
.mt-for .lab { display: block; font-size: 14px; font-weight: 600; color: var(--secondary-text-color); margin-bottom: 8px; }
.mt-for .seg { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); border: 1px solid var(--h-btn-line); border-radius: 12px; overflow: hidden; }
.today .mt-for .seg button { height: 46px; font-size: 15px; font-weight: 600; }
.today .mt-for .seg button + button { border-left: 1px solid var(--h-btn-line); }
.today .mt-for .seg button[aria-checked="true"] { background: var(--h-accent); color: var(--h-on-accent); }
.mt-others { font-size: 13px; color: var(--secondary-text-color); margin-top: 8px; }
.today .mt-others .lnk { padding: 6px 2px; min-height: 32px; }
.mt-amts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
.today .mt .b { height: 52px; border-radius: 12px; justify-content: center; font-size: 16px; }
.today .mt .b.wide { width: 100%; height: 48px; font-size: 15px; }
.mt-note { margin: 0; font-size: 14px; line-height: 1.4; color: var(--primary-text-color); }
.mt-more { display: flex; flex-direction: column; border-top: 1px solid var(--h-line); padding-top: 4px; }
.today .mt-more button { min-height: 44px; text-align: left; font-size: 15px; color: var(--secondary-text-color); }
.today .mt-more button:hover { color: var(--primary-text-color); }
.today.wide .mt { left: 50%; right: auto; bottom: auto; top: 50%; transform: translate(-50%, -50%); width: min(440px, calc(100% - 32px)); border-radius: 20px; padding-bottom: 20px; }
.today.wide .mt .handle { display: none; }
.lockbox { display: flex; gap: 12px; align-items: flex-start; padding: 14px; border-radius: var(--radius); }
.lockbox.night { background: var(--h-night-soft); } .lockbox.night .svg { color: var(--h-night); }
.lockbox.school { background: var(--h-school-soft); } .lockbox.school .svg { color: var(--h-school); }
.blk { padding: 14px 16px !important; }
.blk h3 { margin: 0 0 10px; font-size: 13px; font-weight: 600; color: var(--secondary-text-color); letter-spacing: .02em; display: flex; justify-content: space-between; align-items: baseline; }
.blk h3 span { font-weight: 500; opacity: .85; }
.big { font-size: 20px; font-weight: 600; letter-spacing: -.01em; }
.big small { font-size: 14px; font-weight: 500; color: var(--secondary-text-color); }
.stack { position: relative; height: 14px; border-radius: 7px; background: var(--h-track); overflow: hidden; display: flex; margin: 10px 0 8px; }
.stack i { display: block; height: 100%; }
.stack i + i { box-shadow: -1.5px 0 0 var(--h-surface); }
.stack .mark { position: absolute; top: -2px; bottom: -2px; width: 0; border-left: 2px solid var(--primary-text-color); }
.qbtn { margin-left: 6px; width: 18px; height: 18px; border-radius: 50%; border: 1px solid var(--h-line); background: none; color: var(--secondary-text-color); font-size: 11px; line-height: 16px; padding: 0; cursor: pointer; vertical-align: middle; opacity: .7; }
.qbtn[aria-expanded="true"], .qbtn:hover { opacity: 1; }
.origins { font-size: 12px; color: var(--secondary-text-color); margin: 4px 0; display: grid; gap: 2px; }
.check { display: flex; gap: 8px; align-items: center; font-size: 14px; margin: 6px 0; }
.today .legend { display: flex; flex-wrap: wrap; gap: 4px 12px; font-size: 12px; color: var(--secondary-text-color); }
.today .legend span { display: inline-flex; align-items: center; gap: 5px; }
.today .legend i { width: 8px; height: 8px; border-radius: 2px; display: inline-block; }
.lanes { margin-top: 12px; }
.today .lane { width: 100%; text-align: left; display: grid; grid-template-columns: max-content minmax(0, 1fr) 16px; align-items: center; gap: 10px; padding: 10px 0; min-height: 44px; border-top: 1px solid var(--h-line); margin: 0; font-size: 14px; }
.today .lane:first-child { border-top: 0; }
.today .lane .nm { font-weight: 500; display: flex; align-items: center; gap: 6px; min-width: 0; }
.today .lane .nm i { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.today .lane .bar { height: 6px; border-radius: 3px; background: var(--h-track); overflow: hidden; position: relative; }
.today .lane .bar i { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px; }
.today .lane .v { font-size: 13px; color: var(--secondary-text-color); text-align: right; overflow-wrap: anywhere; }
.today .lane .v.t-out { color: var(--h-out); }
.today .pill { display: inline-flex; padding: 1px 6px; border-radius: 999px; font-size: 11px; font-weight: 600; background: var(--h-accent-soft); color: var(--h-accent); }
.expand { padding: 2px 0 12px; font-size: 13px; color: var(--secondary-text-color); }
.expand .apps { display: flex; flex-direction: column; gap: 2px; margin: 4px 0 6px; }
.expand .apps div { display: flex; justify-content: space-between; gap: 10px; padding: 3px 0; }
.notcounted { font-size: 13px; color: var(--secondary-text-color); padding-top: 8px; border-top: 1px solid var(--h-line); margin-top: 4px; }
.today .dgroup { width: 100%; text-align: left; display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid var(--h-line); }
.today .dgroup:first-of-type { border-top: 0; }
.dgroup .grow { min-width: 0; }
.dgroup .t { font-weight: 500; font-size: 14px; }
.dgroup .r { font-size: 13px; font-weight: 600; white-space: nowrap; }
.dgroup .r.t-ok { color: var(--primary-text-color); }
.dlist { margin: 0 0 8px 48px; font-size: 13px; }
.dlist div { display: flex; justify-content: space-between; gap: 10px; padding: 5px 0; border-top: 1px dashed var(--h-line); }
.dlist div span:last-child { color: var(--secondary-text-color); text-align: right; }
.note { font-size: 13px; color: var(--secondary-text-color); display: flex; gap: 10px; align-items: flex-start; padding: 8px 0; border-top: 1px solid var(--h-line); }
.note:first-of-type { border-top: 0; }
.note .svg { margin-top: 1px; flex: none; }
.namelist { margin-top: 4px; line-height: 1.6; }
.weekc { display: flex; align-items: flex-end; gap: 10px; height: 120px; padding: 4px 0 0; }
.weekc .col { flex: 0 0 44px; display: flex; flex-direction: column; align-items: center; gap: 6px; height: 100%; justify-content: flex-end; }
.weekc .col.wide { flex: 1; align-items: flex-start; justify-content: center; }
.weekc .wb { width: 28px; border-radius: 6px 6px 2px 2px; background: var(--p-other); position: relative; }
.weekc .fill { position: absolute; inset: 0; border-radius: inherit; overflow: hidden; display: flex; flex-direction: column-reverse; }
.weekc .fill i { display: block; width: 100%; }
.weekc .cap { position: absolute; left: -6px; right: -6px; border-top: 2px dashed var(--secondary-text-color); }
.weekc .lbl { font-size: 12px; color: var(--secondary-text-color); }
.weekc + .d { margin-top: 10px; }
.todo { display: flex; align-items: center; gap: 12px; }
.chooser { background: var(--h-surface-2); border-radius: 14px; padding: 12px; }
.chooser .lab { font-size: 12px; color: var(--secondary-text-color); margin: 0 0 6px; }
.chooser .chips { margin: 0 0 10px; }
.menu { display: flex; flex-direction: column; background: var(--h-surface); border: 1px solid var(--h-line); border-radius: 14px; overflow: hidden; }
.menu button { padding: 12px 14px !important; text-align: left; border-top: 1px solid var(--h-line) !important; font-size: 14px; }
.menu button:first-child { border-top: 0 !important; }
.menu button small { display: block; color: var(--secondary-text-color); font-size: 12px; }
.foot { display: flex; justify-content: space-between; align-items: center; padding: 6px 4px; font-size: 13px; }
.empty-detail { display: none; }
.toast.undo { display: flex; align-items: center; gap: 14px; width: max-content; padding: 12px 12px 12px 16px; border-radius: 14px; overflow: hidden; }
.toast.undo button { border: 0; background: none; font: inherit; font-weight: 700; color: var(--h-accent); padding: 6px 10px; border-radius: 8px; cursor: pointer; filter: brightness(1.25); }
:host([dark]) .toast.undo button { color: #b9501c; filter: none; }
.toast .tbar { position: absolute; left: 12px; right: 12px; bottom: 4px; height: 2px; border-radius: 1px; background: currentColor; opacity: .25; transform-origin: left; animation: tbar linear forwards; }
@keyframes tbar { from { transform: scaleX(1); } to { transform: scaleX(0); } }
/* Side by side from 900 px of the page's own width (Home Assistant's sidebar takes part of the window) */
.today.wide .today-cols { display: grid; grid-template-columns: minmax(0, 1fr) 440px; gap: 28px; align-items: start; }
.today.wide .scrim { display: none; }
.today.wide .detail { position: sticky; top: 112px; transform: none; visibility: visible; max-height: calc(100vh - 124px); border-radius: var(--radius); box-shadow: none; background: transparent; margin-top: 6px; z-index: 1; }
.today.wide .detail .handle, .today.wide .detail .closebtn { display: none !important; }
.today.wide .dinner { padding: 0; }
.today.wide .empty-detail { display: block; color: var(--secondary-text-color); padding: 40px 16px; text-align: center; }
.toast { bottom: calc(24px + env(safe-area-inset-bottom, 0px)); z-index: 12; }
@media (prefers-reduced-motion: reduce) { .today *, .toast * { animation: none !important; transition: none !important; } }
/* Schedule (the weekly schedule): the Today redesign's tokens, two mode colors of its own */
:host { --m-homework: #8a52c9; --m-wind: #c78a12; }
:host([dark]) { --m-homework: #b88af0; --m-wind: #e9b34a; }
.sched .card { padding: 0; }
.sched .s-grow { flex: 1; min-width: 0; }
.sched .s-t { font-weight: 600; }
.sched .s-d { color: var(--secondary-text-color); font-size: 13px; }
.sched .b.sm { height: 32px; padding: 0 12px; font-size: 13px; }
.s-kids { display: flex; gap: 8px; flex-wrap: wrap; margin: 8px 0 10px; }
.sched .s-kidchip { display: inline-flex; align-items: center; gap: 8px; height: 40px; padding: 0 14px 0 6px; border-radius: 999px; border: 1px solid var(--h-btn-line); background: var(--h-surface); font-weight: 600; }
.s-kidchip .s-av { width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center; font-size: 13px; background: var(--h-surface-2); }
.sched .s-kidchip[aria-pressed="true"] { background: var(--h-accent-soft); border-color: var(--h-accent); }
.s-kidchip[aria-pressed="true"] .s-av { background: var(--h-accent); color: var(--h-on-accent); }
.s-nowcard { display: flex; align-items: center; gap: 12px; padding: 14px 16px !important; }
.s-nowcard .s-dot { width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center; flex: none; }
.s-cols { display: grid; grid-template-columns: minmax(0, 1fr) 440px; gap: 20px; align-items: start; }
.s-side { position: sticky; top: 12px; margin-top: 22px; }
.s-week { padding: 6px 0 !important; }
.sched .s-wrow { display: grid; grid-template-columns: 52px minmax(0, 1fr); gap: 2px 10px; align-items: center; padding: 10px 14px; width: 100%; text-align: left; border-top: 1px solid var(--h-line); }
.sched .s-wrow:first-of-type { border-top: 0; }
.sched .s-wrow:hover { background: color-mix(in srgb, var(--h-surface-2) 55%, transparent); }
.sched .s-wrow[aria-current="true"] { background: var(--h-accent-soft); }
.s-dl { font-weight: 600; font-size: 14px; line-height: 1.15; }
.s-dl small { display: block; font-weight: 500; font-size: 11px; color: var(--secondary-text-color); }
.s-dl .s-today { color: var(--h-accent); }
.s-sum { grid-column: 2; font-size: 12.5px; color: var(--secondary-text-color); display: flex; gap: 6px 10px; flex-wrap: wrap; align-items: center; }
.s-tag { display: inline-flex; align-items: center; gap: 4px; padding: 1px 8px; border-radius: 999px; font-size: 11.5px; font-weight: 600; white-space: nowrap; }
.s-tag.off { background: color-mix(in srgb, var(--h-ok) 16%, transparent); color: var(--h-ok); }
.s-tag.half { background: var(--h-school-soft); color: var(--h-school); }
.s-tag.over { background: var(--h-accent-soft); color: var(--h-accent); }
.s-bar { position: relative; height: 22px; border-radius: 7px; overflow: hidden; background: var(--h-track); }
.s-seg { position: absolute; top: 0; bottom: 0; }
.s-seg.carried { opacity: .45; }
.s-nowl { position: absolute; top: -2px; bottom: -2px; width: 2px; background: var(--primary-text-color); border-radius: 2px; z-index: 2; }
.s-axisrow { display: grid; grid-template-columns: 52px minmax(0, 1fr); gap: 10px; padding: 8px 14px 0; font-size: 11px; color: var(--secondary-text-color); }
.s-ticks { position: relative; height: 14px; font-size: 11px; color: var(--secondary-text-color); }
.s-ticks span { position: absolute; transform: translateX(-50%); }
.s-ticks span:first-child { transform: none; }
.s-ticks span:last-child { transform: translateX(-100%); }
.sched .s-mrow { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-top: 1px solid var(--h-line); width: 100%; text-align: left; }
.sched .s-mrow:first-child { border-top: 0; }
.s-mrow .s-sw { width: 14px; height: 14px; border-radius: 4px; flex: none; }
.s-up { padding: 4px 0 !important; }
.s-uprow { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-top: 1px solid var(--h-line); }
.s-uprow:first-child { border-top: 0; }
.s-cal { width: 40px; text-align: center; flex: none; line-height: 1.05; }
.s-cal b { display: block; font-size: 17px; }
.s-cal small { font-size: 11px; color: var(--secondary-text-color); text-transform: uppercase; letter-spacing: .04em; }
.s-ed { padding: 16px !important; }
.s-edh { display: flex; align-items: flex-start; gap: 10px; }
.s-edh h2 { margin: 0; font-size: 20px; font-weight: 600; }
.s-segc { display: inline-flex; background: var(--h-surface-2); border-radius: 999px; padding: 3px; margin-top: 12px; }
.sched .s-segc button { padding: 6px 12px; border-radius: 999px; font-size: 13px; font-weight: 600; color: var(--secondary-text-color); }
.sched .s-segc button[aria-pressed="true"] { background: var(--h-surface); color: var(--primary-text-color); box-shadow: 0 1px 2px rgba(0,0,0,.12); }
.s-big { position: relative; margin: 26px 0 6px; user-select: none; touch-action: none; }
.s-big .s-bar { height: 44px; border-radius: 10px; }
.s-big .s-seg { display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 600; color: #fff; overflow: hidden; white-space: nowrap; }
:host([dark]) .s-big .s-seg { color: #111; }
.s-big .s-seg span { padding: 0 4px; overflow: hidden; text-overflow: ellipsis; }
.sched .s-hnd { position: absolute; top: -6px; width: 28px; height: 56px; margin-left: -14px; display: grid; place-items: center; cursor: ew-resize; z-index: 3; touch-action: none; }
.s-hnd i { width: 6px; height: 40px; border-radius: 4px; background: var(--h-surface); box-shadow: 0 0 0 1.5px var(--primary-text-color), 0 1px 4px rgba(0,0,0,.25); }
.s-hnd:hover i, .s-hnd.drag i, .s-hnd:focus-visible i { box-shadow: 0 0 0 2px var(--h-accent), 0 1px 6px rgba(0,0,0,.3); }
.s-hnd .s-tip { position: absolute; top: -24px; background: var(--primary-text-color); color: var(--h-surface); font-size: 11px; font-weight: 600; padding: 2px 6px; border-radius: 6px; white-space: nowrap; opacity: 0; pointer-events: none; }
.s-hnd:hover .s-tip, .s-hnd.drag .s-tip, .s-hnd:focus-visible .s-tip { opacity: 1; }
.s-big .s-axis { padding-top: 4px; }
.s-hint { font-size: 12px; color: var(--secondary-text-color); margin: 2px 0 4px; }
.s-blocks { margin: 10px 0 0; padding: 0; list-style: none; }
.s-blk { display: flex; align-items: center; gap: 8px; padding: 8px 0; border-top: 1px solid var(--h-line); }
.s-blk:first-child { border-top: 0; }
.s-tm { width: 112px; height: 36px; border-radius: 10px; border: 1px solid var(--h-btn-line); background: var(--h-surface); padding: 0 8px; font: inherit; font-size: 14px; color: var(--primary-text-color); }
.s-carried { width: 112px; font-size: 13px; color: var(--secondary-text-color); padding-left: 2px; }
.s-blk select { flex: 1; min-width: 0; height: 36px; border-radius: 10px; border: 1px solid var(--h-btn-line); padding: 0 8px; font: inherit; font-size: 14px; color: var(--primary-text-color); background: var(--h-surface); }
.s-chip { flex: 1; min-width: 0; display: flex; align-items: center; gap: 8px; height: 36px; padding: 0 10px; border-radius: 10px; font-weight: 600; font-size: 14px; }
.sched .s-x { width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center; color: var(--secondary-text-color); flex: none; }
.sched button.s-x:hover { background: var(--h-surface-2); }
.s-add { margin-top: 6px; }
.s-subh { display: flex; align-items: baseline; justify-content: space-between; margin: 22px 0 4px; font-size: 13px; font-weight: 600; color: var(--secondary-text-color); }
.s-lim { display: flex; align-items: center; gap: 10px; padding: 8px 0; border-top: 1px solid var(--h-line); }
.s-subh + .s-lim { border-top: 0; }
.s-pdot { width: 10px; height: 10px; border-radius: 50%; flex: none; }
.s-lim .s-grow { font-weight: 500; }
.s-lim small { display: block; font-weight: 400; color: var(--secondary-text-color); font-size: 12px; }
.s-step { display: inline-flex; align-items: center; border: 1px solid var(--h-btn-line); border-radius: 999px; height: 36px; }
.sched .s-step button { width: 36px; height: 34px; border-radius: 999px; font-size: 18px; line-height: 1; color: var(--secondary-text-color); }
.sched .s-step button:hover { background: var(--h-surface-2); color: var(--primary-text-color); }
.s-step output { min-width: 72px; text-align: center; font-weight: 600; font-size: 14px; }
.s-bed { margin-bottom: 14px; display: grid; gap: 10px; }
.s-bedh { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.s-bedh h2 { margin: 0; font-size: 17px; }
.s-pill { display: inline-flex; align-items: center; gap: 4px; border: 1px solid var(--h-line); background: var(--h-surface-2); color: inherit; border-radius: 999px; padding: 3px 10px; font: inherit; font-size: 12px; cursor: pointer; }
.s-pill.ok { color: var(--h-ok); }
.s-pill.warn, .s-pill.wait { color: var(--secondary-text-color); }
.s-pill.bad { color: var(--h-out); }
.s-pilld { border: 1px solid var(--h-line); border-radius: 10px; padding: 8px 10px; }
.s-pdays { list-style: none; margin: 6px 0; padding: 0; display: grid; gap: 2px; font-size: 13px; }
.s-pdays li { display: flex; gap: 10px; }
.s-pdays li > span:first-child { width: 4.5em; color: var(--secondary-text-color); }
.s-tonight { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.s-bnr { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 8px 10px; border-radius: 10px; background: color-mix(in srgb, var(--h-night) 12%, transparent); font-size: 13px; }
.s-bnr.warn { background: color-mix(in srgb, var(--h-out) 10%, transparent); }
.s-bchips { display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 4px; }
.s-bchip { display: grid; gap: 1px; justify-items: center; border: 1px solid var(--h-line); border-radius: 10px; background: none; color: inherit; font: inherit; padding: 6px 2px; cursor: pointer; }
.s-bchip small { font-size: 11px; color: var(--secondary-text-color); }
.s-bchip b { font-size: 13px; }
.s-bchip i { font-style: normal; font-size: 11px; color: var(--secondary-text-color); }
.s-bchip.marked { border-color: var(--h-night); }
.s-review { border-top: 1px solid var(--h-line); padding-top: 10px; display: grid; gap: 6px; }
@media (max-width: 520px) { .s-bchips { grid-template-columns: repeat(4, minmax(0, 1fr)); } }
.s-sync { margin: 0; padding: 0; list-style: none; }
.s-sync li { display: grid; grid-template-columns: 28px minmax(0, 1fr); gap: 2px 10px; padding: 10px 0; border-top: 1px solid var(--h-line); }
.s-sync li:first-child { border-top: 0; }
.s-ic { width: 28px; height: 28px; border-radius: 8px; display: grid; place-items: center; background: var(--h-surface-2); color: var(--secondary-text-color); }
.s-ic.ok { background: color-mix(in srgb, var(--h-ok) 16%, transparent); color: var(--h-ok); }
.s-sync .s-t { font-size: 14px; display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
.s-sync .s-t small { font-weight: 500; font-size: 12px; color: var(--secondary-text-color); }
.s-sync .s-d { grid-column: 2; }
.s-foot { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 18px; }
.s-sheet { position: fixed; inset: 0; z-index: 50; background: var(--primary-background-color); overflow: auto; }
.s-shtop { position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 6px; height: 56px; padding: 0 8px; background: var(--h-surface); border-bottom: 1px solid var(--h-line); }
.s-shtop .s-t { font-size: 18px; font-weight: 500; flex: 1; }
.s-shtop .s-back { transform: rotate(180deg); }
.s-sheet .card { border-radius: 0; border-left: 0; border-right: 0; box-shadow: none; }
.s-scrim { position: fixed; inset: 0; z-index: 60; background: rgba(0,0,0,.4); display: grid; place-items: center; padding: 16px; }
.s-dlg { width: min(440px, 100%); max-height: calc(100vh - 32px); overflow: auto; background: var(--h-surface); border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,.3); padding: 20px; }
.s-dlg h3 { margin: 0 0 4px; font-size: 18px; font-weight: 600; }
.s-dlg p { margin: 0 0 12px; color: var(--secondary-text-color); font-size: 14px; }
.s-daygrid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin: 8px 0 14px; }
.sched .s-dbox { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; height: 52px; border-radius: 12px; border: 1px solid var(--h-btn-line); font-weight: 600; font-size: 14px; position: relative; }
.s-dbox small { font-size: 11px; font-weight: 500; color: var(--secondary-text-color); }
.sched .s-dbox[aria-pressed="true"] { background: var(--h-accent-soft); border-color: var(--h-accent); }
.s-dbox[aria-pressed="true"]::after { content: ""; position: absolute; top: 6px; right: 6px; width: 8px; height: 8px; border-radius: 50%; background: var(--h-accent); }
.sched .s-dbox:disabled { opacity: .4; cursor: default; }
.s-ck { display: flex; align-items: center; gap: 10px; padding: 8px 0; font-size: 14px; }
.s-ck input[type="checkbox"] { width: 18px; height: 18px; accent-color: var(--h-accent); }
.s-name { flex-direction: column; align-items: stretch; gap: 4px; }
.s-name input { height: 40px; border-radius: 10px; border: 1px solid var(--h-btn-line); padding: 0 10px; font: inherit; background: var(--h-surface); color: var(--primary-text-color); }
.s-acts { display: flex; justify-content: flex-end; gap: 8px; margin-top: 16px; flex-wrap: wrap; }
.s-quick { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 6px; }
.sched .s-quick button { padding: 5px 10px; border-radius: 999px; border: 1px solid var(--h-btn-line); font-size: 13px; font-weight: 500; }
.s-radio { display: flex; align-items: flex-start; gap: 10px; padding: 10px 0; border-top: 1px solid var(--h-line); font-size: 14px; }
.s-radio input { margin-top: 3px; accent-color: var(--h-accent); }
.s-radio small { display: block; color: var(--secondary-text-color); font-size: 12.5px; }
.s-pchips { display: flex; gap: 6px; flex-wrap: wrap; margin: 0 0 8px 28px; }
.sched .s-pchip { padding: 5px 10px; border-radius: 999px; border: 1px solid var(--h-btn-line); font-size: 13px; font-weight: 500; }
.sched .s-pchip[aria-pressed="true"] { background: var(--primary-text-color); color: var(--h-surface); border-color: transparent; }
@media (max-width: 899px) { .s-cols { display: block; } }
`;

customElements.define("hearth-panel", HearthPanel);
