package com.thesiegs.hearth;

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
import android.webkit.WebView;
import android.widget.FrameLayout;

/**
 * The Home Assistant panel: a dashboard in a WebView on the right edge of the screen, mirroring the Settings
 * panel on the left. It signs in with a long-lived access token through the frontend's "external auth" bridge
 * (the same one the Home Assistant Companion app uses), so there is never a login screen. The dashboard itself is
 * HaPanelPage's, kept loaded between openings so the panel shows at once.
 */
public class HaPanelActivity extends Activity {
    static final String DASHBOARD_KEY = "ha_panel_dashboard";
    static final String DEFAULT_DASHBOARD = "lovelace";
    private static final int PANEL_WIDTH_DP = 350;

    private FrameLayout mRoot;
    /** The dashboard (HaPanelPage's, kept loaded between openings), or a message in its place. */
    private WebView mWebView;
    private boolean mShowsPage;

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

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        sOpen = new java.lang.ref.WeakReference<>(this);
        Window window = getWindow();
        window.setLayout(Dp.px(this, PANEL_WIDTH_DP), WindowManager.LayoutParams.MATCH_PARENT);
        window.setGravity(Gravity.END);
        // The home stays as it is beside the panel: no dimming
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);

        float radius = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 28, getResources().getDisplayMetrics());
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(0x11, 0x11, 0x11));
        background.setCornerRadii(new float[]{radius, radius, 0, 0, 0, 0, radius, radius});
        mRoot = new FrameLayout(this);
        mRoot.setBackground(background);
        mRoot.setClipToOutline(true);
        setContentView(mRoot);

        if (!HaConfig.isConfigured(this)) {
            showMessage(getString(R.string.ha_panel_not_set_up), getString(R.string.ha_panel_not_set_up_detail));
        } else {
            show(HaPanelPage.take(this), true);
        }
    }

    private void show(WebView webView, boolean page) {
        if (mWebView != null && !mShowsPage) mWebView.destroy();
        mRoot.removeAllViews();
        mWebView = webView;
        mShowsPage = page;
        mRoot.addView(webView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        webView.requestFocus(View.FOCUS_DOWN);
    }

    /** A message in the dashboard's place (not set up, or unreachable: then the page loads again next time). */
    void showMessage(String title, String detail) {
        if (mShowsPage) {
            HaPanelPage.markFailed();
            HaPanelPage.giveBack(this);
        }
        WebView message = new WebView(this);
        message.setBackgroundColor(Color.TRANSPARENT);
        String html = "<html><body style='background:transparent;color:#ddd;font-family:sans-serif;padding:24px'>"
                + "<h3 style='color:#fff'>" + escape(title) + "</h3><p>" + escape(detail) + "</p></body></html>";
        message.loadDataWithBaseURL(null, html, "text/html", "utf-8", null);
        show(message, false);
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

    /** The panel that's open, if any: the Home button closes it. */
    private static java.lang.ref.WeakReference<HaPanelActivity> sOpen;

    /** Closes the panel if it's open (the Home button). */
    static void closeIfOpen() {
        HaPanelActivity open = sOpen != null ? sOpen.get() : null;
        if (open != null) open.runOnUiThread(open::finish);
    }

    @Override
    public void finish() {
        super.finish();
        overridePendingTransition(0, R.anim.ha_panel_out);
    }

    @Override
    protected void onDestroy() {
        if (sOpen != null && sOpen.get() == this) sOpen = null;
        if (mWebView != null) {
            if (mShowsPage) {
                HaPanelPage.giveBack(this);
            } else {
                mWebView.destroy();
            }
            mWebView = null;
        }
        super.onDestroy();
    }
}
