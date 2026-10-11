package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.Test;

/** Putting Hearth on the kids' profiles: the commands, and what Hearth may do by itself. */
public class KidsProfilesTest {
    private static final String HEARTH = ProfileAppAccess.HEARTH;
    private static final String TUBE = ProfileAppAccess.HEARTHTUBE;
    private static final String APK = "/data/app/hearth/base.apk";

    /** The TV's package manager as the shell sees it: what's installed for each user, and which copies are kept. */
    private static final class FakeShell implements ProfileAppAccess.ShellRunner {
        final Map<Integer, Set<String>> installed = new HashMap<>();
        final Set<String> kept = new HashSet<>();
        /** "user/package/permission" granted. */
        final Set<String> granted = new HashSet<>();
        final List<String> commands = new ArrayList<>();

        FakeShell has(int user, String... packages) {
            installed.computeIfAbsent(user, u -> new HashSet<>()).addAll(Arrays.asList(packages));
            return this;
        }

        FakeShell keeps(int user, String pkg) {
            kept.add(user + "/" + pkg);
            return this;
        }

        @Override
        public String run(String command) {
            commands.add(command);
            String[] words = command.split(" ");
            if (command.startsWith("pm list packages --user ")) {
                StringBuilder out = new StringBuilder("package:com.example.other\n");
                for (String pkg : installed.getOrDefault(Integer.parseInt(words[4]), Collections.emptySet())) {
                    out.append("package:").append(pkg).append('\n');
                }
                return out.toString();
            }
            if (command.startsWith("pm install-existing --user ")) {
                int user = Integer.parseInt(words[3]);
                if (installed.getOrDefault(0, Collections.emptySet()).contains(words[4])) has(user, words[4]);
                return "Package " + words[4] + " installed for user: " + user;
            }
            if (command.startsWith("pm uninstall --user ")) {
                int user = Integer.parseInt(words[3]);
                if (kept.contains(user + "/" + words[4])) return "Failure [DELETE_FAILED_OWNER_BLOCKED]";
                installed.getOrDefault(user, new HashSet<>()).remove(words[4]);
                return "Success";
            }
            if (command.startsWith("pm grant --user ")) {
                // pm grant --user <user> <package> <permission>
                int user = Integer.parseInt(words[3]);
                if (!installed.getOrDefault(user, Collections.emptySet()).contains(words[4])) {
                    return "Exception occurred while executing 'grant': Unknown package: " + words[4];
                }
                granted.add(user + "/" + words[4] + "/" + words[5]);
                return "";
            }
            if (command.contains(" app_process ")) {
                // CLASSPATH=<apk> app_process /system/bin <class> <package> <user> [true|false]
                String pkg = words[4];
                int user = Integer.parseInt(words[5]);
                if (words.length > 6) {
                    if (Boolean.parseBoolean(words[6])) kept.add(user + "/" + pkg);
                    else kept.remove(user + "/" + pkg);
                }
                return pkg + " user " + user + ": blockUninstall=" + kept.contains(user + "/" + pkg);
            }
            throw new AssertionError("Unexpected command: " + command);
        }

        /** Where this exact command ran first; -1 if it didn't. (Hearth's app id starts HearthTube's.) */
        int indexOf(String command) {
            return commands.indexOf(command);
        }

        /** How many times this exact command ran. */
        int ran(String command) {
            return Collections.frequency(commands, command);
        }

        int count(String start) {
            int n = 0;
            for (String c : commands) {
                if (c.startsWith(start)) n++;
            }
            return n;
        }
    }

    private static String keepCommand(String pkg, int user, boolean value) {
        return "CLASSPATH=" + APK + " app_process /system/bin " + KidsBlockUninstallMain.class.getName() + " " + pkg
                + " " + user + " " + value;
    }

