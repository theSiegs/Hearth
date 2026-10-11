package com.thesiegs.hearth;

import android.annotation.SuppressLint;
import android.content.ComponentCallbacks2;
import android.content.Context;
import android.content.MutableContextWrapper;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONObject;

/**
 * The Home Assistant panel's dashboard, kept loaded while the panel is closed, so it shows at once when it opens
 * (loading Home Assistant's frontend takes seconds on a TV). Hearth loads it in the background once its home is up
 * and the panel is on (preload); HaPanelActivity borrows the page while it's open and gives it back when it closes.
 * The page stays connected to Home Assistant meanwhile, as its own app's would. It's let go when the panel is
 * switched off or Home Assistant isn't set up, when its address, token or dashboard change, when it failed to load
 * (the next opening tries again), and when Android runs short of memory (the next opening loads it as before).
 * Main thread only.
 */
final class HaPanelPage {
    private static final String TAG = "HearthHaPanel";
    /** The Dart setting (SettingsService.haPanelEnabled) that turns the panel on. */
    private static final String PANEL_ENABLED_KEY = "ha_panel_enabled";
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

    private static final Handler sMain = new Handler(Looper.getMainLooper());
    private static WebView sWebView;
    private static MutableContextWrapper sContext;
    /** What the page was loaded with: a change to any of them means loading it again. */
    private static String sUrl;
    private static String sToken;
    private static boolean sFailed;
    /** The panel showing the page now, if any. */
    private static HaPanelActivity sHost;

    private HaPanelPage() {
    }

    /** The dashboard's address, or null when Home Assistant isn't set up. */
    private static String url(Context context) {
        if (!HaConfig.isConfigured(context)) return null;
        return HaConfig.baseUrl(context) + "/" + HaPanelActivity.getDashboard(context);
    }

    private static boolean upToDate(Context context) {
        return sWebView != null && !sFailed && sUrl != null && sUrl.equals(url(context))
                && sToken != null && sToken.equals(HaConfig.token(context));
    }

    /** Loads the dashboard in the background if the panel is on and it isn't loaded yet; lets it go if it's off. */
    static void preload(Context context) {
        if (!FlutterPrefs.getBoolean(context, PANEL_ENABLED_KEY, false) || url(context) == null) {
            if (sHost == null) release();
            return;
        }
        if (sHost != null || upToDate(context)) return;
        load(context.getApplicationContext());
        Log.i(TAG, "Loading the dashboard in the background");
    }

    /** The page for the panel to show: the one kept loaded, or a new one loading now. */
    static WebView take(HaPanelActivity host) {
        if (!upToDate(host)) load(host.getApplicationContext());
        if (sHost != null && sHost != host) sHost.finish();
        detach();
        sHost = host;
        sContext.setBaseContext(host);
        sWebView.onResume();
        return sWebView;
    }

    /** The panel closed: the page is kept, out of sight, for next time (unless it failed). */
    static void giveBack(HaPanelActivity host) {
        if (sHost != host || sWebView == null) return;
        sHost = null;
        detach();
        sContext.setBaseContext(host.getApplicationContext());
        sWebView.onPause();
        if (sFailed) release();
    }

    /** Android is short of memory: the page goes unless the panel is showing it. */
    static void onTrimMemory(int level) {
        boolean low = level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW
                || level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL
                || level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE;
        if (low && sHost == null && sWebView != null) {
            Log.i(TAG, "Short of memory: letting the dashboard go");
            release();
        }
    }

    /** The page failed to load (shown as a message instead): it's loaded again next time. */
    static void markFailed() {
        sFailed = true;
    }

    static void release() {
        if (sWebView == null) return;
        detach();
        sWebView.destroy();
        sWebView = null;
        sContext = null;
        sUrl = null;
        sToken = null;
        sFailed = false;
    }

    private static void detach() {
        if (sWebView != null && sWebView.getParent() instanceof ViewGroup) {
            ((ViewGroup) sWebView.getParent()).removeView(sWebView);
        }
    }

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    private static void load(Context appContext) {
        release();
        sContext = new MutableContextWrapper(appContext);
        WebView webView = new WebView(sContext);
        webView.setBackgroundColor(Color.TRANSPARENT);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        webView.addJavascriptInterface(new ExternalApp(), "externalApp");
        webView.addJavascriptInterface(new PanelBridge(), "hearthPanel");
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                view.evaluateJavascript(LEFT_EDGE_SCRIPT, null);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (!request.isForMainFrame()) return;
                sFailed = true;
                if (sHost != null) {
                    sHost.showMessage(sHost.getString(R.string.ha_panel_unreachable),
                            String.valueOf(error.getDescription()));
                }
            }
        });
        sWebView = webView;
        sUrl = url(appContext);
        sToken = HaConfig.token(appContext);
        sFailed = false;
        webView.loadUrl(sUrl);
    }

    private static void callJs(String script) {
        sMain.post(() -> {
            if (sWebView != null) sWebView.evaluateJavascript(script, null);
        });
    }

    private static class PanelBridge {
        @JavascriptInterface
        public void close() {
            sMain.post(() -> {
                if (sHost != null) sHost.finish();
            });
        }
    }

    /** What the Home Assistant frontend looks for as {@code window.externalApp}. */
    private static class ExternalApp {
        @JavascriptInterface
        public void getExternalAuth(String payload) {
            try {
                String callback = new JSONObject(payload).getString("callback");
                JSONObject auth = new JSONObject();
                auth.put("access_token", sToken);
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
