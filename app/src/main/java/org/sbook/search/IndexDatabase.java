package org.sbook.search;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class IndexDatabase extends SQLiteOpenHelper {
    private static final String DB_NAME = "sbook-index.db";
    private static final int DB_VERSION = 1;
    private static final Pattern TOKEN = Pattern.compile("[\\p{L}\\p{M}\\p{N}]+");

    IndexDatabase(Context context) {
        super(context, DB_NAME, null, DB_VERSION);
        setWriteAheadLoggingEnabled(true);
    }

    @Override
    public void onConfigure(SQLiteDatabase db) {
        super.onConfigure(db);
        db.setForeignKeyConstraintsEnabled(true);
        db.rawQuery("PRAGMA synchronous=NORMAL", null).close();
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE documents (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL)");
        db.execSQL("CREATE INDEX documents_name ON documents(name COLLATE NOCASE)");
        db.execSQL("CREATE VIRTUAL TABLE filename_fts USING fts4(name, tokenize=unicode61)");
        db.execSQL("CREATE VIRTUAL TABLE content_fts USING fts4(body, tokenize=unicode61)");
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        reset(db);
    }

    void reset(SQLiteDatabase db) {
        db.execSQL("DROP TABLE IF EXISTS content_fts");
        db.execSQL("DROP TABLE IF EXISTS filename_fts");
        db.execSQL("DROP TABLE IF EXISTS documents");
        onCreate(db);
    }

    long insert(SQLiteDatabase db, String path, String name, String body) {
        ContentValues document = new ContentValues();
        document.put("path", path);
        document.put("name", name);
        long id = db.insertOrThrow("documents", null, document);

        ContentValues filename = new ContentValues();
        filename.put("docid", id);
        filename.put("name", explodeFilenameForSearch(name));
        db.insertOrThrow("filename_fts", null, filename);

        if (body != null && !body.isBlank()) {
            ContentValues content = new ContentValues();
            content.put("docid", id);
            content.put("body", body);
            db.insertOrThrow("content_fts", null, content);
        }
        return id;
    }

    List<SearchResult> search(boolean contents, String rawQuery, int limit) {
        List<SearchResult> results = new ArrayList<>();

        if (rawQuery == null || rawQuery.trim().isEmpty()) {
            return results;
        }

        SQLiteDatabase db = getReadableDatabase();

        if (contents) {
            // Preserve existing full-text behavior.
            String query = toMatchQuery(rawQuery);

            if (query.isEmpty()) {
                return results;
            }

            String sql =
                    "SELECT d.path,d.name," +
                    "snippet(content_fts,0,'','',' … ',12) " +
                    "FROM content_fts " +
                    "JOIN documents d ON d.id=content_fts.docid " +
                    "WHERE content_fts MATCH ? " +
                    "ORDER BY rank LIMIT ?";

            try (Cursor cursor = db.rawQuery(
                    sql,
                    new String[]{
                            query,
                            Integer.toString(limit)
                    })) {

                while (cursor.moveToNext()) {
                    results.add(new SearchResult(
                            cursor.getString(0),
                            cursor.getString(1),
                            cursor.getString(2)
                    ));
                }
            }

            return results;
        }

        /*
         * SBOOK_MULTIWORD_FILENAME_SEARCH
         *
         * Filename syntax:
         *
         *   foo bar
         *       foo AND bar
         *
         *   foo AND bar
         *       foo AND bar
         *
         *   foo OR bar
         *       foo OR bar
         *
         *   foo bar OR baz qux
         *       (foo AND bar) OR (baz AND qux)
         *
         * AND has higher precedence than OR.
         *
         * AND/OR themselves are case-insensitive.
         *
         * Filename comparisons use:
         *
         *       LIKE ? COLLATE NOCASE
         *
         * Every search term is a substring:
         *
         *       ash  -> %ash%
         *       dhya -> %dhya%
         *
         * No reindex is required.
         */

        String normalized = rawQuery.trim();

        /*
         * Normalize explicit AND.
         *
         * Since whitespace already means AND, explicit AND can
         * simply become whitespace.
         *
         * (?i) = case-insensitive Java regex.
         */
        normalized = normalized.replaceAll(
                "(?i)\\s+AND\\s+",
                " "
        );

        /*
         * Split on explicit OR, case-insensitively.
         *
         * Each resulting group is an AND group.
         */
        String[] orGroups = normalized.split(
                "(?i)\\s+OR\\s+"
        );

        StringBuilder where = new StringBuilder();

        List<String> args = new ArrayList<>();

        for (String group : orGroups) {

            group = group.trim();

            if (group.isEmpty()) {
                continue;
            }

            String[] terms = group.split("\\s+");

            List<String> cleanTerms = new ArrayList<>();

            for (String term : terms) {

                term = term.trim();

                if (term.isEmpty()) {
                    continue;
                }

                /*
                 * A stray operator should never become a filename
                 * search term.
                 */
                if (term.equalsIgnoreCase("AND") ||
                        term.equalsIgnoreCase("OR")) {
                    continue;
                }

                cleanTerms.add(term);
            }

            if (cleanTerms.isEmpty()) {
                continue;
            }

            if (where.length() > 0) {
                where.append(" OR ");
            }

            where.append("(");

            for (int i = 0; i < cleanTerms.size(); i++) {

                if (i > 0) {
                    where.append(" AND ");
                }

                where.append(
                        "name LIKE ? COLLATE NOCASE"
                );

                /*
                 * Escape LIKE metacharacters so a filename query
                 * containing % or _ is treated literally.
                 *
                 * '\' is used as SQLite LIKE escape character.
                 */
                String term = cleanTerms.get(i)
                        .replace("\\", "\\\\")
                        .replace("%", "\\%")
                        .replace("_", "\\_");

                /*
                 * Replace the condition we just appended with an
                 * ESCAPE clause.
                 */
                int conditionStart =
                        where.lastIndexOf(
                                "name LIKE ? COLLATE NOCASE"
                        );

                where.replace(
                        conditionStart,
                        where.length(),
                        "name LIKE ? ESCAPE '\\' COLLATE NOCASE"
                );

                args.add("%" + term + "%");
            }

            where.append(")");
        }

        if (where.length() == 0) {
            return results;
        }

        String sql =
                "SELECT path,name,'' FROM documents " +
                "WHERE " + where +
                " ORDER BY name COLLATE NOCASE LIMIT ?";

        args.add(Integer.toString(limit));

        try (Cursor cursor = db.rawQuery(
                sql,
                args.toArray(new String[0]))) {

            while (cursor.moveToNext()) {
                results.add(new SearchResult(
                        cursor.getString(0),
                        cursor.getString(1),
                        cursor.getString(2)
                ));
            }
        }

        return results;
    }

    private List<SearchResult> browse(SQLiteDatabase db, int limit) {
        List<SearchResult> results = new ArrayList<>();
        try (Cursor cursor = db.rawQuery(
                "SELECT path,name,'' FROM documents ORDER BY name COLLATE NOCASE LIMIT ?",
                new String[]{Integer.toString(limit)})) {
            while (cursor.moveToNext()) {
                results.add(new SearchResult(cursor.getString(0), cursor.getString(1), ""));
            }
        }
        return results;
    }

    int count() {
        try (Cursor cursor = getReadableDatabase().rawQuery("SELECT count(*) FROM documents", null)) {
            return cursor.moveToFirst() ? cursor.getInt(0) : 0;
        }
    }

    private static String explodeFilenameForSearch(String name) {
        if (name == null) return "";

        return name
                .replaceAll("[^\\p{L}\\p{M}\\p{N}]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }

    private static String toMatchQuery(String raw) {
        String normalized = raw == null ? "" : raw.trim().toLowerCase(Locale.ROOT);
        Matcher matcher = TOKEN.matcher(normalized);
        StringBuilder output = new StringBuilder();
        while (matcher.find()) {
            if (output.length() > 0) output.append(" AND ");
            output.append('"').append(matcher.group().replace("\"", "\"\"")).append("\"*");
        }
        return output.toString();
    }
}

