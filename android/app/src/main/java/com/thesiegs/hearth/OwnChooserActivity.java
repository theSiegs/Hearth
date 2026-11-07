package com.thesiegs.hearth;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.PowerManager;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.lang.ref.WeakReference;
import java.util.List;
import java.util.Locale;

/**
 * Hearth's own profile picker (experiment, feature/own-chooser): it shows over Google TV's profile chooser, which
 * stays underneath and makes the switch (see {@link OwnChooser}). Picking someone hands the pick to the accessibility
 * service, which selects their tile in Google's chooser; Back, Home, or anything that comes over it closes it onto
 * Google's chooser. It has its own task, so closing it never uncovers Hearth's home.
 */
public class OwnChooserActivity extends Activity {
    private static final String TAG = "HearthOwnChooser";
    private static WeakReference<OwnChooserActivity> sShowing = new WeakReference<>(null);

    private boolean mPicked;
    /** Closed because something came over it, not by Back or Home. */
    private boolean mCovered;

    /** Whether Hearth's picker is up. */
    static boolean isShowing() {
        OwnChooserActivity activity = sShowing.get();
        return activity != null && !activity.isFinishing() && !activity.isDestroyed();
    }

    /** Closes Hearth's picker, if it's up, onto Google's chooser (Home over it does this). */
    static void closeIfOpen() {
        OwnChooserActivity activity = sShowing.get();
        if (activity != null && !activity.isFinishing()) {
            Log.i(TAG, "Closed onto Google's chooser");
            activity.finish();
            activity.overridePendingTransition(0, 0);
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        sShowing = new WeakReference<>(this);
        List<OwnChooser.Entry> entries = OwnChooser.entries(this);
        if (entries.isEmpty()) {
            Log.i(TAG, "Nobody to show: Google's chooser stays");
            finish();
            return;
        }
        setContentView(build(entries));
        Log.i(TAG, "Showing " + entries.size() + " profile(s) over Google's chooser");
        // The faces and the account list for next time
        HaFaces.refreshIfDue(this, false);
        AccountList.refreshIfDue(this);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // The card that hid Google's chooser while this came up
        SwitchCover.hideSoon(250);
    }

    @Override
    protected void onStop() {
        super.onStop();
        // Something came over the picker (the remote's input or settings button, an app): it closes, so whoever comes
        // back finds Google's chooser. Not when the screen went off: it waits there for whoever wakes the TV.
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (!mPicked && !isFinishing() && power != null && power.isInteractive()) {
            Log.i(TAG, "Covered by another screen: closing onto Google's chooser");
            mCovered = true;
            finish();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (sShowing.get() == this) sShowing = new WeakReference<>(null);
        // Closed without a pick: Google's chooser should be in front (the service checks, and opens it if not)
        if (!mPicked) LauncherAccessibilityService.onOwnPickerClosed(!mCovered);
    }

    private void pick(OwnChooser.Entry entry) {
        if (mPicked) return;
        mPicked = true;
        boolean handed = LauncherAccessibilityService.selectInGoogleChooser(entry.name, entry.email);
        Log.i(TAG, handed ? "Picked: selecting the tile in Google's chooser" : "Picked, but the service isn't running");
        finish();
        overridePendingTransition(0, 0);
    }

    private View build(List<OwnChooser.Entry> entries) {
        Context c = this;
        int accent = SwitchCover.accentColor(c);
        FrameLayout root = new FrameLayout(c);
        root.setBackgroundColor(Color.parseColor("#FF0E0E12"));

        LinearLayout column = new LinearLayout(c);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER_HORIZONTAL);

        TextView title = new TextView(c);
        title.setText(R.string.own_chooser_title);
        title.setTextColor(Color.WHITE);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 34);
        title.setTypeface(Typeface.create("sans-serif-light", Typeface.NORMAL));
        column.addView(title, wrap());

        View bar = new View(c);
        GradientDrawable accentBar = new GradientDrawable();
        accentBar.setCornerRadius(Dp.px(c, 2));
        accentBar.setColor(accent);
        bar.setBackground(accentBar);
        LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(Dp.px(c, 64), Dp.px(c, 4));
        barParams.topMargin = Dp.px(c, 14);
        barParams.bottomMargin = Dp.px(c, 36);
        column.addView(bar, barParams);

        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER);
        row.setClipChildren(false);
        row.setClipToPadding(false);
        row.setPadding(Dp.px(c, 24), Dp.px(c, 16), Dp.px(c, 24), Dp.px(c, 16));
        String activeKey = LauncherAccessibilityService.getActiveProfileKey(c);
        View first = null;
        View current = null;
        for (OwnChooser.Entry entry : entries) {
            View tile = tile(c, entry, accent);
            row.addView(tile, new LinearLayout.LayoutParams(Dp.px(c, 168), ViewGroup.LayoutParams.WRAP_CONTENT));
            if (first == null) first = tile;
            if (entry.key != null && entry.key.equals(activeKey)) current = tile;
        }
        HorizontalScrollView scroll = new HorizontalScrollView(c);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.setClipChildren(false);
        scroll.addView(row);
        column.addView(scroll, wrap());

