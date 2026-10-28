package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Reading recipe files: Hearth's own and the repository's copy are valid, and a fetched file can never do more than
 * the engine allows (too long, regular expressions, unknown actions, apps Hearth doesn't type in, bad keypads: the
 * whole file is refused and Hearth's own recipes are used).
 */
public class PinRecipeFileTest {

    private static String repeat(String s, int times) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < times; i++) out.append(s);
        return out.toString();
    }

    // ---- The files in the repository ----

    @Test
    public void hearthsOwnRecipesCoverEveryAppItTypesIn() {
        Map<String, PinRecipeSpec> recipes = PinFakes.builtIn();
        assertEquals(PinRecipeSpec.ALLOWED, recipes.keySet());
        for (PinRecipeSpec spec : recipes.values()) {
            assertEquals(4, spec.pinLength);
            assertTrue(spec.engine <= PinRecipeSpec.ENGINE);
        }
    }

    @Test
    public void theRepositoryCopyIsValidAndNotOlder() {
        Map<String, PinRecipeSpec> builtIn = PinFakes.builtIn();
        Map<String, PinRecipeSpec> repo = PinRecipeSpec.parseFile(PinFakes.repoFile());
        assertEquals(builtIn.keySet(), repo.keySet());
        for (PinRecipeSpec spec : repo.values()) {
            assertTrue(spec.pkg + " in pin-entry/recipes.json is older than Hearth's own",
                    spec.version >= builtIn.get(spec.key()).version);
        }
    }

    @Test
    public void bothFilesFitTheFetchLimit() {
        assertTrue(PinFakes.builtInFile().length() < PinRecipeSpec.MAX_FILE / 2);
        assertTrue(PinFakes.repoFile().length() < PinRecipeSpec.MAX_FILE / 2);
    }

    // ---- What's refused ----

    private static JSONObject file() throws Exception {
        return new JSONObject(PinFakes.builtInFile());
    }

    private static JSONObject recipe(JSONObject file, String pkg) throws Exception {
        JSONArray recipes = file.getJSONArray("recipes");
        for (int i = 0; i < recipes.length(); i++) {
            if (pkg.equals(recipes.getJSONObject(i).getString("package"))) return recipes.getJSONObject(i);
        }
        throw new AssertionError(pkg);
    }

    private static void refused(String why, String json) {
        try {
            PinRecipeSpec.parseFile(json);
            fail("accepted: " + why);
        } catch (PinRecipeSpec.BadRecipes expected) {
            // Refused as a whole
        }
    }

    private static void refused(String why, JSONObject json) {
        refused(why, json.toString());
    }

    @Test
    public void aFileTooLongIsRefused() throws Exception {
        StringBuilder padded = new StringBuilder(PinFakes.builtInFile());
        padded.insert(1, repeat(" ", PinRecipeSpec.MAX_FILE));
        refused("too long", padded.toString());
        // And the fetch stops reading past the limit
        byte[] big = new byte[PinRecipeSpec.MAX_FILE + 1];
        try {
            PinRecipes.read(new ByteArrayInputStream(big));
            fail("read past the limit");
        } catch (PinRecipeSpec.BadRecipes expected) {
            // Stopped
        }
    }

    @Test
    public void somethingThatIsntARecipeFileIsRefused() throws Exception {
        refused("not JSON", "not json");
        refused("empty", "");
        refused("a list", "[]");
        refused("truncated", PinFakes.builtInFile().substring(0, 500));
        refused("no schema", new JSONObject().put("recipes", new JSONArray()));
        refused("another schema", file().put("schema", 2));
        refused("schema as text", file().put("schema", "1"));
        refused("no recipes", new JSONObject().put("schema", 1));
        refused("recipes not a list", new JSONObject().put("schema", 1).put("recipes", new JSONObject()));
    }

    @Test
    public void aRegularExpressionIsRefused() throws Exception {
        JSONObject f = file();
        JSONObject apple = recipe(f, ProfilePairing.APPLE_TV);
        apple.getJSONArray("speech").getJSONObject(0).put("when", new JSONArray().put(
                new JSONObject().put("regex", "(\\d+)+ of (\\d+)+ values entered")));
        refused("a regex condition", f);
        // A phrase is plain text: placeholders only from the closed set, never next to each other
        for (String bad : new String[] {"{n}{n} values", "(a+)+{x}", "{field}, {field}", "{d", "d}", "Upper Case",
                "{n} {n} {n} {n} of"}) {
            JSONObject g = file();
            recipe(g, ProfilePairing.APPLE_TV).getJSONArray("speech").getJSONObject(0).put("when",
                    new JSONArray().put(new JSONObject().put("contains", bad)));
            refused("phrase " + bad, g);
        }
    }

    @Test
    public void anUnknownActionIsRefused() throws Exception {
        JSONObject f = file();
        recipe(f, ProfilePairing.DISNEY).put("typing", new JSONObject().put("by", "intent")
                .put("action", "android.intent.action.VIEW"));
        refused("typing by intent", f);

        JSONObject g = file();
        recipe(g, ProfilePairing.NETFLIX).getJSONArray("speech").getJSONObject(0).put("do",
                new JSONArray().put(new JSONObject().put("launch", "com.example.other")));
        refused("an unknown effect", g);

        JSONObject h = file();
        recipe(h, ProfilePairing.DISNEY).put("confirm", new JSONObject().put("by", "guess"));
        refused("an unknown confirm", h);

        JSONObject i = file();
        recipe(i, ProfilePairing.DISNEY).getJSONArray("screen").getJSONObject(0).getJSONArray("when")
                .put(new JSONObject().put("shell", "input keyevent 23"));
        refused("an unknown condition", i);

        JSONObject j = file();
        recipe(j, ProfilePairing.DISNEY).getJSONArray("outcome").getJSONObject(0).put("is", "UNLOCK_EVERYTHING");
        refused("an unknown result", j);

        JSONObject k = file();
        recipe(k, ProfilePairing.DISNEY).getJSONObject("keys").put("press", "longClick");
        refused("an unknown press", k);
    }

    @Test
    public void anAppHearthDoesntTypeInIsRefused() throws Exception {
        JSONObject f = file();
        recipe(f, ProfilePairing.DISNEY).put("package", "com.example.unpaired");
        refused("an unknown package", f);

        JSONObject g = file();
        recipe(g, ProfilePairing.DISNEY).put("package", ProfilePairing.HULU);
        refused("an app without a built-in recipe", g);

        JSONObject h = file();
        recipe(h, ProfilePairing.NETFLIX).put("slot", PinRecipeSpec.SLOT_CONTENT);
        refused("an app in another slot", h);

        JSONObject i = file();
        i.getJSONArray("recipes").put(new JSONObject(recipe(file(), ProfilePairing.NETFLIX).toString()));
        refused("two recipes for one app", i);

        // A node id is only a name: the engine puts the recipe's own package in front of it
        JSONObject j = file();
        recipe(j, ProfilePairing.DISNEY).getJSONObject("nodes").put("field",
                new JSONObject().put("id", "com.example.other:id/field"));
        refused("an id with a package", j);
    }

    @Test
    public void wrongTypesAndValuesAreRefused() throws Exception {
        String[][] cases = {
                {"version", "\"2\""}, {"version", "0"}, {"version", "1.5"}, {"pinLength", "3"}, {"pinLength", "40"},
                {"stepTimeoutMs", "999999"}, {"engine", "0"}, {"nodes", "[]"}, {"screen", "{}"}, {"screen", "[]"},
                {"outcome", "[]"},
        };
        for (String[] c : cases) {
            JSONObject f = file();
            recipe(f, ProfilePairing.DISNEY).put(c[0], new JSONTokenerValue(c[1]).value());
            refused(c[0] + " = " + c[1], f);
        }
        JSONObject g = file();
        recipe(g, ProfilePairing.DISNEY).getJSONArray("screen").getJSONObject(0).getJSONArray("when")
                .put(new JSONObject().put("node", "notANode"));
        refused("a node that isn't named", g);

        JSONObject h = file();
        recipe(h, ProfilePairing.NETFLIX).getJSONArray("screen").getJSONObject(1).getJSONArray("when")
                .put(new JSONObject().put("flag", "neverSet"));
        refused("a flag never set", h);

        JSONObject i = file();
        recipe(i, ProfilePairing.DISNEY).put("appVersions", new JSONObject().put("from", 10).put("to", 5));
        refused("an empty version range", i);
    }

    /** A JSON value from its text, for the cases above. */
    private static final class JSONTokenerValue {
        private final String mText;

        JSONTokenerValue(String text) {
            mText = text;
        }

        Object value() throws Exception {
            return new org.json.JSONTokener(mText).nextValue();
        }
    }

    @Test
    public void aKeypadWhoseRoutesLeaveTheDigitsIsRefused() throws Exception {
        JSONObject f = file();
        recipe(f, ProfilePairing.NETFLIX).getJSONObject("typing").put("layout",
                new JSONArray("[[\"1\",\"2\",\"3\",\"0\"],[\"4\",\"5\",\"6\"],[\"7\",\"8\",\"9\"]]"));
        refused("0 above a gap", f);

        JSONObject g = file();
        recipe(g, ProfilePairing.NETFLIX).getJSONObject("typing").put("layout",
                new JSONArray("[[\"1\",\"2\",\"3\"],[\"4\",\"5\",\"6\"],[\"7\",\"8\",\"9\"]]"));
        refused("no 0", g);

        JSONObject h = file();
        recipe(h, ProfilePairing.NETFLIX).getJSONObject("typing").put("layout",
                new JSONArray("[[\"1\",\"2\",\"3\"],[\"4\",\"5\",\"6\"],[\"7\",\"8\",\"9\"],[\"0\",\"1\"]]"));
        refused("a digit twice", h);
    }

    // ---- What's let through ----

    @Test
    public void unknownFieldsAreIgnored() throws Exception {
        JSONObject f = file().put("note", "for people").put("later", new JSONObject().put("x", 1));
        recipe(f, ProfilePairing.DISNEY).put("researchedOn", "2026-10-09").put("notes", new JSONArray().put("a"));
        assertEquals(PinRecipeSpec.ALLOWED, PinRecipeSpec.parseFile(f.toString()).keySet());
    }

    @Test
    public void aRecipeForANewerEngineIsSkippedNotHalfRead() throws Exception {
        JSONObject f = file();
        JSONObject netflix = recipe(f, ProfilePairing.NETFLIX);
        netflix.put("engine", PinRecipeSpec.ENGINE + 1).put("typing", new JSONObject().put("by", "somethingNew"));
        Map<String, PinRecipeSpec> recipes = PinRecipeSpec.parseFile(f.toString());
        assertFalse(recipes.containsKey(PinRecipeSpec.key(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX)));
        assertEquals(PinRecipeSpec.ALLOWED.size() - 1, recipes.size());
        // Still for an app Hearth types in, though
        netflix.put("package", "com.example.unpaired");
        refused("a newer recipe for an unknown app", f);
    }

    // ---- Which recipe is used ----

    private static PinRecipeSpec disney(int version, JSONObject appVersions) throws Exception {
        JSONObject f = file();
        JSONObject d = recipe(f, ProfilePairing.DISNEY).put("version", version);
        if (appVersions != null) d.put("appVersions", appVersions);
        return PinRecipeSpec.parseFile(f.toString()).get(PinRecipeSpec.key(PinRecipeSpec.SLOT_PROFILE,
                ProfilePairing.DISNEY));
    }

    @Test
    public void aFetchedRecipeReplacesHearthsOwnOnlyWhenNewer() throws Exception {
        PinRecipeSpec builtIn = disney(1, null);
        assertSame(builtIn, PinRecipes.choose(builtIn, null, 5));
        assertSame(builtIn, PinRecipes.choose(builtIn, disney(1, null), 5));
        PinRecipeSpec newer = disney(2, null);
        assertSame(newer, PinRecipes.choose(builtIn, newer, 5));
        assertSame(newer, PinRecipes.choose(builtIn, newer, -1));
        PinRecipeSpec newerBuiltIn = disney(3, null);
        assertSame(newerBuiltIn, PinRecipes.choose(newerBuiltIn, newer, 5));
        // Nothing for an app Hearth has no recipe of its own for
        assertNull(PinRecipes.choose(null, newer, 5));
        // Another app's recipe never stands in
        PinRecipeSpec netflix = PinFakes.spec(PinRecipeSpec.SLOT_PROFILE, ProfilePairing.NETFLIX);
        assertSame(netflix, PinRecipes.choose(netflix, newer, 5));
    }

    @Test
    public void aFetchedRecipeForSomeAppVersionsIsUsedOnlyForThem() throws Exception {
        PinRecipeSpec builtIn = disney(1, null);
        PinRecipeSpec forNew = disney(2, new JSONObject().put("from", 500));
        assertSame(forNew, PinRecipes.choose(builtIn, forNew, 500));
        assertSame(builtIn, PinRecipes.choose(builtIn, forNew, 499));
        assertSame("version unknown", builtIn, PinRecipes.choose(builtIn, forNew, -1));
        PinRecipeSpec forOld = disney(2, new JSONObject().put("to", 100));
        assertSame(forOld, PinRecipes.choose(builtIn, forOld, 0));
        assertSame(builtIn, PinRecipes.choose(builtIn, forOld, 101));
    }

    @Test
    public void onlyHearthsOwnRepositoryCanStandInForTheAddress() {
        assertTrue(PinRecipes.validOverride(
                "https://raw.githubusercontent.com/theSiegs/Hearth/feature/pin-recipes-data/pin-entry/recipes.json"));
        assertFalse(PinRecipes.validOverride(null));
        assertFalse(PinRecipes.validOverride("https://raw.githubusercontent.com/someone/Hearth/master/x.json"));
        assertFalse(PinRecipes.validOverride("http://raw.githubusercontent.com/theSiegs/Hearth/master/x.json"));
        assertFalse(PinRecipes.validOverride("https://raw.githubusercontent.com/theSiegs/Hearth/../../x/y.json"));
        assertFalse(PinRecipes.validOverride("https://raw.githubusercontent.com/theSiegs/Hearth/master/x.json?a=b"));
        assertFalse(PinRecipes.validOverride("https://raw.githubusercontent.com/theSiegs/Hearth/master/x.txt"));
        assertFalse(PinRecipes.validOverride("https://raw.githubusercontent.com/theSiegs/Hearth@evil.example/x.json"));
    }

    // ---- Phrases: what the Java recipes' regular expressions found, without one ----

    @Test
    public void phrasesFindWhatTheOldPatternsFound() {
        Pattern entered = Pattern.compile("(\\d{1,3}) of (\\d{1,3}) values entered");
        Pattern focused = Pattern.compile("numeric keyboard, ([^,]+), button");
        PinTemplate count = PinTemplate.parse(PinTemplate.Mode.CONTAINS, "{n} of {n} values entered");
        PinTemplate key = PinTemplate.parse(PinTemplate.Mode.CONTAINS, "numeric keyboard, {field}, button");
        String[] said = {"1 of 4 values entered", "entered: 12 of 4 values entered.", "1234 of 4 values entered",
                "of 4 values entered", "3 of 44 values entered", ", numeric keyboard, 7, button, actions",
                "numeric keyboard, delete, button", "numeric keyboard, , button", "numeric keyboard, a, b, button",
                "numeric keyboard, x, nope numeric keyboard, 5, button", "nothing here", ""};
        for (String s : said) {
            Matcher m = entered.matcher(s);
            assertEquals(s, m.find() ? m.group(1) : null, count.match(s));
            Matcher k = focused.matcher(s);
            assertEquals(s, k.find() ? k.group(1) : null, key.match(s));
        }
        PinTemplate digit = PinTemplate.parse(PinTemplate.Mode.EQUALS, "{d}");
        PinTemplate echo = PinTemplate.parse(PinTemplate.Mode.EQUALS, "{d},");
        for (String s : new String[] {"4", "4,", "44", "a", ",", "", "4,,"}) {
            assertEquals(s, s.matches("\\d,?"), digit.match(s) != null || echo.match(s) != null);
        }
        // Long words don't make it slow
        String noise = repeat("1", PinTemplate.TEXT_MAX * 2);
        long start = System.nanoTime();
        assertNull(count.match(noise));
        assertNull(key.match("numeric keyboard, " + repeat("x", PinTemplate.TEXT_MAX)));
        assertTrue((System.nanoTime() - start) < 2_000_000_000L);
    }
}
