package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;

import org.junit.Test;

/**
 * Member, removal and Parent PIN entries carry their writer's signature (docs/household-sync.md, "What's checked"): a
 * TV takes one only from a TV on its member list, signed with that TV's listed key, and an admission only in the name
 * of the TV that wrote it.
 */
public class HouseholdSigningTest {
    private static final long T0 = 1_800_000_000_000L;

    /** A TV key, its id, and a log of its own that signs what it writes. */
    private static final class Key {
        final KeyPair pair;
        final String id;
        final HouseholdLog log;

        Key() throws Exception {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
            generator.initialize(new ECGenParameterSpec("secp256r1"));
            pair = generator.generateKeyPair();
            id = HouseholdIdentity.tvIdOf(pair.getPublic().getEncoded());
            log = new HouseholdLog(id);
            log.setSigner(signer(pair));
        }

        byte[] pub() {
            return pair.getPublic().getEncoded();
        }
    }

    private static HouseholdLog.Signer signer(KeyPair pair) {
        HouseholdIdentity.Signer s = HouseholdIdentity.signer(pair.getPrivate(), pair.getPublic().getEncoded());
        return entry -> {
            try {
                return Base64.getEncoder().encodeToString(s.sign(entry.signedBytes()));
            } catch (Exception e) {
                return null;
            }
        };
    }

