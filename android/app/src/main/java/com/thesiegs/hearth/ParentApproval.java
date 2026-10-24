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
 * <p>Each request ({@link Request}) has its own nonce, listener and answer, so two never take each other's Allow: the
 * Parent PIN dialog has one current request ({@link #start}, {@link #poll}, {@link #cancel}), and a TV asking to join
 * the household (HouseholdJoining) asks with its own ({@link #ask}). An Allow is used once: {@link #poll} reports it once
 * and then forgets it, so it can't open a second dialog. Closing the dialog ends the request and takes the notification
 * off the phones.
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

    /** The Parent PIN dialog's request; null when none. */
    private static Request sCurrent;

    private ParentApproval() {
    }

    /** One question to the parents' phones and its answer. */
    static final class Request {
        private final Context context;
        private final String nonce;
        private final List<String> services;
        private String state = PENDING;
        private HaEvents events;

        private Request(Context context, String nonce, List<String> services) {
            this.context = context;
            this.nonce = nonce;
            this.services = services;
        }

        /** Where it stands: pending, allowed, denied or expired. */
        synchronized String state() {
            return state;
        }

        private void answer(String answer) {
            HaEvents listening;
            synchronized (this) {
                if (!PENDING.equals(state)) return;
                state = answer;
                listening = events;
            }
            Log.i(TAG, "A parent phone answered: " + answer);
            if (listening != null) listening.close();
        }

        /** Ends it if it still waits, and takes its notification off the phones. */
        void cancel() {
            HaEvents listening;
            synchronized (this) {
                if (!PENDING.equals(state)) return;
                state = EXPIRED;
                listening = events;
            }
            if (listening != null) listening.close();
            clearOnPhones(context, nonce, services);
        }
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

    /** The Parent PIN dialog asks the parents' phones. Returns how many it asked (0: no Home Assistant, or no phone). */
    static int start(Context context) {
        cancel(context);
        String profile = ProfileUsers.displayName(context, LauncherAccessibilityService.getActiveProfileKey(context));
        String tv = ShareDiscovery.deviceName(context);
        Request request = ask(context, context.getString(R.string.parent_approval_title),
                context.getString(R.string.parent_approval_message, profile, tv),
                context.getString(R.string.parent_approval_ha_message, profile, tv));
        if (request == null) return 0;
        synchronized (ParentApproval.class) {
            sCurrent = request;
        }
        return request.services.size();
    }

    /**
     * Asks the parents' phones something, in its own words: {@code message} on the phone, {@code haMessage} in Home
     * Assistant's own list. Null when there is no one to ask (no Home Assistant, or no phone chosen).
     */
    static Request ask(Context context, String title, String message, String haMessage) {
        if (!HaConfig.isConfigured(context)) return null;
        List<String> services = parentPhones(context);
        if (services.isEmpty()) return null;
        byte[] bytes = new byte[8];
        RANDOM.nextBytes(bytes);
        Request request = new Request(context, AgentAuth.hex(bytes), services);
        String nonce = request.nonce;
        Log.i(TAG, "Asking " + services.size() + " parent phone(s): " + title);
        WORKER.execute(() -> {
            boolean listened = HaEvents.listen(context, PhoneApproval.EVENT, PhoneApproval.ANSWER_MS, data -> {
                String action = data != null ? data.optString("action") : "";
                if (action.equals(ACTION_PREFIX + "ALLOW_" + nonce)) {
                    request.answer(ALLOWED);
                } else if (action.equals(ACTION_PREFIX + "DENY_" + nonce)) {
                    request.answer(DENIED);
                }
            }, events -> {
                boolean waiting;
                synchronized (request) {
                    waiting = PENDING.equals(request.state);
                    if (waiting) request.events = events;
                }
                if (!waiting) {
                    events.close();
                    return;
                }
                int sent = 0;
                for (String service : services) {
                    if (send(context, service, nonce, title, message)) sent++;
                }
                if (sent == 0) {
                    Log.i(TAG, "Couldn't send the request to a parent phone");
                    events.close();
                } else {
                    postPersistent(context, nonce, title, haMessage);
                }
            });
            if (!listened) Log.i(TAG, "Couldn't listen for a parent phone's answer");
            synchronized (request) {
                if (PENDING.equals(request.state)) request.state = EXPIRED;
            }
            clearOnPhones(context, nonce, services);
        });
        return request;
    }

    /** Where the Parent PIN dialog's request stands: none, pending, allowed (reported once), denied or expired. */
    static String poll() {
        synchronized (ParentApproval.class) {
            if (sCurrent == null) return NONE;
            String state = sCurrent.state();
            if (ALLOWED.equals(state)) sCurrent = null;
            return state;
        }
    }

    /** The Parent PIN dialog closed: ends its request if it still waits and takes the notification off the phones. */
    static void cancel(Context context) {
        Request request;
        synchronized (ParentApproval.class) {
            request = sCurrent;
            sCurrent = null;
        }
        if (request != null) request.cancel();
    }

    private static boolean send(Context context, String service, String nonce, String title, String message) {
        try {
            return HaApi.callService(context, "notify", service, new JSONObject()
                    .put("title", title)
                    .put("message", message)
                    .put("data", pushData(context.getString(R.string.approval_allow),
                            context.getString(R.string.approval_deny), nonce)));
        } catch (Exception e) {
            return false;
        }
    }

    /** The same request in Home Assistant's own list, for someone who opens it or a push that was dismissed. */
    private static void postPersistent(Context context, String nonce, String title, String message) {
        try {
            HaApi.callService(context, "persistent_notification", "create", new JSONObject()
                    .put("notification_id", TAG_PREFIX + nonce)
                    .put("title", title)
                    .put("message", message));
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
