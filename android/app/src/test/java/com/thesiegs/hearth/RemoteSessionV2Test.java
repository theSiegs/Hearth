package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Version 2 of the remote API (docs/tv-remote-api.md, V2): told roles, welcome, time, sync, kids, ask, errors. */
public class RemoteSessionV2Test {
    static final String KID = "user:10";
    static final String OTHER_KID = "user:11";
    static final String ADULT = "user:0";
    static final String YOUTUBE = "com.google.android.youtube.tv";
    static final String GAME = "com.example.game";
    static final long NOW = 1_794_336_012_400L;

    /** A TV with a kid's entry, as HaAllowance keeps it from a person document. */
    static final class TvV2 extends RemoteSessionTest.FakeTv {
        String mode = RemoteSession.MODE_LOCAL;
        String front = KID;
        final Map<String, JSONObject> entries = new HashMap<>();
        JSONObject rules;
        final List<String> asked = new ArrayList<>();
        JSONObject askAnswer;

        TvV2() throws Exception {
            state.put("app", YOUTUBE);
            entries.put(KID, RemoteSessionV2Test.entry(document(10, 42, null, null)));
            rules = new JSONObject().put("all", new JSONObject().put("weekday", 120).put("weekend", 180));
            askAnswer = new JSONObject().put("ok", true).put("request",
                    new JSONObject().put("id", "r1").put("status", "pending"));
        }

        @Override public boolean allowed(String pkg) {
            return true; // the profile in front holds nothing: only a kid's own rules can
        }

        @Override public String mode() {
            return mode;
        }

        @Override public long now() {
            return NOW;
        }

        @Override public String zone() {
            return "America/Denver";
        }

        @Override public JSONArray tvs() {
            try {
                return new JSONArray().put(new JSONObject().put("id", "9c1e44d07a2b11f0").put("n", "the kitchen TV"));
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }

        @Override public String frontProfileKey() {
            return front;
        }

        @Override public JSONObject entry(String profileKey) {
            return entries.get(profileKey);
        }

        @Override public JSONObject person(String profileKey) {
            try {
                return new JSONObject().put("id", "a:" + profileKey.replace("user:", "p"))
                        .put("name", KID.equals(profileKey) ? "Sam" : "Alex");
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }

        @Override public List<String> kids() {
            return List.of(KID);
        }

        @Override public JSONObject rules(String profileKey) {
            return KID.equals(profileKey) ? rules : null;
        }

        @Override public JSONObject askHomeAssistant(String profileKey, int minutes, String group) {
            asked.add(profileKey + " " + minutes + " " + group);
            return askAnswer;
        }
    }

    /** A person document: All with [allLeft] (78 used), YouTube with [youtubeLeft], Games out of time. */
    static JSONObject document(int youtubeLeft, int allLeft, JSONObject lock, JSONObject request) throws Exception {
        JSONArray groups = new JSONArray()
                .put(new JSONObject().put("id", "all").put("name", "All screen time").put("minutes_left", allLeft)
                        .put("minutes_used", 78).put("apps", new JSONArray())
                        .put("except", new JSONArray().put("com.android.dialer")))
                .put(new JSONObject().put("id", "youtube").put("name", "YouTube").put("minutes_left", youtubeLeft)
                        .put("apps", new JSONArray().put(YOUTUBE)))
                .put(new JSONObject().put("id", "games").put("name", "Games").put("minutes_left", 0)
                        .put("apps", new JSONArray().put(GAME)));
        JSONObject person = new JSONObject().put("groups", groups).put("locked", lock != null)
                .put("next_lock", new JSONObject().put("at", "2099-01-01T20:30:00-07:00").put("kind", "bedtime"));
        if (lock != null) person.put("lock", lock);
        if (request != null) person.put("request", request);
        return person;
    }

    static JSONObject entry(JSONObject person) throws Exception {
        return HaAllowance.profilesFromDocument(new JSONObject().put("profiles", new JSONObject().put("p", person)))
                .getJSONObject("p");
    }

    private static byte[] msg(String json) {
        return json.getBytes(StandardCharsets.UTF_8);
    }

    private static JSONObject one(List<JSONObject> out) {
        assertEquals(1, out.size());
        return out.get(0);
    }

    private static RemoteSession.Fixed phone(String role, String kid) {
        return new RemoteSession.Fixed(new RemoteSession.Binding(role, kid));
    }

    private static RemoteSession v2(TvV2 tv, RemoteSession.Phone phone) {
        RemoteSession session = new RemoteSession(tv, phone);
        session.handle(msg("{\"t\":\"hello\",\"v\":2,\"client\":\"Glint - Pixel\"}"));
        return session;
    }

    @Test
    public void aV1HelloOnAV2TvIsVersion1Exactly() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession session = new RemoteSession(tv, phone(RemoteSession.ROLE_PARENT, null));
        JSONObject state = one(session.handle(msg("{\"t\":\"hello\",\"v\":1}")));
        assertEquals("state", state.getString("t"));
        assertFalse(state.has("time"));
        // No request ids, no ok, no new messages
        assertTrue(session.handle(msg("{\"t\":\"media\",\"do\":\"pause\",\"id\":\"m1\"}")).isEmpty());
        JSONObject error = one(session.handle(msg("{\"t\":\"sync\",\"id\":\"s1\"}")));
        assertEquals("unsupported", error.getString("code"));
        assertFalse(error.has("re"));
        assertFalse(error.has("message"));
    }