    @Test
    public void aMissingCopyIsKeptBeforeItIsAdded() throws Exception {
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE);
        List<String> log = ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(10));
        assertTrue(shell.installed.get(10).containsAll(Arrays.asList(HEARTH, TUBE)));
        assertTrue(shell.kept.containsAll(Arrays.asList("10/" + HEARTH, "10/" + TUBE)));
        // A running kids' profile checks its apps as soon as one is added: the flag goes on first
        int keep = shell.indexOf(keepCommand(HEARTH, 10, true));
        int add = shell.indexOf("pm install-existing --user 10 " + HEARTH);
        assertTrue(keep >= 0 && keep < add);
        assertEquals(Arrays.asList("user 10: added and kept " + HEARTH, "user 10: added and kept " + TUBE), log);
    }

    @Test
    public void aCopyThatIsThereAndKeptIsLeftAlone() throws Exception {
        // Nothing to add: no install-existing, so no Family Link notice
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE).has(11, HEARTH, TUBE).keeps(11, HEARTH).keeps(11, TUBE);
        List<String> log = ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(11));
        assertEquals(0, shell.count("pm install-existing"));
        assertEquals(-1, shell.indexOf(keepCommand(HEARTH, 11, true)));
        assertTrue(log.isEmpty());
    }

    @Test
    public void aCopyThatIsThereButNotKeptIsKept() throws Exception {
        FakeShell shell = new FakeShell().has(0, HEARTH).has(12, HEARTH);
        List<String> log = ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(12));
        assertEquals(0, shell.count("pm install-existing"));
        assertTrue(shell.kept.contains("12/" + HEARTH));
        assertTrue(log.contains("user 12: kept " + HEARTH));
    }

    @Test
    public void hearthTubeOnlyWhenTheOwnerHasIt() throws Exception {
        FakeShell shell = new FakeShell().has(0, HEARTH);
        List<String> log = ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(10));
        assertEquals(0, shell.ran("pm install-existing --user 10 " + TUBE));
        assertFalse(shell.installed.get(10).contains(TUBE));
        assertTrue(log.contains("user 10: skipped " + TUBE + " (not installed for the owner)"));
    }

    @Test
    public void onlyTheAppsAskedForOnEachProfile() throws Exception {
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE);
        Map<Integer, List<String>> packages = new LinkedHashMap<>();
        packages.put(10, Collections.singletonList(TUBE));
        ProfileAppAccess.addToKids(APK, shell, packages);
        assertEquals(0, shell.ran("pm install-existing --user 10 " + HEARTH));
        assertTrue(shell.installed.get(10).contains(TUBE));
    }

    @Test
    public void neverTheOwnersUser() throws Exception {
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE);
        try {
            ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(0));
            fail("added to the owner's user");
        } catch (IllegalArgumentException expected) {
            // refused
        }
        try {
            ProfileAppAccess.remove(APK, shell, Collections.singletonList(0));
            fail("removed from the owner's user");
        } catch (IllegalArgumentException expected) {
            // refused
        }
        assertEquals(0, shell.count("pm uninstall"));
        assertEquals(0, shell.count("pm install-existing"));
    }

    @Test
    public void removeLiftsTheFlagBeforeItUninstalls() throws Exception {
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE).has(10, HEARTH, TUBE).keeps(10, HEARTH).keeps(10, TUBE);
        ProfileAppAccess.remove(APK, shell, Collections.singletonList(10));
        assertTrue(shell.installed.get(10).isEmpty());
        assertTrue(shell.kept.isEmpty());
        assertTrue(shell.indexOf(keepCommand(HEARTH, 10, false)) < shell.indexOf("pm uninstall --user 10 " + HEARTH));
        // The owner's copies stay
        assertTrue(shell.installed.get(0).containsAll(Arrays.asList(HEARTH, TUBE)));
    }

    @Test
    public void hearthMayReadWatchNextOnEachKidsProfile() throws Exception {
        // Without READ_TV_LISTINGS in that user, Android shows Hearth's copy only the Watch Next entries it wrote
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE);
        List<String> log = ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(10));
        assertTrue(shell.granted.contains("10/" + HEARTH + "/android.permission.READ_TV_LISTINGS"));
        // After the copy is there
        assertTrue(shell.indexOf("pm install-existing --user 10 " + HEARTH)
                < shell.indexOf("pm grant --user 10 " + HEARTH + " android.permission.READ_TV_LISTINGS"));
        // Only Hearth's
        assertEquals(0, shell.count("pm grant --user 10 " + TUBE));
        assertEquals(Arrays.asList("user 10: added and kept " + HEARTH, "user 10: added and kept " + TUBE), log);
    }

    @Test
    public void aCopyPutThereEarlierGetsTheGrantToo() throws Exception {
        // Copies added before Hearth granted it: a Fix grants it without adding anything (no Family Link notice)
        FakeShell shell = new FakeShell().has(0, HEARTH, TUBE).has(11, HEARTH, TUBE).keeps(11, HEARTH).keeps(11, TUBE);
        List<String> log = ProfileAppAccess.addToKids(APK, shell, Collections.singletonList(11));
        assertEquals(0, shell.count("pm install-existing"));
        assertTrue(shell.granted.contains("11/" + HEARTH + "/android.permission.READ_TV_LISTINGS"));
        assertTrue(log.isEmpty());
    }

    @Test
    public void noGrantWhereHearthIsntPut() throws Exception {
        // The owner has no Hearth to copy: nothing to grant to
        FakeShell shell = new FakeShell().has(0, TUBE);
        Map<Integer, List<String>> packages = new LinkedHashMap<>();
        packages.put(10, Collections.singletonList(HEARTH));
        List<String> log = ProfileAppAccess.addToKids(APK, shell, packages);
        assertEquals(0, shell.count("pm grant"));
        assertTrue(log.contains("user 10: skipped " + HEARTH + " (not installed for the owner)"));
    }

    @Test
    public void theGrantIsOnlyEverHearthsOnAnotherProfile() {
        assertEquals("pm grant --user 12 " + HEARTH + " android.permission.READ_TV_LISTINGS",
                ProfileAppAccess.grantWatchNextCommand(HEARTH, 12));
        try {
            ProfileAppAccess.grantWatchNextCommand(HEARTH, 0);
            fail("granted in the owner's user");
        } catch (IllegalArgumentException expected) {
            // refused
        }
        try {
            ProfileAppAccess.grantWatchNextCommand(TUBE, 12);
            fail("granted to another app");
        } catch (IllegalArgumentException expected) {
            // refused
        }
    }

    @Test
    public void stateReadsWhatsInstalledAndKept() throws Exception {
        FakeShell shell = new FakeShell().has(10, HEARTH).keeps(10, HEARTH);
        List<ProfileAppAccess.AppStatus> state = ProfileAppAccess.state(APK, shell, Collections.singletonList(10));
        assertEquals(2, state.size());
        assertTrue(state.get(0).installed && state.get(0).protectedFromRemoval);
        assertFalse(state.get(1).installed || state.get(1).protectedFromRemoval);
        assertEquals(0, shell.count("pm install-existing"));
        assertEquals(-1, shell.indexOf(keepCommand(HEARTH, 10, true)));
    }

    // --- What Hearth may do by itself ---

    private static KidsProfiles.Kid kid(int user, boolean running, boolean hearth, boolean tube) {
        return new KidsProfiles.Kid(user, user, "Sam", running, hearth, tube);
    }

    @Test
    public void nothingByItselfUntilAParentHasSetItUpAndTheTvTrustsHearth() {
        List<KidsProfiles.Kid> kids = Collections.singletonList(kid(13, false, false, false));
        assertTrue(KidsProfiles.autoFixes(false, true, kids, true, Collections.emptySet()).isEmpty());
        assertTrue(KidsProfiles.autoFixes(true, false, kids, true, Collections.emptySet()).isEmpty());
        Map<KidsProfiles.Kid, List<String>> fixes = KidsProfiles.autoFixes(true, true, kids, true, Collections.emptySet());
        assertEquals(Arrays.asList(HEARTH, TUBE), fixes.get(kids.get(0)));
    }

    @Test
    public void notWhileTheProfileRuns() {
        List<KidsProfiles.Kid> kids = Collections.singletonList(kid(13, true, false, false));
        assertTrue(KidsProfiles.autoFixes(true, true, kids, true, Collections.emptySet()).isEmpty());
    }

    @Test
    public void onceForEachAppAndProfile() {
        KidsProfiles.Kid sam = kid(13, false, false, false);
        Set<String> done = new HashSet<>(Collections.singletonList(KidsProfiles.autoKey(13, HEARTH)));
        Map<KidsProfiles.Kid, List<String>> fixes =
                KidsProfiles.autoFixes(true, true, Collections.singletonList(sam), true, done);
        assertEquals(Collections.singletonList(TUBE), fixes.get(sam));
        done.add(KidsProfiles.autoKey(13, TUBE));
        assertTrue(KidsProfiles.autoFixes(true, true, Collections.singletonList(sam), true, done).isEmpty());
    }

    @Test
    public void hearthTubeByItselfOnlyWhenTheOwnerHasIt() {
        KidsProfiles.Kid ready = kid(10, false, true, false);
        assertTrue(KidsProfiles.autoFixes(true, true, Collections.singletonList(ready), false, Collections.emptySet())
                .isEmpty());
        assertEquals(Collections.singletonList(TUBE),
                KidsProfiles.autoFixes(true, true, Collections.singletonList(ready), true, Collections.emptySet())
                        .get(ready));
    }

    @Test
    public void aRefusedConnectionRanNothing() {
        assertTrue(KidsProfiles.refused(new RuntimeException(new ConnectException("refused"))));
        // Waiting on "Allow debugging?" ran nothing either, but means the TV may not trust Hearth's key any more
        assertFalse(KidsProfiles.refused(new SocketTimeoutException("timeout")));
    }
}
