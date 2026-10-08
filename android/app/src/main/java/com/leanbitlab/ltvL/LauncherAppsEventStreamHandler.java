package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.pm.LauncherApps;
import android.os.UserHandle;
import android.util.Log;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;

public class LauncherAppsEventStreamHandler implements EventChannel.StreamHandler
{
    private static final String TAG = "HearthAppsEvents";

    private final LauncherApps _launcherApps;
    private final MainActivity _activity;

    private LauncherApps.Callback _launcherAppsCallback;

    public LauncherAppsEventStreamHandler(MainActivity activity)
    {
        _activity = activity;
        _launcherApps = (LauncherApps) _activity.getSystemService(Context.LAUNCHER_APPS_SERVICE);
    }

    @Override
    public void onCancel(Object arguments)
    {
        if (_launcherApps != null && _launcherAppsCallback != null) {
            try {
                _launcherApps.unregisterCallback(_launcherAppsCallback);
            } catch (Exception e) {
                Log.w(TAG, "Couldn't unregister the apps callback", e);
            }
            _launcherAppsCallback = null;
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events)
    {
        _launcherAppsCallback = new LauncherAppsCallback(events);
        _launcherApps.registerCallback(_launcherAppsCallback);
    }

    /** An event for Dart: {"action": action}, plus {key: value} when a key is given. */
    private static Map<String, Object> event(String action, String key, Object value)
    {
        Map<String, Object> event = new HashMap<>();
        event.put("action", action);
        if (key != null) event.put(key, value);
        return event;
    }

    private class LauncherAppsCallback extends LauncherApps.Callback
    {
        private final EventChannel.EventSink _eventSink;

        public LauncherAppsCallback(EventChannel.EventSink eventSink)
        {
            _eventSink = eventSink;
        }

        @Override
        public void onPackageRemoved(String packageName, UserHandle user) {
            send(event("PACKAGE_REMOVED", "packageName", packageName));
        }

        @Override
        public void onPackageAdded(String packageName, UserHandle user) {
            Map<String, Serializable> application = _activity.getApplication(packageName);

            if (!application.isEmpty()) {
                send(event("PACKAGE_ADDED", "activityInfo", application));
            }
        }

        @Override
        public void onPackageChanged(String packageName, UserHandle user) {
            Map<String, Serializable> application = _activity.getApplication(packageName);

            if (!application.isEmpty()) {
                send(event("PACKAGE_CHANGED", "activityInfo", application));
            }
        }

        @Override
        public void onPackagesAvailable(String[] packageNames, UserHandle user, boolean replacing) {
            List<Map<String, Serializable>> applications = new ArrayList<>(packageNames.length);

            for (String name : packageNames) {
                Map<String, Serializable> application = _activity.getApplication(name);

                if (!application.isEmpty()) {
                    applications.add(application);
                }
            }

            if (!applications.isEmpty()) {
                send(event("PACKAGES_AVAILABLE", "activitiesInfo", applications));
            }
        }

        @Override
        public void onPackagesUnavailable(String[] packageNames, UserHandle user, boolean replacing) {
        }

        // Switching Google TV profiles suspends/unsuspends apps for kids profiles.
        @Override
        public void onPackagesSuspended(String[] packageNames, UserHandle user) {
            send(event("PACKAGES_SUSPENSION_CHANGED", null, null));
        }

        @Override
        public void onPackagesUnsuspended(String[] packageNames, UserHandle user) {
            send(event("PACKAGES_SUSPENSION_CHANGED", null, null));
        }

        private void send(Map<String, Object> event) {
            _activity.runOnUiThread(() -> {
                try {
                    _eventSink.success(event);
                } catch (Exception e) {
                    Log.w(TAG, "Couldn't send " + event.get("action") + " to Dart", e);
                }
            });
        }
    }
}
