package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** A phone's session on the remote API: its commands, the TV's answers, and the kid rules. */
public class RemoteSessionTest {
    /** A TV that records what it was asked. */
    static final class FakeTv implements RemoteSession.Tv {
        final List<String> did = new ArrayList<>();
        JSONObject state;
        boolean mediaSession = true;
        boolean seekable = true;

        FakeTv() throws Exception {
            state = new JSONObject().put("on", true).put("app", "com.example.video").put("title", "A film")
                    .put("positionMs", 1000).put("positionAtMs", 5000);
        }

        @Override public JSONObject state() {
            try {
                return new JSONObject(state.toString());
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }

        @Override public void media(String action) throws RemoteSession.Refused {
            if (!mediaSession) throw new RemoteSession.Refused(RemoteSession.NO_SESSION);
            did.add("media " + action);
        }

        @Override public void seekTo(long positionMs) throws RemoteSession.Refused {
            if (!seekable) throw new RemoteSession.Refused(RemoteSession.UNSUPPORTED);
            did.add("seekTo " + positionMs);
        }

        @Override public void seekBy(long deltaMs) {
            did.add("seekBy " + deltaMs);
        }

        @Override public void launch(String pkg) {
            did.add("launch " + pkg);
        }

        @Override public void volumeSet(int percent) {
            did.add("volume " + percent);
        }

        @Override public void volumeStep(int direction) {
            did.add("step " + direction);
        }

        @Override public void mute(boolean muted) {
            did.add("mute " + muted);
        }

        @Override public JSONArray apps() {
            try {
                return new JSONArray()
                        .put(new JSONObject().put("pkg", "com.example.video").put("label", "Video"))
                        .put(new JSONObject().put("pkg", "com.example.game").put("label", "Game"));
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }

        @Override public boolean allowed(String pkg) {
            return !"com.example.game".equals(pkg);
        }

        @Override public byte[] art(String id) {
            return "art1".equals(id) ? new byte[]{1, 2, 3} : null;
        }
    }

    private static byte[] msg(String json) {
        return json.getBytes(StandardCharsets.UTF_8);
    }

    private static JSONObject one(List<JSONObject> out) {
        assertEquals(1, out.size());
        return out.get(0);
    }

    @Test
    public void helloAnswersTheStateAndNothingWorksBeforeIt() throws Exception {
        FakeTv tv = new FakeTv();
        RemoteSession session = new RemoteSession(tv, true);
        JSONObject before = one(session.handle(msg("{\"t\":\"media\",\"do\":\"pause\"}")));
        assertEquals("bad_request", before.getString("code"));
        assertTrue(tv.did.isEmpty());

        assertEquals("unsupported", one(session.handle(msg("{\"t\":\"hello\",\"v\":2}"))).getString("code"));
        JSONObject state = one(session.handle(msg("{\"t\":\"hello\",\"v\":1,\"client\":\"Glint\"}")));
        assertEquals("state", state.getString("t"));
        assertEquals("A film", state.getString("title"));
    }

    @Test
    public void stateGoesOutOnlyWhenItChanges() throws Exception {
        FakeTv tv = new FakeTv();
        RemoteSession session = new RemoteSession(tv, true);
        assertNull(session.stateIfChanged()); // not before hello
        session.handle(msg("{\"t\":\"hello\",\"v\":1}"));
        assertNull(session.stateIfChanged());
        tv.state.put("positionAtMs", 9000); // only the read time moved
        assertNull(session.stateIfChanged());
        tv.state.put("playing", false);
        assertFalse(session.stateIfChanged().getBoolean("playing"));
        assertNull(session.stateIfChanged());
    }

    @Test
    public void mediaSeekAndVolumeReachTheTv() throws Exception {
        FakeTv tv = new FakeTv();
        RemoteSession session = new RemoteSession(tv, false);
        session.handle(msg("{\"t\":\"hello\",\"v\":1}"));
        assertTrue(session.handle(msg("{\"t\":\"media\",\"do\":\"toggle\"}")).isEmpty());
        session.handle(msg("{\"t\":\"seek\",\"byMs\":-30000}"));
        session.handle(msg("{\"t\":\"seek\",\"toMs\":-5}"));
        session.handle(msg("{\"t\":\"volume\",\"set\":40}"));
        session.handle(msg("{\"t\":\"volume\",\"step\":-1}"));
        session.handle(msg("{\"t\":\"volume\",\"mute\":true}"));
        assertEquals(List.of("media toggle", "seekBy -30000", "seekTo 0", "volume 40", "step -1", "mute true"), tv.did);

        assertEquals("bad_request", one(session.handle(msg("{\"t\":\"volume\",\"set\":140}"))).getString("code"));
        assertEquals("unsupported", one(session.handle(msg("{\"t\":\"media\",\"do\":\"eject\"}"))).getString("code"));
        tv.mediaSession = false;
        JSONObject error = one(session.handle(msg("{\"t\":\"media\",\"do\":\"play\"}")));
        assertEquals("no_session", error.getString("code"));
        assertEquals("media", error.getString("for"));
        tv.seekable = false;
        assertEquals("unsupported", one(session.handle(msg("{\"t\":\"seek\",\"toMs\":1}"))).getString("code"));
        assertEquals("unsupported", one(session.handle(msg("{\"t\":\"key\",\"k\":\"up\"}"))).getString("code"));
        assertEquals("bad_request", one(session.handle(msg("not json"))).getString("code"));
    }

    @Test
    public void aRestrictedPhoneCanTOpenAHeldApp() throws Exception {
        FakeTv tv = new FakeTv();
        RemoteSession restricted = new RemoteSession(tv, false);
        restricted.handle(msg("{\"t\":\"hello\",\"v\":1}"));
        assertTrue(restricted.restricted());
        assertEquals("not_allowed", one(restricted.handle(msg("{\"t\":\"launch\",\"pkg\":\"com.example.game\"}")))
                .getString("code"));
        restricted.handle(msg("{\"t\":\"launch\",\"pkg\":\"com.example.video\"}"));
        assertEquals(List.of("launch com.example.video"), tv.did);

        JSONArray apps = one(restricted.handle(msg("{\"t\":\"apps\"}"))).getJSONArray("list");
        assertTrue(apps.getJSONObject(0).getBoolean("allowed"));
        assertFalse(apps.getJSONObject(1).getBoolean("allowed"));
    }

    @Test
    public void anAdultPhoneThatSaysItIsAKidSIsRestricted() throws Exception {
        FakeTv tv = new FakeTv();
        RemoteSession adult = new RemoteSession(tv, true);
        adult.handle(msg("{\"t\":\"hello\",\"v\":1}"));
        assertFalse(adult.restricted());
        adult.handle(msg("{\"t\":\"launch\",\"pkg\":\"com.example.game\"}"));
        assertEquals(List.of("launch com.example.game"), tv.did);

        RemoteSession kid = new RemoteSession(tv, true);
        kid.handle(msg("{\"t\":\"hello\",\"v\":1,\"kid\":true}"));
        assertTrue(kid.restricted());
        // kid:false never grants
        RemoteSession restricted = new RemoteSession(tv, false);
        restricted.handle(msg("{\"t\":\"hello\",\"v\":1,\"kid\":false}"));
        assertTrue(restricted.restricted());
    }

    @Test
    public void artIsFetchedByIdAndByeEnds() throws Exception {
        FakeTv tv = new FakeTv();
        RemoteSession session = new RemoteSession(tv, true);
        session.handle(msg("{\"t\":\"hello\",\"v\":1}"));
        JSONObject art = one(session.handle(msg("{\"t\":\"art\",\"id\":\"art1\"}")));
        assertEquals("AQID", art.getString("data"));
        assertEquals("image/jpeg", art.getString("mime"));
        assertEquals("no_session", one(session.handle(msg("{\"t\":\"art\",\"id\":\"gone\"}"))).getString("code"));
        session.handle(msg("{\"t\":\"bye\"}"));
        assertTrue(session.ended());
        assertNull(session.stateIfChanged());
    }

    @Test
    public void phonesPairRestrictedAndAnAdultMarkSurvivesPairingAgain() {
        RemotePhones phones = new RemotePhones(new FakeContext("com.thesiegs.hearth"));
        phones.add("aa", "Alex's phone", 10);
        assertFalse(phones.get("aa").adult);
        assertTrue(phones.setAdult("aa", true));
        phones.add("aa", "Alex's phone", 20);
        assertTrue(phones.get("aa").adult);
        assertEquals(20, phones.get("aa").pairedAt);
        phones.add("bb", "Sam's phone", 30);
        assertEquals("bb", phones.list().get(0).fingerprint);
        assertTrue(phones.remove("aa"));
        assertNull(phones.get("aa"));
        assertFalse(phones.setAdult("aa", true));
    }
}
