package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.Test;

/** The secrets of a copy between TVs: what the receiving TV accepts of them. */
public class ShareSecretsTest {
    /** A vault and a pairing table in memory. */
    private static final class Fake implements ShareSecrets.Target {
        final Map<String, String> chosen = new HashMap<>();
        final Map<String, String> status = new HashMap<>();
        final List<String> saved = new ArrayList<>();
        final List<String> kids = new ArrayList<>();

        @Override
        public boolean isKids(String profileKey) {
            return kids.contains(profileKey);
        }

        @Override
        public String chosenProfile(String pkg, String profileKey) {
            return chosen.get(pkg + "|" + profileKey);
        }

        @Override
        public String status(String owner, String pkg, String appProfile) {
            String s = status.get(owner + "|" + pkg + "|" + appProfile);
            return s == null ? PinVault.STATUS_NONE : s;
        }

        @Override
        public boolean save(String owner, String pkg, String appProfile, char[] pin) {
            saved.add(owner + "|" + pkg + "|" + appProfile + "|" + new String(pin));
            return true;
        }
    }

    private static final String NETFLIX = "com.netflix.ninja";

    private static String pins(String... lines) {
        return "{\"v\":1,\"pins\":[" + String.join(",", lines) + "]}";
    }

    private static String line(String profile, String pkg, String name, String pin) {
        return "{" + (profile == null ? "" : "\"profile\":\"" + profile + "\",") + "\"pkg\":\"" + pkg
                + "\",\"appProfile\":\"" + name + "\",\"pin\":\"" + pin + "\"}";
    }

    @Test
    public void aPinGoesToTheProfileItWasMappedToWhenPairedWithThatAppProfile() {
        Fake here = new Fake();
        here.chosen.put(NETFLIX + "|user:0:alex", "Alex");
        Map<String, Object> result = ShareSecrets.applyPins(pins(line("p1", NETFLIX, "alex", "1234")),
                Collections.singletonMap("p1", "user:0:alex"), here);
        assertEquals(1, result.get("added"));
        assertEquals(Collections.singletonList("user:0:alex|" + NETFLIX + "|alex|1234"), here.saved);
    }

    @Test
    public void aPinForAnAppProfileNobodyHereIsPairedWithIsSkipped() {
        Fake here = new Fake();
        here.chosen.put(NETFLIX + "|user:0:alex", "Someone else");
        Map<String, Object> result = ShareSecrets.applyPins(pins(line("p1", NETFLIX, "alex", "1234")),
                Collections.singletonMap("p1", "user:0:alex"), here);
        assertEquals(1, result.get("skipped"));
        assertTrue(here.saved.isEmpty());
    }

    @Test
    public void aProfileTheParentDidNotCopyGetsNothing() {
        Fake here = new Fake();
        Map<String, Object> result = ShareSecrets.applyPins(pins(line("p2", NETFLIX, "sam", "1234")),
                Collections.singletonMap("p1", "user:0:alex"), here);
        assertEquals(1, result.get("skipped"));
        assertTrue(here.saved.isEmpty());
    }

    @Test
    public void aPinThatWorksHereStaysAndOneTheAppRefusedIsReplaced() {
        Fake here = new Fake();
        here.chosen.put(NETFLIX + "|user:0:alex", "alex");
        here.status.put("user:0:alex|" + NETFLIX + "|alex", PinVault.STATUS_SAVED);
        Map<String, String> targets = Collections.singletonMap("p1", "user:0:alex");
        assertEquals(1, ShareSecrets.applyPins(pins(line("p1", NETFLIX, "alex", "1234")), targets, here).get("kept"));
        assertTrue(here.saved.isEmpty());

        here.status.put("user:0:alex|" + NETFLIX + "|alex", PinVault.STATUS_REJECTED);
        assertEquals(1, ShareSecrets.applyPins(pins(line("p1", NETFLIX, "alex", "1234")), targets, here).get("added"));
    }

    @Test
    public void aKidsProfileGetsNoGoogleTvPin() {
        Fake here = new Fake();
        here.kids.add("user:11");
        String google = LauncherAccessibilityService.GOOGLE_TV_PACKAGE;
        Map<String, Object> result = ShareSecrets.applyPins(pins(line("p1", google, "pin", "1234")),
                Collections.singletonMap("p1", "user:11"), here);
        assertEquals(1, result.get("skipped"));
        assertTrue(here.saved.isEmpty());

        Map<String, Object> adult = ShareSecrets.applyPins(pins(line("p1", google, "pin", "1234")),
                Collections.singletonMap("p1", "user:0:alex"), here);
        assertEquals(1, adult.get("added"));
    }

