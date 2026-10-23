package com.thesiegs.hearth;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * A parent allows what asks for the Parent PIN from their phone, instead of the PIN being typed with the remote. When
 * the Parent PIN dialog opens, Hearth sends the phones of the adults who have phone approval on (PhoneApproval's
 * switch and notify service, set from each adult's own profile) an actionable Home Assistant notification and listens
 * for the answer (HaEvents). Allow: the dialog completes as if the PIN had been entered. Deny, or no answer: the dialog
 * stays and the PIN still works. Typing the PIN is never blocked while a request waits.
 *
 * <p>One request at a time. An Allow is used once: {@link #poll} reports it once and then forgets it, so it can't
 * open a second dialog. Closing the dialog ends the request and takes the notification off the phones.
 */
final class ParentApproval {
    private static final String TAG = "HearthApproval";
    static final String NONE = "none";
    static final String PENDING = "pending";
    static final String ALLOWED = "allowed";
    static final String DENIED = "denied";
    static final String EXPIRED = "expired";
    private static final String ACTION_PREFIX = "HEARTH_PARENT_";
    private static final String TAG_PREFIX = "hearth-parent-";
    private static final ExecutorService WORKER = Executors.newCachedThreadPool();
    private static final SecureRandom RANDOM = new SecureRandom();

    private static String sNonce;
    private static String sState = NONE;
    private static HaEvents sEvents;
    private static List<String> sServices = new ArrayList<>();

    private ParentApproval() {
    }

    /** The phones that may answer: each adult profile that has phone approval on and a phone chosen, once each. */
    static List<String> parentPhones(Context context) {
        Set<String> services = new LinkedHashSet<>();
        for (String key : ProfilePairing.getHearthProfiles(context)) {
            if (ProfilePairing.isKids(context, key) || !PhoneApproval.isOn(context, key)) continue;
            String service = PhoneApproval.notifyService(context, key);
            if (service != null) services.add(service);
        }
        return new ArrayList<>(services);
    }

    /** Asks the parents' phones. Returns how many it asked (0: Home Assistant isn't set up, or no phone is chosen). */
    static int start(Context context) {
        cancel(context);
        if (!HaConfig.isConfigured(context)) return 0;
        List<String> services = parentPhones(context);
        if (services.isEmpty()) return 0;
        byte[] bytes = new byte[8];
        RANDOM.nextBytes(bytes);
        String nonce = AgentAuth.hex(bytes);
        String profile = ProfileUsers.displayName(context, LauncherAccessibilityService.getActiveProfileKey(context));
        synchronized (ParentApproval.class) {
            sNonce = nonce;
            sState = PENDING;
            sServices = services;
        }
        Log.i(TAG, "Asking " + services.size() + " parent phone(s) to allow what asks for the Parent PIN");
        WORKER.execute(() -> {
            boolean listened = HaEvents.listen(context, PhoneApproval.EVENT, PhoneApproval.ANSWER_MS, data -> {
                String action = data != null ? data.optString("action") : "";
                if (action.equals(ACTION_PREFIX + "ALLOW_" + nonce)) {
                    answer(nonce, ALLOWED);
                } else if (action.equals(ACTION_PREFIX + "DENY_" + nonce)) {
                    answer(nonce, DENIED);
                }
            }, events -> {
                boolean current;
                synchronized (ParentApproval.class) {
                    current = nonce.equals(sNonce) && PENDING.equals(sState);
                    if (current) sEvents = events;
                }
                if (!current) {
                    events.close();
                    return;
                }
                int sent = 0;
                for (String service : services) {
                    if (send(context, service, nonce, profile)) sent++;
                }
                if (sent == 0) {
                    Log.i(TAG, "Couldn't send the request to a parent phone");
                    events.close();
                } else {
                    postPersistent(context, nonce, profile);
                }
            });
            if (!listened) Log.i(TAG, "Couldn't listen for a parent phone's answer");
            synchronized (ParentApproval.class) {
                if (nonce.equals(sNonce) && PENDING.equals(sState)) sState = EXPIRED;
            }
            clearOnPhones(context, nonce, services);
        });
        return services.size();
    }

    private static void answer(String nonce, String state) {
        HaEvents events;
        synchronized (ParentApproval.class) {
            if (!nonce.equals(sNonce) || !PENDING.equals(sState)) return;
            sState = state;
            events = sEvents;
        }
        Log.i(TAG, "A parent phone answered: " + state);
        if (events != null) events.close();
    }

    /** Where the request stands: none, pending, allowed (reported once), denied or expired. */
    static synchronized String poll() {
        String state = sState;
        if (ALLOWED.equals(state)) {
            sState = NONE;
            sNonce = null;
        }
        return state;
    }

    /** The dialog closed: ends a request still waiting and takes its notification off the phones. */
    static void cancel(Context context) {
        String nonce;
        List<String> services;
        HaEvents events;
        synchronized (ParentApproval.class) {
            nonce = sNonce;
            services = sServices;
            events = sEvents;
            boolean waiting = PENDING.equals(sState);
            sNonce = null;
            sState = NONE;
            sEvents = null;
            sServices = new ArrayList<>();
            if (nonce == null || !waiting) return;
        }
        if (events != null) events.close();
        clearOnPhones(context, nonce, services);
    }

    private static boolean send(Context context, String service, String nonce, String profile) {
        try {
            return HaApi.callService(context, "notify", service, new JSONObject()
                    .put("title", context.getString(R.string.parent_approval_title))
                    .put("message", context.getString(R.string.parent_approval_message, profile,
                            ShareDiscovery.deviceName(context)))
                    .put("data", pushData(context.getString(R.string.approval_allow),
                            context.getString(R.string.approval_deny), nonce)));
        } catch (Exception e) {
            return false;
        }
    }

    /** The same request in Home Assistant's own list, for someone who opens it or a push that was dismissed. */
    private static void postPersistent(Context context, String nonce, String profile) {
        try {
            HaApi.callService(context, "persistent_notification", "create", new JSONObject()
                    .put("notification_id", TAG_PREFIX + nonce)
                    .put("title", context.getString(R.string.parent_approval_title))
                    .put("message", context.getString(R.string.parent_approval_ha_message, profile,
                            ShareDiscovery.deviceName(context))));
        } catch (Exception e) {
            Log.i(TAG, "The request wasn't posted in Home Assistant: " + e.getClass().getSimpleName());
        }
    }

    /** Allow and Deny buttons; a tap on the notification itself does nothing and doesn't dismiss it. */
    static JSONObject pushData(String allowTitle, String denyTitle, String nonce) throws Exception {
        JSONArray actions = new JSONArray()
                .put(new JSONObject().put("action", ACTION_PREFIX + "ALLOW_" + nonce).put("title", allowTitle))
                .put(new JSONObject().put("action", ACTION_PREFIX + "DENY_" + nonce).put("title", denyTitle));
        return new JSONObject().put("actions", actions).put("tag", TAG_PREFIX + nonce)
                .put("priority", "high").put("ttl", 0).put("timeout", PhoneApproval.ANSWER_MS / 1000)
                .put("channel", "Hearth").put("sticky", "true").put("clickAction", "noAction");
    }

    private static void clearOnPhones(Context context, String nonce, List<String> services) {
        HaApi.EXECUTOR.execute(() -> {
            try {
                for (String service : services) {
                    HaApi.callService(context, "notify", service, new JSONObject().put("message", "clear_notification")
                            .put("data", new JSONObject().put("tag", TAG_PREFIX + nonce)));
                }
                HaApi.callService(context, "persistent_notification", "dismiss",
                        new JSONObject().put("notification_id", TAG_PREFIX + nonce));
            } catch (Exception e) {
                Log.i(TAG, "The notification wasn't cleared: " + e.getClass().getSimpleName());
            }
        });
    }
}
