package com.thesiegs.hearth;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.HashMap;
import java.util.Map;

import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

/** Test TVs: preferences in a map, and Keystore keys (SecretBox's and the TV key) in memory. */
final class HouseholdTvs {
    private HouseholdTvs() {
    }

    static final class MapBacking implements HouseholdStore.Backing {
        final Map<String, String> map = new HashMap<>();

        @Override
        public String get(String key) {
            return map.get(key);
        }

        @Override
        public void put(String key, String value) {
            map.put(key, value);
        }

        @Override
        public void remove(String key) {
            map.remove(key);
        }
    }

    static SecretBox.Keys memoryKeys() {
        Map<String, SecretKey> keys = new HashMap<>();
        return alias -> {
            SecretKey key = keys.get(alias);
            if (key == null) {
                KeyGenerator generator = KeyGenerator.getInstance("AES");
                generator.init(256);
                key = generator.generateKey();
                keys.put(alias, key);
            }
            return key;
        };
    }

    /** A TV key kept in memory, like the Keystore's: made, loaded, deleted. */
    static final class MemoryIdentities implements HouseholdIdentity.Keys {
        KeyPair pair;
        int created;

        @Override
        public HouseholdIdentity.Signer load() {
            return pair == null ? null : HouseholdIdentity.signer(pair.getPrivate(), pair.getPublic().getEncoded());
        }

        @Override
        public HouseholdIdentity.Signer create() {
            try {
                KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
                generator.initialize(new ECGenParameterSpec("secp256r1"));
                pair = generator.generateKeyPair();
                created++;
                return load();
            } catch (Exception e) {
                return null;
            }
        }

        @Override
        public void delete() {
            pair = null;
        }
    }

    /** One TV: its preferences and keys, so it can be opened again as after a restart. */
    static final class Tv {
        final MapBacking backing = new MapBacking();
        final SecretBox.Keys keys = memoryKeys();
        final MemoryIdentities identities = new MemoryIdentities();
        HouseholdStore store;

        Tv() {
            reopen();
        }

        HouseholdStore reopen() {
            store = HouseholdStore.open(backing, keys, identities);
            return store;
        }
    }
}
