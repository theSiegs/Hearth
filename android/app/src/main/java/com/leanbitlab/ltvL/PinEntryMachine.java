package com.leanbitlab.ltvL;

/**
 * One attempt at typing a streaming app's profile PIN after Profile Pairing picked the profile (see
 * docs/design/streaming-pin-entry.md). Pure logic, fed by events from the app's {@link PinRecipe} and timers, so it's
 * tested without a TV; the {@link Driver} does the typing and shows the outcome.
 *
 * The rules it keeps: never type on a PIN screen that doesn't match the recipe; confirm every digit before the next;
 * one attempt per launch, never retried within it (a rejected PIN is tried again on the next launch).
 */
final class PinEntryMachine {

    /** What the recipe made of the PIN screen. */
    enum Screen {
        /** The screen the recipe knows: safe to type. */
        MATCH,
        /** A PIN screen that isn't laid out the way the recipe knows: the app changed. */
        CHANGED,
        /** The app says the profile is locked out (too many wrong PINs). */
        LOCKED_OUT,
    }

    /** What the app did with the typed PIN. */
    enum Outcome { ACCEPTED, REJECTED, LOCKED_OUT }

    /** How the attempt ended. */
    enum Result {
        /** No PIN screen came up: the profile isn't locked (or was already open). Nothing typed. */
        NO_PIN_SCREEN,
        ACCEPTED,
        /** Not accepted; tried again (once) on the next launch. */
        REJECTED,
        /** The PIN screen isn't the one the recipe knows: nothing typed, entry paused for the app. */
        SCREEN_CHANGED,
        LOCKED_OUT,
        /** Something unexpected mid-entry (a digit not confirmed, a timeout, the app left). */
        BROKEN,
        /** The parent pressed Back or Home. */
        CANCELLED,
    }

    interface Driver {
        /** Type the PIN's digit at {@code index}, then report {@link #onDigit}. */
        void typeDigit(int index);

        /** The attempt is over; {@code digitsTyped} went into the app (to say so when the parent takes over). */
        void finished(Result result, int digitsTyped);
    }

    private enum State { WAITING_FOR_SCREEN, TYPING, WAITING_FOR_OUTCOME, DONE }

    private final Driver driver;
    private final int length;
    private State state = State.WAITING_FOR_SCREEN;
    private int typed;

    PinEntryMachine(Driver driver, int length) {
        this.driver = driver;
        this.length = length;
    }

    boolean isDone() {
        return state == State.DONE;
    }

    /** The PIN screen came up (or the recipe saw something else on it). */
    void onScreen(Screen screen) {
        if (state != State.WAITING_FOR_SCREEN) return;
        switch (screen) {
            case CHANGED:
                finish(Result.SCREEN_CHANGED);
                return;
            case LOCKED_OUT:
                finish(Result.LOCKED_OUT);
                return;
            case MATCH:
                state = State.TYPING;
                driver.typeDigit(0);
        }
    }

    /** The PIN screen didn't come up in time: the profile has no lock. */
    void onNoScreen() {
        if (state == State.WAITING_FOR_SCREEN) finish(Result.NO_PIN_SCREEN);
    }

    /** The digit last asked for went in ({@code confirmed}), or couldn't be confirmed. */
    void onDigit(boolean confirmed) {
        if (state != State.TYPING) return;
        if (!confirmed) {
            finish(Result.BROKEN);
            return;
        }
        typed++;
        if (typed < length) {
            driver.typeDigit(typed);
        } else {
            state = State.WAITING_FOR_OUTCOME;
        }
    }

    void onOutcome(Outcome outcome) {
        if (state != State.WAITING_FOR_OUTCOME) return;
        switch (outcome) {
            case ACCEPTED:
                finish(Result.ACCEPTED);
                return;
            case LOCKED_OUT:
                finish(Result.LOCKED_OUT);
                return;
            case REJECTED:
                finish(Result.REJECTED);
        }
    }

    /** A step took too long, or the app left the front, before the outcome. */
    void onBroken() {
        if (state == State.TYPING || state == State.WAITING_FOR_OUTCOME) finish(Result.BROKEN);
        else if (state == State.WAITING_FOR_SCREEN) finish(Result.NO_PIN_SCREEN);
    }

    void onCancel() {
        if (state != State.DONE) finish(Result.CANCELLED);
    }

    private void finish(Result result) {
        state = State.DONE;
        driver.finished(result, typed);
    }
}
