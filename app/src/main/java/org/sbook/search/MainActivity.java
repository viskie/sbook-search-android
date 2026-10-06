package org.sbook.search;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.Spinner;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

@SuppressLint("SetTextI18n")
public final class MainActivity extends Activity implements LibraryService.Listener {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService searchWorker = Executors.newSingleThreadExecutor();
    private final AtomicInteger searchGeneration = new AtomicInteger();

    private TextView phaseView;
    private TextView detailView;
    private ProgressBar progressBar;
    private Button setupButton;
    private Button filenameButton;
    private Button contentButton;
    private EditText searchInput;
    private ScriptKeyboardView keyboard;
    private TextView resultCount;
    private ResultAdapter resultAdapter;
    private IndexDatabase database;
    private LibraryService service;
    private boolean bound;
    private boolean ready;
    private boolean contentMode;
    private Runnable pendingSearch;

    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            service = ((LibraryService.LocalBinder) binder).getService();
            bound = true;
            service.setListener(MainActivity.this);
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            bound = false;
            service = null;
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        database = new IndexDatabase(this);
        setContentView(createContentView());
        boolean storedReady = getSharedPreferences(LibraryService.PREFS, MODE_PRIVATE)
                .getBoolean(LibraryService.PREF_READY, false);
        int storedCount = getSharedPreferences(LibraryService.PREFS, MODE_PRIVATE)
                .getInt(LibraryService.PREF_COUNT, 0);
        applySnapshot(storedReady
                ? new LibraryService.Snapshot("Ready", String.format(Locale.getDefault(), "%,d files indexed", storedCount),
                100, storedCount, false, true, null)
                : new LibraryService.Snapshot("Dataset required",
                "313.5 MiB download • extraction and indexing happen on this device",
                0, 0, false, false, null));
    }

    @Override
    protected void onStart() {
        super.onStart();
        bindService(new Intent(this, LibraryService.class), connection, Context.BIND_AUTO_CREATE);
    }

    @Override
    protected void onStop() {
        if (bound) {
            service.setListener(null);
            unbindService(connection);
            bound = false;
        }
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        if (pendingSearch != null) mainHandler.removeCallbacks(pendingSearch);
        searchWorker.shutdownNow();
        database.close();
        super.onDestroy();
    }

    @Override
    public void onLibraryProgress(LibraryService.Snapshot snapshot) {
        runOnUiThread(() -> applySnapshot(snapshot));
    }

    private View createContentView() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Ui.BLACK);

        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.VERTICAL);
        header.setPadding(Ui.dp(this, 18), Ui.dp(this, 16), Ui.dp(this, 18), Ui.dp(this, 13));
        header.setBackgroundColor(Ui.ORANGE);
        TextView eyebrow = Ui.text(this, "OFFLINE MULTILINGUAL LIBRARY", 11, Ui.BLACK, true);
        eyebrow.setLetterSpacing(.12f);
        TextView title = Ui.text(this, "SBook Search", 29, Ui.BLACK, true);
        TextView subtitle = Ui.text(this, "81K-document filename + full-text index", 14, Ui.BLACK, false);
        header.addView(eyebrow);
        header.addView(title);
        header.addView(subtitle);
        root.addView(header);

        LinearLayout status = new LinearLayout(this);
        status.setOrientation(LinearLayout.VERTICAL);
        status.setPadding(Ui.dp(this, 16), Ui.dp(this, 13), Ui.dp(this, 16), Ui.dp(this, 13));
        status.setBackground(Ui.outlined(Ui.CHARCOAL, Ui.ORANGE_DARK, 12, this));
        LinearLayout.LayoutParams statusParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        statusParams.setMargins(Ui.dp(this, 12), Ui.dp(this, 12), Ui.dp(this, 12), Ui.dp(this, 8));
        status.setLayoutParams(statusParams);
        phaseView = Ui.text(this, "Dataset required", 17, Ui.WHITE, true);
        detailView = Ui.text(this, "", 13, Ui.MUTED, false);
        detailView.setPadding(0, Ui.dp(this, 4), 0, Ui.dp(this, 8));
        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(100);
        progressBar.setProgressTintList(ColorStateList.valueOf(Ui.ORANGE));
        progressBar.setProgressBackgroundTintList(ColorStateList.valueOf(Ui.MID));
        setupButton = actionButton("DOWNLOAD + BUILD INDEX");
        setupButton.setOnClickListener(view -> startSetup());
        status.addView(phaseView);
        status.addView(detailView);
        status.addView(progressBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Ui.dp(this, 7)));
        LinearLayout.LayoutParams buttonParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Ui.dp(this, 48));
        buttonParams.setMargins(0, Ui.dp(this, 11), 0, 0);
        status.addView(setupButton, buttonParams);
        root.addView(status);

        LinearLayout modeRow = new LinearLayout(this);
        modeRow.setOrientation(LinearLayout.HORIZONTAL);
        modeRow.setPadding(Ui.dp(this, 12), Ui.dp(this, 4), Ui.dp(this, 12), Ui.dp(this, 6));
        filenameButton = modeButton("FILE NAMES");
        contentButton = modeButton("DOCUMENT TEXT");
        filenameButton.setOnClickListener(view -> setContentMode(false));
        contentButton.setOnClickListener(view -> setContentMode(true));
        modeRow.addView(filenameButton, new LinearLayout.LayoutParams(0, Ui.dp(this, 44), 1));
        LinearLayout.LayoutParams contentParams = new LinearLayout.LayoutParams(0, Ui.dp(this, 44), 1);
        contentParams.setMargins(Ui.dp(this, 8), 0, 0, 0);
        modeRow.addView(contentButton, contentParams);
        root.addView(modeRow);

        LinearLayout searchRow = new LinearLayout(this);
        searchRow.setOrientation(LinearLayout.HORIZONTAL);
        searchRow.setGravity(Gravity.CENTER_VERTICAL);
        searchRow.setPadding(Ui.dp(this, 12), 0, Ui.dp(this, 12), Ui.dp(this, 4));
        searchInput = new EditText(this);
        searchInput.setSingleLine(true);
        searchInput.setTextColor(Ui.WHITE);
        searchInput.setHintTextColor(Ui.MUTED);
        searchInput.setHint("Search indexed file names…");
        searchInput.setTextSize(17);
        searchInput.setPadding(Ui.dp(this, 14), 0, Ui.dp(this, 12), 0);
        searchInput.setBackground(Ui.outlined(Ui.CHARCOAL, Ui.MID, 10, this));
        searchInput.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) { scheduleSearch(); }
            @Override public void afterTextChanged(Editable s) {}
        });
        searchRow.addView(searchInput, new LinearLayout.LayoutParams(0, Ui.dp(this, 52), 1));

        Spinner scriptSpinner = new Spinner(this);
        ArrayAdapter<String> scriptAdapter = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, ScriptKeyboardView.SCRIPT_NAMES) {
            @Override
            public View getView(int position, View convertView, ViewGroup parent) {
                TextView view = (TextView) super.getView(position, convertView, parent);
                view.setTextColor(Ui.BLACK);
                view.setTextSize(13);
                view.setTypeface(Typeface.DEFAULT_BOLD);
                view.setGravity(Gravity.CENTER);
                return view;
            }

            @Override
            public View getDropDownView(int position, View convertView, ViewGroup parent) {
                TextView view = (TextView) super.getDropDownView(position, convertView, parent);
                view.setTextColor(Ui.WHITE);
                view.setBackgroundColor(Ui.CHARCOAL);
                view.setPadding(Ui.dp(MainActivity.this, 14), Ui.dp(MainActivity.this, 12),
                        Ui.dp(MainActivity.this, 14), Ui.dp(MainActivity.this, 12));
                return view;
            }
        };
        scriptSpinner.setAdapter(scriptAdapter);
        scriptSpinner.setBackground(Ui.background(Ui.ORANGE, 10, this));
        scriptSpinner.setPopupBackgroundDrawable(Ui.background(Ui.CHARCOAL, 4, this));
        scriptSpinner.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                if (keyboard == null) return;
                if (position == 0) keyboard.useSystemKeyboard();
                else keyboard.showScript(ScriptKeyboardView.SCRIPT_NAMES[position]);
            }
            @Override public void onNothingSelected(AdapterView<?> parent) {}
        });
        LinearLayout.LayoutParams spinnerParams = new LinearLayout.LayoutParams(
                Ui.dp(this, 112), Ui.dp(this, 52));
        spinnerParams.setMargins(Ui.dp(this, 8), 0, 0, 0);
        searchRow.addView(scriptSpinner, spinnerParams);
        root.addView(searchRow);

        resultCount = Ui.text(this, "Install the dataset to begin", 12, Ui.MUTED, false);
        resultCount.setPadding(Ui.dp(this, 15), Ui.dp(this, 4), Ui.dp(this, 15), Ui.dp(this, 5));
        root.addView(resultCount);

        ListView results = new ListView(this);
        results.setDividerHeight(0);
        results.setCacheColorHint(Ui.BLACK);
        results.setBackgroundColor(Ui.BLACK);
        resultAdapter = new ResultAdapter(this);
        results.setAdapter(resultAdapter);
        results.setOnItemClickListener((parent, view, position, id) -> {
            SearchResult item = resultAdapter.getItem(position);
            Intent intent = new Intent(this, DocumentActivity.class);
            intent.putExtra(DocumentActivity.EXTRA_PATH, item.path);
            intent.putExtra(DocumentActivity.EXTRA_QUERY, searchInput.getText().toString());
            startActivity(intent);
        });
        root.addView(results, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        keyboard = new ScriptKeyboardView(this, searchInput);
        keyboard.setVisibility(View.GONE);
        root.addView(keyboard, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        setContentMode(false);
        return root;
    }

    private Button actionButton(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextColor(Ui.BLACK);
        button.setTextSize(14);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setAllCaps(false);
        button.setBackground(Ui.background(Ui.ORANGE, 9, this));
        return button;
    }

    private Button modeButton(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextSize(13);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setAllCaps(false);
        return button;
    }

    private void setContentMode(boolean value) {
        contentMode = value;
        filenameButton.setTextColor(value ? Ui.MUTED : Ui.BLACK);
        filenameButton.setBackground(Ui.background(value ? Ui.CHARCOAL : Ui.ORANGE, 9, this));
        contentButton.setTextColor(value ? Ui.BLACK : Ui.MUTED);
        contentButton.setBackground(Ui.background(value ? Ui.ORANGE : Ui.CHARCOAL, 9, this));
        if (searchInput != null) {
            searchInput.setHint(value ? "Search Devanagari or other document text…" : "Search indexed file names…");
            scheduleSearch();
        }
    }

    private void startSetup() {
        if (android.os.Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 9);
        }
        Intent intent = new Intent(this, LibraryService.class).setAction(LibraryService.ACTION_START);
        startForegroundService(intent);
        setupButton.setEnabled(false);
    }

    private void applySnapshot(LibraryService.Snapshot snapshot) {
        ready = snapshot.ready;
        phaseView.setText(snapshot.phase);
        detailView.setText(snapshot.detail);
        progressBar.setProgress(snapshot.percent, true);
        setupButton.setEnabled(!snapshot.running);
        setupButton.setText(snapshot.error != null ? "RETRY DOWNLOAD + INDEX"
                : snapshot.ready ? "REBUILD DATASET" : "DOWNLOAD + BUILD INDEX");
        setupButton.setVisibility(snapshot.running ? View.GONE : View.VISIBLE);
        searchInput.setEnabled(snapshot.ready);
        filenameButton.setEnabled(snapshot.ready);
        contentButton.setEnabled(snapshot.ready);
        if (snapshot.ready) {
            resultCount.setText(String.format(Locale.getDefault(),
                    "%,d files ready • showing up to 100 results", snapshot.files));
            scheduleSearch();
        } else if (snapshot.running) {
            resultCount.setText("Search unlocks when indexing completes");
        }
    }

    private void scheduleSearch() {
        if (!ready || searchInput == null) return;
        if (pendingSearch != null) mainHandler.removeCallbacks(pendingSearch);
        int generation = searchGeneration.incrementAndGet();
        String query = searchInput.getText().toString();
        boolean searchContents = contentMode;
        pendingSearch = () -> searchWorker.execute(() -> {
            try {
                List<SearchResult> results = database.search(searchContents, query, 100);
                mainHandler.post(() -> {
                    if (generation != searchGeneration.get() || isFinishing()) return;
                    resultAdapter.setItems(results);
                    resultCount.setText(results.size() + (results.size() == 1 ? " result" : " results")
                            + (results.size() == 100 ? " • refine to narrow" : ""));
                });
            } catch (RuntimeException exception) {
                mainHandler.post(() -> resultCount.setText("Search index is busy — try again"));
            }
        });
        mainHandler.postDelayed(pendingSearch, 180);
    }

    private static final class ResultAdapter extends BaseAdapter {
        private final Context context;
        private final List<SearchResult> items = new ArrayList<>();

        ResultAdapter(Context context) {
            this.context = context;
        }

        void setItems(List<SearchResult> values) {
            items.clear();
            items.addAll(values);
            notifyDataSetChanged();
        }

        @Override public int getCount() { return items.size(); }
        @Override public SearchResult getItem(int position) { return items.get(position); }
        @Override public long getItemId(int position) { return position; }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            LinearLayout card;
            if (convertView instanceof LinearLayout) {
                card = (LinearLayout) convertView;
            } else {
                card = new LinearLayout(context);
                card.setOrientation(LinearLayout.VERTICAL);
                card.setPadding(Ui.dp(context, 14), Ui.dp(context, 11), Ui.dp(context, 14), Ui.dp(context, 11));
                card.setBackground(Ui.outlined(Ui.CHARCOAL, Ui.MID, 10, context));
                TextView name = Ui.text(context, "", 16, Ui.WHITE, true);
                TextView path = Ui.text(context, "", 11, Ui.ORANGE, false);
                TextView snippet = Ui.text(context, "", 13, Ui.MUTED, false);
                snippet.setMaxLines(3);
                card.addView(name);
                card.addView(path);
                card.addView(snippet);
                LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                params.setMargins(Ui.dp(context, 12), Ui.dp(context, 4), Ui.dp(context, 12), Ui.dp(context, 4));
                card.setLayoutParams(params);
            }
            SearchResult result = getItem(position);
            ((TextView) card.getChildAt(0)).setText(result.name);
            ((TextView) card.getChildAt(1)).setText(result.path);
            TextView snippet = (TextView) card.getChildAt(2);
            snippet.setText(result.snippet);
            snippet.setVisibility(result.snippet.isBlank() ? View.GONE : View.VISIBLE);
            return card;
        }
    }
}
