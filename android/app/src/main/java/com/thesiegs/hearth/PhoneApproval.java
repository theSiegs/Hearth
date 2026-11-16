package com.thesiegs.hearth;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * A profile's owner allows a switch into their PIN-locked Google TV profile from their phone, instead of the PIN being
 * typed with the remote. When Google TV's PIN screen comes up for a profile that has this on, Hearth sends that
 * person's phone an actionable Home Assistant notification (through the companion app's notify service they chose) and
 * listens for the answer (HaEvents). Allow: Hearth types the profile's saved Google TV PIN (ProfilePairingService,
 * GooglePinRecipe). Deny, or no answer: the PIN screen stays for whoever is at the TV. The PIN screen is never covered
 * while waiting, so typing the PIN still works.
 *
 * Settings are per profile (each adult sets their own, from their profile): on/off and the notify service; the PIN
 * is in PinVault under the profile's key. The settings follow the adult to the household's other TVs (Household,
 * kind "approval", signed); the PIN does too, as a saved PIN. With no phone chosen, a TV paired with the Hearth
 * integration asks the companion apps of the person Home Assistant maps the profile to (the state document's
 * {@code adult_phones}); a phone chosen on any TV wins over those.
 */
final class PhoneApproval {
    private static final String TAG = "HearthApproval";
    private static final String PREFS = "phone_approval";
    static final String EVENT = "mobile_app_notification_action";
    private static final String ACTION_PREFIX = "HEARTH_APPROVE_";
    private static final String TAG_PREFIX = "hearth-approval-";
    /** How long a phone has to answer. */
    static final long ANSWER_MS = 120_000;
    /**
     * After the PIN screen comes up, how long the arrows, OK, Back and Delete don't count as someone using it: the OK
     * that picked the profile on the chooser (its key-up, a repeat, or a second press of a laggy remote) lands about
     * then. A digit always counts.
     */
    static final long GRACE_MS = 2_000;
    /** Home Assistant's phones for each adult profile (the state document's adult_phones), as JSON. */
    private static final String HA_PREFS = "phone_approval_ha";
    private static final String HA_PHONES = "adult_phones";
    private static final ExecutorService WORKER = Executors.newCachedThreadPool();
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** The request waiting for an answer, if any (main thread). */
    private static Request sPending;

    static final class Request {
        final String key;
        final String name;
        final String nonce;
        /** The phones asked (their notify services), cleared the same when it ends. */
        final List<String> services;
        /** When Google TV's PIN screen came up, in uptime (as key events' times). */
        final long pinShownAt;
        final long at = SystemClock.elapsedRealtime();
        /** Its wait for the phone's answer (main thread). */
        HaEventSession.Waiter waiter;

        Request(String key, String name, String nonce, List<String> services, long pinShownAt) {
            this.key = key;
            this.name = name;
            this.nonce = nonce;
            this.services = services;
            this.pinShownAt = pinShownAt;
        }
    }

