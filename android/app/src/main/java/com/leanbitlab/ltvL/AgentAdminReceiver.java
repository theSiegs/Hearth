package com.leanbitlab.ltvL;

import android.app.admin.DeviceAdminReceiver;

/**
 * Hearth as a device admin with no policies, in a kids profile's user. Google TV uninstalls every app that isn't
 * on a kids profile's list each time the profile starts; Android won't uninstall an active device admin, so the
 * agent stays. Activated once per profile from a computer (Google TV disables Settings in kids profiles):
 * adb shell dpm set-active-admin --user N com.leanbitlab.ltvL/.AgentAdminReceiver
 */
public class AgentAdminReceiver extends DeviceAdminReceiver {
}
