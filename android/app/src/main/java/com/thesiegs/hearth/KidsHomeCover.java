package com.thesiegs.hearth;

import android.content.Context;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

/**
 * A welcome card over Google TV's kids home while Hearth gives it its moment (KIDS_HOME_GRACE_MS). Google TV puts up
 * a kid's bedtime / time up screen from that home only while the home is the resumed activity, a few seconds after
 * it comes up (2.7 s on the TV, 2026-10-11); an accessibility overlay doesn't pause it the way Hearth's own screen
 * would, so the kid sees Hearth's card instead of Google TV's home, and still gets Google's screen when it's due.
 * The card goes when Google's screen comes up, when Hearth takes the home over, or when anything else comes up.
 * Main thread only.
 */
final class KidsHomeCover {
    private static final String TAG = "HearthProfile";
    /** The card never outstays this, whatever happens. */
    private static final long MAX_MS = 10_000;

    private static View sCover;
    private static final Runnable sTimeout = KidsHomeCover::hideNow;
    private static android.os.Handler sHandler;
    private static Context sContext;

    private KidsHomeCover() {
    }

    static void show(Context context, String name) {
        if (sCover != null) return;
        try {
            Context c = context;
            LinearLayout box = new LinearLayout(c);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setGravity(Gravity.CENTER);
            box.setBackgroundColor(Color.parseColor("#FF0E0E12"));

            ProgressBar spinner = new ProgressBar(c);
            box.addView(spinner, new LinearLayout.LayoutParams(Dp.px(c, 48), Dp.px(c, 48)));

            TextView title = new TextView(c);
            title.setText(name != null && !name.isEmpty()
                    ? c.getString(R.string.kids_home_cover, name) : c.getString(R.string.kids_home_cover_unnamed));
            title.setTextColor(Color.WHITE);
            title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
            title.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            titleParams.topMargin = Dp.px(c, 20);
            box.addView(title, titleParams);

            View bar = new View(c);
            GradientDrawable accent = new GradientDrawable();
            accent.setCornerRadius(Dp.px(c, 2));
            accent.setColor(accentColor(c));
            bar.setBackground(accent);
            LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(Dp.px(c, 64), Dp.px(c, 4));
            barParams.topMargin = Dp.px(c, 16);
            box.addView(bar, barParams);

            // Not focusable or touchable: Google TV's home stays the resumed, focused window underneath
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.OPAQUE);
            c.getSystemService(WindowManager.class).addView(box, params);
            sCover = box;
            sContext = c;
            if (sHandler == null) sHandler = new android.os.Handler(android.os.Looper.getMainLooper());
            sHandler.removeCallbacks(sTimeout);
            sHandler.postDelayed(sTimeout, MAX_MS);
        } catch (Exception e) {
            Log.w(TAG, "Couldn't show the welcome card over Google TV's kids home", e);
            sCover = null;
        }
    }

    /** The card goes after a moment: Hearth is coming up over it, and shouldn't flash Google's home first. */
    static void hideSoon(long delayMs) {
        if (sCover == null || sHandler == null) return;
        sHandler.removeCallbacks(sTimeout);
        sHandler.postDelayed(sTimeout, delayMs);
    }

    static void hideNow() {
        if (sHandler != null) sHandler.removeCallbacks(sTimeout);
        if (sCover == null) return;
        try {
            sContext.getSystemService(WindowManager.class).removeView(sCover);
        } catch (Exception ignored) {
        }
        sCover = null;
        sContext = null;
    }

    static boolean isShowing() {
        return sCover != null;
    }

    private static int accentColor(Context context) {
        String hex = FlutterPrefs.getString(context, "accent_color", null);
        try {
            if (hex != null) return Color.parseColor("#" + hex.replace("#", ""));
        } catch (Exception ignored) {
        }
        return Color.parseColor("#7C4DFF");
    }
}
