package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayDeque;

/**
 * Shows Home Assistant notifications as a Google TV style card over whatever is playing. Drawn as an
 * accessibility overlay, so it needs no "display over other apps" permission and never takes focus.
 * Notifications queue and show one at a time.
 */
final class HaNotificationOverlay {
    private static final int CARD = Color.parseColor("#1F2023");
    private static final int TEXT = Color.parseColor("#E8EAED");
    private static final int TEXT_DIM = Color.parseColor("#BDC1C6");
    private static final int DEFAULT_ACCENT = Color.parseColor("#8AB4F8");

    private final AccessibilityService mService;
    private final WindowManager mWindowManager;
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final ArrayDeque<HaNotificationServer.Notification> mQueue = new ArrayDeque<>();
    private View mShowing;

    HaNotificationOverlay(AccessibilityService service) {
        mService = service;
        mWindowManager = (WindowManager) service.getSystemService(AccessibilityService.WINDOW_SERVICE);
    }

    /** Safe to call from any thread. */
    void enqueue(HaNotificationServer.Notification notification) {
        mHandler.post(() -> {
            mQueue.add(notification);
            if (mShowing == null) showNext();
        });
    }

    void dismissAll() {
        mHandler.removeCallbacksAndMessages(null);
        mQueue.clear();
        hide();
    }

    private void showNext() {
        HaNotificationServer.Notification n = mQueue.poll();
        if (n == null) return;
        try {
            View card = buildCard(n);
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                            | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT);
            params.gravity = gravity(n.position);
            params.x = dp(32);
            params.y = dp(32);
            params.windowAnimations = android.R.style.Animation_Toast;
            mWindowManager.addView(card, params);
            mShowing = card;
            mHandler.postDelayed(() -> {
                hide();
                showNext();
            }, n.durationSeconds * 1000L);
        } catch (Exception e) {
            mShowing = null;
            showNext();
        }
    }

    private void hide() {
        if (mShowing != null) {
            try {
                mWindowManager.removeView(mShowing);
            } catch (Exception ignored) {
            }
            mShowing = null;
        }
    }

    /** Home Assistant positions: 0 bottom-right, 1 bottom-left, 2 top-right, 3 top-left, 4 center. */
    static int gravity(int position) {
        switch (position) {
            case 0: return Gravity.BOTTOM | Gravity.END;
            case 1: return Gravity.BOTTOM | Gravity.START;
            case 3: return Gravity.TOP | Gravity.START;
            case 4: return Gravity.CENTER;
            case 2:
            default: return Gravity.TOP | Gravity.END;
        }
    }

    private View buildCard(HaNotificationServer.Notification n) {
        int accent = DEFAULT_ACCENT;
        if (n.backgroundColor != null) {
            try {
                accent = Color.parseColor(n.backgroundColor);
            } catch (IllegalArgumentException ignored) {
            }
        }

        LinearLayout card = new LinearLayout(mService);
        card.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable background = new GradientDrawable();
        background.setColor(CARD);
        background.setCornerRadius(dp(16));
        card.setBackground(background);
        card.setElevation(dp(8));
        card.setClipToOutline(true);

        Bitmap image = decode(n.image);
        if (image != null) {
            ImageView picture = new ImageView(mService);
            picture.setImageBitmap(image);
            picture.setAdjustViewBounds(true);
            picture.setScaleType(ImageView.ScaleType.CENTER_CROP);
            card.addView(picture, new LinearLayout.LayoutParams(dp(360), dp(203)));
        }

        LinearLayout row = new LinearLayout(mService);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, 0, dp(20), 0);

        View stripe = new View(mService);
        stripe.setBackgroundColor(accent);
        row.addView(stripe, new LinearLayout.LayoutParams(dp(5), LinearLayout.LayoutParams.MATCH_PARENT));

        Bitmap icon = decode(n.icon);
        if (icon != null) {
            ImageView iconView = new ImageView(mService);
            iconView.setImageBitmap(icon);
            LinearLayout.LayoutParams iconParams = new LinearLayout.LayoutParams(dp(40), dp(40));
            iconParams.setMargins(dp(16), dp(14), 0, dp(14));
            row.addView(iconView, iconParams);
        }

        LinearLayout texts = new LinearLayout(mService);
        texts.setOrientation(LinearLayout.VERTICAL);
        texts.setPadding(dp(16), dp(14), 0, dp(14));
        if (n.title != null && !n.title.isEmpty()) {
            TextView title = new TextView(mService);
            title.setText(n.title);
            title.setTextColor(TEXT);
            title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
            title.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            title.setMaxWidth(dp(image != null ? 300 : 420));
            texts.addView(title);
        }
        if (n.message != null && !n.message.isEmpty()) {
            TextView message = new TextView(mService);
            message.setText(n.message);
            message.setTextColor(n.title == null || n.title.isEmpty() ? TEXT : TEXT_DIM);
            message.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
            message.setMaxLines(4);
            message.setMaxWidth(dp(image != null ? 300 : 420));
            texts.addView(message);
        }
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        row.addView(texts, textParams);

        card.addView(row, new LinearLayout.LayoutParams(image != null ? dp(360) : LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT));
        card.setMinimumWidth(dp(280));
        texts.setMinimumWidth(dp(200));
        return card;
    }

    private Bitmap decode(byte[] bytes) {
        if (bytes == null || bytes.length == 0) return null;
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = Math.max(1, Math.max(bounds.outWidth, bounds.outHeight) / 720);
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
        } catch (Exception e) {
            return null;
        }
    }

    private int dp(int value) {
        return Math.round(value * mService.getResources().getDisplayMetrics().density);
    }
}
