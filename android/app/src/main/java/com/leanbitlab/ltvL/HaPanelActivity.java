package com.leanbitlab.ltvL;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import org.json.JSONObject;

/**
 * The Home Assistant panel: a dashboard in a WebView on the right edge of the screen, mirroring the Settings
 * panel on the left. It signs in with a long-lived access token through the frontend's "external auth" bridge
 * (the same one the Home Assistant Companion app uses), so there is never a login screen.
 */
public class HaPanelActivity extends Activity {
    static final String TOKEN_KEY = "ha_panel_token";
    static final String DASHBOARD_KEY = "ha_panel_dashboard";
    static final String DEFAULT_DASHBOARD = "hearth-tv/family_room";
    private static final int PANEL_WIDTH_DP = 350;
    /** Long-lived tokens don't expire; tell the frontend so, so it never asks to refresh. */
    private static final long TOKEN_LIFETIME_SECONDS = 10L * 365 * 24 * 3600;

    private WebView mWebView;
    private String mToken;

    static String getDashboard(Context context) {
        String path = prefs(context).getString(DASHBOARD_KEY, null);
        return path == null || path.isEmpty() ? DEFAULT_DASHBOARD : path;
    }

    static boolean hasToken(Context context) {
        String token = prefs(context).getString(TOKEN_KEY, null);
        return token != null && !token.isEmpty();
    }

    static void setConfig(Context context, String token, String dashboard) {
        SharedPreferences.Editor editor = prefs(context).edit();
        if (token != null) {
            if (token.isEmpty()) editor.remove(TOKEN_KEY);
            else editor.putString(TOKEN_KEY, token);
        }
        if (dashboard != null) {
            String path = dashboard.trim().replaceAll("^/+|/+$", "");
            if (path.isEmpty()) editor.remove(DASHBOARD_KEY);
            else editor.putString(DASHBOARD_KEY, path);
        }
        editor.apply();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(LauncherAccessibilityService.DEVICE_PREFS, MODE_PRIVATE);
    }

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window window = getWindow();
        int width = Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, PANEL_WIDTH_DP, getResources().getDisplayMetrics()));
        window.setLayout(width, WindowManager.LayoutParams.MATCH_PARENT);
        window.setGravity(Gravity.END);
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        window.setDimAmount(0.7f);

        float radius = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 28, getResources().getDisplayMetrics());
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(0x11, 0x11, 0x11));
        background.setCornerRadii(new float[]{radius, radius, 0, 0, 0, 0, radius, radius});
        FrameLayout root = new FrameLayout(this);
        root.setBackground(background);
        root.setClipToOutline(true);

        mToken = prefs(this).getString(TOKEN_KEY, null);
        String baseUrl = prefs(this).getString(HaStatusReporter.URL_KEY, null);

        mWebView = new WebView(this);
        mWebView.setBackgroundColor(Color.TRANSPARENT);
        WebSettings settings = mWebView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        mWebView.addJavascriptInterface(new ExternalApp(), "externalApp");
        mWebView.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    showMessage("Can't reach Home Assistant", String.valueOf(error.getDescription()));
                }
            }
        });
        root.addView(mWebView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root);

        if (baseUrl == null || baseUrl.isEmpty() || mToken == null || mToken.isEmpty()) {
            showMessage("Home Assistant panel isn't set up",
                    "Add the Home Assistant address and an access token in Settings → Home Assistant.");
        } else {
            mWebView.loadUrl(baseUrl.replaceAll("/+$", "") + "/" + getDashboard(this));
        }
        mWebView.requestFocus(View.FOCUS_DOWN);
    }

    private void showMessage(String title, String detail) {
        String html = "<html><body style='background:transparent;color:#ddd;font-family:sans-serif;padding:24px'>"
                + "<h3 style='color:#fff'>" + escape(title) + "</h3><p>" + escape(detail) + "</p></body></html>";
        mWebView.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
    }

    private static String escape(String s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getKeyCode() == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_UP) {
            finish();
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    public void finish() {
        super.finish();
        overridePendingTransition(0, R.anim.ha_panel_out);
    }

    @Override
    protected void onDestroy() {
        if (mWebView != null) {
            mWebView.destroy();
            mWebView = null;
        }
        super.onDestroy();
    }

    private void callJs(String script) {
        runOnUiThread(() -> {
            if (mWebView != null) mWebView.evaluateJavascript(script, null);
        });
    }

    /** What the Home Assistant frontend looks for as {@code window.externalApp}. */
    private class ExternalApp {
        @JavascriptInterface
        public void getExternalAuth(String payload) {
            try {
                String callback = new JSONObject(payload).getString("callback");
                JSONObject auth = new JSONObject();
                auth.put("access_token", mToken);
                auth.put("expires_in", TOKEN_LIFETIME_SECONDS);
                callJs(callback + "(true, " + auth + ");");
            } catch (Exception ignored) {
            }
        }

        @JavascriptInterface
        public void revokeExternalAuth(String payload) {
            try {
                callJs(new JSONObject(payload).getString("callback") + "(true);");
            } catch (Exception ignored) {
            }
        }

        /** Messages from the frontend; it waits for an answer to "config/get" before finishing its setup. */
        @JavascriptInterface
        public void externalBus(String message) {
            try {
                JSONObject msg = new JSONObject(message);
                if (!"config/get".equals(msg.optString("type"))) return;
                JSONObject config = new JSONObject();
                config.put("hasSettingsScreen", false);
                config.put("canWriteTag", false);
                config.put("hasExoPlayer", false);
                config.put("canCommissionMatter", false);
                config.put("canImportThreadCredentials", false);
                config.put("hasAssist", false);
                JSONObject reply = new JSONObject();
                reply.put("id", msg.get("id"));
                reply.put("type", "result");
                reply.put("success", true);
                reply.put("result", config);
                callJs("window.externalBus(" + reply + ");");
            } catch (Exception ignored) {
            }
        }
    }
}
