package com.leanbitlab.ltvL;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.Log;
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
    private static final String TAG = "HearthHaPanel";
    static final String DASHBOARD_KEY = "ha_panel_dashboard";
    static final String DEFAULT_DASHBOARD = "lovelace";
    private static final int PANEL_WIDTH_DP = 350;
    /** Long-lived tokens don't expire; tell the frontend so, so it never asks to refresh. */
    private static final long TOKEN_LIFETIME_SECONDS = 10L * 365 * 24 * 3600;

    /**
     * Left with nothing further left closes the panel, like Right does for Settings. Only the page knows the layout,
     * so it decides: it closes unless a focusable element sits to the left on the same line, or the focus is on a
     * slider or text field, which use Left themselves.
     */
    private static final String LEFT_EDGE_SCRIPT = "(function(){"
            + "if(window.__hearthLeftEdge)return;window.__hearthLeftEdge=true;"
            + "function active(){var a=document.activeElement;while(a&&a.shadowRoot&&a.shadowRoot.activeElement)a=a.shadowRoot.activeElement;return a;}"
            + "function rects(root,out){var els=root.querySelectorAll('*');for(var i=0;i<els.length;i++){var el=els[i];"
            + "if(el.shadowRoot)rects(el.shadowRoot,out);"
            + "if(el.tabIndex>=0&&!el.disabled){var r=el.getBoundingClientRect();if(r.width>0&&r.height>0)out.push(r);}}return out;}"
            + "window.addEventListener('keydown',function(e){if(e.key!=='ArrowLeft')return;var a=active();"
            + "if(a&&a!==document.body&&a!==document.documentElement){"
            + "if(a.matches('input,textarea,select,[role=slider],ha-slider,md-slider'))return;"
            + "var r=a.getBoundingClientRect();"
            + "if(rects(document,[]).some(function(o){return o.right<=r.left+1&&o.bottom>r.top&&o.top<r.bottom;}))return;}"
            + "e.preventDefault();e.stopPropagation();hearthPanel.close();},true);"
            + "})();";

    private WebView mWebView;
    private String mToken;

    static String getDashboard(Context context) {
        String path = HaConfig.prefs(context).getString(DASHBOARD_KEY, null);
        return path == null || path.isEmpty() ? DEFAULT_DASHBOARD : path;
    }

    static boolean hasToken(Context context) {
        return HaConfig.token(context) != null;
    }

    static void setConfig(Context context, String token, String dashboard) {
        SharedPreferences.Editor editor = HaConfig.prefs(context).edit();
        if (token != null) {
            if (token.isEmpty()) editor.remove(HaConfig.TOKEN_KEY);
            else editor.putString(HaConfig.TOKEN_KEY, token);
        }
        if (dashboard != null) {
            String path = dashboard.trim().replaceAll("^/+|/+$", "");
            if (path.isEmpty()) editor.remove(DASHBOARD_KEY);
            else editor.putString(DASHBOARD_KEY, path);
        }
        editor.apply();
    }

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window window = getWindow();
        window.setLayout(Dp.px(this, PANEL_WIDTH_DP), WindowManager.LayoutParams.MATCH_PARENT);
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

        mToken = HaConfig.token(this);

        mWebView = new WebView(this);
        mWebView.setBackgroundColor(Color.TRANSPARENT);
        WebSettings settings = mWebView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        mWebView.addJavascriptInterface(new ExternalApp(), "externalApp");
        mWebView.addJavascriptInterface(new PanelBridge(), "hearthPanel");
        mWebView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                view.evaluateJavascript(LEFT_EDGE_SCRIPT, null);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    showMessage(getString(R.string.ha_panel_unreachable), String.valueOf(error.getDescription()));
                }
            }
        });
        root.addView(mWebView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root);

        if (!HaConfig.isConfigured(this)) {
            showMessage(getString(R.string.ha_panel_not_set_up), getString(R.string.ha_panel_not_set_up_detail));
        } else {
            mWebView.loadUrl(HaConfig.baseUrl(this) + "/" + getDashboard(this));
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

    private class PanelBridge {
        @JavascriptInterface
        public void close() {
            runOnUiThread(HaPanelActivity.this::finish);
        }
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
            } catch (Exception e) {
                Log.w(TAG, "Couldn't answer the dashboard's sign-in request", e);
            }
        }

        @JavascriptInterface
        public void revokeExternalAuth(String payload) {
            try {
                callJs(new JSONObject(payload).getString("callback") + "(true);");
            } catch (Exception e) {
                Log.w(TAG, "Couldn't answer the dashboard's sign-out request", e);
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
            } catch (Exception e) {
                Log.w(TAG, "Couldn't answer the dashboard's config request", e);
            }
        }
    }
}
