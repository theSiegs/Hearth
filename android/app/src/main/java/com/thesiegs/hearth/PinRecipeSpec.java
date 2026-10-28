package com.thesiegs.hearth;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * One streaming app's PIN recipe as data: how {@link DataPinRecipe} recognises the app's PIN screen, finds and presses
 * its keys, confirms each digit and reads the app's answer. Read from Hearth's own recipes (the asset
 * {@code pin-recipes.json}) or from {@code pin-entry/recipes.json} in Hearth's repository; the format is in
 * {@code docs/pin-recipes.md}.
 *
 * <p>A recipe only describes; everything it can make Hearth do is built in: click a key whose label is a digit, set a
 * named PIN field's text to the digits typed so far, move the D-pad focus and press OK. It names no packages but the
 * app it is for (and only one of {@link #ALLOWED}, the apps Hearth already has recipes for), no intents, no regular
 * expressions. Parsing is strict about everything it knows (types, enums, bounds, references); fields it doesn't know
 * are ignored, and a recipe that needs a newer engine than {@link #ENGINE} is left out. Any error rejects the whole
 * file. Immutable once read, so it is shared between threads freely.
 */
final class PinRecipeSpec {
    /** The file format this Hearth reads; a file of another fails as a whole. */
    static final int SCHEMA = 1;
    /** What this Hearth's engine can do; a recipe asking for more ("engine": higher) is skipped. */
    static final int ENGINE = 1;
    /** The longest file Hearth reads, in characters (the fetch stops at as many bytes). */
    static final int MAX_FILE = 64 * 1024;
    static final int MAX_RECIPES = 16;

    static final String SLOT_PROFILE = "profile";
    static final String SLOT_CONTENT = "content";
    static final String SLOT_GOOGLE_TV = "google-tv";

    /**
     * The only (slot, app) pairs a recipe may be for: the apps Hearth types PINs in today. A file can change how
     * Hearth types in one of them, never add an app.
     */
    static final Set<String> ALLOWED = Collections.unmodifiableSet(new HashSet<>(java.util.Arrays.asList(
            key(SLOT_PROFILE, ProfilePairing.DISNEY),
            key(SLOT_PROFILE, ProfilePairing.APPLE_TV),
            key(SLOT_PROFILE, ProfilePairing.NETFLIX),
            key(SLOT_PROFILE, ProfilePairing.MAX),
            key(SLOT_CONTENT, ProfilePairing.PARAMOUNT),
            key(SLOT_GOOGLE_TV, LauncherAccessibilityService.GOOGLE_TV_PACKAGE))));

    static String key(String slot, String pkg) {
        return slot + "|" + pkg;
    }

    // ---- What a recipe is made of ----

    enum Is { MATCH, CHANGED, LOCKED_OUT, ACCEPTED, REJECTED, HEARD }

    enum CondKind {
        NODE, NO_NODE, NODE_SHOWS_TEXT, TEXT, KEYS_ALL, KEYS_SOME, KEYS_NOT_ALL, IN_APP, NOT_IN_APP, FLAG, NO_FLAG,
        HEARD, SINCE_LAST_DIGIT, COUNT_DROPPED
    }

    /** One test on the window or on what the recipe heard. */
    static final class Cond {
        final CondKind kind;
        final String name;
        final long ms;

        Cond(CondKind kind, String name, long ms) {
            this.kind = kind;
            this.name = name;
            this.ms = ms;
        }
    }

    /** All of {@code when} hold: the screen (or the answer) is {@code is}. */
    static final class Rule {
        final List<Cond> when;
        final Is is;

        Rule(List<Cond> when, Is is) {
            this.when = when;
            this.is = is;
        }
    }

    enum EffectKind { SET, FOCUS, OUTCOME, ECHO, COUNT }

    static final class Effect {
        final EffectKind kind;
        final String flag;
        final PinEntryMachine.Outcome outcome;

        Effect(EffectKind kind, String flag, PinEntryMachine.Outcome outcome) {
            this.kind = kind;
            this.flag = flag;
            this.outcome = outcome;
        }
    }

    /** All phrases heard in what the app said: the effects happen, then (unless {@code stop} is false) nothing else. */
    static final class SpeechRule {
        final List<PinTemplate> when;
        final List<Effect> effects;
        final boolean stop;

        SpeechRule(List<PinTemplate> when, List<Effect> effects, boolean stop) {
            this.when = when;
            this.effects = effects;
            this.stop = stop;
        }
    }

    enum Label { TEXT, DESCRIPTION, DESCRIPTION_AFTER_LAST_COMMA }

    enum Duplicates { LAST, FIRST, FAIL }

    /** How the keypad's digit keys (and any extra keys that must be there) are found in the window. */
    static final class Keys {
        /** Found by view id (under the app's own package), or by walking the tree. */
        final String byId;
        final int walkDepth;
        /** A named node to walk inside instead of the whole window (never itself a key). */
        final String in;
        final boolean onlyVisible;
        final boolean onlyClickable;
        /** A digit-labelled node that isn't clickable spoils the whole keypad. */
        final boolean mustBeClickable;
        /** Don't look inside a digit-labelled node. */
        final boolean stopAtKey;
        final Label label;
        /** The node pressed: the labelled node, or its nearest clickable ancestor within {@code maxUp} steps. */
        final boolean pressAncestor;
        final int maxUp;
        /** No clickable ancestor: the keypad is spoiled (false), or the labelled node itself is pressed (true). */
        final boolean otherwiseSelf;
        final Duplicates duplicates;
        /** Labels of further keys that must be there for the keypad to count as whole ("Delete"). */
        final List<String> extra;

        Keys(String byId, int walkDepth, String in, boolean onlyVisible, boolean onlyClickable,
                boolean mustBeClickable, boolean stopAtKey, Label label, boolean pressAncestor, int maxUp,
                boolean otherwiseSelf, Duplicates duplicates, List<String> extra) {
            this.byId = byId;
            this.walkDepth = walkDepth;
            this.in = in;
            this.onlyVisible = onlyVisible;
            this.onlyClickable = onlyClickable;
            this.mustBeClickable = mustBeClickable;
            this.stopAtKey = stopAtKey;
            this.label = label;
            this.pressAncestor = pressAncestor;
            this.maxUp = maxUp;
            this.otherwiseSelf = otherwiseSelf;
            this.duplicates = duplicates;
            this.extra = extra;
        }
    }

    enum Typing { CLICK, DPAD }

    enum Confirm { CLICK, COUNT, SPOKEN_COUNT, ECHO, SETTLE }

    enum CountAs { LENGTH, DOTS }

    final String slot;
    final String pkg;
    final int version;
    final int engine;
    final int pinLength;
    /** The app versions the recipe is for (inclusive); a fetched recipe outside them leaves Hearth's own in place. */
    final long appFrom, appTo;
    final boolean appRange;
    /** Named nodes, each found by view id under the app's package. */
    final Map<String, String> nodes;
    final Keys keys;
    final List<SpeechRule> speech;
    /** The focused key's label from focus events, read this way; null: from speech (FOCUS effects) only. */
    final Label focusFromEvents;
    final List<Rule> screen;
    final Typing typing;
    /** D-pad keypads: each digit's {row, column}. */
    final int[][] layout;
    final String setTextField;
    final Confirm confirm;
    final String countNode;
    final CountAs countAs;
    final long pollMs, waitMs, settleMs;
    /** Ways the last digit counts as in although the count didn't move (each a list of conditions, all needed). */
    final List<List<Cond>> orOnLastDigit;
    final List<Rule> outcome;
    final long stepTimeoutMs, outcomeTimeoutMs;

    private PinRecipeSpec(Parsed p) {
        slot = p.slot;
        pkg = p.pkg;
        version = p.version;
        engine = p.engine;
        pinLength = p.pinLength;
        appFrom = p.appFrom;
        appTo = p.appTo;
        appRange = p.appRange;
        nodes = Collections.unmodifiableMap(p.nodes);
        keys = p.keys;
        speech = Collections.unmodifiableList(p.speech);
        focusFromEvents = p.focusFromEvents;
        screen = Collections.unmodifiableList(p.screen);
        typing = p.typing;
        layout = p.layout;
        setTextField = p.setTextField;
        confirm = p.confirm;
        countNode = p.countNode;
        countAs = p.countAs;
        pollMs = p.pollMs;
        waitMs = p.waitMs;
        settleMs = p.settleMs;
        orOnLastDigit = Collections.unmodifiableList(p.orOnLastDigit);
        outcome = Collections.unmodifiableList(p.outcome);
        stepTimeoutMs = p.stepTimeoutMs;
        outcomeTimeoutMs = p.outcomeTimeoutMs;
    }

    String key() {
        return key(slot, pkg);
    }

    /** Whether this recipe is for that version of the app (-1: not known, which a recipe with versions isn't for). */
    boolean coversAppVersion(long versionCode) {
        if (!appRange) return true;
        return versionCode >= 0 && versionCode >= appFrom && versionCode <= appTo;
    }

    /** The keypad's last row: 0's. */
    int lastRow() {
        return layout[0][0];
    }

    int[] position(char digit) {
        return layout[digit - '0'];
    }

    // ---- Reading a file ----

    /** Why a file was refused (no PIN or app text in it, only what's wrong). */
    static final class BadRecipes extends IllegalArgumentException {
        BadRecipes(String message) {
            super(message);
        }
    }

    /**
     * The recipes in a file, by {@link #key}, or {@link BadRecipes} for anything wrong with it. Recipes needing a newer
     * engine are left out (not an error); the rest must all be valid.
     */
    static Map<String, PinRecipeSpec> parseFile(String json) {
        if (json == null) throw new BadRecipes("no file");
        if (json.length() > MAX_FILE) throw new BadRecipes("the file is too long");
        String trimmed = json.trim();
        if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) throw new BadRecipes("the file isn't an object");
        JSONObject file;
        try {
            file = new JSONObject(trimmed);
        } catch (Exception e) {
            throw new BadRecipes("not JSON");
        }
        if (intOf(file, "schema", "file", 0, Integer.MAX_VALUE, -1) != SCHEMA) {
            throw new BadRecipes("schema must be " + SCHEMA);
        }
        JSONArray recipes = arrayOf(file, "recipes", "file", true);
        if (recipes.length() > MAX_RECIPES) throw new BadRecipes("too many recipes");
        Map<String, PinRecipeSpec> out = new LinkedHashMap<>();
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < recipes.length(); i++) {
            Object item = recipes.opt(i);
            if (!(item instanceof JSONObject)) throw new BadRecipes("recipe " + i + " isn't an object");
            JSONObject r = (JSONObject) item;
            int engine = intOf(r, "engine", "recipe " + i, 1, Integer.MAX_VALUE, -1);
            String slot = stringOf(r, "slot", "recipe " + i, true);
            String pkg = stringOf(r, "package", "recipe " + i, true);
            String key = key(slot, pkg);
            if (!ALLOWED.contains(key)) throw new BadRecipes("recipe " + i + " is for an app Hearth doesn't type in");
            if (!seen.add(key)) throw new BadRecipes("two recipes for the same app");
            // A recipe for a newer engine may use fields this one would ignore: skipped, never half-read
            if (engine > ENGINE) continue;
            out.put(key, parse(r, slot, pkg, engine, "recipe " + i));
        }
        return Collections.unmodifiableMap(out);
    }

    /** Fields as they're read, before they're frozen into a spec. */
    private static final class Parsed {
        String slot, pkg;
        int version, engine, pinLength;
        long appFrom, appTo = Long.MAX_VALUE;
        boolean appRange;
        Map<String, String> nodes = new LinkedHashMap<>();
        Keys keys;
        List<SpeechRule> speech = new ArrayList<>();
        Label focusFromEvents;
        List<Rule> screen = new ArrayList<>();
        Typing typing;
        int[][] layout;
        String setTextField;
        Confirm confirm;
        String countNode;
        CountAs countAs = CountAs.LENGTH;
        long pollMs, waitMs, settleMs;
        List<List<Cond>> orOnLastDigit = new ArrayList<>();
        List<Rule> outcome = new ArrayList<>();
        long stepTimeoutMs, outcomeTimeoutMs;
        Set<String> flagsSet = new HashSet<>();
        Set<String> flagsRead = new HashSet<>();
        boolean focusEffect, countEffect, echoEffect, outcomeEffect;
    }

    private static PinRecipeSpec parse(JSONObject r, String slot, String pkg, int engine, String where) {
        Parsed p = new Parsed();
        p.slot = slot;
        p.pkg = pkg;
        p.engine = engine;
        p.version = intOf(r, "version", where, 1, Integer.MAX_VALUE, -1);
        p.pinLength = intOf(r, "pinLength", where, 4, 8, -1);

        JSONObject apps = objectOf(r, "appVersions", where, false);
        if (apps != null) {
            p.appRange = true;
            p.appFrom = longOf(apps, "from", where + " appVersions", 0, Long.MAX_VALUE, 0);
            p.appTo = longOf(apps, "to", where + " appVersions", 0, Long.MAX_VALUE, Long.MAX_VALUE);
            if (p.appFrom > p.appTo) throw new BadRecipes(where + ": appVersions from is after to");
        }

        JSONObject nodes = objectOf(r, "nodes", where, false);
        if (nodes != null) {
            if (nodes.length() > 16) throw new BadRecipes(where + ": too many nodes");
            for (Iterator<String> it = nodes.keys(); it.hasNext(); ) {
                String name = it.next();
                checkName(name, where + " node name");
                JSONObject node = objectOf(nodes, name, where + " nodes", true);
                p.nodes.put(name, idOf(node, "id", where + " node " + name));
            }
        }

        JSONObject keys = objectOf(r, "keys", where, false);
        if (keys != null) p.keys = keys(keys, p, where + " keys");

        JSONArray speech = arrayOf(r, "speech", where, false);
        if (speech != null) {
            if (speech.length() > 32) throw new BadRecipes(where + ": too many speech rules");
            for (int i = 0; i < speech.length(); i++) p.speech.add(speechRule(speech.opt(i), p, where + " speech " + i));
        }

        String focus = stringOf(r, "focusFromEvents", where, false);
        if (focus != null) p.focusFromEvents = label(focus, where + " focusFromEvents");

        p.screen = rules(arrayOf(r, "screen", where, true), p, where + " screen", false);
        boolean match = false;
        for (Rule rule : p.screen) match |= rule.is == Is.MATCH;
        if (!match) throw new BadRecipes(where + ": no screen rule says MATCH");

        JSONObject typing = objectOf(r, "typing", where, true);
        String by = stringOf(typing, "by", where + " typing", true);
        if ("click".equals(by)) {
            p.typing = Typing.CLICK;
            if (p.keys == null) throw new BadRecipes(where + ": click typing needs keys");
            String field = stringOf(typing, "setTextFallback", where + " typing", false);
            if (field != null) p.setTextField = nodeRef(field, p, where + " typing");
        } else if ("dpad".equals(by)) {
            p.typing = Typing.DPAD;
            p.layout = layout(arrayOf(typing, "layout", where + " typing", true), where + " typing layout");
        } else {
            throw new BadRecipes(where + ": unknown typing");
        }

        JSONObject confirm = objectOf(r, "confirm", where, true);
        String how = stringOf(confirm, "by", where + " confirm", true);
        String cw = where + " confirm";
        p.pollMs = longOf(confirm, "pollMs", cw, 20, 1_000, 100);
        p.waitMs = longOf(confirm, "waitMs", cw, 100, 10_000, 1_500);
        switch (how) {
            case "click":
                p.confirm = Confirm.CLICK;
                break;
            case "count":
                p.confirm = Confirm.COUNT;
                p.countNode = nodeRef(stringOf(confirm, "node", cw, true), p, cw);
                String as = stringOf(confirm, "countAs", cw, false);
                if (as != null) {
                    if ("length".equals(as)) p.countAs = CountAs.LENGTH;
                    else if ("dots".equals(as)) p.countAs = CountAs.DOTS;
                    else throw new BadRecipes(cw + ": unknown countAs");
                }
                break;
            case "spokenCount":
                p.confirm = Confirm.SPOKEN_COUNT;
                if (!p.countEffect) throw new BadRecipes(cw + ": spokenCount needs a speech rule that counts");
                break;
            case "echo":
                p.confirm = Confirm.ECHO;
                if (!p.echoEffect) throw new BadRecipes(cw + ": echo needs a speech rule that echoes");
                break;
            case "settle":
                p.confirm = Confirm.SETTLE;
                p.settleMs = longOf(confirm, "settleMs", cw, 50, 5_000, -1);
                break;
            default:
                throw new BadRecipes(cw + ": unknown confirm");
        }
        boolean clickConfirm = p.confirm == Confirm.CLICK || p.confirm == Confirm.COUNT;
        if (clickConfirm != (p.typing == Typing.CLICK)) {
            throw new BadRecipes(cw + ": this confirm doesn't fit the typing");
        }
        JSONArray last = arrayOf(confirm, "orOnLastDigit", cw, false);
        if (last != null) {
            if (p.confirm != Confirm.COUNT && p.confirm != Confirm.ECHO) {
                throw new BadRecipes(cw + ": orOnLastDigit is only for count and echo");
            }
            if (last.length() > 8) throw new BadRecipes(cw + ": too many orOnLastDigit");
            for (int i = 0; i < last.length(); i++) {
                Object item = last.opt(i);
                if (!(item instanceof JSONArray)) throw new BadRecipes(cw + ": orOnLastDigit holds lists");
                List<Cond> way = conds((JSONArray) item, p, cw + " orOnLastDigit " + i, true);
                for (Cond c : way) {
                    boolean heardOnly = c.kind == CondKind.FLAG || c.kind == CondKind.NO_FLAG || c.kind == CondKind.HEARD;
                    // An echo is waited for without a look at the window; a count has the field's count before
                    if (p.confirm == Confirm.ECHO && !heardOnly) {
                        throw new BadRecipes(cw + ": an echo's orOnLastDigit tests only what was heard");
                    }
                }
                p.orOnLastDigit.add(way);
            }
        }

        p.outcome = rules(arrayOf(r, "outcome", where, true), p, where + " outcome", true);
        if (p.outcome.isEmpty()) throw new BadRecipes(where + ": no outcome rules");

        p.stepTimeoutMs = longOf(r, "stepTimeoutMs", where, 1_000, 30_000,
                p.typing == Typing.DPAD ? DataPinRecipe.MAX_MOVES * DataPinRecipe.MOVE_WAIT_MS : 2_500);
        p.outcomeTimeoutMs = longOf(r, "outcomeTimeoutMs", where, 1_000, 30_000, 6_000);

        if (p.typing == Typing.DPAD && p.focusFromEvents == null && !p.focusEffect) {
            throw new BadRecipes(where + ": a D-pad keypad needs the focused key from events or speech");
        }
        for (String flag : p.flagsRead) {
            if (!p.flagsSet.contains(flag)) throw new BadRecipes(where + ": a flag is read but never set");
        }
        return new PinRecipeSpec(p);
    }

    private static Keys keys(JSONObject k, Parsed p, String where) {
        String byId = null;
        int depth = 0;
        String in = null;
        boolean visible = false, clickable = false;
        JSONObject find = objectOf(k, "find", where, true);
        if (find.has("id")) {
            byId = idOf(find, "id", where + " find");
        } else if (find.has("walk")) {
            depth = intOf(find, "walk", where + " find", 0, 40, -1);
            String scope = stringOf(find, "in", where + " find", false);
            if (scope != null) in = nodeRef(scope, p, where + " find");
        } else {
            throw new BadRecipes(where + ": find needs id or walk");
        }
        JSONArray only = arrayOf(k, "only", where, false);
        if (only != null) {
            for (int i = 0; i < only.length(); i++) {
                Object o = only.opt(i);
                if ("visible".equals(o)) visible = true;
                else if ("clickable".equals(o)) clickable = true;
                else throw new BadRecipes(where + ": unknown filter in only");
            }
        }
        boolean mustBeClickable = boolOf(k, "mustBeClickable", where, false);
        boolean stopAtKey = boolOf(k, "stopAtKey", where, false);
        Label label = label(stringOf(k, "label", where, true), where);
        String press = stringOf(k, "press", where, false);
        boolean ancestor;
        if (press == null || "self".equals(press)) ancestor = false;
        else if ("clickableAncestor".equals(press)) ancestor = true;
        else throw new BadRecipes(where + ": unknown press");
        int maxUp = intOf(k, "maxUp", where, 0, 64, 64);
        String otherwise = stringOf(k, "otherwise", where, false);
        boolean self;
        if (otherwise == null || "fail".equals(otherwise)) self = false;
        else if ("self".equals(otherwise)) self = true;
        else throw new BadRecipes(where + ": unknown otherwise");
        String dup = stringOf(k, "duplicates", where, false);
        Duplicates duplicates;
        if (dup == null || "last".equals(dup)) duplicates = Duplicates.LAST;
        else if ("first".equals(dup)) duplicates = Duplicates.FIRST;
        else if ("fail".equals(dup)) duplicates = Duplicates.FAIL;
        else throw new BadRecipes(where + ": unknown duplicates");
        List<String> extra = new ArrayList<>();
        JSONArray extras = arrayOf(k, "extra", where, false);
        if (extras != null) {
            if (extras.length() > 4) throw new BadRecipes(where + ": too many extra keys");
            for (int i = 0; i < extras.length(); i++) {
                Object e = extras.opt(i);
                if (!(e instanceof String) || ((String) e).isEmpty() || ((String) e).length() > 40) {
                    throw new BadRecipes(where + ": an extra key is a label of 1-40 characters");
                }
                String s = (String) e;
                if (s.length() == 1 && s.charAt(0) >= '0' && s.charAt(0) <= '9') {
                    throw new BadRecipes(where + ": an extra key can't be a digit");
                }
                extra.add(s);
            }
        }
        return new Keys(byId, depth, in, visible, clickable, mustBeClickable, stopAtKey, label, ancestor, maxUp, self,
                duplicates, Collections.unmodifiableList(extra));
    }

    private static SpeechRule speechRule(Object item, Parsed p, String where) {
        if (!(item instanceof JSONObject)) throw new BadRecipes(where + " isn't an object");
        JSONObject r = (JSONObject) item;
        JSONArray when = arrayOf(r, "when", where, true);
        if (when.length() == 0 || when.length() > 4) throw new BadRecipes(where + ": 1-4 phrases");
        List<PinTemplate> templates = new ArrayList<>();
        for (int i = 0; i < when.length(); i++) {
            Object o = when.opt(i);
            if (!(o instanceof JSONObject)) throw new BadRecipes(where + ": a phrase is an object");
            JSONObject m = (JSONObject) o;
            PinTemplate.Mode mode = null;
            String text = null;
            int found = 0;
            for (String[] option : new String[][] {{"equals", "EQUALS"}, {"contains", "CONTAINS"},
                    {"startsWith", "STARTS_WITH"}}) {
                if (m.has(option[0])) {
                    found++;
                    mode = PinTemplate.Mode.valueOf(option[1]);
                    text = stringOf(m, option[0], where, true);
                }
            }
            if (found != 1) throw new BadRecipes(where + ": a phrase is one of equals, contains, startsWith");
            try {
                templates.add(PinTemplate.parse(mode, text));
            } catch (IllegalArgumentException e) {
                throw new BadRecipes(where + ": " + e.getMessage());
            }
        }
        JSONArray does = arrayOf(r, "do", where, true);
        if (does.length() == 0 || does.length() > 4) throw new BadRecipes(where + ": 1-4 effects");
        List<Effect> effects = new ArrayList<>();
        PinTemplate capturing = null;
        for (PinTemplate t : templates) {
            if (t.hasPlaceholder()) {
                capturing = t;
                break;
            }
        }
        for (int i = 0; i < does.length(); i++) {
            Object o = does.opt(i);
            if (!(o instanceof JSONObject)) throw new BadRecipes(where + ": an effect is an object");
            JSONObject e = (JSONObject) o;
            if (e.has("set")) {
                String flag = stringOf(e, "set", where, true);
                checkName(flag, where + " flag");
                p.flagsSet.add(flag);
                effects.add(new Effect(EffectKind.SET, flag, null));
            } else if (e.has("focus")) {
                trueOf(e, "focus", where);
                p.focusEffect = true;
                effects.add(new Effect(EffectKind.FOCUS, null, null));
            } else if (e.has("outcome")) {
                String o2 = stringOf(e, "outcome", where, true);
                PinEntryMachine.Outcome outcome;
                if ("ACCEPTED".equals(o2)) outcome = PinEntryMachine.Outcome.ACCEPTED;
                else if ("REJECTED".equals(o2)) outcome = PinEntryMachine.Outcome.REJECTED;
                else throw new BadRecipes(where + ": an outcome heard is ACCEPTED or REJECTED");
                p.outcomeEffect = true;
                effects.add(new Effect(EffectKind.OUTCOME, null, outcome));
            } else if (e.has("echo")) {
                trueOf(e, "echo", where);
                p.echoEffect = true;
                effects.add(new Effect(EffectKind.ECHO, null, null));
            } else if (e.has("count")) {
                trueOf(e, "count", where);
                if (capturing == null || !capturing.capturesNumber()) {
                    throw new BadRecipes(where + ": count needs a phrase whose first placeholder is {d} or {n}");
                }
                p.countEffect = true;
                effects.add(new Effect(EffectKind.COUNT, null, null));
            } else {
                throw new BadRecipes(where + ": unknown effect");
            }
        }
        boolean stop = boolOf(r, "stop", where, true);
        return new SpeechRule(Collections.unmodifiableList(templates), Collections.unmodifiableList(effects), stop);
    }

    private static List<Rule> rules(JSONArray rules, Parsed p, String where, boolean outcome) {
        if (rules.length() > 12) throw new BadRecipes(where + ": too many rules");
        List<Rule> out = new ArrayList<>();
        for (int i = 0; i < rules.length(); i++) {
            Object item = rules.opt(i);
            if (!(item instanceof JSONObject)) throw new BadRecipes(where + " " + i + " isn't an object");
            JSONObject r = (JSONObject) item;
            List<Cond> when = conds(arrayOf(r, "when", where + " " + i, true), p, where + " " + i, false);
            if (when.isEmpty()) throw new BadRecipes(where + " " + i + ": a rule needs a condition");
            String is = stringOf(r, "is", where + " " + i, true);
            Is value;
            try {
                value = Is.valueOf(is);
            } catch (IllegalArgumentException e) {
                throw new BadRecipes(where + " " + i + ": unknown is");
            }
            boolean fits = outcome
                    ? value == Is.ACCEPTED || value == Is.REJECTED || value == Is.LOCKED_OUT || value == Is.HEARD
                    : value == Is.MATCH || value == Is.CHANGED || value == Is.LOCKED_OUT;
            if (!fits) throw new BadRecipes(where + " " + i + ": this is doesn't fit");
            if (value == Is.HEARD && !p.outcomeEffect) {
                throw new BadRecipes(where + " " + i + ": HEARD needs a speech rule that hears an outcome");
            }
            out.add(new Rule(when, value));
        }
        return out;
    }

    private static List<Cond> conds(JSONArray conds, Parsed p, String where, boolean confirm) {
        if (conds.length() > 8) throw new BadRecipes(where + ": too many conditions");
        List<Cond> out = new ArrayList<>();
        for (int i = 0; i < conds.length(); i++) {
            Object item = conds.opt(i);
            if (!(item instanceof JSONObject)) throw new BadRecipes(where + ": a condition is an object");
            out.add(cond((JSONObject) item, p, where, confirm));
        }
        if (confirm && out.isEmpty()) throw new BadRecipes(where + ": an empty list of conditions");
        return Collections.unmodifiableList(out);
    }

    private static final String[] COND_KEYS = {"node", "noNode", "nodeShowsText", "text", "keys", "inApp", "flag",
            "noFlag", "heard", "sinceLastDigitMs", "countDropped"};

    private static Cond cond(JSONObject c, Parsed p, String where, boolean confirm) {
        String which = null;
        for (String k : COND_KEYS) {
            if (c.has(k)) {
                if (which != null) throw new BadRecipes(where + ": a condition tests one thing");
                which = k;
            }
        }
        if (which == null) throw new BadRecipes(where + ": unknown condition");
        switch (which) {
            case "node":
                return new Cond(CondKind.NODE, nodeRef(stringOf(c, which, where, true), p, where), 0);
            case "noNode":
                return new Cond(CondKind.NO_NODE, nodeRef(stringOf(c, which, where, true), p, where), 0);
            case "nodeShowsText":
                return new Cond(CondKind.NODE_SHOWS_TEXT, nodeRef(stringOf(c, which, where, true), p, where), 0);
            case "text": {
                String text = stringOf(c, which, where, true);
                if (text.isEmpty() || text.length() > 200) throw new BadRecipes(where + ": text is 1-200 characters");
                return new Cond(CondKind.TEXT, text, 0);
            }
            case "keys": {
                if (p.keys == null) throw new BadRecipes(where + ": keys tested but none described");
                String k = stringOf(c, which, where, true);
                if ("all".equals(k)) return new Cond(CondKind.KEYS_ALL, null, 0);
                if ("some".equals(k)) return new Cond(CondKind.KEYS_SOME, null, 0);
                if ("notAll".equals(k)) return new Cond(CondKind.KEYS_NOT_ALL, null, 0);
                throw new BadRecipes(where + ": keys is all, some or notAll");
            }
            case "inApp":
                return new Cond(boolOf(c, which, where, true) ? CondKind.IN_APP : CondKind.NOT_IN_APP, null, 0);
            case "flag":
            case "noFlag": {
                String flag = stringOf(c, which, where, true);
                checkName(flag, where + " flag");
                p.flagsRead.add(flag);
                return new Cond("flag".equals(which) ? CondKind.FLAG : CondKind.NO_FLAG, flag, 0);
            }
            case "heard":
                trueOf(c, which, where);
                if (!p.outcomeEffect) throw new BadRecipes(where + ": heard needs a speech rule that hears an outcome");
                return new Cond(CondKind.HEARD, null, 0);
            case "sinceLastDigitMs":
                return new Cond(CondKind.SINCE_LAST_DIGIT, null, longOf(c, which, where, 0, 30_000, -1));
            default: // countDropped
                trueOf(c, which, where);
                if (!confirm) throw new BadRecipes(where + ": countDropped is only for orOnLastDigit");
                return new Cond(CondKind.COUNT_DROPPED, null, 0);
        }
    }

    /**
     * A D-pad keypad as on screen: rows of key labels, "" for a place without a digit key. Each digit once; and every
     * route the engine takes between two digits ({@link DataPinRecipe#nextMove}) must stay on digit keys and take at
     * most {@link DataPinRecipe#MAX_MOVES} moves, so a recipe can't send the focus off the keypad.
     */
    private static int[][] layout(JSONArray rows, String where) {
        if (rows.length() == 0 || rows.length() > 6) throw new BadRecipes(where + ": 1-6 rows");
        int[][] positions = new int[10][];
        String[][] grid = new String[rows.length()][];
        for (int r = 0; r < rows.length(); r++) {
            Object row = rows.opt(r);
            if (!(row instanceof JSONArray)) throw new BadRecipes(where + ": a row is a list");
            JSONArray cells = (JSONArray) row;
            if (cells.length() == 0 || cells.length() > 12) throw new BadRecipes(where + ": 1-12 keys a row");
            grid[r] = new String[cells.length()];
            for (int c = 0; c < cells.length(); c++) {
                Object cell = cells.opt(c);
                if (!(cell instanceof String)) throw new BadRecipes(where + ": a key is a string");
                String s = (String) cell;
                grid[r][c] = s;
                if (s.isEmpty()) continue;
                if (s.length() != 1 || s.charAt(0) < '0' || s.charAt(0) > '9') {
                    throw new BadRecipes(where + ": a key is a digit, or \"\" for none");
                }
                if (positions[s.charAt(0) - '0'] != null) throw new BadRecipes(where + ": a digit twice");
                positions[s.charAt(0) - '0'] = new int[] {r, c};
            }
        }
        for (int[] at : positions) {
            if (at == null) throw new BadRecipes(where + ": a digit is missing");
        }
        int lastRow = positions[0][0];
        for (int from = 0; from <= 9; from++) {
            for (int to = 0; to <= 9; to++) {
                if (from == to) continue;
                int[] at = positions[from];
                int moves = 0;
                while (at[0] != positions[to][0] || at[1] != positions[to][1]) {
                    int move = DataPinRecipe.nextMove(at, positions[to], lastRow);
                    at = new int[] {at[0] + (move == PinNode.Host.DOWN ? 1 : move == PinNode.Host.UP ? -1 : 0),
                            at[1] + (move == PinNode.Host.RIGHT ? 1 : move == PinNode.Host.LEFT ? -1 : 0)};
                    boolean onKey = at[0] >= 0 && at[0] < grid.length && at[1] >= 0 && at[1] < grid[at[0]].length
                            && !grid[at[0]][at[1]].isEmpty();
                    if (!onKey || ++moves > DataPinRecipe.MAX_MOVES) {
                        throw new BadRecipes(where + ": a route between two digits leaves the digit keys");
                    }
                }
            }
        }
        int[][] out = new int[10][];
        for (int d = 0; d <= 9; d++) out[d] = positions[d].clone();
        return out;
    }

    // ---- Strict field readers: the right type or an error; missing optional fields get their default ----

    private static Label label(String s, String where) {
        if ("text".equals(s)) return Label.TEXT;
        if ("description".equals(s)) return Label.DESCRIPTION;
        if ("descriptionAfterLastComma".equals(s)) return Label.DESCRIPTION_AFTER_LAST_COMMA;
        throw new BadRecipes(where + ": unknown label");
    }

    private static String nodeRef(String name, Parsed p, String where) {
        if (!p.nodes.containsKey(name)) throw new BadRecipes(where + ": a node that isn't in nodes");
        return name;
    }

    private static void checkName(String name, String where) {
        if (name == null || name.isEmpty() || name.length() > 32) throw new BadRecipes(where + ": 1-32 characters");
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (i > 0 && c >= '0' && c <= '9');
            if (!ok) throw new BadRecipes(where + ": letters and digits only");
        }
    }

    /** A view id's name (after the app's ":id/"), letters, digits and underscores only. */
    private static String idOf(JSONObject o, String name, String where) {
        String id = stringOf(o, name, where, true);
        if (id.isEmpty() || id.length() > 80) throw new BadRecipes(where + ": an id is 1-80 characters");
        for (int i = 0; i < id.length(); i++) {
            char c = id.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
            if (!ok) throw new BadRecipes(where + ": an id is letters, digits and _");
        }
        return id;
    }

    private static String stringOf(JSONObject o, String name, String where, boolean required) {
        Object v = o.opt(name);
        if (v == null || v == JSONObject.NULL) {
            if (required) throw new BadRecipes(where + ": " + name + " is missing");
            return null;
        }
        if (!(v instanceof String)) throw new BadRecipes(where + ": " + name + " must be a string");
        return (String) v;
    }

    private static JSONObject objectOf(JSONObject o, String name, String where, boolean required) {
        Object v = o.opt(name);
        if (v == null || v == JSONObject.NULL) {
            if (required) throw new BadRecipes(where + ": " + name + " is missing");
            return null;
        }
        if (!(v instanceof JSONObject)) throw new BadRecipes(where + ": " + name + " must be an object");
        return (JSONObject) v;
    }

    private static JSONArray arrayOf(JSONObject o, String name, String where, boolean required) {
        Object v = o.opt(name);
        if (v == null || v == JSONObject.NULL) {
            if (required) throw new BadRecipes(where + ": " + name + " is missing");
            return null;
        }
        if (!(v instanceof JSONArray)) throw new BadRecipes(where + ": " + name + " must be a list");
        return (JSONArray) v;
    }

    private static boolean boolOf(JSONObject o, String name, String where, boolean fallback) {
        Object v = o.opt(name);
        if (v == null || v == JSONObject.NULL) return fallback;
        if (!(v instanceof Boolean)) throw new BadRecipes(where + ": " + name + " must be true or false");
        return (Boolean) v;
    }

    private static void trueOf(JSONObject o, String name, String where) {
        if (!Boolean.TRUE.equals(o.opt(name))) throw new BadRecipes(where + ": " + name + " must be true");
    }

    /** A whole number in [min, max]; {@code fallback} when missing, or an error when it's -1 (required). */
    private static long longOf(JSONObject o, String name, String where, long min, long max, long fallback) {
        Object v = o.opt(name);
        if (v == null || v == JSONObject.NULL) {
            if (fallback == -1) throw new BadRecipes(where + ": " + name + " is missing");
            return fallback;
        }
        if (!(v instanceof Integer) && !(v instanceof Long)) {
            throw new BadRecipes(where + ": " + name + " must be a whole number");
        }
        long n = ((Number) v).longValue();
        if (n < min || n > max) throw new BadRecipes(where + ": " + name + " is out of range");
        return n;
    }

    private static int intOf(JSONObject o, String name, String where, int min, int max, int fallback) {
        return (int) longOf(o, name, where, min, max, fallback);
    }
}