    private PhoneApproval() {
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean isOn(Context context, String key) {
        return key != null && prefs(context).getBoolean(key + "|on", false);
    }

    /** Turned on or off here by the profile's owner: the household's other TVs take it. */
    static void setOn(Context context, String key, boolean on) {
        if (key == null) return;
        putSynced(context, key, HouseholdBridge.APPROVAL_ON, on ? "1" : "0");
        Household.onApprovalChanged(context, key, HouseholdBridge.APPROVAL_ON);
    }

    /** The notify service the profile's owner chose ("mobile_app_alex_phone"), or null (none chosen). */
    static String notifyService(Context context, String key) {
        return key == null ? null : prefs(context).getString(key + "|notify", null);
    }

    /** Chosen here by the profile's owner (null: none, Home Assistant's phones apply): the other TVs take it. */
    static void setNotifyService(Context context, String key, String service) {
        if (key == null) return;
        putSynced(context, key, HouseholdBridge.APPROVAL_NOTIFY, isNotifyService(service) ? service : null);
        Household.onApprovalChanged(context, key, HouseholdBridge.APPROVAL_NOTIFY);
    }

    /** The settings that sync for a profile, as household items (HouseholdBridge.APPROVAL): only those set here. */
    static java.util.Map<String, String> synced(Context context, String key) {
        java.util.Map<String, String> out = new java.util.HashMap<>();
        if (key == null) return out;
        SharedPreferences prefs = prefs(context);
        if (prefs.contains(key + "|on")) out.put(HouseholdBridge.APPROVAL_ON, prefs.getBoolean(key + "|on", false) ? "1" : "0");
        String service = prefs.getString(key + "|notify", null);
        if (service != null) out.put(HouseholdBridge.APPROVAL_NOTIFY, service);
        return out;
    }

    /** Saves one synced setting without publishing it (the household's, or the caller publishes); null clears it. */
    static void putSynced(Context context, String key, String item, String value) {
        if (key == null) return;
        SharedPreferences.Editor editor = prefs(context).edit();
        if (HouseholdBridge.APPROVAL_ON.equals(item)) {
            if ("1".equals(value) || "0".equals(value)) editor.putBoolean(key + "|on", "1".equals(value));
            else editor.remove(key + "|on");
        } else if (HouseholdBridge.APPROVAL_NOTIFY.equals(item)) {
            if (isNotifyService(value)) editor.putString(key + "|notify", value);
            else editor.remove(key + "|notify");
        } else {
            return;
        }
        editor.apply();
    }

    /** Only a companion app's notify service: what a phone's actionable notifications go through. */
    static boolean isNotifyService(String service) {
        return HouseholdBridge.isNotifyService(service);
    }

    /**
     * Takes the Hearth integration's phones for each adult profile from its state document ({@code adult_phones}:
     * {profile key: [notify service, ...]}); none in the document: none.
     */
    static void applyHaDocument(Context context, JSONObject state) {
        if (state == null) return;
        JSONObject phones = state.optJSONObject(HA_PHONES);
        SharedPreferences.Editor editor = context.getSharedPreferences(HA_PREFS, Context.MODE_PRIVATE).edit();
        if (phones == null || phones.length() == 0) editor.remove(HA_PHONES);
        else editor.putString(HA_PHONES, phones.toString());
        editor.apply();
    }

    /** Home Assistant's phones for this profile's person (while the TV is paired with the integration); maybe empty. */
    static List<String> haPhones(Context context, String key) {
        if (key == null || !HaIntegration.isPaired(context)) return new ArrayList<>();
        return phonesIn(context.getSharedPreferences(HA_PREFS, Context.MODE_PRIVATE).getString(HA_PHONES, null), key);
    }

    /** The notify services {@code json} (adult_phones) lists for {@code key}, companion apps' only, once each. */
    static List<String> phonesIn(String json, String key) {
        List<String> out = new ArrayList<>();
        if (json == null || key == null) return out;
        try {
            JSONArray services = new JSONObject(json).optJSONArray(key);
            for (int i = 0; services != null && i < services.length(); i++) {
                String service = services.optString(i, "");
                if (isNotifyService(service) && !out.contains(service)) out.add(service);
            }
        } catch (Exception ignored) {
            // None
        }
        return out;
    }

    /** The phones that are asked for this profile: the one its owner chose (on any TV), else Home Assistant's. */
    static List<String> phones(Context context, String key) {
        return choose(notifyService(context, key), haPhones(context, key));
    }

    /** A chosen phone wins over Home Assistant's. */
    static List<String> choose(String chosen, List<String> fromHa) {
        if (isNotifyService(chosen)) {
            List<String> out = new ArrayList<>();
            out.add(chosen);
            return out;
        }
        return fromHa;
    }

    static boolean hasPin(Context context, String key) {
        return PinVault.has(context, key, LauncherAccessibilityService.GOOGLE_TV_PACKAGE, GooglePinRecipe.VAULT_NAME);
    }

    /** Everything this profile needs for an approval: Home Assistant, the switch, a phone and the PIN. */
    static boolean isReady(Context context, String key) {
        return HaConfig.isConfigured(context) && isOn(context, key) && !phones(context, key).isEmpty()
                && hasPin(context, key);
    }

    /** The companion apps' notify services Home Assistant has ({service, name}), for Settings; empty when unreachable. */
    static List<String> notifyServices(Context context) {
        List<String> out = new ArrayList<>();
        JSONArray domains = HaApi.services(context);
        if (domains == null) return out;
        for (int i = 0; i < domains.length(); i++) {
            JSONObject domain = domains.optJSONObject(i);
            if (domain == null || !"notify".equals(domain.optString("domain"))) continue;
            JSONObject services = domain.optJSONObject("services");
            if (services == null) continue;
            for (java.util.Iterator<String> it = services.keys(); it.hasNext(); ) {
                String service = it.next();
                if (isNotifyService(service)) out.add(service);
            }
        }
        java.util.Collections.sort(out);
        return out;
    }

    /** A plain notification to the profile's phones, so its owner knows it reaches them. False when none got it. */
    static boolean sendTest(Context context, String key) {
        boolean sent = false;
        for (String service : phones(context, key)) {
            try {
                sent |= HaApi.callService(context, "notify", service, new JSONObject()
                        .put("title", context.getString(R.string.approval_test_title))
                        .put("message", context.getString(R.string.approval_test_message)));
            } catch (Exception e) {
                // The next phone
            }
        }
        return sent;
    }

    /**
     * Google TV's PIN screen came up (LauncherAccessibilityService, main thread). Works out whose it is from the account
     * address it shows, off the main thread, and asks that person's phone if they have this on. {@code shownAt}: when
     * the screen came up, in uptime.
     */
    static void onPinScreen(LauncherAccessibilityService service, long shownAt) {
        Context context = service.getApplicationContext();
        if (!HaConfig.isConfigured(context)) return;
        AccessibilityNodeInfo root = service.getRootInActiveWindow();
        if (root == null) return;
        WORKER.execute(() -> {
            List<CharSequence> texts = new ArrayList<>();
            collectTexts(root, texts, 0);
            String key = profileOnScreen(context, texts);
            if (key == null || !isReady(context, key)) return;
            String name = ProfileUsers.displayName(context, key);
            MAIN.post(() -> ask(context, key, name, shownAt));
        });
    }

    /** The adult's profile whose Google account address a screen shows, or null. */
    static String profileOnScreen(Context context, List<CharSequence> texts) {
        for (String key : ProfilePairing.getHearthProfiles(context)) {
            String email = ProfileUsers.emailOf(context, key);
            if (email != null && containsEmail(texts, email)) return key;
        }
        return null;
    }

    static boolean containsEmail(List<CharSequence> texts, String email) {
        String wanted = email.trim().toLowerCase(Locale.ROOT);
        for (CharSequence text : texts) {
            if (text != null && text.toString().trim().toLowerCase(Locale.ROOT).equals(wanted)) return true;
        }
        return false;
    }

    private static void collectTexts(AccessibilityNodeInfo node, List<CharSequence> out, int depth) {
        if (node == null || depth > 25) return;
        if (node.getText() != null && node.getText().length() > 0) out.add(node.getText());
        for (int i = 0; i < node.getChildCount(); i++) collectTexts(node.getChild(i), out, depth + 1);
    }

    /** Sends the request once its answer can be heard, then waits for it (main thread). */
    private static void ask(Context context, String key, String name, long shownAt) {
        Request pending = sPending;
        // The same profile's screen again (Google redraws it): still the same request
        if (pending != null && pending.key.equals(key) && SystemClock.elapsedRealtime() - pending.at < ANSWER_MS) return;
        if (pending != null && pending.waiter != null) pending.waiter.close();
        List<String> services = phones(context, key);
        if (services.isEmpty()) return;
        byte[] bytes = new byte[8];
        RANDOM.nextBytes(bytes);
        Request request = new Request(key, name, AgentAuth.hex(bytes), services, shownAt);
        sPending = request;
        Toast.makeText(context, context.getString(R.string.approval_asked, name), Toast.LENGTH_LONG).show();
        Log.i(TAG, "Asking " + LogNames.key(key) + "'s phone to allow the switch"
                + (notifyService(context, key) == null ? " (Home Assistant's phones for their person)" : ""));
        request.waiter = HaBridgeService.events(context).await(ANSWER_MS, new HaEventSession.Listener() {
            @Override
            public void onOpen(HaEventSession.Waiter waiter) {
                if (sendRequest(context, request)) {
                    StringBuilder names = new StringBuilder();
                    for (String service : request.services) {
                        if (names.length() > 0) names.append(", ");
                        names.append(LogNames.of(service));
                    }
                    Log.i(TAG, "Home Assistant took the request for " + names);
                } else {
                    Log.i(TAG, "Couldn't send the request to the phone");
                    waiter.close();
                }
            }

            @Override
            public void onEvent(JSONObject data) {
                Boolean allowed = HaEvents.answer(data, ACTION_PREFIX, request.nonce);
                if (allowed != null) MAIN.post(() -> onAnswer(context, request, allowed));
            }

            @Override
            public void onEnd(boolean listened) {
                if (!listened) Log.i(TAG, "Couldn't listen for the phone's answer");
                MAIN.post(() -> {
                    if (sPending == request) {
                        sPending = null;
                        clearOnPhone(context, request);
                    }
                });
            }
        });
    }

    /** The request to each of its phones (the first answer decides); true when at least one took it. */
    private static boolean sendRequest(Context context, Request request) {
        boolean sent = false;
        for (String service : request.services) {
            try {
                sent |= HaApi.callService(context, "notify", service, new JSONObject()
                        .put("title", context.getString(R.string.approval_title, request.name))
                        .put("message", context.getString(R.string.approval_message))
                        .put("data", pushData(context.getString(R.string.approval_allow),
                                context.getString(R.string.approval_deny), request.nonce)));
            } catch (Exception e) {
                // The next phone
            }
        }
        // Also inside Home Assistant, so someone who opens it (or a push that was dismissed) can see the request
        if (sent) {
            try {
                HaApi.callService(context, "persistent_notification", "create", persistentNotification(context, request));
            } catch (Exception ignored) {
                // The phones have it
            }
        }
        return sent;
    }

    /**
     * The companion app's extras for the request: Allow and Deny buttons, and a tap on the notification itself does
     * nothing (not even open Home Assistant, which has nothing to answer) and doesn't dismiss it.
     */
    static JSONObject pushData(String allowTitle, String denyTitle, String nonce) throws Exception {
        JSONArray actions = new JSONArray()
                .put(new JSONObject().put("action", ACTION_PREFIX + "ALLOW_" + nonce).put("title", allowTitle))
                .put(new JSONObject().put("action", ACTION_PREFIX + "DENY_" + nonce).put("title", denyTitle));
        return new JSONObject().put("actions", actions).put("tag", TAG_PREFIX + nonce)
                .put("priority", "high").put("ttl", 0).put("timeout", ANSWER_MS / 1000)
                .put("channel", "Hearth").put("sticky", "true").put("clickAction", "noAction");
    }

    /** The same request as a notification in Home Assistant's own list, taken away when the request is over. */
    static JSONObject persistentNotification(Context context, Request request) throws Exception {
        return new JSONObject().put("notification_id", TAG_PREFIX + request.nonce)
                .put("title", context.getString(R.string.approval_title, request.name))
                .put("message", context.getString(R.string.approval_ha_message, ShareDiscovery.deviceName(context)));
    }

    /** Whether Google TV's PIN screen is what's in front, for this profile's account (main thread). */
    private static boolean pinScreenUpFor(Context context, String key) {
        AccessibilityNodeInfo root = LauncherAccessibilityService.activeRoot();
        if (root == null || !GooglePinRecipe.keypadUp(context, root)
                || !LauncherAccessibilityService.GOOGLE_TV_PACKAGE.contentEquals(root.getPackageName())) {
            return false;
        }
        String email = ProfileUsers.emailOf(context, key);
        List<CharSequence> texts = new ArrayList<>();
        collectTexts(root, texts, 0);
        return email != null && containsEmail(texts, email);
    }

    /**
     * A remote key while a request waits (main thread): someone at the TV is using the PIN screen themselves, so the
     * phone's answer must not type over what they do. The request ends and its notification goes from the phone.
     * Only a key someone presses on the PIN screen counts ({@link #endsRequest}): a held key's repeats, the keys a
     * TV's own power and volume buttons or an HDMI-CEC device send, and the press that picked the profile are not
     * typing the PIN. {@code downTime}: when the press began, in uptime.
     */
    static void onRemoteKey(Context context, int keyCode, int repeatCount, long downTime, String device) {
        Request request = sPending;
        if (request == null || !endsRequest(keyCode, repeatCount, downTime, request.pinShownAt)) return;
        sPending = null;
        if (request.waiter != null) request.waiter.close();
        Log.i(TAG, "The remote is in use on the PIN screen (key " + android.view.KeyEvent.keyCodeToString(keyCode)
                + " from " + device + ", " + (downTime - request.pinShownAt) + " ms after it came up): no longer asking"
                + " the phone");
        clearOnPhone(context, request);
    }

    /**
     * Whether a key pressed at {@code downTime} (uptime) means someone is using the PIN screen that came up at
     * {@code pinShownAt}: a first press of a key it takes ({@link #isPinScreenKey}) that began after it came up; a
     * digit at once, the arrows, OK, Back and Delete only once {@link #GRACE_MS} has passed (the OK that picked the
     * profile on the chooser, or a second press of it, lands in that time).
     */
    static boolean endsRequest(int keyCode, int repeatCount, long downTime, long pinShownAt) {
        if (!isPinScreenKey(keyCode, repeatCount) || downTime < pinShownAt) return false;
        return isDigit(keyCode) || downTime - pinShownAt >= GRACE_MS;
    }

    static boolean isDigit(int keyCode) {
        return (keyCode >= android.view.KeyEvent.KEYCODE_0 && keyCode <= android.view.KeyEvent.KEYCODE_9)
                || (keyCode >= android.view.KeyEvent.KEYCODE_NUMPAD_0 && keyCode <= android.view.KeyEvent.KEYCODE_NUMPAD_9);
    }

    /** A first press of a key the PIN screen takes: digits, the arrows, OK, Back, Delete. */
    static boolean isPinScreenKey(int keyCode, int repeatCount) {
        if (repeatCount != 0) return false;
        if (isDigit(keyCode)) return true;
        switch (keyCode) {
            case android.view.KeyEvent.KEYCODE_DPAD_UP:
            case android.view.KeyEvent.KEYCODE_DPAD_DOWN:
            case android.view.KeyEvent.KEYCODE_DPAD_LEFT:
            case android.view.KeyEvent.KEYCODE_DPAD_RIGHT:
            case android.view.KeyEvent.KEYCODE_DPAD_CENTER:
            case android.view.KeyEvent.KEYCODE_ENTER:
            case android.view.KeyEvent.KEYCODE_BACK:
            case android.view.KeyEvent.KEYCODE_DEL:
                return true;
            default:
                return false;
        }
    }

    /** The notification goes from the phones, and from Home Assistant's own list, once the request is over. */
    private static void clearOnPhone(Context context, Request request) {
        HaApi.EXECUTOR.execute(() -> {
            try {
                for (String service : request.services) {
                    HaApi.callService(context, "notify", service, new JSONObject().put("message", "clear_notification")
                            .put("data", new JSONObject().put("tag", TAG_PREFIX + request.nonce)));
                }
                HaApi.callService(context, "persistent_notification", "dismiss",
                        new JSONObject().put("notification_id", TAG_PREFIX + request.nonce));
            } catch (Exception e) {
                Log.i(TAG, "The notification wasn't cleared: " + e.getClass().getSimpleName());
            }
        });
    }

    private static void onAnswer(Context context, Request request, boolean allowed) {
        if (sPending != request) return;
        sPending = null;
        if (request.waiter != null) request.waiter.close();
        clearOnPhone(context, request);
        if (!allowed) {
            Log.i(TAG, LogNames.key(request.key) + " didn't allow the switch");
            Toast.makeText(context, context.getString(R.string.approval_denied, request.name), Toast.LENGTH_LONG).show();
            return;
        }
        // Only onto Google TV's PIN screen for that profile, still up (not one that closed, or someone typed the PIN)
        if (!pinScreenUpFor(context, request.key)) {
            Log.i(TAG, "Allowed, but Google TV's PIN screen is gone");
            return;
        }
        Log.i(TAG, LogNames.key(request.key) + " allowed the switch");
        ProfilePairingService.typeGooglePin(request.key, request.name);
    }
}