    @Test
    public void aV2HelloGetsWelcomeThenStateWithTime() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession session = new RemoteSession(tv, phone(RemoteSession.ROLE_KID, KID));
        List<JSONObject> out = session.handle(msg("{\"t\":\"hello\",\"v\":2,\"client\":\"HearthTube - Pixel\"}"));
        assertEquals(2, out.size());
        JSONObject welcome = out.get(0);
        assertEquals("welcome", welcome.getString("t"));
        assertEquals(2, welcome.getInt("v"));
        assertEquals("kid", welcome.getString("role"));
        assertEquals("local", welcome.getString("mode"));
        assertEquals("Sam", welcome.getJSONObject("person").getString("name"));
        assertEquals("9c1e44d07a2b11f0", welcome.getJSONArray("tvs").getJSONObject(0).getString("id"));
        assertEquals(NOW, welcome.getLong("now"));
        assertEquals("America/Denver", welcome.getString("tz"));
        assertFalse(welcome.has("ha"));

        JSONObject time = out.get(1).getJSONObject("time");
        assertEquals(10, time.getInt("minutesLeft"));
        assertEquals("youtube", time.getJSONObject("group").getString("id"));
        assertFalse(time.getBoolean("locked"));
        assertEquals("2099-01-01T20:30:00-07:00", time.getString("until"));
    }

    @Test
    public void timeIsOnlyForTheProfileInFrontThatTheRoleMaySee() throws Exception {
        TvV2 tv = new TvV2();
        // A parent's phone: the profile in front's
        assertEquals(10, v2(tv, phone(RemoteSession.ROLE_PARENT, null)).handle(msg("{\"t\":\"hello\",\"v\":2}"))
                .get(1).getJSONObject("time").getInt("minutesLeft"));
        // Not this one: never
        assertTrue(new RemoteSession(tv, phone(RemoteSession.ROLE_NONE, null))
                .handle(msg("{\"t\":\"hello\",\"v\":2}")).get(1).isNull("time"));
        // Another kid's phone: not this kid's minutes
        assertTrue(new RemoteSession(tv, phone(RemoteSession.ROLE_KID, OTHER_KID))
                .handle(msg("{\"t\":\"hello\",\"v\":2}")).get(1).isNull("time"));
        // An adult's profile in front has no limit
        tv.front = ADULT;
        assertTrue(new RemoteSession(tv, phone(RemoteSession.ROLE_PARENT, null))
                .handle(msg("{\"t\":\"hello\",\"v\":2}")).get(1).isNull("time"));
    }