        TextView note = new TextView(c);
        note.setText(R.string.own_chooser_note);
        note.setTextColor(Color.parseColor("#99FFFFFF"));
        note.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        note.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams noteParams = wrap();
        noteParams.topMargin = Dp.px(c, 28);
        column.addView(note, noteParams);

        FrameLayout.LayoutParams columnParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER);
        root.addView(column, columnParams);
        View focus = current != null ? current : first;
        if (focus != null) focus.post(focus::requestFocus);
        return root;
    }

    private static LinearLayout.LayoutParams wrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private View tile(Context c, OwnChooser.Entry entry, int accent) {
        LinearLayout tile = new LinearLayout(c);
        tile.setOrientation(LinearLayout.VERTICAL);
        tile.setGravity(Gravity.CENTER_HORIZONTAL);
        tile.setFocusable(true);
        tile.setClickable(true);
        tile.setPadding(Dp.px(c, 8), Dp.px(c, 8), Dp.px(c, 8), Dp.px(c, 8));
        tile.setContentDescription(entry.label());

        int size = Dp.px(c, 112);
        FrameLayout ring = new FrameLayout(c);
        int pad = Dp.px(c, 4);
        ring.setPadding(pad, pad, pad, pad);
        GradientDrawable ringBg = new GradientDrawable();
        ringBg.setShape(GradientDrawable.OVAL);
        ringBg.setColor(Color.TRANSPARENT);
        ring.setBackground(ringBg);
        ImageView face = new ImageView(c);
        face.setImageBitmap(faceOf(c, entry, size, accent));
        ring.addView(face, new FrameLayout.LayoutParams(size, size));
        tile.addView(ring, wrap());

        TextView name = new TextView(c);
        name.setText(entry.label());
        name.setTextColor(Color.parseColor("#CCFFFFFF"));
        name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        name.setSingleLine(true);
        name.setEllipsize(android.text.TextUtils.TruncateAt.END);
        name.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams nameParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        nameParams.topMargin = Dp.px(c, 12);
        tile.addView(name, nameParams);

        TextView caption = new TextView(c);
        caption.setText(entry.kids ? getString(R.string.own_chooser_kids)
                : entry.locked ? getString(R.string.own_chooser_pin) : getString(R.string.own_chooser_adult));
        caption.setTextColor(Color.parseColor("#80FFFFFF"));
        caption.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        caption.setGravity(Gravity.CENTER);
        tile.addView(caption, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        tile.setOnFocusChangeListener((v, hasFocus) -> {
            float scale = hasFocus ? 1.12f : 1f;
            v.animate().scaleX(scale).scaleY(scale).setDuration(120).start();
            ringBg.setStroke(hasFocus ? Dp.px(c, 4) : 0, accent);
            name.setTextColor(hasFocus ? Color.WHITE : Color.parseColor("#CCFFFFFF"));
        });
        tile.setOnClickListener(v -> pick(entry));
        return tile;
    }

    /** The profile's photo (Home Assistant's, else the chooser's), else its initial on the accent colour. */
    private static Bitmap faceOf(Context c, OwnChooser.Entry entry, int size, int accent) {
        byte[] png = entry.name != null ? ProfileAvatars.read(c, entry.name) : null;
        if (png != null) {
            Bitmap photo = BitmapFactory.decodeByteArray(png, 0, png.length);
            if (photo != null) return photo;
        }
        Bitmap out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(out);
        Paint circle = new Paint(Paint.ANTI_ALIAS_FLAG);
        circle.setColor(accent);
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, circle);
        Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        text.setColor(Color.WHITE);
        text.setTextSize(size * 0.45f);
        text.setTextAlign(Paint.Align.CENTER);
        String label = entry.label();
        String initial = label.isEmpty() ? "?" : label.substring(0, label.offsetByCodePoints(0, 1))
                .toUpperCase(Locale.getDefault());
        canvas.drawText(initial, size / 2f, size / 2f - (text.descent() + text.ascent()) / 2, text);
        return out;
    }
}
