package com.thesiegs.hearth;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import java.net.InetAddress;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * How a TV that wants a profile finds the one that has it, without typing an address with a remote: the sending TV
 * announces itself on the home network while its copy waits (service type {@code _hearth-share._tcp}), and the
 * receiving TV lists what it hears. Only an address on the home network is taken (LocalNet). The announcement says
 * the TV's name and port and nothing else; what is copied is only ever sent after the digits match (ShareSession).
 */
final class ShareDiscovery {
    private static final String TAG = "HearthShareFind";
    static final String TYPE = "_hearth-share._tcp.";

    private static NsdManager sManager;
    private static NsdManager.RegistrationListener sRegistration;
    private static NsdManager.DiscoveryListener sDiscovery;
    /** Found services by name, resolved to an address; names waiting to be resolved, one at a time. */
    private static final Map<String, Map<String, Object>> sFound = new LinkedHashMap<>();
    private static final Deque<NsdServiceInfo> sToResolve = new ArrayDeque<>();
    private static boolean sResolving;

    private ShareDiscovery() {
    }

    /** What the TV is called to its owner (Settings > Device name), else its model. */
    static String deviceName(Context context) {
        String name = null;
        try {
            name = Settings.Global.getString(context.getContentResolver(), "device_name");
        } catch (RuntimeException ignored) {
        }
        return name == null || name.trim().isEmpty() ? Build.MODEL : name.trim();
    }

    /** Announces this TV's waiting copy on {@code port} until {@link #stopAdvertising}. */
    static synchronized void advertise(Context context, int port) {
        stopAdvertising();
        NsdManager manager = manager(context);
        if (manager == null) return;
        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName(deviceName(context));
        info.setServiceType(TYPE);
        info.setPort(port);
        sRegistration = new NsdManager.RegistrationListener() {
            @Override public void onRegistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                Log.i(TAG, "Couldn't announce this TV: " + errorCode);
            }

            @Override public void onUnregistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
            }

            @Override public void onServiceRegistered(NsdServiceInfo serviceInfo) {
            }

            @Override public void onServiceUnregistered(NsdServiceInfo serviceInfo) {
            }
        };
        try {
            manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, sRegistration);
        } catch (RuntimeException e) {
            Log.i(TAG, "Couldn't announce this TV: " + e.getClass().getSimpleName());
            sRegistration = null;
        }
    }

    static synchronized void stopAdvertising() {
        if (sManager != null && sRegistration != null) {
            try {
                sManager.unregisterService(sRegistration);
            } catch (RuntimeException ignored) {
            }
        }
        sRegistration = null;
    }

    /** Starts listening for TVs that are waiting to send; {@link #found} lists them. */
    static synchronized void startFinding(Context context) {
        stopFinding();
        NsdManager manager = manager(context);
        if (manager == null) return;
        sDiscovery = new NsdManager.DiscoveryListener() {
            @Override public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                Log.i(TAG, "Couldn't look for TVs: " + errorCode);
            }

            @Override public void onStopDiscoveryFailed(String serviceType, int errorCode) {
            }

            @Override public void onDiscoveryStarted(String serviceType) {
            }

            @Override public void onDiscoveryStopped(String serviceType) {
            }

            @Override public void onServiceFound(NsdServiceInfo serviceInfo) {
                synchronized (ShareDiscovery.class) {
                    sToResolve.add(serviceInfo);
                    resolveNext();
                }
            }

            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {
                synchronized (ShareDiscovery.class) {
                    sFound.remove(serviceInfo.getServiceName());
                }
            }
        };
        try {
            manager.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, sDiscovery);
        } catch (RuntimeException e) {
            Log.i(TAG, "Couldn't look for TVs: " + e.getClass().getSimpleName());
            sDiscovery = null;
        }
    }

    static synchronized void stopFinding() {
        if (sManager != null && sDiscovery != null) {
            try {
                sManager.stopServiceDiscovery(sDiscovery);
            } catch (RuntimeException ignored) {
            }
        }
        sDiscovery = null;
        sFound.clear();
        sToResolve.clear();
        sResolving = false;
    }

    /** The TVs found so far on the home network: {name, host, port}. */
    static synchronized List<Map<String, Object>> found() {
        return new ArrayList<>(sFound.values());
    }

    @SuppressWarnings("deprecation") // resolveService is what API 28 to 33 have
    private static void resolveNext() {
        if (sResolving || sToResolve.isEmpty() || sManager == null) return;
        NsdServiceInfo next = sToResolve.poll();
        sResolving = true;
        try {
            sManager.resolveService(next, new NsdManager.ResolveListener() {
                @Override public void onResolveFailed(NsdServiceInfo serviceInfo, int errorCode) {
                    done();
                }

                @Override public void onServiceResolved(NsdServiceInfo serviceInfo) {
                    InetAddress host = serviceInfo.getHost();
                    synchronized (ShareDiscovery.class) {
                        if (host != null && LocalNet.isLocal(host)) {
                            Map<String, Object> tv = new HashMap<>();
                            tv.put("name", serviceInfo.getServiceName());
                            tv.put("host", host.getHostAddress());
                            tv.put("port", serviceInfo.getPort());
                            sFound.put(serviceInfo.getServiceName(), tv);
                        }
                    }
                    done();
                }

                private void done() {
                    synchronized (ShareDiscovery.class) {
                        sResolving = false;
                        resolveNext();
                    }
                }
            });
        } catch (RuntimeException e) {
            sResolving = false;
        }
    }

    private static NsdManager manager(Context context) {
        if (sManager == null) {
            sManager = (NsdManager) context.getApplicationContext().getSystemService(Context.NSD_SERVICE);
        }
        return sManager;
    }
}
