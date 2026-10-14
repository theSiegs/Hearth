package com.thesiegs.hearth;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;

/**
 * The TV's connection, for the top bar's data usage (Flutter's NetworkService): how it's connected ("wifi", "wired",
 * "cellular" or "none"), whether a VPN is on, and whether the connection reaches the internet (Android has validated
 * it). Read once on request, and sent again whenever Android's default network changes.
 */
final class NetworkStatus implements EventChannel.StreamHandler {
    static final String CHANNEL = "com.thesiegs.hearth/network";
    private static final String TAG = "HearthNetwork";

    private final Context mContext;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private ConnectivityManager.NetworkCallback mCallback;

    NetworkStatus(Context context) {
        mContext = context.getApplicationContext();
    }

    /** {type, vpn, internet} for the default network now. */
    static Map<String, Object> read(Context context) {
        Map<String, Object> status = new HashMap<>();
        status.put("type", "none");
        status.put("vpn", false);
        status.put("internet", false);
        ConnectivityManager connectivity = context.getSystemService(ConnectivityManager.class);
        if (connectivity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return status;
        try {
            Network active = connectivity.getActiveNetwork();
            NetworkCapabilities caps = active != null ? connectivity.getNetworkCapabilities(active) : null;
            if (caps == null) return status;
            boolean vpn = caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
            status.put("vpn", vpn);
            status.put("internet", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
            String type = typeOf(caps);
            // A VPN's own network says nothing about the link under it: that's the other network carrying traffic
            if (type == null && vpn) {
                for (Network network : connectivity.getAllNetworks()) {
                    NetworkCapabilities other = connectivity.getNetworkCapabilities(network);
                    if (other != null && !other.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                            && other.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                        type = typeOf(other);
                        if (type != null) break;
                    }
                }
            }
            status.put("type", type != null ? type : "none");
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't read the network: " + e.getClass().getSimpleName());
        }
        return status;
    }

    private static String typeOf(NetworkCapabilities caps) {
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) return "wired";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return "wifi";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return "cellular";
        return null;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        ConnectivityManager connectivity = mContext.getSystemService(ConnectivityManager.class);
        events.success(read(mContext));
        if (connectivity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return;
        Runnable send = () -> events.success(read(mContext));
        mCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onCapabilitiesChanged(Network network, NetworkCapabilities caps) {
                mMain.post(send);
            }

            @Override
            public void onLost(Network network) {
                mMain.post(send);
            }
        };
        try {
            connectivity.registerDefaultNetworkCallback(mCallback);
        } catch (RuntimeException e) {
            Log.w(TAG, "Couldn't follow the network: " + e.getClass().getSimpleName());
            mCallback = null;
        }
    }

    @Override
    public void onCancel(Object arguments) {
        ConnectivityManager connectivity = mContext.getSystemService(ConnectivityManager.class);
        if (connectivity != null && mCallback != null) {
            try {
                connectivity.unregisterNetworkCallback(mCallback);
            } catch (RuntimeException ignored) {
                // Already gone
            }
        }
        mCallback = null;
    }
}
