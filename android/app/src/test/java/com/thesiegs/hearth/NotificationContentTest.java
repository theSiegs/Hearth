package com.thesiegs.hearth;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class NotificationContentTest {
    @Test
    public void firstTextSkipsMissingAndBlankOnes() {
        assertEquals("Movie night", NotificationContent.firstText(null, "  ", "\n", " Movie night ", "later"));
    }

    @Test
    public void firstTextIsEmptyWhenNothingHasText() {
        assertEquals("", NotificationContent.firstText(null, " "));
        assertEquals("", NotificationContent.firstText());
    }
}
