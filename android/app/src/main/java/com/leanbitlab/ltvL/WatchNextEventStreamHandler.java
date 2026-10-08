package com.leanbitlab.ltvL;

import android.content.Context;
import android.database.ContentObserver;
import android.media.tv.TvContract;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.RequiresApi;

import io.flutter.plugin.common.EventChannel;

/**
 * The Watch Next event channel: true whenever this user's Watch Next changes, or another profile's as its agent
 * reports it (AgentHub). Flutter then reads the list again.
 */
final class WatchNextEventStreamHandler implements EventChannel.StreamHandler {
    private static final String TAG = "HearthWatchNext";
    // Apps often write several programs at once: one event for the burst.
    private static final long DEBOUNCE_MS = 500;

    private final Context mContext;
    private final Handler mMainHandler = new Handler(Looper.getMainLooper());
    private ContentObserver mObserver;
    private boolean mObserverRegistered;
    private Runnable mDebounce;

    WatchNextEventStreamHandler(Context context) {
        mContext = context;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return; // Watch Next is API 26+
        }

        mObserver = new ContentObserver(mMainHandler) {
            @Override
            public void onChange(boolean selfChange, Uri uri) {
                super.onChange(selfChange, uri);
                if (mDebounce != null) {
                    mMainHandler.removeCallbacks(mDebounce);
                }
                mDebounce = () -> {
                    try {
                        events.success(true);
                    } catch (Exception e) {
                        Log.w(TAG, "Couldn't send a Watch Next change", e);
                    }
                };
                mMainHandler.postDelayed(mDebounce, DEBOUNCE_MS);
            }
        };

        registerObserverApi26();
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private void registerObserverApi26() {
        try {
            mContext.getContentResolver().registerContentObserver(
                    TvContract.WatchNextPrograms.CONTENT_URI, true, mObserver);
            // Another profile's Continue Watching, as its agent reports it
            mContext.getContentResolver().registerContentObserver(AgentHub.watchNextUri(mContext), false, mObserver);
            mObserverRegistered = true;
        } catch (Exception e) {
            Log.w(TAG, "Can't watch Watch Next", e);
        }
    }

    @Override
    public void onCancel(Object arguments) {
        if (mDebounce != null) {
            mMainHandler.removeCallbacks(mDebounce);
            mDebounce = null;
        }
        if (mObserverRegistered && mObserver != null) {
            try {
                mContext.getContentResolver().unregisterContentObserver(mObserver);
            } catch (Exception e) {
                Log.w(TAG, "Couldn't stop watching Watch Next", e);
            }
            mObserverRegistered = false;
        }
        mObserver = null;
    }
}
