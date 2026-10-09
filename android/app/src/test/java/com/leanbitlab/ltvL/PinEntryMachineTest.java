package com.leanbitlab.ltvL;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

public class PinEntryMachineTest {

    /** Records what the machine asked for; types every digit at once unless told otherwise. */
    private static final class FakeDriver implements PinEntryMachine.Driver {
        final List<Integer> typed = new ArrayList<>();
        PinEntryMachine.Result result;
        int digitsTyped = -1;
        PinEntryMachine machine;
        /** Index of a digit whose entry can't be confirmed; -1 for none. */
        int failAt = -1;

        @Override
        public void typeDigit(int index) {
            typed.add(index);
            machine.onDigit(index != failAt);
        }

        @Override
        public void finished(PinEntryMachine.Result result, int digitsTyped) {
            this.result = result;
            this.digitsTyped = digitsTyped;
        }
    }

    private static FakeDriver run(int rejectionsSoFar, int lockoutAfter) {
        FakeDriver driver = new FakeDriver();
        driver.machine = new PinEntryMachine(driver, 4, rejectionsSoFar, lockoutAfter);
        return driver;
    }

    @Test
    public void typesEachDigitThenWaitsForTheApp() {
        FakeDriver d = run(0, 5);
        d.machine.onScreen(PinEntryMachine.Screen.MATCH);
        assertEquals(List.of(0, 1, 2, 3), d.typed);
        d.machine.onOutcome(PinEntryMachine.Outcome.ACCEPTED);
        assertEquals(PinEntryMachine.Result.ACCEPTED, d.result);
        assertEquals(4, d.digitsTyped);
    }

    @Test
    public void noPinScreenMeansNothingTyped() {
        FakeDriver d = run(0, 5);
        d.machine.onNoScreen();
        assertEquals(PinEntryMachine.Result.NO_PIN_SCREEN, d.result);
        assertEquals(List.of(), d.typed);
    }

    @Test
    public void aChangedScreenIsNeverTypedOn() {
        FakeDriver d = run(0, 5);
        d.machine.onScreen(PinEntryMachine.Screen.CHANGED);
        assertEquals(PinEntryMachine.Result.SCREEN_CHANGED, d.result);
        assertEquals(List.of(), d.typed);
    }

    @Test
    public void aDigitThatIsNotConfirmedStopsBeforeTheNext() {
        FakeDriver d = run(0, 5);
        d.failAt = 2;
        d.machine.onScreen(PinEntryMachine.Screen.MATCH);
        assertEquals(List.of(0, 1, 2), d.typed);
        assertEquals(PinEntryMachine.Result.BROKEN, d.result);
        assertEquals(2, d.digitsTyped);
    }

    @Test
    public void aWrongPinIsTriedOncePerLaunchAndAgainNextTime() {
        FakeDriver d = run(0, 5);
        d.machine.onScreen(PinEntryMachine.Screen.MATCH);
        d.machine.onOutcome(PinEntryMachine.Outcome.REJECTED);
        assertEquals(PinEntryMachine.Result.REJECTED, d.result);

        // The next launch, with one rejection on record, still tries
        FakeDriver next = run(1, 5);
        next.machine.onScreen(PinEntryMachine.Screen.MATCH);
        assertEquals(4, next.typed.size());
    }

    @Test
    public void stopsBeforeAnAttemptThatCouldLockTheProfile() {
        // Five allowed: the 4th rejection stops further tries, so the 5th (locking) attempt is never made
        FakeDriver fourth = run(3, 5);
        fourth.machine.onScreen(PinEntryMachine.Screen.MATCH);
        fourth.machine.onOutcome(PinEntryMachine.Outcome.REJECTED);
        assertEquals(PinEntryMachine.Result.REJECTED_STOPPED, fourth.result);

        FakeDriver after = run(4, 5);
        after.machine.onScreen(PinEntryMachine.Screen.MATCH);
        assertEquals(PinEntryMachine.Result.NOT_TRIED, after.result);
        assertEquals(List.of(), after.typed);
    }

    @Test
    public void anUnknownLimitStopsAfterThreeRejections() {
        FakeDriver third = run(2, 0);
        third.machine.onScreen(PinEntryMachine.Screen.MATCH);
        third.machine.onOutcome(PinEntryMachine.Outcome.REJECTED);
        assertEquals(PinEntryMachine.Result.REJECTED_STOPPED, third.result);
    }

    @Test
    public void lockoutAndCancelAndLeavingEndIt() {
        FakeDriver locked = run(0, 5);
        locked.machine.onScreen(PinEntryMachine.Screen.LOCKED_OUT);
        assertEquals(PinEntryMachine.Result.LOCKED_OUT, locked.result);

        FakeDriver cancelled = run(0, 5);
        cancelled.machine.onCancel();
        assertEquals(PinEntryMachine.Result.CANCELLED, cancelled.result);

        FakeDriver left = run(0, 5);
        left.machine.onScreen(PinEntryMachine.Screen.MATCH);
        left.machine.onBroken();
        assertEquals(PinEntryMachine.Result.BROKEN, left.result);
        assertEquals(4, left.digitsTyped);
    }

    @Test
    public void lateEventsAfterTheEndAreIgnored() {
        FakeDriver d = run(0, 5);
        d.machine.onNoScreen();
        d.machine.onScreen(PinEntryMachine.Screen.MATCH);
        d.machine.onOutcome(PinEntryMachine.Outcome.ACCEPTED);
        assertEquals(PinEntryMachine.Result.NO_PIN_SCREEN, d.result);
        assertEquals(List.of(), d.typed);
    }
}
