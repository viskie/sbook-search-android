package org.sbook.search;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

import java.util.ArrayList;
import java.util.List;

public class BookmarkDatabase
        extends SQLiteOpenHelper {

    private static final String DB_NAME =
            "sbook_library.db";

    private static final int DB_VERSION = 1;

    public BookmarkDatabase(Context context) {
        super(
                context,
                DB_NAME,
                null,
                DB_VERSION
        );
    }

    @Override
    public void onConfigure(SQLiteDatabase db) {

        super.onConfigure(db);

        db.setForeignKeyConstraintsEnabled(true);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {

        db.execSQL(
            "CREATE TABLE categories (" +
            "id INTEGER PRIMARY KEY AUTOINCREMENT," +
            "name TEXT NOT NULL UNIQUE COLLATE NOCASE," +
            "created_at INTEGER NOT NULL)"
        );

        db.execSQL(
            "CREATE TABLE bookmarks (" +
            "id INTEGER PRIMARY KEY AUTOINCREMENT," +
            "file_path TEXT NOT NULL UNIQUE," +
            "display_name TEXT NOT NULL," +
            "created_at INTEGER NOT NULL," +
            "last_opened_at INTEGER NOT NULL DEFAULT 0)"
        );

        db.execSQL(
            "CREATE TABLE bookmark_categories (" +
            "bookmark_id INTEGER NOT NULL," +
            "category_id INTEGER NOT NULL," +

            "PRIMARY KEY(" +
            "bookmark_id," +
            "category_id)," +

            "FOREIGN KEY(bookmark_id) " +
            "REFERENCES bookmarks(id) " +
            "ON DELETE CASCADE," +

            "FOREIGN KEY(category_id) " +
            "REFERENCES categories(id) " +
            "ON DELETE CASCADE)"
        );

        ContentValues values =
                new ContentValues();

        values.put(
                "name",
                "Uncategorized"
        );

        values.put(
                "created_at",
                System.currentTimeMillis()
        );

        db.insert(
                "categories",
                null,
                values
        );
    }

    @Override
    public void onUpgrade(
            SQLiteDatabase db,
            int oldVersion,
            int newVersion) {
    }

    // ========================================================
    // Categories
    // ========================================================

    public long createCategory(String name) {

        if (name == null)
            return -1;

        name = name.trim();

        if (name.isEmpty())
            return -1;

        ContentValues values =
                new ContentValues();

        values.put("name", name);

        values.put(
                "created_at",
                System.currentTimeMillis()
        );

        return getWritableDatabase()
                .insertWithOnConflict(
                        "categories",
                        null,
                        values,
                        SQLiteDatabase.CONFLICT_IGNORE
                );
    }

    public void renameCategory(
            long id,
            String name) {

        if (name == null)
            return;

        name = name.trim();

        if (name.isEmpty())
            return;

        ContentValues values =
                new ContentValues();

        values.put(
                "name",
                name
        );

        getWritableDatabase().update(
                "categories",
                values,
                "id=?",
                new String[]{
                        String.valueOf(id)
                }
        );
    }

    public void deleteCategory(long id) {

        getWritableDatabase().delete(
                "categories",
                "id=?",
                new String[]{
                        String.valueOf(id)
                }
        );
    }

    public List<Category> getCategories() {

        List<Category> result =
                new ArrayList<>();

        Cursor cursor =
                getReadableDatabase()
                        .rawQuery(

                "SELECT " +
                "c.id," +
                "c.name," +
                "COUNT(bc.bookmark_id) " +

                "FROM categories c " +

                "LEFT JOIN bookmark_categories bc " +
                "ON c.id=bc.category_id " +

                "GROUP BY c.id,c.name " +

                "ORDER BY c.name COLLATE NOCASE",

                null
        );

        try {

            while (cursor.moveToNext()) {

                result.add(
                        new Category(
                                cursor.getLong(0),
                                cursor.getString(1),
                                cursor.getInt(2)
                        )
                );
            }

        } finally {

            cursor.close();
        }

        return result;
    }

    // ========================================================
    // Bookmarks
    // ========================================================

    public long addBookmark(
            String filePath,
            String displayName) {

        ContentValues values =
                new ContentValues();

        values.put(
                "file_path",
                filePath
        );

        values.put(
                "display_name",
                displayName
        );

        values.put(
                "created_at",
                System.currentTimeMillis()
        );

        long id =
                getWritableDatabase()
                        .insertWithOnConflict(

                                "bookmarks",
                                null,
                                values,

                                SQLiteDatabase
                                        .CONFLICT_IGNORE
                        );

        if (id == -1)
            id = getBookmarkId(filePath);

        return id;
    }

    public long getBookmarkId(
            String path) {

        Cursor cursor =
                getReadableDatabase()
                        .query(

                "bookmarks",

                new String[]{
                        "id"
                },

                "file_path=?",

                new String[]{
                        path
                },

                null,
                null,
                null
        );

        try {

            if (cursor.moveToFirst())
                return cursor.getLong(0);

        } finally {

            cursor.close();
        }

        return -1;
    }

    public boolean isBookmarked(
            String path) {

        return getBookmarkId(path) != -1;
    }

    public void removeBookmark(
            String path) {

        getWritableDatabase().delete(
                "bookmarks",
                "file_path=?",
                new String[]{
                        path
                }
        );
    }

    public void addToCategory(
            long bookmarkId,
            long categoryId) {

        ContentValues values =
                new ContentValues();

        values.put(
                "bookmark_id",
                bookmarkId
        );

        values.put(
                "category_id",
                categoryId
        );

        getWritableDatabase()
                .insertWithOnConflict(

                        "bookmark_categories",
                        null,
                        values,

                        SQLiteDatabase
                                .CONFLICT_IGNORE
                );
    }

    public List<Bookmark> getBookmarks(
            long categoryId) {

        List<Bookmark> result =
                new ArrayList<>();

        Cursor cursor =
                getReadableDatabase()
                        .rawQuery(

                "SELECT " +
                "b.id," +
                "b.file_path," +
                "b.display_name," +
                "b.created_at," +
                "b.last_opened_at " +

                "FROM bookmarks b " +

                "JOIN bookmark_categories bc " +
                "ON b.id=bc.bookmark_id " +

                "WHERE bc.category_id=? " +

                "ORDER BY " +
                "b.display_name COLLATE NOCASE",

                new String[]{
                        String.valueOf(
                                categoryId
                        )
                }
        );

        try {

            while (cursor.moveToNext()) {

                result.add(
                        new Bookmark(
                                cursor.getLong(0),
                                cursor.getString(1),
                                cursor.getString(2),
                                cursor.getLong(3),
                                cursor.getLong(4)
                        )
                );
            }

        } finally {

            cursor.close();
        }

        return result;
    }

    public void markOpened(String path) {

        ContentValues values =
                new ContentValues();

        values.put(
                "last_opened_at",
                System.currentTimeMillis()
        );

        getWritableDatabase().update(
                "bookmarks",
                values,
                "file_path=?",
                new String[]{
                        path
                }
        );
    }

    // ========================================================
    // Models
    // ========================================================

    public static class Category {

        public final long id;

        public final String name;

        public final int count;

        public Category(
                long id,
                String name,
                int count) {

            this.id = id;
            this.name = name;
            this.count = count;
        }

        @Override
        public String toString() {

            return name +
                    "   (" +
                    count +
                    ")";
        }
    }

    public static class Bookmark {

        public final long id;

        public final String path;

        public final String name;

        public final long createdAt;

        public final long lastOpenedAt;

        public Bookmark(
                long id,
                String path,
                String name,
                long createdAt,
                long lastOpenedAt) {

            this.id = id;
            this.path = path;
            this.name = name;
            this.createdAt = createdAt;
            this.lastOpenedAt =
                    lastOpenedAt;
        }

        @Override
        public String toString() {
            return name;
        }
    }
}
