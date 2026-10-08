package com.leanbitlab.ltvL;

import android.content.Context;

/** Sizes for the views Hearth draws itself (overlays, cards, the panel), from dp to rounded pixels. */
final class Dp {
    private Dp() {}

    static int px(Context context, int dp) {
        return Math.round(dp * context.getResources().getDisplayMetrics().density);
    }
}
