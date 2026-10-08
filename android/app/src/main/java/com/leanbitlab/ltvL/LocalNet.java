package com.leanbitlab.ltvL;

import java.net.InetAddress;
import java.net.URL;
import java.net.UnknownHostException;

/**
 * The home network rule: Hearth's own servers answer only addresses on it, and Hearth sends plain HTTP only to
 * hosts on it, so nothing (a token, what's on screen) crosses the internet unencrypted.
 */
final class LocalNet {
    private LocalNet() {}

    /** This TV or an address on the home network: private IPv4 ranges, link-local, or IPv6 unique local. */
    static boolean isLocal(InetAddress address) {
        return address.isLoopbackAddress() || address.isSiteLocalAddress() || address.isLinkLocalAddress()
                || isUniqueLocalIpv6(address);
    }

    /**
     * Whether a request to this URL may go out: https anywhere, plain http only to the home network, nothing
     * else. Throws when a plain http URL's host can't be resolved.
     */
    static boolean allows(URL url) throws UnknownHostException {
        String protocol = url.getProtocol();
        if ("https".equalsIgnoreCase(protocol)) return true;
        return "http".equalsIgnoreCase(protocol) && isLocal(InetAddress.getByName(url.getHost()));
    }

    private static boolean isUniqueLocalIpv6(InetAddress address) {
        byte[] bytes = address.getAddress();
        return bytes.length == 16 && (bytes[0] & 0xFE) == 0xFC;
    }
}
