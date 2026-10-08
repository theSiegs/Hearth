package com.leanbitlab.ltvL;

import android.app.Activity;
import android.content.Context;
import android.util.Log;

import io.flutter.plugin.common.EventChannel;

/** The weather event channel: the last weather Breezy Weather sent, then each new one (see WeatherReceiver). */
final class WeatherEventStreamHandler implements EventChannel.StreamHandler {
    private static final String TAG = "HearthWeather";

    private final Activity mActivity;

    WeatherEventStreamHandler(Activity activity) {
        mActivity = activity;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        WeatherReceiver.setListener(weatherJson -> mActivity.runOnUiThread(() -> {
            try {
                events.success(weatherJson);
            } catch (Exception e) {
                Log.w(TAG, "Couldn't send the weather", e);
            }
        }));
        String latest = latestWeather(mActivity);
        if (latest != null) {
            events.success(latest);
        }
    }

    @Override
    public void onCancel(Object arguments) {
        WeatherReceiver.setListener(null);
    }

    /** The weather JSON WeatherReceiver last stored, or null. */
    static String latestWeather(Context context) {
        return context.getSharedPreferences(WeatherReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                .getString(WeatherReceiver.KEY_WEATHER_JSON, null);
    }
}
