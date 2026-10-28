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
 * is in PinVault under the profile's key.
 */
final class PhoneApproval {
    private static final String TAG = "HearthApproval";
    private static final String PREFS = "phone_approval";
    static final String EVENT = "mobile_app_notification_action";
    private static final String ACTION_PREFIX = "HEARTH_APPROVE_";
    private static final String TAG_PREFIX = "hearth-approval-";
    /** How long a phone has to answer. */
    static final long ANSWER_MS = 120_000;
    private static final ExecutorService WORKER = Executors.newCachedThreadPool();
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** The request waiting for an answer, if any (main thread). */
    private static Request sPending;

    static final class Request {
        final String key;
        final String name;
        final String nonce;
        final long at = SystemClock.elapsedRealtime();
        /** Its wait for the phone's answer (main thread). */
        HaEventSession.Waiter waiter;

        Request(String key, String name, String nonce) {
            this.key = key;
            this.name = name;
            this.nonce = nonce;
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

    static void setOn(Context context, String key, boolean on) {
        prefs(context).edit().putBoolean(key + "|on", on).apply();
    }

    /** The Home Assistant notify service that reaches this profile's owner ("mobile_app_alex_phone"), or null. */
    static String notifyService(Context context, String key) {
        return key == null ? null : prefs(context).getString(key + "|notify", null);
    }

    static void setNotifyService(Context context, String key, String service) {
        if (service == null || !isNotifyService(service)) {
            prefs(context).edit().remove(key + "|notify").apply();
        } else {
            prefs(context).edit().putString(key + "|notify", service).apply();
        }
    }

    /** Only a companion app's notify service: what a phone's actionable notifications go through. */
    static boolean isNotifyService(String service) {
        return service != null && service.matches("mobile_app_[a-z0-9_]{1,100}");
    }

    static boolean hasPin(Context context, String key) {
        return PinVault.has(context, key, LauncherAccessibilityService.GOOGLE_TV_PACKAGE, GooglePinRecipe.VAULT_NAME);
    }

    /** Everything this profile needs for an approval: Home Assistant, the switch, a phone and the PIN. */
    static boolean isReady(Context context, String key) {
        return HaConfig.isConfigured(context) && isOn(context, key) && notifyService(context, key) != null
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

    /** A plain notification to the chosen phone, so its owner knows it reaches them. False when it couldn't be sent. */
    static boolean sendTest(Context context, String key) {
        String service = notifyService(context, key);
        if (service == null) return false;
        try {
            return HaApi.callService(context, "notify", service, new JSONObject()
                    .put("title", context.getString(R.string.approval_test_title))
                    .put("message", context.getString(R.string.approval_test_message)));
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Google TV's PIN screen came up (LauncherAccessibilityService, main thread). Works out whose it is from the account
     * address it shows, off the main thread, and asks that person's phone if they have this on.
     */
    static void onPinScreen(LauncherAccessibilityService service) {
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
            MAIN.post(() -> ask(context, key, name));
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
    private static void ask(Context context, String key, String name) {
        Request pending = sPending;
        // The same profile's screen again (Google redraws it): still the same request
        if (pending != null && pending.key.equals(key) && SystemClock.elapsedRealtime() - pending.at < ANSWER_MS) return;
        if (pending != null && pending.waiter != null) pending.waiter.close();
        byte[] bytes = new byte[8];
        RANDOM.nextBytes(bytes);
        Request request = new Request(key, name, AgentAuth.hex(bytes));
        sPending = request;
        String service = notifyService(context, key);
        Toast.makeText(context, context.getString(R.string.approval_asked, name), Toast.LENGTH_LONG).show();
        Log.i(TAG, "Asking " + LogNames.key(key) + "'s phone to allow the switch");
        request.waiter = HaBridgeService.events(context).await(ANSWER_MS, new HaEventSession.Listener() {
            @Override
            public void onOpen(HaEventSession.Waiter waiter) {
                if (sendRequest(context, service, request)) {
                    Log.i(TAG, "Home Assistant took the request for " + LogNames.of(service));
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
                        clearOnPhone(context, service, request);
                    }
                });
            }
        });
    }

    private static boolean sendRequest(Context context, String service, Request request) {
        try {
            boolean sent = HaApi.callService(context, "notify", service, new JSONObject()
                    .put("title", context.getString(R.string.approval_title, request.name))
                    .put("message", context.getString(R.string.approval_message))
                    .put("data", pushData(context.getString(R.string.approval_allow),
                            context.getString(R.string.approval_deny), request.nonce)));
            // Also inside Home Assistant, so someone who opens it (or a push that was dismissed) can see the request
            if (sent) {
                HaApi.callService(context, "persistent_notification", "create", persistentNotification(context, request));
            }
            return sent;
        } catch (Exception e) {
            return false;
        }
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
     * Only a key someone presses on the PIN screen counts: a held key's repeats, and the keys a TV's own power and
     * volume buttons or an HDMI-CEC device send, are not typing the PIN.
     */
    static void onRemoteKey(Context context, int keyCode, int repeatCount, String device) {
        Request request = sPending;
        if (request == null || !isPinScreenKey(keyCode, repeatCount)) return;
        sPending = null;
        if (request.waiter != null) request.waiter.close();
        Log.i(TAG, "The remote is in use on the PIN screen (key " + android.view.KeyEvent.keyCodeToString(keyCode)
                + " from " + device + "): no longer asking the phone");
        clearOnPhone(context, notifyService(context, request.key), request);
    }

    /** A first press of a key the PIN screen takes: digits, the arrows, OK, Back, Delete. */
    static boolean isPinScreenKey(int keyCode, int repeatCount) {
        if (repeatCount != 0) return false;
        if (keyCode >= android.view.KeyEvent.KEYCODE_0 && keyCode <= android.view.KeyEvent.KEYCODE_9) return true;
        if (keyCode >= android.view.KeyEvent.KEYCODE_NUMPAD_0 && keyCode <= android.view.KeyEvent.KEYCODE_NUMPAD_9) return true;
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

    /** The notification goes from the phone, and from Home Assistant's own list, once the request is over. */
    private static void clearOnPhone(Context context, String service, Request request) {
        HaApi.EXECUTOR.execute(() -> {
            try {
                HaApi.callService(context, "notify", service, new JSONObject().put("message", "clear_notification")
                        .put("data", new JSONObject().put("tag", TAG_PREFIX + request.nonce)));
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
        clearOnPhone(context, notifyService(context, request.key), request);
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
