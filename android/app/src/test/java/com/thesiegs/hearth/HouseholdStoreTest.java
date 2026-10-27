package com.thesiegs.hearth;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Base64;

import org.junit.Test;

/**
 * What a TV keeps of its household: its key and the entries survive a restart, an invitation is single use, leaving and
 * removal forget, a cleared Keystore is said, not hidden, and a version 1 household converts keeping its person ids.
 */
public class HouseholdStoreTest {
    private static final long T0 = 1_800_000_000_000L;

    @Test
    public void aNewTvIsInNoHouseholdAndHasNoKey() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        assertFalse(tv.store.joined());
        assertFalse(tv.store.lost());
        assertFalse(tv.store.removed());
        assertNull(tv.store.tvId());
        assertNull(tv.store.householdId());
        assertTrue(tv.store.enabled());
        assertNull(tv.identities.pair);
    }

    @Test
    public void startingAHouseholdMakesThisTvItsOnlyMemberAndSurvivesARestart() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        assertTrue(tv.store.create("Office", T0));
        assertFalse(tv.store.create("Office", T0));
        String tvId = tv.store.tvId();
        assertEquals(HouseholdIdentity.tvIdOf(tv.store.publicKey()), tvId);
        assertEquals(16, tv.store.householdId().length());
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(tv.store.log(), tvId));
        HouseholdStore again = tv.reopen();
        assertTrue(again.joined());
        assertEquals(tvId, again.tvId());
        assertEquals("Office", HouseholdMembers.nameOf(again.log().get(HouseholdMembers.KIND, HouseholdBridge.SHARED, tvId).value));
    }

    @Test
    public void noSecretIsInThePreferencesInTheClear() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        tv.store.log().put("pin", "Sam", "disney", "135790", T0);
        tv.store.save();
        HouseholdStore.Invitation inv = tv.store.invite("Office", T0);
        String secret = Base64.getEncoder().encodeToString(inv.secret);
        String salt = Base64.getEncoder().encodeToString(inv.personSalt);
        for (String value : tv.backing.map.values()) {
            assertFalse(value.contains("135790"));
            assertFalse(value.contains(secret));
            assertFalse(value.contains(salt));
        }
    }

    @Test
    public void entriesSurviveARestart() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        tv.store.log().put("pin", "Sam", "disney", "135790", T0);
        tv.store.log().delete("pin", "Sam", "hulu", T0 + 1);
        assertTrue(tv.store.save());
        HouseholdStore again = tv.reopen();
        assertEquals("135790", again.log().get("pin", "Sam", "disney").value);
        assertNull(again.log().get("pin", "Sam", "hulu"));
        // the TV's own member entry, the PIN and the delete
        assertEquals(3, again.log().all().size());
        HouseholdEntry next = again.log().put("pin", "Sam", "disney", "2468", T0 + 2);
        assertEquals(4, next.seq);
    }

    @Test
    public void anInvitationCarriesTheHouseholdAndIsUsedOnce() throws Exception {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        HouseholdStore.Invitation inv = HouseholdStore.Invitation.fromJson(tv.store.invite("Office", T0).toJson());
        assertNotNull(inv);
        assertEquals(tv.store.householdId(), inv.householdId);
        assertEquals(tv.store.tvId(), inv.byTv);
        byte[] data = ShareCrypto.bytes("transcript");
        byte[] wrong = ShareCrypto.hkdfExtract(new byte[32], data);
        assertFalse(tv.store.useInvite(data, wrong, T0 + 1));
        byte[] mac = ShareCrypto.hkdfExtract(inv.secret, data);
        assertTrue(tv.store.useInvite(data, mac, T0 + 1));
        assertFalse(tv.store.useInvite(data, mac, T0 + 2));
    }

    @Test
    public void anInvitationRunsOut() throws Exception {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        HouseholdStore.Invitation inv = tv.store.invite("Office", T0);
        byte[] data = ShareCrypto.bytes("transcript");
        assertFalse(tv.store.useInvite(data, ShareCrypto.hkdfExtract(inv.secret, data), T0 + HouseholdStore.INVITE_MS + 1));
    }

    @Test
    public void anInvitationThatIsNotOneIsRefused() {
        assertNull(HouseholdStore.Invitation.fromJson("not json"));
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        HouseholdStore.Invitation inv = tv.store.invite("Office", T0);
        // the inviting TV's id has to be its key's
        HouseholdStore.Invitation forged = new HouseholdStore.Invitation(inv.householdId, inv.personSalt, "tv-0000000000000000",
                inv.byKey, inv.byName, inv.secret);
        assertNull(HouseholdStore.Invitation.fromJson(forged.toJson()));
    }

    @Test
    public void joiningTakesTheHouseholdAndListsTheInvitingTv() {
        HouseholdTvs.Tv first = new HouseholdTvs.Tv();
        first.store.create("Office", T0);
        HouseholdTvs.Tv second = new HouseholdTvs.Tv();
        second.store.create("Kitchen", T0);
        second.store.log().put("look", "Alex", "theme", "dark", T0);
        String before = second.store.tvId();
        HouseholdStore.Invitation inv = first.store.invite("Office", T0);
        assertTrue(second.store.join(inv, "Kitchen", T0 + 1));
        assertEquals(first.store.householdId(), second.store.householdId());
        // a new key, so a new id
        assertNotEquals(before, second.store.tvId());
        assertNull(second.store.log().get("look", "Alex", "theme"));
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(second.store.log(), first.store.tvId()));
        assertNotNull(second.store.joinProofFor(first.store.tvId()));
        assertNull(second.store.joinProofFor("tv-0000000000000000"));
        // the same people are the same ids on both TVs
        assertEquals(first.store.seal().personId("alex@example.com"), second.store.seal().personId("alex@example.com"));
        assertFalse(second.store.join(null, "Kitchen", T0));
    }

    @Test
    public void removingAnotherTvIsFinalAndThisTvCantBeRemovedThatWay() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        String other = HouseholdIdentity.tvIdOf(new byte[] {1, 2, 3});
        tv.store.admit(other, new byte[] {1, 2, 3}, "Kitchen", T0);
        assertTrue(tv.store.remove(other, T0 + 1));
        assertEquals(HouseholdMembers.Standing.REMOVED, HouseholdMembers.standing(tv.store.log(), other));
        tv.store.admit(other, new byte[] {1, 2, 3}, "Kitchen", T0 + 2);
        assertEquals(HouseholdMembers.Standing.REMOVED, HouseholdMembers.standing(tv.store.log(), other));
        assertFalse(tv.store.remove(tv.store.tvId(), T0 + 3));
    }

    @Test
    public void leavingRemovesThisTvThenForgetsEverything() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        String id = tv.store.tvId();
        tv.store.beginLeaving(T0 + 1);
        assertFalse(tv.store.joined());
        assertTrue(tv.store.syncs());
        assertTrue(tv.store.leaving());
        assertTrue(tv.store.log().isRemoved(HouseholdMembers.KIND, HouseholdBridge.SHARED, id));
        // still leaving after a restart, until it has told another TV
        assertTrue(tv.reopen().leaving());
        assertFalse(tv.store.leavingExpired(T0 + HouseholdStore.LEAVING_MS));
        assertTrue(tv.store.leavingExpired(T0 + HouseholdStore.LEAVING_MS + 2));
        tv.store.leave();
        assertFalse(tv.store.syncs());
        assertNull(tv.identities.pair);
        assertTrue(tv.backing.map.keySet().stream().allMatch("enabled"::equals));
        assertFalse(tv.reopen().joined());
        assertFalse(tv.store.lost());
    }

    @Test
    public void aRemovedTvSaysSoUntilItStartsOrJoinsAgain() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        tv.store.markRemoved();
        assertFalse(tv.store.joined());
        assertTrue(tv.reopen().removed());
        assertNull(tv.identities.pair);
        tv.store.create("Office", T0 + 1);
        assertFalse(tv.store.removed());
    }

    @Test
    public void aClearedKeystoreMakesTheTvLostNotQuietlyNew() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        tv.identities.pair = null;
        HouseholdStore after = tv.reopen();
        assertFalse(after.joined());
        assertTrue(after.lost());
        assertNull(after.householdId());
        // it stays lost after another restart, until it starts or joins a household
        assertTrue(tv.reopen().lost());
        HouseholdTvs.Tv other = new HouseholdTvs.Tv();
        other.store.create("Kitchen", T0);
        assertTrue(tv.store.join(other.store.invite("Kitchen", T0), "Office", T0));
        assertFalse(tv.store.lost());
    }

    @Test
    public void anUnreadableLogStartsEmptyButKeepsTheHousehold() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.create("Office", T0);
        tv.store.log().put("look", "Alex", "theme", "dark", T0);
        tv.store.save();
        tv.backing.put("log_sealed", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        HouseholdStore again = tv.reopen();
        assertTrue(again.joined());
        assertEquals(0, again.log().all().size());
    }

    @Test
    public void theSwitchIsOnUntilTurnedOffAndSurvivesARestart() {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.store.setEnabled(false);
        assertFalse(tv.reopen().enabled());
        tv.store.setEnabled(true);
        assertTrue(tv.reopen().enabled());
    }

    // ---- Version 1 ----

    /** A TV as version 1 left it: the household key sealed, and its entries. */
    static HouseholdTvs.Tv v1Tv(byte[] key) {
        HouseholdTvs.Tv tv = new HouseholdTvs.Tv();
        tv.backing.put("tv_id", "tv-1111111111111111");
        tv.backing.put("key_sealed", SecretBox.seal(tv.keys, HouseholdStore.KEY_ALIAS, key));
        HouseholdLog log = new HouseholdLog("tv-1111111111111111");
        log.put("pin", "a:old", "disney", "135790", T0);
        StringBuilder entries = new StringBuilder("[");
        for (HouseholdEntry e : log.all()) entries.append(org.json.JSONObject.quote(e.toJson()));
        entries.append("]");
        tv.backing.put("log_sealed", SecretBox.sealText(tv.keys, HouseholdStore.LOG_ALIAS,
                "{\"entries\":" + entries + ",\"vector\":{\"tv-1111111111111111\":1}}"));
        return tv;
    }

    @Test
    public void aVersion1HouseholdConvertsKeepingItsIdPersonIdsAndEntries() throws Exception {
        byte[] key = new byte[32];
        new java.security.SecureRandom().nextBytes(key);
        HouseholdTvs.Tv tv = v1Tv(key);
        HouseholdStore store = tv.reopen();
        assertTrue(store.joined());
        assertEquals(HouseholdSeal.v1Id(key), store.householdId());
        assertEquals(HouseholdIdentity.tvIdOf(store.publicKey()), store.tvId());
        assertEquals("135790", store.log().get("pin", "a:old", "disney").value);
        // the person id is what version 1 made: a keyed hash under its person key
        byte[] prk = ShareCrypto.hkdfExtract(new byte[0], key);
        byte[] personKey = ShareCrypto.hkdfExpand(prk, ShareCrypto.bytes("hearth-household-person-v1"), 32);
        byte[] mac = ShareCrypto.hkdfExtract(personKey, ShareCrypto.bytes("alex@example.com"));
        assertEquals("a:" + HouseholdSeal.hex(mac, 12), store.seal().personId("Alex@example.com"));
        // the old key admits the other converting TVs for a while, then is dropped
        assertNotNull(store.v1AdmitKey(T0));
        assertArrayEquals(HouseholdSeal.v1AdmitKey(key), store.v1AdmitKey(T0 + 1));
        assertNull(store.v1AdmitKey(T0 + HouseholdStore.V1_GRACE_MS + 1));
        assertNull(store.v1AdmitKey(T0 + 2));
        // and it stays converted
        assertEquals(store.tvId(), tv.reopen().tvId());
        assertEquals(1, tv.identities.created);
    }

    @Test
    public void aVersion1KeyThatNoLongerOpensIsLost() {
        HouseholdTvs.Tv tv = v1Tv(new byte[32]);
        HouseholdTvs.Tv elsewhere = new HouseholdTvs.Tv();
        elsewhere.backing.map.putAll(tv.backing.map);
        HouseholdStore store = elsewhere.reopen();
        assertTrue(store.lost());
        assertFalse(store.joined());
        assertTrue(elsewhere.reopen().lost());
    }
}