    /** {@code on}'s list with {@code of} on it, added by {@code on} (saying whether it signs). */
    private static void list(Key on, Key of, boolean signing) {
        on.log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, of.id,
                HouseholdMembers.value("TV", of.pub(), on.id, signing), T0);
    }

    private static HouseholdEntry member(Key writer, Key of, String by, boolean signing, long at) {
        return writer.log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, of.id,
                HouseholdMembers.value("TV", of.pub(), by, signing), at);
    }

    @Test
    public void entriesOfTheSignedKindsAreSignedAndRoundTrip() throws Exception {
        Key a = new Key();
        HouseholdEntry e = a.log.put(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "", "hash", T0);
        assertFalse(e.sig.isEmpty());
        HouseholdEntry back = HouseholdEntry.fromJson(e.toJson());
        assertEquals(e.sig, back.sig);
        assertTrue(HouseholdIdentity.verify(a.pub(), back.signedBytes(), Base64.getDecoder().decode(back.sig)));
        // other kinds aren't signed: they'd cost a Keystore signature per play saved
        assertTrue(a.log.put("watch", "alex", "x", "v", T0).sig.isEmpty());
    }

    @Test
    public void anEntryFromATvNotOnTheListOrRemovedIsRefused() throws Exception {
        Key here = new Key();
        Key stranger = new Key();
        HouseholdEntry pin = stranger.log.put(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "", "h", T0);
        assertFalse(HouseholdMembers.accepts(here.log, pin));
        list(here, stranger, true);
        assertTrue(HouseholdMembers.accepts(here.log, pin));
        here.log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, stranger.id, T0 + 1);
        // removed: what it wrote, before or after, isn't taken
        assertFalse(HouseholdMembers.accepts(here.log, pin));
        // other kinds aren't checked here (the channel proved the TV that sent them is listed)
        assertTrue(HouseholdMembers.accepts(here.log, stranger.log.put("look", "alex", "", "{}", T0)));
    }

    @Test
    public void aSignatureMustBeTheWritersListedKey() throws Exception {
        Key here = new Key();
        Key a = new Key();
        Key b = new Key();
        list(here, a, true);
        list(here, b, true);
        // b signs an entry that says a wrote it
        HouseholdEntry mine = b.log.put(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "", "h", T0);
        HouseholdEntry forged = new HouseholdEntry(mine.kind, mine.profile, mine.item, mine.value, mine.clock, a.id,
                mine.seq, mine.deleted).signed(mine.sig);
        assertFalse(HouseholdMembers.accepts(here.log, forged));
        // and a changed value breaks the signature
        HouseholdEntry changed = new HouseholdEntry(mine.kind, mine.profile, mine.item, "other", mine.clock, mine.tv,
                mine.seq, mine.deleted).signed(mine.sig);
        assertFalse(HouseholdMembers.accepts(here.log, changed));
        assertFalse(HouseholdMembers.accepts(here.log, mine.signed("not base64!")));
        assertTrue(HouseholdMembers.accepts(here.log, mine));
    }

    @Test
    public void anAdmissionMustNameItsWriterAndHoldTheKeyOfItsId() throws Exception {
        Key here = new Key();
        Key a = new Key();
        Key b = new Key();
        Key extra = new Key();
        list(here, a, true);
        list(here, b, true);
        // a member can't list a key in another member's name
        assertFalse(HouseholdMembers.accepts(here.log, member(a, extra, b.id, true, T0 + 1)));
        // nor give an id another key
        HouseholdEntry wrongKey = a.log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, extra.id,
                HouseholdMembers.value("TV", b.pub(), a.id, true), T0 + 2);
        assertFalse(HouseholdMembers.accepts(here.log, wrongKey));
        // in its own name it can, and the list says who added it
        HouseholdEntry admitted = member(a, extra, a.id, true, T0 + 3);
        assertTrue(HouseholdMembers.accepts(here.log, admitted));
        assertEquals(a.id, HouseholdMembers.byOf(admitted.value, ""));
    }

    @Test
    public void aTvThatSignsCantBeMadeOutNotToAndUnsignedEntriesInItsNameAreRefused() throws Exception {
        Key here = new Key();
        Key a = new Key();
        Key b = new Key();
        list(here, a, true);
        list(here, b, true);
        // b says a doesn't sign
        assertFalse(HouseholdMembers.accepts(here.log, member(b, a, b.id, false, T0 + 1)));
        // an unsigned entry in a's name (what a TV of an older build would send)
        HouseholdEntry unsigned = new HouseholdEntry(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "", "h",
                T0 << 16, a.id, 5, false);
        assertFalse(HouseholdMembers.accepts(here.log, unsigned));
    }

    @Test
    public void aTvOfAnOlderBuildIsTakenAsBeforeButCantClaimToSign() throws Exception {
        Key here = new Key();
        Key old = new Key();
        Key fresh = new Key();
        // listed without saying it signs: a TV on a build from before signing
        list(here, old, false);
        HouseholdLog oldLog = new HouseholdLog(old.id);
        HouseholdEntry pin = oldLog.put(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "", "h", T0);
        assertTrue(pin.sig.isEmpty());
        assertTrue(HouseholdMembers.accepts(here.log, pin));
        // its admissions too (it added a TV)
        HouseholdEntry admitted = oldLog.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, fresh.id,
                HouseholdMembers.value("New", fresh.pub(), old.id), T0 + 1);
        assertTrue(HouseholdMembers.accepts(here.log, admitted));
        // but unsigned, it can't say a TV signs (that would shut out an older TV's own entries)
        HouseholdEntry claims = oldLog.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, fresh.id,
                HouseholdMembers.value("New", fresh.pub(), old.id, true), T0 + 2);
        assertFalse(HouseholdMembers.accepts(here.log, claims));
    }

    @Test
    public void overARealExchangeAForgedAdmissionIsRefusedAndASignedOneTaken() throws Exception {
        HouseholdTvs.Tv a = new HouseholdTvs.Tv();
        a.store.create("Office", T0);
        HouseholdTvs.Tv b = new HouseholdTvs.Tv();
        assertTrue(b.store.join(a.store.invite("Office", T0), "Kitchen", T0));
        HouseholdSyncExchangeTest.exchange(b.store, a.store, null, T0 + 100);
        Key extra = new Key();
        Key other = new Key();
        // b lists a key it holds in a's name, and another in its own
        b.store.log().put(HouseholdMembers.KIND, HouseholdBridge.SHARED, extra.id,
                HouseholdMembers.value("Extra", extra.pub(), a.store.tvId(), true), T0 + 200);
        b.store.log().put(HouseholdMembers.KIND, HouseholdBridge.SHARED, other.id,
                HouseholdMembers.value("Other", other.pub(), b.store.tvId(), true), T0 + 201);
        HouseholdSyncExchangeTest.exchange(b.store, a.store, null, T0 + 300);
        assertEquals(HouseholdMembers.Standing.UNKNOWN, HouseholdMembers.standing(a.store.log(), extra.id));
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(a.store.log(), other.id));
        assertNull(a.store.log().get(HouseholdMembers.KIND, HouseholdBridge.SHARED, extra.id));
        // a TV that meets a only through b hears of the one b added, and not the other
        HouseholdTvs.Tv c = new HouseholdTvs.Tv();
        assertTrue(c.store.join(a.store.invite("Office", T0), "Attic", T0));
        HouseholdSyncExchangeTest.exchange(c.store, a.store, null, T0 + 500);
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(c.store.log(), other.id));
        assertEquals(HouseholdMembers.Standing.UNKNOWN, HouseholdMembers.standing(c.store.log(), extra.id));
    }

    @Test
    public void aRefusedEntryIsCountedSoItIsntSentAgainAndAgain() throws Exception {
        HouseholdTvs.Tv a = new HouseholdTvs.Tv();
        a.store.create("Office", T0);
        HouseholdTvs.Tv b = new HouseholdTvs.Tv();
        assertTrue(b.store.join(a.store.invite("Office", T0), "Kitchen", T0));
        // b holds an entry for a in a's name (from the invitation), which a refuses
        HouseholdSyncExchangeTest.exchange(b.store, a.store, null, T0 + 100);
        HouseholdSync.Result[] again = HouseholdSyncExchangeTest.exchange(b.store, a.store, null, T0 + 200);
        assertEquals(0, again[0].sent);
        assertEquals(0, again[1].sent);
    }

    @Test
    public void aTvsOwnEntryForATvNotKnownHereIsTakenOnlyFromTheTvThatLetThisOneIn() throws Exception {
        Key here = new Key();
        Key inviter = new Key();
        Key other = new Key();
        list(here, inviter, true);
        // other's own entry, written again (renamed, or a day on): it replaced the one its adder wrote
        HouseholdEntry own = member(other, other, inviter.id, true, T0 + 1);
        assertFalse(HouseholdMembers.accepts(here.log, own));
        assertFalse(HouseholdMembers.accepts(here.log, own, false));
        assertTrue(HouseholdMembers.accepts(here.log, own, true));
        // but never one signed with another key, unsigned, or not saying it signs
        Key forger = new Key();
        HouseholdEntry forgerSigned = forger.log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, other.id,
                own.value, T0 + 1);
        HouseholdEntry forged = new HouseholdEntry(own.kind, own.profile, own.item, own.value, own.clock, own.tv,
                own.seq, own.deleted).signed(forgerSigned.sig);
        assertFalse(HouseholdMembers.accepts(here.log, forged, true));
        assertFalse(HouseholdMembers.accepts(here.log, own.signed(""), true));
        HouseholdLog oldLog = new HouseholdLog(other.id);
        assertFalse(HouseholdMembers.accepts(here.log, oldLog.put(HouseholdMembers.KIND, HouseholdBridge.SHARED,
                other.id, HouseholdMembers.value("TV", other.pub(), inviter.id), T0 + 2), true));
        // nor one for a TV removed here, nor another TV's entry for it (that's an admission, by a listed TV only)
        Key removed = new Key();
        here.log.put(HouseholdMembers.KIND, HouseholdBridge.SHARED, removed.id,
                HouseholdMembers.value("TV", removed.pub(), here.id, true), T0);
        here.log.delete(HouseholdMembers.KIND, HouseholdBridge.SHARED, removed.id, T0 + 1);
        assertFalse(HouseholdMembers.accepts(here.log, member(removed, removed, inviter.id, true, T0 + 5), true));
        Key stranger = new Key();
        assertFalse(HouseholdMembers.accepts(here.log, member(stranger, other, stranger.id, true, T0 + 6), true));
    }

    @Test
    public void aTvThatJoinsListsTheTvsThatWroteTheirOwnEntriesSinceTheyWereAdded() throws Exception {
        HouseholdTvs.Tv a = new HouseholdTvs.Tv();
        a.store.create("Office", T0);
        HouseholdTvs.Tv c = new HouseholdTvs.Tv();
        assertTrue(c.store.join(a.store.invite("Office", T0), "Attic", T0));
        HouseholdSyncExchangeTest.exchange(c.store, a.store, null, T0 + 100);
        // A day on, each TV writes its own entry again, which replaces the one a wrote when it let c in
        long day = T0 + HouseholdMembers.REFRESH_MS + 1000;
        assertTrue(c.store.publishSelf("Attic", day));
        assertTrue(a.store.publishSelf("Office", day));
        HouseholdSyncExchangeTest.exchange(c.store, a.store, null, day + 100);
        c.store.log().put(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "", "hash", day + 150);
        HouseholdSyncExchangeTest.exchange(c.store, a.store, null, day + 160);
        // A new TV, let in by a: its first exchange lists every TV, c too, and takes what c signed
        HouseholdTvs.Tv n = new HouseholdTvs.Tv();
        assertTrue(n.store.join(a.store.invite("Office", day + 200), "Kitchen", day + 200));
        HouseholdSyncExchangeTest.exchange(n.store, a.store, null, day + 300);
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(n.store.log(), c.store.tvId()));
        assertEquals("hash", n.store.log().get(HouseholdBridge.PARENT_PIN, HouseholdBridge.SHARED, "").value);
        assertEquals(3, HouseholdMembers.list(n.store.log().all(), new java.util.HashMap<>(), new java.util.HashMap<>(),
                n.store.tvId(), "Kitchen", day + 300).size());
        // once c hears of n from a, the two sync with each other
        HouseholdSyncExchangeTest.exchange(c.store, a.store, null, day + 400);
        HouseholdSyncExchangeTest.exchange(n.store, c.store, null, day + 500);
        assertEquals(3, HouseholdMembers.list(c.store.log().all(), new java.util.HashMap<>(), new java.util.HashMap<>(),
                c.store.tvId(), "Attic", day + 500).size());
    }

    @Test
    public void aTvLetInByATvThatJoinedListsTheTvThatLetThatOneIn() throws Exception {
        HouseholdTvs.Tv a = new HouseholdTvs.Tv();
        a.store.create("Office", T0);
        HouseholdTvs.Tv c = new HouseholdTvs.Tv();
        assertTrue(c.store.join(a.store.invite("Office", T0 + 10), "Attic", T0 + 10));
        HouseholdSyncExchangeTest.exchange(c.store, a.store, null, T0 + 100);
        // A new TV, let in by c (not the TV that made the household), before a's entry is a day old
        HouseholdTvs.Tv n = new HouseholdTvs.Tv();
        assertTrue(n.store.join(c.store.invite("Attic", T0 + 200), "Kitchen", T0 + 200));
        HouseholdSyncExchangeTest.exchange(n.store, c.store, null, T0 + 300);
        assertEquals(HouseholdMembers.Standing.MEMBER, HouseholdMembers.standing(n.store.log(), a.store.tvId()));
        HouseholdSyncExchangeTest.exchange(a.store, c.store, null, T0 + 400);
        HouseholdSyncExchangeTest.exchange(n.store, a.store, null, T0 + 500);
        assertEquals(3, HouseholdMembers.list(a.store.log().all(), new java.util.HashMap<>(), new java.util.HashMap<>(),
                a.store.tvId(), "Office", T0 + 500).size());
    }
}
