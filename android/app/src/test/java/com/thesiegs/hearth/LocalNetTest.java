package com.thesiegs.hearth;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.net.InetAddress;
import java.net.URL;

/** The home network rule: plain HTTP only to this TV and the home network, https anywhere. */
public class LocalNetTest {
    private static boolean local(String literal) throws Exception {
        return LocalNet.isLocal(InetAddress.getByName(literal));
    }

    @Test
    public void privateRangesLoopbackAndLinkLocalAreLocal() throws Exception {
        assertTrue(local("127.0.0.1"));
        assertTrue(local("10.1.2.3"));
        assertTrue(local("172.16.0.1"));
        assertTrue(local("172.31.255.254"));
        assertTrue(local("192.168.0.20"));
        assertTrue(local("169.254.10.10"));
        assertTrue(local("::1"));
        assertTrue(local("fe80::1"));
    }

    @Test
    public void ipv6UniqueLocalIsLocalButOtherIpv6IsNot() throws Exception {
        assertTrue(local("fc00::1"));
        assertTrue(local("fd12:3456:789a::1"));
        assertFalse(local("fe00::1"));
        assertFalse(local("2001:db8::1"));
    }

    @Test
    public void publicAndDocumentationAddressesAreNotLocal() throws Exception {
        assertFalse(local("8.8.8.8"));
        assertFalse(local("172.32.0.1"));
        assertFalse(local("192.0.2.10"));
        assertFalse(local("100.64.0.1"));
    }

    @Test
    public void httpsGoesAnywhereButPlainHttpOnlyHome() throws Exception {
        assertTrue(LocalNet.allows(new URL("https://8.8.8.8/api")));
        assertTrue(LocalNet.allows(new URL("HTTPS://8.8.8.8/api")));
        assertTrue(LocalNet.allows(new URL("http://192.168.1.5:8123/api/states")));
        assertTrue(LocalNet.allows(new URL("http://127.0.0.1:8080/")));
        assertFalse(LocalNet.allows(new URL("http://8.8.8.8/api")));
        assertFalse(LocalNet.allows(new URL("http://192.0.2.10/")));
    }

    @Test
    public void otherProtocolsAreRefusedEvenAtHome() throws Exception {
        assertFalse(LocalNet.allows(new URL("ftp://192.168.1.5/file")));
        assertFalse(LocalNet.allows(new URL("file:///etc/hosts")));
    }
}
