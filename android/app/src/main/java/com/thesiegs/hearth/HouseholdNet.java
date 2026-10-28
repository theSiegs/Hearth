package com.thesiegs.hearth;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.util.Log;

import java.io.IOException;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * How the TVs of a household find each other and talk (docs/household-sync.md): each TV in one announces
 * {@code _hearth-sync._tcp} on the home network (its name is the TV's id; attributes carry the household's id, which is
 * not secret and not the key, and the TV's name), listens on a port of its own, and lists the others it hears. Only
 * addresses on the home network are taken or answered (LocalNet). What crosses is only ever sealed under the household
 * key (HouseholdSync): a stranger who connects learns nothing and takes nothing.
 *
 * <p>A TV in no household can look without announcing ({@link #lookAround}), to show that one is there to join.
 */
final class HouseholdNet {
    private static final String TAG = "HearthHouseholdNet";
    static final String TYPE = "_hearth-sync._tcp.";
    private static final String HOUSEHOLD_ATTRIBUTE = "h";
    private static final String NAME_ATTRIBUTE = "n";
    private static final int MAX_NAME = 60;

    /** Another TV of the household, as found. */
    static final class Peer {
        final String tvId;
        final String host;
        final int port;
        /** What the TV is called, as it announces it; null from a TV too old to say. */
        final String name;

        Peer(String tvId, String host, int port, String name) {
            this.tvId = tvId;
            this.host = host;
            this.port = port;
            this.name = name;
        }
    }

    /** A TV of any household heard on the network (not proof it is in one: the id isn't secret). */
    static final class Heard {
        final String tvId;
        final String householdId;
        final String name;
        /** Where it listens, for a TV that asks to join its household; null host when not known. */
        final String host;
        final int port;

        Heard(String tvId, String householdId, String name) {
            this(tvId, householdId, name, null, 0);
        }

        Heard(String tvId, String householdId, String name, String host, int port) {
            this.tvId = tvId;
            this.householdId = householdId;
            this.name = name;
            this.host = host;
            this.port = port;
        }
    }

    /** Something connected and is local: the caller runs the exchange (and closes the socket). */
    interface Handler {
        void accepted(Socket socket);
    }

    // Every s* field here is guarded by HouseholdNet.class (the NSD callbacks take it too).
    private static NsdManager sManager;
    private static NsdManager.RegistrationListener sRegistration;
    private static NsdManager.DiscoveryListener sDiscovery;
    private static ServerSocket sServer;
    private static Thread sAcceptor;
    private static String sTvId;
    private static String sHouseholdId;
    private static final Map<String, Peer> sPeers = new LinkedHashMap<>();
    private static final Map<String, Heard> sHeard = new LinkedHashMap<>();
    private static final Deque<NsdServiceInfo> sToResolve = new ArrayDeque<>();
    private static boolean sResolving;

    private HouseholdNet() {
    }

    /** Listens, announces and looks, for this household. Does nothing if it is already running for it. */
    static synchronized void start(Context context, String tvId, String householdId, Handler handler) {
        if (sServer != null && tvId.equals(sTvId) && householdId.equals(sHouseholdId)) return;
        stop();
        sTvId = tvId;
        sHouseholdId = householdId;
        try {
            sServer = new ServerSocket(0);
        } catch (IOException e) {
            Log.w(TAG, "Couldn't listen for the household: " + Household.why(e));
            sServer = null;
            return;
        }
        final ServerSocket server = sServer;
        sAcceptor = new Thread(() -> acceptLoop(server, handler), "household-accept");
        sAcceptor.setDaemon(true);
        sAcceptor.start();
        NsdManager manager = manager(context);
        if (manager == null) return;
        announce(manager, tvId, householdId, server.getLocalPort(), ShareDiscovery.deviceName(context));
        discover(manager);
    }

    /**
     * Looks for the TVs of any household without announcing this one (a TV in none, on the Household page or in
     * setup). Does nothing while this TV runs for a household: it is looking already.
     */
    static synchronized void lookAround(Context context) {
        if (sServer != null || sDiscovery != null) return;
        NsdManager manager = manager(context);
        if (manager != null) discover(manager);
    }

    /** Stops what {@link #lookAround} started; a household's own looking goes on. */
    static synchronized void stopLooking() {
        if (sServer == null) stop();
    }

    /** The TVs of any household heard so far, this one left out. */
    static synchronized List<Heard> heard() {
        return new ArrayList<>(sHeard.values());
    }

    static synchronized void stop() {
        if (sManager != null) {
            if (sRegistration != null) {
                try {
                    sManager.unregisterService(sRegistration);
                } catch (RuntimeException ignored) {
                }
            }
            if (sDiscovery != null) {
                try {
                    sManager.stopServiceDiscovery(sDiscovery);
                } catch (RuntimeException ignored) {
                }
            }
        }
        sRegistration = null;
        sDiscovery = null;
        if (sServer != null) {
            try {
                sServer.close();
            } catch (IOException ignored) {
            }
        }
        sServer = null;
        sAcceptor = null;
        sPeers.clear();
        sHeard.clear();
        sToResolve.clear();
        sResolving = false;
        sTvId = null;
        sHouseholdId = null;
    }

    /** The other TVs of the household heard so far. */
    static synchronized List<Peer> peers() {
        return new ArrayList<>(sPeers.values());
    }

    private static void acceptLoop(ServerSocket server, Handler handler) {
        while (!server.isClosed()) {
            try {
                Socket socket = server.accept();
                InetAddress remote = socket.getInetAddress();
                if (remote == null || !LocalNet.isLocal(remote)) {
                    socket.close();
                    continue;
                }
                handler.accepted(socket);
            } catch (IOException e) {
                if (!server.isClosed()) Log.i(TAG, "Accept failed: " + Household.why(e));
            }
        }
    }

    private static void announce(NsdManager manager, String tvId, String householdId, int port, String name) {
        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName(tvId);
        info.setServiceType(TYPE);
        info.setPort(port);
        info.setAttribute(HOUSEHOLD_ATTRIBUTE, householdId);
        if (name != null && !name.isEmpty()) {
            info.setAttribute(NAME_ATTRIBUTE, name.length() > MAX_NAME ? name.substring(0, MAX_NAME) : name);
        }
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
            Log.i(TAG, "Couldn't announce this TV: " + Household.why(e));
            sRegistration = null;
        }
    }

    private static void discover(NsdManager manager) {
        sDiscovery = new NsdManager.DiscoveryListener() {
            @Override public void onStartDiscoveryFailed(String serviceType, int errorCode) {
                Log.i(TAG, "Couldn't look for the household: " + errorCode);
            }

            @Override public void onStopDiscoveryFailed(String serviceType, int errorCode) {
            }

            @Override public void onDiscoveryStarted(String serviceType) {
            }

            @Override public void onDiscoveryStopped(String serviceType) {
            }

            @Override public void onServiceFound(NsdServiceInfo serviceInfo) {
                synchronized (HouseholdNet.class) {
                    if (serviceInfo.getServiceName().equals(sTvId)) return;
                    sToResolve.add(serviceInfo);
                    resolveNext();
                }
            }

            @Override public void onServiceLost(NsdServiceInfo serviceInfo) {
                synchronized (HouseholdNet.class) {
                    sPeers.remove(serviceInfo.getServiceName());
                    sHeard.remove(serviceInfo.getServiceName());
                }
            }
        };
        try {
            manager.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, sDiscovery);
        } catch (RuntimeException e) {
            Log.i(TAG, "Couldn't look for the household: " + Household.why(e));
            sDiscovery = null;
        }
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
                    String household = attribute(serviceInfo, HOUSEHOLD_ATTRIBUTE);
                    String name = attribute(serviceInfo, NAME_ATTRIBUTE);
                    String tvId = serviceInfo.getServiceName();
                    synchronized (HouseholdNet.class) {
                        if (host != null && LocalNet.isLocal(host) && household != null && !tvId.equals(sTvId)) {
                            sHeard.put(tvId, new Heard(tvId, household, name, host.getHostAddress(),
                                    serviceInfo.getPort()));
                            if (household.equals(sHouseholdId)) {
                                sPeers.put(tvId, new Peer(tvId, host.getHostAddress(), serviceInfo.getPort(), name));
                                Household.peerFound();
                            }
                        }
                    }
                    done();
                }

                private void done() {
                    synchronized (HouseholdNet.class) {
                        sResolving = false;
                        resolveNext();
                    }
                }
            });
        } catch (RuntimeException e) {
            sResolving = false;
        }
    }

    private static String attribute(NsdServiceInfo info, String key) {
        byte[] value = info.getAttributes().get(key);
        if (value == null) return null;
        String text = new String(value, StandardCharsets.UTF_8).trim();
        if (text.isEmpty()) return null;
        // A name is shown on the screen: kept short. The household's id is compared whole.
        return NAME_ATTRIBUTE.equals(key) && text.length() > MAX_NAME ? text.substring(0, MAX_NAME) : text;
    }

    private static NsdManager manager(Context context) {
        if (sManager == null) {
            sManager = (NsdManager) context.getApplicationContext().getSystemService(Context.NSD_SERVICE);
        }
        return sManager;
    }
}
