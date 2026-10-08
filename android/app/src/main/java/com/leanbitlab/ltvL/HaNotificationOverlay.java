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
import android.graphics.drawable.StateListDrawable;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayDeque;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Shows Home Assistant notifications as a Google TV style card over whatever is playing. Drawn as an
 * accessibility overlay, so it needs no "display over other apps" permission. A card takes focus only when it
 * has buttons (so the remote can press them; Back dismisses it), and a camera card refreshes its picture every
 * second, picture-in-picture style. Notifications queue and show one at a time.
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
    /**
     * Fetches camera pictures, so a slow camera never holds up button presses. Made by the first camera card and
     * shut down by dismissAll(). Main thread only.
     */
    private ExecutorService mCameraExecutor;
    private static final long CAMERA_REFRESH_MS = 1000;
    /** Cards with buttons stay up at least this long, so there's time to reach the remote. */
    private static final int MIN_ACTION_SECONDS = 30;

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

    /** Takes every card down and stops the camera thread; the next camera card starts a new one. */
    void dismissAll() {
        mHandler.removeCallbacksAndMessages(null);
        mQueue.clear();
        hide();
        if (mCameraExecutor != null) {
            mCameraExecutor.shutdown();
            mCameraExecutor = null;
        }
    }

    private void showNext() {
        HaNotificationServer.Notification n = mQueue.poll();
        if (n == null) return;
        try {
            View card = buildCard(n);
            int flags = WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;
            if (n.actions.isEmpty()) flags |= WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
            WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY, flags, PixelFormat.TRANSLUCENT);
            params.gravity = gravity(n.position);
            params.x = dp(32);
            params.y = dp(32);
            params.windowAnimations = android.R.style.Animation_Toast;
            mWindowManager.addView(card, params);
            mShowing = card;
            int seconds = n.actions.isEmpty() ? n.durationSeconds : Math.max(n.durationSeconds, MIN_ACTION_SECONDS);
            mHandler.postDelayed(this::next, seconds * 1000L);
        } catch (Exception e) {
            mShowing = null;
            showNext();
        }
    }

    private void next() {
        mHandler.removeCallbacksAndMessages(null);
        hide();
        showNext();
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
        boolean wide = image != null || n.camera != null;
        if (n.camera != null) {
            ImageView picture = new ImageView(mService);
            picture.setScaleType(ImageView.ScaleType.CENTER_CROP);
            picture.setBackgroundColor(Color.BLACK);
            if (image != null) picture.setImageBitmap(image);
            card.addView(picture, new LinearLayout.LayoutParams(dp(400), dp(225)));
            refreshCamera(card, picture, n.camera);
        } else if (image != null) {
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
            title.setMaxWidth(dp(wide ? 300 : 420));
            texts.addView(title);
        }
        if (n.message != null && !n.message.isEmpty()) {
            TextView message = new TextView(mService);
            message.setText(n.message);
            message.setTextColor(n.title == null || n.title.isEmpty() ? TEXT : TEXT_DIM);
            message.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
            message.setMaxLines(4);
            message.setMaxWidth(dp(wide ? 300 : 420));
            texts.addView(message);
        }
        LinearLayout.LayoutParams textParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        row.addView(texts, textParams);

        int width = n.camera != null ? dp(400) : image != null ? dp(360) : LinearLayout.LayoutParams.WRAP_CONTENT;
        if (!isBlank(n.title) || !isBlank(n.message)) {
            card.addView(row, new LinearLayout.LayoutParams(width, LinearLayout.LayoutParams.WRAP_CONTENT));
        }
        if (!n.actions.isEmpty()) {
            card.addView(buildButtons(n, accent), new LinearLayout.LayoutParams(width, LinearLayout.LayoutParams.WRAP_CONTENT));
        }
        card.setMinimumWidth(dp(280));
        texts.setMinimumWidth(dp(200));
        return card;
    }

    /** Reloads the camera picture every second while this card is showing. */
    private void refreshCamera(View card, ImageView picture, String camera) {
        if (mCameraExecutor == null) {
            mCameraExecutor = Executors.newSingleThreadExecutor(r -> new Thread(r, "HearthHaCamera"));
        }
        mCameraExecutor.execute(() -> {
            Bitmap frame = decode(HaApi.cameraImage(mService, camera));
            mHandler.post(() -> {
                if (mShowing != card) return;
                if (frame != null) picture.setImageBitmap(frame);
                mHandler.postDelayed(() -> {
                    if (mShowing == card) refreshCamera(card, picture, camera);
                }, CAMERA_REFRESH_MS);
            });
        });
    }

    /**
     * The card's buttons plus a Close button, which starts with the focus: an action like "Unlock" should take a
     * deliberate press, never a stray OK.
     */
    private View buildButtons(HaNotificationServer.Notification n, int accent) {
        LinearLayout buttons = new LinearLayout(mService);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.END);
        buttons.setPadding(dp(12), 0, dp(12), dp(12));
        for (org.json.JSONObject action : n.actions) {
            addButton(buttons, action.optString("title"), accent, () -> {
                run(action);
                next();
            });
        }
        View close = addButton(buttons, "Close", accent, this::next);
        close.post(close::requestFocus);
        return buttons;
    }

    private View addButton(LinearLayout buttons, String title, int accent, Runnable onPress) {
        TextView button = new TextView(mService);
        button.setText(title);
        button.setTextColor(TEXT);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        button.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        button.setPadding(dp(18), dp(10), dp(18), dp(10));
        button.setFocusable(true);
        button.setBackground(buttonBackground(accent));
        button.setOnClickListener(v -> onPress.run());
        button.setOnKeyListener((v, keyCode, event) -> {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_UP) {
                next();
                return true;
            }
            return false;
        });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        params.setMarginStart(dp(8));
        buttons.addView(button, params);
        return button;
    }

    private void run(org.json.JSONObject action) {
        String[] service = action.optString("service").split("\\.", 2);
        org.json.JSONObject data = action.optJSONObject("data");
        HaApi.EXECUTOR.execute(() -> HaApi.callService(mService, service[0], service[1], data));
    }

    private android.graphics.drawable.Drawable buttonBackground(int accent) {
        GradientDrawable focused = new GradientDrawable();
        focused.setColor(accent);
        focused.setCornerRadius(dp(20));
        GradientDrawable normal = new GradientDrawable();
        normal.setColor(Color.parseColor("#33FFFFFF"));
        normal.setCornerRadius(dp(20));
        StateListDrawable states = new StateListDrawable();
        states.addState(new int[]{android.R.attr.state_focused}, focused);
        states.addState(new int[]{}, normal);
        return states;
    }

    private static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
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
        return Dp.px(mService, value);
    }
}
