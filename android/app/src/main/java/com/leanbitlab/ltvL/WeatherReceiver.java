package com.leanbitlab.ltvL;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

public class WeatherReceiver extends BroadcastReceiver {
    public static final String ACTION_GENERIC_WEATHER = "nodomain.freeyourgadget.gadgetbridge.ACTION_GENERIC_WEATHER";
    public static final String ACTION_BREEZY_UPDATE_NOTIFIER = "org.breezyweather.ACTION_UPDATE_NOTIFIER";
    public static final String ACTION_BREEZY_UPDATE_NOTIFIER_DEBUG = "org.breezyweather.debug.ACTION_UPDATE_NOTIFIER";
    public static final String PREFS_NAME = "lwidget_breezy_weather_data";
    public static final String KEY_WEATHER_JSON = "weather_json";

    public interface WeatherListener {
        void onWeatherUpdated(String weatherJson);
    }

    private static WeatherListener sListener;

    public static void setListener(WeatherListener listener) {
        sListener = listener;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        boolean breezy = ACTION_BREEZY_UPDATE_NOTIFIER.equals(action) || ACTION_BREEZY_UPDATE_NOTIFIER_DEBUG.equals(action);
        if (!breezy && !ACTION_GENERIC_WEATHER.equals(action)) return;
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String weatherJson = intent.getStringExtra("WeatherJson");
        if (weatherJson != null && !weatherJson.isEmpty()) {
            prefs.edit().putString(KEY_WEATHER_JSON, weatherJson).apply();
            if (sListener != null) sListener.onWeatherUpdated(weatherJson);
        } else if (breezy) {
            // Breezy's notifier can come without the data: pass on the last weather saved
            String saved = prefs.getString(KEY_WEATHER_JSON, null);
            if (sListener != null && saved != null) sListener.onWeatherUpdated(saved);
        }
    }
}
