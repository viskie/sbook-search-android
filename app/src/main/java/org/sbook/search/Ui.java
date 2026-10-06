package org.sbook.search;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

final class Ui {
    static final int ORANGE = Color.rgb(255, 121, 0);
    static final int ORANGE_DARK = Color.rgb(217, 95, 0);
    static final int BLACK = Color.rgb(8, 8, 8);
    static final int CHARCOAL = Color.rgb(23, 23, 23);
    static final int MID = Color.rgb(48, 48, 48);
    static final int WHITE = Color.rgb(255, 248, 240);
    static final int MUTED = Color.rgb(190, 180, 170);

    private Ui() {}

    static int dp(Context context, int value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    static GradientDrawable background(int color, float radiusDp, Context context) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(context, (int) radiusDp));
        return drawable;
    }

    static GradientDrawable outlined(int fill, int stroke, float radiusDp, Context context) {
        GradientDrawable drawable = background(fill, radiusDp, context);
        drawable.setStroke(dp(context, 1), stroke);
        return drawable;
    }

    static TextView text(Context context, String value, float sp, int color, boolean bold) {
        TextView view = new TextView(context);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setTypeface(Typeface.create("sans", bold ? Typeface.BOLD : Typeface.NORMAL));
        return view;
    }

    static void margins(View view, int left, int top, int right, int bottom) {
        ViewGroup.MarginLayoutParams params = (ViewGroup.MarginLayoutParams) view.getLayoutParams();
        params.setMargins(left, top, right, bottom);
        view.setLayoutParams(params);
    }
}

