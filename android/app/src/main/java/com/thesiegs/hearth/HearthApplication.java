package com.thesiegs.hearth;

import android.app.Application;

/** Hearth's process start: before anything reads a setting, bring the old Hearth's data over when that's due. */
public class HearthApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        if (!RestartActivity.isRestartProcess(this)) LegacyMove.runIfDue(this);
    }
}