    @Test
    public void requestIdsAreAnsweredOkOrWithTheirError() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession session = v2(tv, phone(RemoteSession.ROLE_PARENT, null));
        JSONObject ok = one(session.handle(msg("{\"t\":\"media\",\"do\":\"pause\",\"id\":\"m1\"}")));
        assertEquals("ok", ok.getString("t"));
        assertEquals("m1", ok.getString("re"));
        // Without an id, nothing as in v1
        assertTrue(session.handle(msg("{\"t\":\"media\",\"do\":\"play\"}")).isEmpty());
        JSONObject error = one(session.handle(msg("{\"t\":\"volume\",\"set\":140,\"id\":\"v1\"}")));
        assertEquals("bad_request", error.getString("code"));
        assertEquals("v1", error.getString("re"));
        assertEquals("volume", error.getString("for"));
        assertEquals("bad_request", error.getString("message"));
        assertEquals("bad_request", one(session.handle(msg("{\"t\":\"media\",\"do\":\"play\",\"id\":7}")))
                .getString("code"));
        JSONObject apps = one(session.handle(msg("{\"t\":\"apps\",\"id\":\"a1\"}")));
        assertEquals("a1", apps.getString("re"));
    }

    @Test
    public void artKeepsV1sIdUnlessTheArtComesAsArt() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession session = v2(tv, phone(RemoteSession.ROLE_PARENT, null));
        JSONObject art = one(session.handle(msg("{\"t\":\"art\",\"id\":\"art1\"}")));
        assertEquals("art1", art.getString("id"));
        assertFalse(art.has("re"));
        art = one(session.handle(msg("{\"t\":\"art\",\"art\":\"art1\",\"id\":\"q1\"}")));
        assertEquals("art1", art.getString("id"));
        assertEquals("q1", art.getString("re"));
    }

    @Test
    public void everyMessageIsCheckedAgainstTheRole() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession none = v2(tv, phone(RemoteSession.ROLE_NONE, null));
        RemoteSession kid = v2(tv, phone(RemoteSession.ROLE_KID, KID));
        RemoteSession parent = v2(tv, phone(RemoteSession.ROLE_PARENT, null));
        String ask = "{\"t\":\"ask\",\"id\":\"q\",\"ask\":\"a7\",\"minutes\":30}";
        assertEquals("not_bound", one(none.handle(msg(ask))).getString("code"));
        assertEquals("forbidden", one(parent.handle(msg(ask))).getString("code"));
        for (String type : new String[]{"kids", "answer", "hold", "hold_end", "ha_ticket"}) {
            String m = "{\"t\":\"" + type + "\",\"id\":\"x\"}";
            assertEquals(type, "forbidden", one(none.handle(msg(m))).getString("code"));
            assertEquals(type, "forbidden", one(kid.handle(msg(m))).getString("code"));
        }
        // Mode local: no one-tap HA; answers and holds aren't built on the TV yet
        assertEquals("forbidden", one(parent.handle(msg("{\"t\":\"ha_ticket\",\"id\":\"h\"}"))).getString("code"));
        assertEquals("unsupported", one(parent.handle(msg("{\"t\":\"answer\",\"ask\":\"a7\",\"minutes\":0}")))
                .getString("code"));
        // Mode ha: Home Assistant answers and holds
        tv.mode = RemoteSession.MODE_HA;
        for (String type : new String[]{"answer", "hold", "hold_end"}) {
            assertEquals(type, "ha_rules", one(parent.handle(msg("{\"t\":\"" + type + "\"}"))).getString("code"));
        }
        assertEquals("unsupported", one(parent.handle(msg("{\"t\":\"ha_ticket\",\"id\":\"h\"}"))).getString("code"));
    }

    @Test
    public void aKidsPhoneOpensOnlyWhatTheKidsOwnRulesAllow() throws Exception {
        TvV2 tv = new TvV2();
        tv.front = ADULT; // an adult's profile in front holds nothing
        RemoteSession kid = v2(tv, phone(RemoteSession.ROLE_KID, KID));
        assertEquals("not_allowed", one(kid.handle(msg("{\"t\":\"launch\",\"pkg\":\"" + GAME + "\"}")))
                .getString("code"));
        kid.handle(msg("{\"t\":\"launch\",\"pkg\":\"" + YOUTUBE + "\"}"));
        assertEquals(List.of("launch " + YOUTUBE), tv.did);
        JSONArray apps = one(kid.handle(msg("{\"t\":\"apps\"}"))).getJSONArray("list");
        assertTrue(apps.getJSONObject(0).getBoolean("allowed"));
        assertFalse(apps.getJSONObject(1).getBoolean("allowed")); // com.example.game
        // A parent's phone opens it
        RemoteSession parent = v2(tv, phone(RemoteSession.ROLE_PARENT, null));
        parent.handle(msg("{\"t\":\"launch\",\"pkg\":\"" + GAME + "\"}"));
        assertEquals("launch " + GAME, tv.did.get(1));
    }

    @Test
    public void syncTellsRoleModeRulesAndTheKidsTime() throws Exception {
        TvV2 tv = new TvV2();
        JSONObject synced = one(v2(tv, phone(RemoteSession.ROLE_NONE, null))
                .handle(msg("{\"t\":\"sync\",\"id\":\"s1\"}")));
        assertEquals("synced", synced.getString("t"));
        assertEquals("s1", synced.getString("re"));
        assertEquals("none", synced.getString("role"));
        assertEquals("local", synced.getString("mode"));
        assertFalse(synced.has("time"));

        RemoteSession kid = v2(tv, phone(RemoteSession.ROLE_KID, KID));
        synced = one(kid.handle(msg("{\"t\":\"sync\",\"id\":\"s2\",\"have\":\"r-none\",\"usage\":[]}")));
        JSONObject rules = synced.getJSONObject("rules");
        String tag = rules.getString("tag");
        assertTrue(tag.startsWith("r-"));
        assertEquals("America/Denver", rules.getString("tz"));
        assertEquals(120, rules.getJSONObject("all").getInt("weekday"));
        JSONObject time = synced.getJSONObject("time");
        assertEquals(42, time.getJSONObject("all").getInt("left"));
        assertEquals(78, time.getJSONObject("all").getInt("used"));
        assertEquals(10, time.getJSONObject("groups").getJSONObject("youtube").getInt("left"));
        assertEquals(0, time.getJSONObject("groups").getJSONObject("games").getInt("left"));
        assertEquals("2026-11-10", time.getString("day"));
        assertEquals(NOW, time.getLong("asOf"));
        assertTrue(time.isNull("hold"));
        assertEquals("not_taken", synced.getString("usage"));
        assertFalse(synced.has("ask"));
        // The same rules: not sent again
        synced = one(kid.handle(msg("{\"t\":\"sync\",\"have\":\"" + tag + "\"}")));
        assertTrue(synced.isNull("rules"));
        tv.rules.put("bedtime", new JSONObject().put("from", "20:30").put("to", "07:00"));
        assertNotEquals(tag, one(kid.handle(msg("{\"t\":\"sync\",\"have\":\"" + tag + "\"}")))
                .getJSONObject("rules").getString("tag"));
        // Mode ha: never rules, usage not taken
        tv.mode = RemoteSession.MODE_HA;
        synced = one(kid.handle(msg("{\"t\":\"sync\",\"have\":\"" + tag + "\",\"usage\":[]}")));
        assertTrue(synced.isNull("rules"));
        assertEquals("ha", synced.getString("mode"));
        assertEquals("not_taken", synced.getString("usage"));
    }

    @Test
    public void standingDownMakesThePairingNotThisOne() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession.Fixed tube = phone(RemoteSession.ROLE_KID, KID);
        JSONObject synced = one(v2(tv, tube).handle(msg("{\"t\":\"sync\",\"standDown\":true}")));
        assertTrue(tube.stoodDown);
        assertEquals("none", synced.getString("role"));
        assertFalse(synced.has("time"));
    }

    @Test
    public void kidsListsEveryKidsTimeForAParent() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession parent = v2(tv, phone(RemoteSession.ROLE_PARENT, null));
        JSONObject kids = one(parent.handle(msg("{\"t\":\"kids\",\"id\":\"k1\"}")));
        assertEquals("k1", kids.getString("re"));
        JSONObject sam = kids.getJSONArray("list").getJSONObject(0);
        assertEquals("Sam", sam.getJSONObject("person").getString("name"));
        assertEquals(42, sam.getJSONObject("time").getJSONObject("all").getInt("left"));
        assertEquals(10, sam.getJSONObject("time").getJSONObject("groups").getJSONObject("youtube").getInt("left"));
        assertEquals(0, sam.getJSONArray("asks").length());
        // Mode ha: display only, no asks list
        tv.mode = RemoteSession.MODE_HA;
        sam = one(parent.handle(msg("{\"t\":\"kids\"}"))).getJSONArray("list").getJSONObject(0);
        assertFalse(sam.has("asks"));
    }

    @Test
    public void aKidsAskGoesToHomeAssistantAndItsAnswerComesBack() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession.Fixed sams = phone(RemoteSession.ROLE_KID, KID);
        RemoteSession kid = v2(tv, sams);
        String ask = "{\"t\":\"ask\",\"id\":\"q9\",\"ask\":\"a7\",\"minutes\":30,\"group\":\"youtube\"}";
        // Mode local: household asks aren't built yet
        assertEquals("unsupported", one(kid.handle(msg(ask))).getString("code"));
        assertTrue(tv.asked.isEmpty());

        tv.mode = RemoteSession.MODE_HA;
        JSONObject ok = one(kid.handle(msg(ask)));
        assertEquals("ok", ok.getString("t"));
        assertEquals("q9", ok.getString("re"));
        assertEquals(List.of(KID + " 30 youtube"), tv.asked);
        // A resend is the same ask
        assertEquals("ok", one(kid.handle(msg(ask))).getString("t"));
        assertEquals(1, tv.asked.size());
        assertEquals("waiting", one(kid.handle(msg("{\"t\":\"sync\"}"))).getJSONObject("ask").getString("status"));
        assertTrue(kid.pushes().isEmpty());

        // Home Assistant's status says it was approved
        tv.entries.put(KID, entry(document(40, 72, null, new JSONObject().put("id", "r1").put("status", "approved")
                .put("minutes", 30).put("answered", "2026-11-10T10:30:00-07:00"))));
        List<JSONObject> pushes = kid.pushes();
        JSONObject answered = pushes.get(pushes.size() - 1);
        assertEquals("answered", answered.getString("t"));
        assertEquals("a7", answered.getString("ask"));
        assertEquals(30, answered.getInt("minutes"));
        assertEquals("an adult", answered.getString("by"));
        // Once
        for (JSONObject push : kid.pushes()) assertNotEquals("answered", push.getString("t"));
        JSONObject synced = one(kid.handle(msg("{\"t\":\"sync\"}")));
        assertEquals("a7", synced.getJSONObject("ask").getString("id"));
        assertEquals("approved", synced.getJSONObject("ask").getString("status"));
    }

    @Test
    public void anAskHomeAssistantRefusesOrCantHear() throws Exception {
        TvV2 tv = new TvV2();
        tv.mode = RemoteSession.MODE_HA;
        RemoteSession kid = v2(tv, phone(RemoteSession.ROLE_KID, KID));
        tv.askAnswer = new JSONObject().put("error", "too_often").put("retry_in", 600);
        JSONObject error = one(kid.handle(msg("{\"t\":\"ask\",\"id\":\"q1\",\"ask\":\"a1\",\"minutes\":15}")));
        assertEquals("too_often", error.getString("code"));
        assertEquals(600, error.getInt("retryInSec"));
        assertEquals("q1", error.getString("re"));

        // Home Assistant away: still ok, and it goes at the next sync
        tv.askAnswer = new JSONObject().put("error", "unreachable");
        assertEquals("ok", one(kid.handle(msg("{\"t\":\"ask\",\"id\":\"q2\",\"ask\":\"a2\",\"minutes\":15}")))
                .getString("t"));
        assertEquals("waiting", one(kid.handle(msg("{\"t\":\"sync\"}"))).getJSONObject("ask").getString("status"));
        tv.askAnswer = new JSONObject().put("ok", true).put("request", new JSONObject().put("id", "r2"));
        kid.handle(msg("{\"t\":\"sync\"}"));
        assertEquals(4, tv.asked.size()); // refused, unreachable, retried while unreachable, then through

        assertEquals("bad_request", one(kid.handle(msg("{\"t\":\"ask\",\"ask\":\"a3\",\"minutes\":0}")))
                .getString("code"));
    }

    @Test
    public void unpairForgetsThePhoneAndEnds() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession.Fixed alexs = phone(RemoteSession.ROLE_PARENT, null);
        RemoteSession session = v2(tv, alexs);
        JSONObject ok = one(session.handle(msg("{\"t\":\"unpair\",\"id\":\"u1\"}")));
        assertEquals("u1", ok.getString("re"));
        assertTrue(alexs.unpaired);
        assertTrue(session.ended());
    }

    @Test
    public void aMinuteTickingDownIsNotAChangeButMoreTimeIs() throws Exception {
        TvV2 tv = new TvV2();
        RemoteSession session = v2(tv, phone(RemoteSession.ROLE_PARENT, null));
        assertTrue(session.pushes().isEmpty());
        tv.entries.put(KID, entry(document(9, 41, null, null)));
        assertTrue(session.pushes().isEmpty());
        tv.entries.put(KID, entry(document(39, 71, null, null)));
        JSONObject state = one(session.pushes());
        assertEquals(39, state.getJSONObject("time").getInt("minutesLeft"));
        // Bedtime starts: a change
        tv.entries.put(KID, entry(document(39, 71, new JSONObject().put("kind", "bedtime")
                .put("until", "2099-01-02T07:00:00-07:00"), null)));
        JSONObject time = one(session.pushes()).getJSONObject("time");
        assertTrue(time.getBoolean("locked"));
        assertEquals("bedtime", time.getString("why"));
        assertEquals("2099-01-02T07:00:00-07:00", time.getString("until"));
    }

    @Test
    public void phonesKeepTheirToldRole() {
        RemotePhones phones = new RemotePhones(new FakeContext("com.thesiegs.hearth"));
        phones.add("aa", "Glint - Pixel", 10);
        assertEquals(RemoteSession.ROLE_NONE, phones.get("aa").role);
        assertFalse(phones.setRole("aa", RemoteSession.ROLE_KID, null)); // a kid's phone needs its kid
        assertFalse(phones.setRole("aa", "owner", null));
        assertTrue(phones.setRole("aa", RemoteSession.ROLE_KID, KID));
        assertEquals(KID, phones.get("aa").binding().profileKey);
        phones.setLastAsk("aa", new JSONObject());
        // Bound to another kid: the last ask was someone else's
        assertTrue(phones.setRole("aa", RemoteSession.ROLE_KID, OTHER_KID));
        assertNull(phones.lastAsk("aa"));
        phones.add("aa", "Glint - Pixel", 20); // pairing again keeps the binding
        assertEquals(OTHER_KID, phones.get("aa").profileKey);
        assertTrue(phones.setAdult("aa", true));
        assertTrue(phones.get("aa").adult());
        assertNull(phones.get("aa").profileKey);
    }
}
