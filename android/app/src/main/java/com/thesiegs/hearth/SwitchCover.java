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
 * A welcome card over Google TV's home while a profile switch finishes, so the person sees Hearth's card instead of
 * Google's home before Hearth comes up:
 * <ul>
 * <li>a kids profile's home, while Hearth gives it its moment (KIDS_HOME_GRACE_MS). Google TV puts up a kid's
 * bedtime / time up screen from that home only while the home is the resumed activity, a few seconds after it comes
 * up (2.7 s on the TV, 2026-10-11); an accessibility overlay doesn't pause it the way Hearth's own screen would, so
 * the kid still gets Google's screen when it's due.</li>
 * <li>an adult's home after a pick in the chooser, while Hearth reads who the home says is logged in (up to a few
 * seconds) before it takes over.</li>
 * </ul>
 * Only where Hearth will take the home over: never while "Use Google TV's home" is on, or during Google's own setup.
 * The card goes when any of Google TV's own screens comes up (the chooser, a PIN, time up), so none is ever hidden;
 * when Hearth takes the home over; when anything else comes up; or after {@link #MAX_MS}. Main thread only.
 */
final class SwitchCover {
    private static final String TAG = "HearthProfile";
    /** The card never outstays this, whatever happens. */
    private static final long MAX_MS = 10_000;

    private static View sCover;
    private static final Runnable sTimeout = SwitchCover::hideNow;
    private static android.os.Handler sHandler;
    /**
     * The accessibility service that put the card up (its overlay needs that service's window manager); held only
     * while the card shows.
     */
    private static Context sContext;

    private SwitchCover() {
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
                    ? c.getString(R.string.switch_cover, name) : c.getString(R.string.switch_cover_unnamed));
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
