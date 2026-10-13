package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.security.GeneralSecurityException;

import org.junit.Test;

/** Hearth and a profile's agent proving they share the agent's key, and what Hearth seals for one connection. */
public class AgentAuthTest {
    private static final String KEY = "12,-34,56,-78";

    @Test
    public void eachSideProvesTheKeyWithoutSendingIt() {
        String agentNonce = AgentAuth.nonce();
        String hubNonce = AgentAuth.nonce();
        String hub = AgentAuth.proof(KEY, AgentAuth.HUB, agentNonce, hubNonce);
        assertTrue(AgentAuth.verify(AgentAuth.proof(KEY, AgentAuth.HUB, agentNonce, hubNonce), hub));
        assertFalse(hub.contains(KEY));
        // The hub's proof doesn't pass as the agent's, nor one made with another key or for other nonces
        assertNotEquals(hub, AgentAuth.proof(KEY, AgentAuth.AGENT, agentNonce, hubNonce));
        assertFalse(AgentAuth.verify(AgentAuth.proof("1,2,3,4", AgentAuth.HUB, agentNonce, hubNonce), hub));
        assertFalse(AgentAuth.verify(AgentAuth.proof(KEY, AgentAuth.HUB, AgentAuth.nonce(), hubNonce), hub));
        assertFalse(AgentAuth.verify(hub, null));
        assertNotEquals(AgentAuth.nonce(), AgentAuth.nonce());
    }

    @Test
    public void aSealedSecretOpensOnlyForItsConnection() throws GeneralSecurityException {
        String agentNonce = AgentAuth.nonce();
        String hubNonce = AgentAuth.nonce();
        String sealed = AgentAuth.seal(KEY, agentNonce, hubNonce, "secret material");
        assertFalse(sealed.contains("secret"));
        assertEquals("secret material", AgentAuth.open(KEY, agentNonce, hubNonce, sealed));
        try {
            AgentAuth.open(KEY, AgentAuth.nonce(), hubNonce, sealed);
            fail("opened for another connection");
        } catch (GeneralSecurityException expected) {
            // Sealed for another connection
        }
        try {
            AgentAuth.open("1,2,3,4", agentNonce, hubNonce, sealed);
            fail("opened with another key");
        } catch (GeneralSecurityException expected) {
            // Another key
        }
    }
}