    @Test
    public void theWholeTvContentPinIsOnlyForParamountsContentPin() {
        Fake here = new Fake();
        Map<String, String> none = Collections.emptyMap();
        assertEquals(1, ShareSecrets.applyPins(pins(line(null, ContentPin.PACKAGE, ContentPin.VAULT_PROFILE, "1234")),
                none, here).get("added"));
        assertEquals(1, ShareSecrets.applyPins(pins(line(null, NETFLIX, "alex", "1234")), none, here).get("skipped"));
        assertEquals(1, ShareSecrets.applyPins(pins(line(null, ContentPin.PACKAGE, "alex", "1234")), none, here)
                .get("skipped"));
    }

    @Test
    public void badLinesAreSkippedAndNeverSaved() {
        Fake here = new Fake();
        here.chosen.put(NETFLIX + "|user:0:alex", "alex");
        Map<String, String> targets = Collections.singletonMap("p1", "user:0:alex");
        String all = pins(
                line("p1", NETFLIX, "alex", "12a4"),
                line("p1", NETFLIX, "alex", "12"),
                line("p1", NETFLIX, "alex", "123456789"),
                line("p1", "com.example.unknown", "alex", "1234"),
                line("p1", NETFLIX, "", "1234"),
                "{\"profile\":\"p1\"}",
                "7");
        Map<String, Object> result = ShareSecrets.applyPins(all, targets, here);
        assertEquals(0, result.get("added"));
        assertEquals(7, result.get("skipped"));
        assertTrue(here.saved.isEmpty());
        assertEquals(0, ShareSecrets.applyPins("nonsense", targets, here).get("added"));
    }

    @Test
    public void theSummaryHasCountsAndTheHostButNeverASecret() {
        Map<String, Object> summary = ShareSecrets.summary("{\"v\":1,\"pins\":[" + line("p1", NETFLIX, "alex", "1234")
                + "],\"ha\":{\"url\":\"http://192.0.2.10:8123\",\"token\":\"abc\"}}");
        assertEquals(1, summary.get("pins"));
        assertEquals("192.0.2.10", summary.get("ha"));
        assertFalse(summary.toString().contains("1234"));
        assertFalse(summary.toString().contains("abc"));
        assertEquals(true, ShareSecrets.summary("{\"haFailed\":true}").get("haFailed"));
        assertEquals("", ShareSecrets.summary("{\"ha\":{\"url\":\"http://192.0.2.10:8123\",\"token\":\"\"}}").get("ha"));
    }

    @Test
    public void thePinsHaveToBeDigitsOfAPinsLength() {
        assertTrue(ShareSecrets.validPin("1234"));
        assertTrue(ShareSecrets.validPin("123456"));
        assertFalse(ShareSecrets.validPin("12"));
        assertFalse(ShareSecrets.validPin("1 34"));
        assertFalse(ShareSecrets.validPin(""));
        assertFalse(ShareSecrets.validPin(null));
    }

    @Test
    public void theTokenNameSaysWhereItCameFromAndIsDifferentEachMinute() {
        String a = ShareSecrets.tokenName("Study TV", new Date(0));
        String b = ShareSecrets.tokenName("Study TV", new Date(60_000));
        assertTrue(a.startsWith("Hearth copy from Study TV "));
        assertFalse(a.equals(b));
        assertTrue(ShareSecrets.tokenName(null, new Date(0)).startsWith("Hearth copy from another TV "));
    }

    @Test
    public void aVaultIdIsReadBackAsItsSlot() {
        PinVault.Slot profile = PinVault.parseSlot(PinVault.id("user:0:alex", NETFLIX, "Alex  R"), "user:0:alex");
        assertEquals(NETFLIX, profile.pkg);
        assertEquals("alex r", profile.appProfile);
        assertNull(PinVault.parseSlot(PinVault.id("user:0:alex", NETFLIX, "Alex"), "user:11"));
        assertNull(PinVault.parseSlot(PinVault.id("user:0:alex", NETFLIX, "Alex"), null));
        PinVault.Slot shared = PinVault.parseSlot(PinVault.id(null, ContentPin.PACKAGE, ContentPin.VAULT_PROFILE), null);
        assertEquals(ContentPin.VAULT_PROFILE.toLowerCase(), shared.appProfile);
        assertNull(PinVault.parseSlot("paused|" + NETFLIX, null));
        assertNull(PinVault.parseSlot("breaks|" + NETFLIX, null));
    }
}
