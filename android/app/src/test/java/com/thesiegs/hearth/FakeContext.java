package com.thesiegs.hearth;

import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * A Context for plain JUnit: a package name, in-memory SharedPreferences per file, and the activities it was asked
 * to start. Everything else is android.jar's stub (returns defaults).
 */
final class FakeContext extends ContextWrapper {
    final String packageName;
    final Map<String, Prefs> files = new HashMap<>();
    final List<Intent> started = new ArrayList<>();

    FakeContext(String packageName) {
        super(null);
        this.packageName = packageName;
    }

    @Override
    public String getPackageName() {
        return packageName;
    }

    @Override
    public Prefs getSharedPreferences(String name, int mode) {
        return files.computeIfAbsent(name, n -> new Prefs());
    }

    @Override
    public void startActivity(Intent intent) {
        started.add(intent);
    }

    /** SharedPreferences over a map; edits apply on apply() or commit(). */
    static final class Prefs implements SharedPreferences {
        final Map<String, Object> values = new HashMap<>();

        @Override
        public Map<String, ?> getAll() {
            return new HashMap<>(values);
        }

        @Override
        public String getString(String key, String defValue) {
            return values.containsKey(key) ? (String) values.get(key) : defValue;
        }

        @SuppressWarnings("unchecked")
        @Override
        public Set<String> getStringSet(String key, Set<String> defValues) {
            return values.containsKey(key) ? (Set<String>) values.get(key) : defValues;
        }

        @Override
        public int getInt(String key, int defValue) {
            return values.containsKey(key) ? (Integer) values.get(key) : defValue;
        }

        @Override
        public long getLong(String key, long defValue) {
            return values.containsKey(key) ? (Long) values.get(key) : defValue;
        }

        @Override
        public float getFloat(String key, float defValue) {
            return values.containsKey(key) ? (Float) values.get(key) : defValue;
        }

        @Override
        public boolean getBoolean(String key, boolean defValue) {
            return values.containsKey(key) ? (Boolean) values.get(key) : defValue;
        }

        @Override
        public boolean contains(String key) {
            return values.containsKey(key);
        }

        @Override
        public Editor edit() {
            return new Edits();
        }

        @Override
        public void registerOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener listener) {
        }

        @Override
        public void unregisterOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener listener) {
        }

        private final class Edits implements Editor {
            private final Map<String, Object> puts = new HashMap<>();
            private final Set<String> removes = new HashSet<>();
            private boolean clear;

            private Editor put(String key, Object value) {
                removes.remove(key);
                puts.put(key, value);
                return this;
            }

            @Override
            public Editor putString(String key, String value) {
                return value == null ? remove(key) : put(key, value);
            }

            @Override
            public Editor putStringSet(String key, Set<String> values) {
                return values == null ? remove(key) : put(key, new HashSet<>(values));
            }

            @Override
            public Editor putInt(String key, int value) {
                return put(key, value);
            }

            @Override
            public Editor putLong(String key, long value) {
                return put(key, value);
            }

            @Override
            public Editor putFloat(String key, float value) {
                return put(key, value);
            }

            @Override
            public Editor putBoolean(String key, boolean value) {
                return put(key, value);
            }

            @Override
            public Editor remove(String key) {
                puts.remove(key);
                removes.add(key);
                return this;
            }

            @Override
            public Editor clear() {
                clear = true;
                return this;
            }

            @Override
            public boolean commit() {
                apply();
                return true;
            }

            @Override
            public void apply() {
                if (clear) values.clear();
                for (String key : removes) values.remove(key);
                values.putAll(puts);
            }
        }
    }
}
