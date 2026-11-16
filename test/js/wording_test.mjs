// The words people see on Hearth's page and the family card: one daily time, categories with limits, bonus time,
// Unlimited and Pause screens (docs/contracts/time-model.md). No string a person reads says pool, budget, max, "All
// screen time" or grown-up (ids, option keys, CSS classes and comments may).
// Run: node --test test/js/wording_test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const FILES = ["hearth-panel.js", "hearth-family-card.js"];

// The text of every string and template literal (template expressions left out), comments skipped
function literals(source) {
  const out = [];
  let i = 0;
  const n = source.length;
  const readString = (quote) => {
    let text = "";
    i++;
    while (i < n && source[i] !== quote) {
      if (source[i] === "\\") {
        text += source[i + 1] || "";
        i += 2;
        continue;
      }
      text += source[i++];
    }
    i++;
    return text;
  };
  const readTemplate = () => {
    let text = "";
    i++;
    while (i < n && source[i] !== "`") {
      if (source[i] === "\\") {
        text += source[i + 1] || "";
        i += 2;
        continue;
      }
      if (source[i] === "$" && source[i + 1] === "{") {
        i += 2;
        scan(1);
        text += " ";
        continue;
      }
      text += source[i++];
    }
    i++;
    out.push(text);
  };
  // Code until the closing brace of [depth] (0: the whole file)
  const scan = (depth) => {
    let level = depth;
    while (i < n) {
      const c = source[i];
      const next = source[i + 1];
      if (c === "/" && next === "/") {
        while (i < n && source[i] !== "\n") i++;
      } else if (c === "/" && next === "*") {
        i = source.indexOf("*/", i + 2) + 2;
      } else if (c === '"' || c === "'") {
        out.push(readString(c));
      } else if (c === "`") {
        readTemplate();
      } else if (c === "/" && /[(,=:!&|?{};\[]\s*$/.test(source.slice(Math.max(0, i - 20), i))) {
        // A regular expression literal
        i++;
        while (i < n && source[i] !== "/") i += source[i] === "\\" ? 2 : 1;
        i++;
      } else if (c === "{") {
        level++;
        i++;
      } else if (c === "}") {
        level--;
        i++;
        if (depth && level === 0) return;
      } else i++;
    }
  };
  scan(0);
  return out;
}

// What a person could read in a literal: without HTML attributes (ids, classes, data-*, aria values stay: they're read)
function visible(text) {
  return text
    .replace(/<style[\s\S]*?<\/style>/g, " ")
    .replace(/\s(?!aria-label|title|placeholder|alt)[\w-]+="[^"]*"/g, " ")
    .replace(/<\/?[\w-]+/g, " ");
}

const FORBIDDEN = [/(?<![.\w-])pools?(?![\w-])/i, /(?<![.\w-])budgets?(?![\w-])/i, /All screen time/i, /grown-up/i, /(?<![.\w-])max(?![\w-])/];

for (const file of FILES) {
  test(`${file}: no pool, budget, max, "All screen time" or grown-up in what people read`, () => {
    const source = readFileSync(fileURLToPath(new URL(`../../custom_components/hearth/frontend/${file}`, import.meta.url)), "utf8");
    const found = [];
    for (const raw of literals(source)) {
      // An id, a key or a selector (no space): not something a person reads
      if (!/\s/.test(raw.trim())) continue;
      // CSS (the page's style sheet)
      if (/[{};]\s*$|^\s*[.:#@][\w-]/m.test(raw) && /\{[^}]*:[^}]*\}/.test(raw)) continue;
      const text = visible(raw);
      for (const pattern of FORBIDDEN) {
        const m = text.match(pattern);
        if (m) found.push(`${m[0]}: ${text.trim().slice(0, 120)}`);
      }
    }
    assert.deepEqual(found, []);
  });
}
