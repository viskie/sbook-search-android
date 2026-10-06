package org.sbook.search;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.Spannable;
import android.text.SpannableString;
import android.text.style.BackgroundColorSpan;
import android.text.style.ForegroundColorSpan;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class DocumentActivity extends Activity {
    static final String EXTRA_PATH = "path";
    static final String EXTRA_QUERY = "query";
    private static final long MAX_PREVIEW = 16L * 1024L * 1024L;

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private TextView body;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String relativePath = getIntent().getStringExtra(EXTRA_PATH);
        String query = getIntent().getStringExtra(EXTRA_QUERY);
        setContentView(createView(relativePath == null ? "Document" : new File(relativePath).getName(), relativePath));
        worker.execute(() -> loadDocument(relativePath, query == null ? "" : query));
    }

    @Override
    protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }

    private LinearLayout createView(String name, String path) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.BLACK);

        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setOrientation(LinearLayout.HORIZONTAL);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(Ui.dp(this, 8), Ui.dp(this, 8), Ui.dp(this, 12), Ui.dp(this, 8));
        toolbar.setBackgroundColor(Ui.ORANGE);
        Button back = new Button(this);
        back.setText("‹");
        back.setTextSize(28);
        back.setTextColor(Ui.BLACK);
        back.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        back.setOnClickListener(view -> finish());
        toolbar.addView(back, new LinearLayout.LayoutParams(Ui.dp(this, 48), Ui.dp(this, 48)));
        LinearLayout labels = new LinearLayout(this);
        labels.setOrientation(LinearLayout.VERTICAL);
        TextView title = Ui.text(this, name, 19, Ui.BLACK, true);
        title.setSingleLine(true);
        TextView location = Ui.text(this, path == null ? "" : path, 11, Ui.BLACK, false);
        location.setSingleLine(true);
        labels.addView(title);
        labels.addView(location);
        toolbar.addView(labels, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        root.addView(toolbar);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        body = Ui.text(this, "Loading document…", 16, Ui.WHITE, false);
        body.setTypeface(Typeface.create("sans", Typeface.NORMAL));
        body.setTextIsSelectable(true);
        body.setLineSpacing(0, 1.18f);
        body.setPadding(Ui.dp(this, 18), Ui.dp(this, 18), Ui.dp(this, 18), Ui.dp(this, 28));
        scroll.addView(body, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        return root;
    }

    private void loadDocument(String relativePath, String query) {
        try {
            if (relativePath == null) throw new IOException("Missing document path");
            File root = new File(getFilesDir(), "library");
            File file = new File(root, relativePath);
            String rootPath = root.getCanonicalPath() + File.separator;
            if (!file.getCanonicalPath().startsWith(rootPath) || !file.isFile()) {
                throw new IOException("Document is no longer available");
            }
            if (!isTextFile(file.getName())) {
                postText("This file is stored offline but does not have a built-in text preview.\n\n" +
                        "Path: " + relativePath + "\nSize: " + humanSize(file.length()));
                return;
            }
            if (file.length() > MAX_PREVIEW) {
                postText("This document is too large for the in-app preview (" + humanSize(file.length()) + ").");
                return;
            }
            byte[] data;
            try (FileInputStream input = new FileInputStream(file)) {
                data = new byte[(int) file.length()];
                int offset = 0;
                while (offset < data.length) {
                    int read = input.read(data, offset, data.length - offset);
                    if (read < 0) break;
                    offset += read;
                }
            }
            String content = new String(data, StandardCharsets.UTF_8);
            postHighlighted(content, query);
        } catch (IOException exception) {
            postText("Unable to open document\n\n" + exception.getMessage());
        }
    }

    private void postText(String value) {
        runOnUiThread(() -> body.setText(value));
    }

    private void postHighlighted(String content, String query) {
        if (query.isBlank()) {
            postText(content);
            return;
        }
        SpannableString highlighted = new SpannableString(content);
        String lower = content.toLowerCase(Locale.ROOT);
        String needle = query.trim().toLowerCase(Locale.ROOT);
        int start = 0;
        int matches = 0;
        while (!needle.isEmpty() && matches < 250 && (start = lower.indexOf(needle, start)) >= 0) {
            int end = start + needle.length();
            highlighted.setSpan(new BackgroundColorSpan(Ui.ORANGE), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
            highlighted.setSpan(new ForegroundColorSpan(Ui.BLACK), start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE);
            start = end;
            matches++;
        }
        runOnUiThread(() -> body.setText(highlighted));
    }

    private static boolean isTextFile(String name) {
        int metadata = name.indexOf("---");
        String lower = (metadata > 0 ? name.substring(0, metadata) : name).toLowerCase(Locale.ROOT);
        return lower.endsWith(".org") || lower.endsWith(".txt") || lower.endsWith(".md")
                || lower.endsWith(".markdown") || lower.endsWith(".html") || lower.endsWith(".htm")
                || lower.endsWith(".xml") || lower.endsWith(".json") || lower.endsWith(".csv")
                || lower.endsWith(".tsv") || lower.endsWith(".tex") || lower.endsWith(".srt")
                || lower.endsWith(".vtt") || lower.endsWith(".yaml") || lower.endsWith(".yml");
    }

    private static String humanSize(long bytes) {
        return String.format(Locale.US, "%.1f MiB", bytes / 1024d / 1024d);
    }
}
