package org.sbook.search;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.sqlite.SQLiteDatabase;
import android.os.Binder;
import android.os.IBinder;
import android.os.SystemClock;

import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class LibraryService extends Service {
    static final String ACTION_START = "org.sbook.search.START";
    static final String ACTION_REINDEX = "org.sbook.search.REINDEX";
    static final String PREFS = "library";
    static final String PREF_READY = "ready";
    static final String PREF_COUNT = "count";

    private static final String CHANNEL_ID = "library_setup";
    private static final int NOTIFICATION_ID = 77;
    private static final String BASE = "https://raw.githubusercontent.com/viskie/sbook_data_hashed/master/";
    private static final String PREFIX = "fec6266effb94db18b83a6392088aa7a-016e2a370490433d66b3cef384d6e5ba9a5a016b-org.tar.bz2";
    private static final Part[] PARTS = {
            new Part(PREFIX + "aa", 94_371_840L),
            new Part(PREFIX + "ab", 94_371_840L),
            new Part(PREFIX + "ac", 94_371_840L),
            new Part(PREFIX + "ad", 45_583_585L)
    };
    private static final long TOTAL_DOWNLOAD = 328_699_105L;
    private static final long MAX_INDEXED_FILE = 32L * 1024L * 1024L;

    public interface Listener {
        void onLibraryProgress(Snapshot snapshot);
    }

    public static final class Snapshot {
        public final String phase;
        public final String detail;
        public final int percent;
        public final int files;
        public final boolean running;
        public final boolean ready;
        public final String error;

        Snapshot(String phase, String detail, int percent, int files,
                 boolean running, boolean ready, String error) {
            this.phase = phase;
            this.detail = detail;
            this.percent = percent;
            this.files = files;
            this.running = running;
            this.ready = ready;
            this.error = error;
        }
    }

    public final class LocalBinder extends Binder {
        LibraryService getService() {
            return LibraryService.this;
        }
    }

    private final IBinder binder = new LocalBinder();
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private volatile Listener listener;
    private volatile Snapshot snapshot = new Snapshot("Waiting", "Dataset not installed", 0, 0,
            false, false, null);
    private volatile boolean running;
    private long lastPublishTime;

    @Override
    public void onCreate() {
        super.onCreate();
        createChannel();
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        if (prefs.getBoolean(PREF_READY, false)) {
            int count = prefs.getInt(PREF_COUNT, 0);
            snapshot = new Snapshot("Ready", formatCount(count) + " files indexed", 100, count,
                    false, true, null);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && !running) {
            if (ACTION_START.equals(intent.getAction())) {
                running = true;
                startForeground(
                        NOTIFICATION_ID,
                        notification("Preparing library", 0, true));
                worker.execute(this::installLibrary);

            } else if (ACTION_REINDEX.equals(intent.getAction())) {
                running = true;
                startForeground(
                        NOTIFICATION_ID,
                        notification("Reindexing existing library", 0, true));
                worker.execute(this::reindexExistingLibrary);
            }
        }
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    @Override
    public void onDestroy() {
        listener = null;
        worker.shutdownNow();
        super.onDestroy();
    }

    void setListener(Listener value) {
        listener = value;
        if (value != null) value.onLibraryProgress(snapshot);
    }

    Snapshot getSnapshot() {
        return snapshot;
    }

    private void installLibrary() {
        IndexDatabase index = new IndexDatabase(this);
        try {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(PREF_READY, false).apply();
            publish("Downloading", "Connecting to GitHub…", 0, 0, true, false, null, true);

            File partsDir = new File(getFilesDir(), "archive-parts");
            if (!partsDir.exists() && !partsDir.mkdirs()) {
                throw new IOException("Cannot create archive directory");
            }
            downloadParts(partsDir);

            File libraryRoot = new File(getFilesDir(), "library");
            deleteTree(libraryRoot);
            if (!libraryRoot.mkdirs()) throw new IOException("Cannot create library directory");

            SQLiteDatabase db = index.getWritableDatabase();
            index.reset(db);
            int fileCount = extractAndIndex(partsDir, libraryRoot, index, db);

            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean(PREF_READY, true)
                    .putInt(PREF_COUNT, fileCount)
                    .apply();
            deleteTree(partsDir);
            publish("Ready", formatCount(fileCount) + " files indexed", 100, fileCount,
                    false, true, null, true);
            updateNotification("Library ready — " + formatCount(fileCount) + " files", 100, false);
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        } catch (Exception exception) {
            String message = exception.getMessage();
            if (message == null || message.isBlank()) message = exception.getClass().getSimpleName();
            publish("Setup failed", message, 0, snapshot.files,
                    false, false, message, true);
            updateNotification("Setup failed: " + message, 0, false);
            stopForeground(STOP_FOREGROUND_DETACH);
            stopSelf();
        } finally {
            running = false;
            index.close();
        }
    }

    private void reindexExistingLibrary() {
        IndexDatabase index = new IndexDatabase(this);

        try {
            File root = new File(getFilesDir(), "library");

            if (!root.isDirectory()) {
                throw new IOException(
                        "Downloaded library not found.");
            }

            publish(
                    "Reindexing",
                    "Scanning existing library…",
                    0,
                    0,
                    true,
                    false,
                    null,
                    true);

            SQLiteDatabase db =
                    index.getWritableDatabase();

            /*
             * Search DB only.
             *
             * Does NOT delete files/library.
             * Does NOT touch bookmark database.
             * Does NOT download anything.
             */
            index.reset(db);

            int[] count = {0};

            db.beginTransaction();

            try {
                reindexDirectory(
                        root,
                        root,
                        index,
                        db,
                        count);

                db.setTransactionSuccessful();

            } finally {
                db.endTransaction();
            }

            getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_READY, true)
                    .putInt(PREF_COUNT, count[0])
                    .apply();

            publish(
                    "Ready",
                    formatCount(count[0]) +
                            " files reindexed",
                    100,
                    count[0],
                    false,
                    true,
                    null,
                    true);

            updateNotification(
                    "Reindex complete — " +
                            formatCount(count[0]) +
                            " files",
                    100,
                    false);

            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();

        } catch (Exception exception) {

            String message = exception.getMessage();

            if (message == null ||
                    message.isBlank()) {
                message =
                        exception
                                .getClass()
                                .getSimpleName();
            }

            publish(
                    "Reindex failed",
                    message,
                    0,
                    snapshot.files,
                    false,
                    false,
                    message,
                    true);

            updateNotification(
                    "Reindex failed: " + message,
                    0,
                    false);

            stopForeground(STOP_FOREGROUND_DETACH);
            stopSelf();

        } finally {
            running = false;
            index.close();
        }
    }


    private void reindexDirectory(
            File root,
            File directory,
            IndexDatabase index,
            SQLiteDatabase db,
            int[] count)
            throws IOException {

        File[] files = directory.listFiles();

        if (files == null)
            return;

        for (File file : files) {

            if (file.isDirectory()) {

                reindexDirectory(
                        root,
                        file,
                        index,
                        db,
                        count);

                continue;
            }

            if (!file.isFile())
                continue;

            String relative =
                    root.toPath()
                            .relativize(file.toPath())
                            .toString()
                            .replace(
                                    File.separatorChar,
                                    '/');

            String body = null;

            /*
             * Same content-indexing rule as original
             * extraction/indexing routine.
             */
            if (isTextFile(file.getName()) &&
                    file.length() <= MAX_INDEXED_FILE) {

                try (FileInputStream input =
                             new FileInputStream(file);

                     ByteArrayOutputStream text =
                             new ByteArrayOutputStream(
                                     (int) Math.min(
                                             file.length(),
                                             256 * 1024L))) {

                    byte[] buffer =
                            new byte[64 * 1024];

                    int read;

                    while ((read =
                            input.read(buffer)) != -1) {

                        text.write(
                                buffer,
                                0,
                                read);
                    }

                    body =
                            new String(
                                    text.toByteArray(),
                                    StandardCharsets.UTF_8);
                }
            }

            /*
             * logicalName stays ORIGINAL.
             *
             * IndexDatabase.insert() stores that original
             * name in documents, while only filename_fts
             * receives the exploded representation.
             */
            index.insert(
                    db,
                    relative,
                    logicalName(file.getName()),
                    body);

            count[0]++;

            if ((count[0] % 100) == 0) {

                publish(
                        "Reindexing",
                        formatCount(count[0]) +
                                " files • " +
                                file.getName(),
                        0,
                        count[0],
                        true,
                        false,
                        null,
                        false);
            }
        }
    }

    private void downloadParts(File partsDir) throws IOException {
        long completedBefore = 0;
        for (Part part : PARTS) {
            File destination = new File(partsDir, part.name);
            long existing = destination.exists() ? destination.length() : 0;
            if (existing > part.size) {
                if (!destination.delete()) throw new IOException("Cannot replace " + part.name);
                existing = 0;
            }
            if (existing == part.size) {
                completedBefore += part.size;
                continue;
            }
            downloadPart(part, destination, existing, completedBefore);
            if (destination.length() != part.size) {
                throw new IOException("Incomplete download: " + part.name);
            }
            completedBefore += part.size;
        }
    }

    private void downloadPart(Part part, File destination, long existing, long completedBefore)
            throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(BASE + part.name).openConnection();
        connection.setConnectTimeout(30_000);
        connection.setReadTimeout(60_000);
        connection.setRequestProperty("User-Agent", "SBookSearch-Android/1.0");
        if (existing > 0) connection.setRequestProperty("Range", "bytes=" + existing + "-");
        connection.connect();

        int response = connection.getResponseCode();
        boolean append = existing > 0 && response == HttpURLConnection.HTTP_PARTIAL;
        if (response != HttpURLConnection.HTTP_OK && response != HttpURLConnection.HTTP_PARTIAL) {
            throw new IOException("GitHub returned HTTP " + response);
        }
        if (!append) existing = 0;

        try (InputStream input = new BufferedInputStream(connection.getInputStream(), 64 * 1024);
             RandomAccessFile output = new RandomAccessFile(destination, "rw")) {
            if (append) output.seek(existing);
            else output.setLength(0);
            byte[] buffer = new byte[64 * 1024];
            long written = existing;
            int read;
            while ((read = input.read(buffer)) != -1) {
                output.write(buffer, 0, read);
                written += read;
                long total = completedBefore + written;
                int percent = (int) Math.min(100, total * 100 / TOTAL_DOWNLOAD);
                publish("Downloading", humanBytes(total) + " of " + humanBytes(TOTAL_DOWNLOAD),
                        percent, 0, true, false, null, false);
            }
        } finally {
            connection.disconnect();
        }
    }

    private int extractAndIndex(File partsDir, File libraryRoot, IndexDatabase index, SQLiteDatabase db)
            throws IOException {
        List<InputStream> streams = new ArrayList<>();
        for (Part part : PARTS) streams.add(new BufferedInputStream(new FileInputStream(new File(partsDir, part.name))));

        int fileCount = 0;
        db.beginTransaction();
        try (InputStream joined = new java.io.SequenceInputStream(Collections.enumeration(streams));
             ProgressInputStream compressed = new ProgressInputStream(joined, TOTAL_DOWNLOAD);
             BZip2CompressorInputStream bzip = new BZip2CompressorInputStream(compressed, true);
             TarArchiveInputStream tar = new TarArchiveInputStream(bzip)) {
            TarArchiveEntry entry;
            byte[] buffer = new byte[64 * 1024];
            String rootPath = libraryRoot.getCanonicalPath() + File.separator;
            while ((entry = tar.getNextTarEntry()) != null) {
                String relative = cleanRelativePath(entry.getName());
                if (relative.isEmpty()) continue;
                File destination = new File(libraryRoot, relative);
                String canonical = destination.getCanonicalPath();
                if (!canonical.startsWith(rootPath)) throw new IOException("Unsafe archive path");

                if (entry.isDirectory()) {
                    if (!destination.exists() && !destination.mkdirs()) {
                        throw new IOException("Cannot create " + relative);
                    }
                    continue;
                }
                if (!entry.isFile()) continue;
                File parent = destination.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    throw new IOException("Cannot create " + parent.getName());
                }

                boolean collectText = isTextFile(destination.getName()) && entry.getSize() <= MAX_INDEXED_FILE;
                ByteArrayOutputStream text = collectText
                        ? new ByteArrayOutputStream((int) Math.min(entry.getSize(), 256 * 1024L)) : null;
                try (BufferedOutputStream output = new BufferedOutputStream(new FileOutputStream(destination))) {
                    int read;
                    while ((read = tar.read(buffer)) != -1) {
                        output.write(buffer, 0, read);
                        if (text != null) text.write(buffer, 0, read);
                    }
                }

                String body = text == null ? null : new String(text.toByteArray(), StandardCharsets.UTF_8);
                index.insert(db, relative, logicalName(destination.getName()), body);
                fileCount++;
                int percent = (int) Math.min(99, compressed.count * 100 / TOTAL_DOWNLOAD);
                publish("Extracting & indexing",
                        formatCount(fileCount) + " files • " + destination.getName(),
                        percent, fileCount, true, false, null, false);
            }
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
        return fileCount;
    }

    private void publish(String phase, String detail, int percent, int files,
                         boolean isRunning, boolean ready, String error, boolean force) {
        long now = SystemClock.elapsedRealtime();
        if (!force && now - lastPublishTime < 250) return;
        lastPublishTime = now;
        snapshot = new Snapshot(phase, detail, percent, files, isRunning, ready, error);
        Listener target = listener;
        if (target != null) target.onLibraryProgress(snapshot);
        if (isRunning) updateNotification(phase + " — " + detail, percent, true);
    }

    private void createChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "Library setup", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Download, extraction, and search indexing progress");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private Notification notification(String text, int percent, boolean ongoing) {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pending = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("SBook Search")
                .setContentText(text)
                .setContentIntent(pending)
                .setOnlyAlertOnce(true)
                .setOngoing(ongoing)
                .setProgress(100, Math.max(0, percent), percent <= 0)
                .build();
    }

    private void updateNotification(String text, int percent, boolean ongoing) {
        getSystemService(NotificationManager.class)
                .notify(NOTIFICATION_ID, notification(text, percent, ongoing));
    }

    private static boolean isTextFile(String name) {
        String lower = logicalName(name).toLowerCase(Locale.ROOT);
        return lower.endsWith(".org") || lower.endsWith(".txt") || lower.endsWith(".md")
                || lower.endsWith(".markdown") || lower.endsWith(".html") || lower.endsWith(".htm")
                || lower.endsWith(".xml") || lower.endsWith(".json") || lower.endsWith(".csv")
                || lower.endsWith(".tsv") || lower.endsWith(".tex") || lower.endsWith(".srt")
                || lower.endsWith(".vtt") || lower.endsWith(".yaml") || lower.endsWith(".yml");
    }

    private static String logicalName(String archiveName) {
        int metadata = archiveName.indexOf("---");
        return metadata > 0 ? archiveName.substring(0, metadata) : archiveName;
    }

    private static String cleanRelativePath(String path) {
        String value = path.replace('\\', '/');
        while (value.startsWith("./")) value = value.substring(2);
        while (value.startsWith("/")) value = value.substring(1);
        return value;
    }

    private static void deleteTree(File file) throws IOException {
        if (!file.exists()) return;
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) for (File child : children) deleteTree(child);
        }
        if (!file.delete()) throw new IOException("Cannot remove old " + file.getName());
    }

    private static String humanBytes(long bytes) {
        return String.format(Locale.US, "%.1f MiB", bytes / 1024d / 1024d);
    }

    private static String formatCount(int value) {
        return String.format(Locale.US, "%,d", value);
    }

    private static final class Part {
        final String name;
        final long size;

        Part(String name, long size) {
            this.name = name;
            this.size = size;
        }
    }

    private static final class ProgressInputStream extends FilterInputStream {
        private final long total;
        private long count;

        ProgressInputStream(InputStream input, long total) {
            super(input);
            this.total = total;
        }

        @Override
        public int read() throws IOException {
            int value = super.read();
            if (value >= 0) count++;
            return value;
        }

        @Override
        public int read(byte[] bytes, int offset, int length) throws IOException {
            int value = super.read(bytes, offset, length);
            if (value > 0) count += value;
            return value;
        }
    }
}
