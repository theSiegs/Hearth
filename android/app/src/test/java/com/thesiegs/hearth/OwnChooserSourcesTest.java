package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Where Hearth's own picker gets people from: the account list (AccountList) and Home Assistant (HaFaces). */
public class OwnChooserSourcesTest {
    private static final String DUMP = String.join("\n",
            "User UserInfo{0:Owner:4c13}:",
            "  Accounts: 2",
            "    Account {name=alex@example.com, type=com.google}",
            "    Account {name=sam@example.com, type=com.google}",
            "    Account {name=someone@example.org, type=com.example.other}",
            "  ",
            "  AccountId, Action_Type, timestamp, UID, TableName, Key",
            "  Accounts History",
            "  1,action_account_add,2026-10-15 00:40:34,10069,accounts,0",
            "  Account visibility:",
            "    alex@example.com",
            "      com.google.android.apps.tv.launcherx, 2",
            "User UserInfo{10:configured_user:1010}:",
            "  Accounts: 1",
            "    Account {name=jo.kid@example.com, type=com.google}",
            "User UserInfo{13:new_user:1010}:",
            "  Accounts: 0",
            "");

    @Test
    public void readsEachUsersGoogleAccounts() {
        Map<Integer, List<String>> users = AccountList.parse(DUMP);
        assertEquals(Arrays.asList("alex@example.com", "sam@example.com"), users.get(0));
        assertEquals(Arrays.asList("jo.kid@example.com"), users.get(10));
        // No Google account: left out; other account types and the visibility list don't count
        assertFalse(users.containsKey(13));
        assertEquals(2, users.size());
    }

    @Test
    public void readsWindowsLineEndingsAndNothing() {
        assertEquals(2, AccountList.parse(DUMP.replace("\n", "\r\n")).size());
        assertTrue(AccountList.parse(null).isEmpty());
        assertTrue(AccountList.parse("").isEmpty());
    }

    @Test
    public void anAccountNotYetNamedShowsItsAddressStandIn() {
        assertEquals("sam", OwnChooser.standIn("sam@example.com"));
        assertEquals("sam", new OwnChooser.Entry(null, null, "sam@example.com", false, false).label());
        assertEquals("Sam Lee", new OwnChooser.Entry("user:0", "Sam Lee", "sam@example.com", false, false).label());
    }

    @Test
    public void thePickerIsOnlyWantedRightAfterHearthOpenedTheChooser() {
        assertFalse(OwnChooser.wantedNow(0, 5_000));
        assertTrue(OwnChooser.wantedNow(1_000, 1_200));
        assertFalse(OwnChooser.wantedNow(1_000, 1_000 + OwnChooser.WANTED_MS));
        // A chooser opened by another app (asking which account to use) is never covered
        assertFalse(OwnChooser.wantedNow(5_000, 1_000));
    }

    // --- Home Assistant faces ---

    private static List<HaFaces.Person> people() throws Exception {
        return HaFaces.people(new JSONArray("["
                + "{\"entity_id\":\"person.alex\",\"attributes\":{\"friendly_name\":\"Alex Rivera\","
                + "\"entity_picture\":\"/api/image/serve/abc/512x512\"}},"
                + "{\"entity_id\":\"person.sam\",\"attributes\":{\"friendly_name\":\"Sam\"}},"
                + "{\"entity_id\":\"sensor.x\",\"attributes\":{\"friendly_name\":\"Sam\"}},"
                + "{\"entity_id\":\"person.jo\",\"attributes\":{\"friendly_name\":\"Jo Rivera\","
                + "\"entity_picture\":\"https://elsewhere.example/jo.png\"}}"
                + "]"));
    }

    @Test
    public void readsThePeople() throws Exception {
        List<HaFaces.Person> people = people();
        assertEquals(3, people.size());
        assertEquals("/api/image/serve/abc/512x512", people.get(0).picture);
        assertNull(people.get(1).picture);
    }

    @Test
    public void theIntegrationsMappingComesFirst() throws Exception {
        Map<String, String> mapped = new HashMap<>();
        mapped.put("user:10", "person.jo");
        assertEquals("person.jo", HaFaces.personFor("user:10", "Sam", mapped, people()).id);
    }

    @Test
    public void elseTheOnePersonWithThatWholeOrFirstName() throws Exception {
        assertEquals("person.alex", HaFaces.personFor("user:0", "Alex Rivera", new HashMap<>(), people()).id);
        assertEquals("person.alex", HaFaces.personFor("user:0", "alex", new HashMap<>(), people()).id);
        assertEquals("person.sam", HaFaces.personFor("user:0:sam", "Sam", new HashMap<>(), people()).id);
        assertNull(HaFaces.personFor("user:11", "Robin", new HashMap<>(), people()));
    }

    @Test
    public void twoPeopleWithThatFirstNameIsNobody() throws Exception {
        List<HaFaces.Person> people = HaFaces.people(new JSONArray("["
                + "{\"entity_id\":\"person.a\",\"attributes\":{\"friendly_name\":\"Sam Lee\"}},"
                + "{\"entity_id\":\"person.b\",\"attributes\":{\"friendly_name\":\"Sam Rivera\"}}]"));
        assertNull(HaFaces.personFor("user:0", "Sam", new HashMap<>(), people));
    }

    @Test
    public void onlyPicturesHomeAssistantServesItself() {
        assertTrue(HaFaces.fetchable("/api/image/serve/abc/512x512"));
        assertTrue(HaFaces.fetchable("/local/people/sam.jpg"));
        assertFalse(HaFaces.fetchable("https://elsewhere.example/jo.png"));
        assertFalse(HaFaces.fetchable("//elsewhere.example/jo.png"));
        assertFalse(HaFaces.fetchable(null));
    }
}
