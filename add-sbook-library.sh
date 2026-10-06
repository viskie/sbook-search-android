#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SBook Search Android
# Parent navigation + Library / Categories / Bookmarks
#
# Result:
#
#             SBOOK
#       ┌───────────────┐
#       │ Search        │ -> existing MainActivity
#       │ ★ Library     │ -> new LibraryActivity
#       └───────────────┘
#
# Library:
#   Categories -> Bookmarks -> existing DocumentActivity
#
# Existing MainActivity and IndexDatabase are NOT modified.
#
# Usage:
#   chmod +x add-sbook-library.sh
#   ./add-sbook-library.sh
#
#   ./add-sbook-library.sh --build
#   ./add-sbook-library.sh --restore
# ============================================================

ROOT="$(pwd)"
APP="$ROOT/app"
SRC="$APP/src/main"
JAVA_ROOT="$SRC/java"
RES="$SRC/res"
MANIFEST="$SRC/AndroidManifest.xml"

BACKUP="$ROOT/.sbook-library-backup"

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

ok() {
    echo "[OK] $*"
}

info() {
    echo "[..] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

# ------------------------------------------------------------
# Verify project
# ------------------------------------------------------------

[[ -f "$ROOT/gradlew" ]] ||
    die "Run this script from the sbook-search-android repository root."

[[ -f "$MANIFEST" ]] ||
    die "AndroidManifest.xml not found."

MAIN="$(
    find "$JAVA_ROOT" \
        -type f \
        -name MainActivity.java \
        | head -1
)"

DOC="$(
    find "$JAVA_ROOT" \
        -type f \
        -name DocumentActivity.java \
        | head -1
)"

[[ -n "$MAIN" ]] ||
    die "MainActivity.java not found."

[[ -n "$DOC" ]] ||
    die "DocumentActivity.java not found."

PACKAGE="$(
    grep -m1 '^package ' "$MAIN" |
    sed 's/^package[[:space:]]*//;s/;//'
)"

[[ -n "$PACKAGE" ]] ||
    die "Could not determine Java package."

PKG_DIR="$(dirname "$MAIN")"

ok "Package: $PACKAGE"
ok "MainActivity found"
ok "DocumentActivity found"

# ------------------------------------------------------------
# Detect DocumentActivity Intent extra
# ------------------------------------------------------------

PATH_EXTRA="$(
    grep -Eo 'getStringExtra[[:space:]]*\([[:space:]]*"[^"]+"' "$DOC" \
        | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        || true
)"

if [[ -z "$PATH_EXTRA" ]]; then
    PATH_EXTRA="path"

    warn "Could not automatically determine DocumentActivity path extra."
    warn "Using fallback: path"
else
    ok "Document path Intent extra: $PATH_EXTRA"
fi

# ------------------------------------------------------------
# Backup
# ------------------------------------------------------------

backup() {

    mkdir -p "$BACKUP"

    if [[ ! -f "$BACKUP/AndroidManifest.xml" ]]; then
        cp -a "$MANIFEST" \
              "$BACKUP/AndroidManifest.xml"

        ok "Manifest backed up."
    fi
}

restore() {

    [[ -f "$BACKUP/AndroidManifest.xml" ]] ||
        die "No backup found."

    cp -a \
        "$BACKUP/AndroidManifest.xml" \
        "$MANIFEST"

    rm -f \
        "$PKG_DIR/HomeActivity.java" \
        "$PKG_DIR/LibraryActivity.java" \
        "$PKG_DIR/BookmarkDatabase.java" \
        "$PKG_DIR/BookmarkDialogs.java"

    rm -f \
        "$RES/layout/activity_home.xml" \
        "$RES/layout/activity_library.xml"

    ok "Original manifest restored."
    ok "Generated Library files removed."

    exit 0
}

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

build() {

    command -v java >/dev/null ||
        die "Java not found."

    echo
    java -version 2>&1 | head -3
    echo

    chmod +x "$ROOT/gradlew"

    info "Building debug APK..."

    "$ROOT/gradlew" assembleDebug

    APK="$APP/build/outputs/apk/debug/app-debug.apk"

    echo

    if [[ -f "$APK" ]]; then

        echo "=========================================="
        echo "       BUILD SUCCESSFUL"
        echo "=========================================="
        echo
        echo "APK:"
        echo "$APK"
        echo

    else

        warn "Build finished but expected APK not found:"
        warn "$APK"
    fi
}

case "${1:-}" in

    --restore)
        restore
        ;;

    --build)
        build
        exit 0
        ;;

esac

backup

mkdir -p "$RES/layout"

# ============================================================
# BookmarkDatabase.java
# ============================================================

cat > "$PKG_DIR/BookmarkDatabase.java" <<EOF
package $PACKAGE;

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
EOF

ok "Created BookmarkDatabase.java"

# ============================================================
# BookmarkDialogs.java
# ============================================================

cat > "$PKG_DIR/BookmarkDialogs.java" <<EOF
package $PACKAGE;

import android.app.Activity;
import android.app.AlertDialog;
import android.widget.EditText;
import android.widget.Toast;

import java.io.File;
import java.util.List;

public final class BookmarkDialogs {

    private BookmarkDialogs() {
    }

    public static void bookmark(
            Activity activity,
            BookmarkDatabase db,
            File file) {

        if (file == null)
            return;

        long bookmarkId =
                db.addBookmark(
                        file.getAbsolutePath(),
                        file.getName()
                );

        if (bookmarkId == -1) {

            Toast.makeText(
                    activity,
                    "Unable to create bookmark",
                    Toast.LENGTH_SHORT
            ).show();

            return;
        }

        chooseCategory(
                activity,
                db,
                bookmarkId
        );
    }

    private static void chooseCategory(
            Activity activity,
            BookmarkDatabase db,
            long bookmarkId) {

        List<BookmarkDatabase.Category>
                categories =
                db.getCategories();

        String[] names =
                new String[
                        categories.size() + 1
                ];

        names[0] =
                "+ New category";

        for (
                int i = 0;
                i < categories.size();
                i++
        ) {

            names[i + 1] =
                    categories
                            .get(i)
                            .name;
        }

        new AlertDialog.Builder(activity)

                .setTitle(
                        "Add to Library"
                )

                .setItems(
                        names,

                        (dialog, which) -> {

                            if (which == 0) {

                                createCategory(
                                        activity,
                                        db,
                                        bookmarkId
                                );

                                return;
                            }

                            BookmarkDatabase.Category
                                    category =
                                    categories.get(
                                            which - 1
                                    );

                            db.addToCategory(
                                    bookmarkId,
                                    category.id
                            );

                            Toast.makeText(
                                    activity,
                                    "Added to " +
                                            category.name,
                                    Toast.LENGTH_SHORT
                            ).show();
                        }
                )

                .setNegativeButton(
                        "Cancel",
                        null
                )

                .show();
    }

    private static void createCategory(
            Activity activity,
            BookmarkDatabase db,
            long bookmarkId) {

        EditText input =
                new EditText(activity);

        input.setHint(
                "Category name"
        );

        new AlertDialog.Builder(activity)

                .setTitle(
                        "New category"
                )

                .setView(input)

                .setPositiveButton(
                        "Create",

                        (dialog, which) -> {

                            String name =
                                    input
                                            .getText()
                                            .toString()
                                            .trim();

                            if (name.isEmpty())
                                return;

                            long id =
                                    db.createCategory(
                                            name
                                    );

                            if (id != -1) {

                                db.addToCategory(
                                        bookmarkId,
                                        id
                                );

                                Toast.makeText(
                                        activity,
                                        "Added to " +
                                                name,
                                        Toast.LENGTH_SHORT
                                ).show();
                            }
                        }
                )

                .setNegativeButton(
                        "Cancel",
                        null
                )

                .show();
    }
}
EOF

ok "Created BookmarkDialogs.java"

# ============================================================
# HomeActivity.java
# ============================================================

cat > "$PKG_DIR/HomeActivity.java" <<EOF
package $PACKAGE;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;

public class HomeActivity
        extends Activity {

    @Override
    protected void onCreate(
            Bundle savedInstanceState) {

        super.onCreate(
                savedInstanceState
        );

        setContentView(
                R.layout.activity_home
        );

        Button search =
                findViewById(
                        R.id.openSearch
                );

        Button library =
                findViewById(
                        R.id.openLibrary
                );

        search.setOnClickListener(
                v -> startActivity(
                        new Intent(
                                this,
                                MainActivity.class
                        )
                )
        );

        library.setOnClickListener(
                v -> startActivity(
                        new Intent(
                                this,
                                LibraryActivity.class
                        )
                )
        );
    }
}
EOF

ok "Created HomeActivity.java"

# ============================================================
# LibraryActivity.java
# ============================================================

cat > "$PKG_DIR/LibraryActivity.java" <<EOF
package $PACKAGE;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.util.List;

public class LibraryActivity
        extends Activity {

    private BookmarkDatabase db;

    private ListView list;

    private TextView title;

    private Button newCategory;

    private boolean insideCategory =
            false;

    @Override
    protected void onCreate(
            Bundle savedInstanceState) {

        super.onCreate(
                savedInstanceState
        );

        setContentView(
                R.layout.activity_library
        );

        db =
                new BookmarkDatabase(
                        this
                );

        list =
                findViewById(
                        R.id.libraryList
                );

        title =
                findViewById(
                        R.id.libraryTitle
                );

        newCategory =
                findViewById(
                        R.id.newCategory
                );

        newCategory
                .setOnClickListener(
                        v -> createCategory()
                );

        showCategories();
    }

    @Override
    protected void onResume() {

        super.onResume();

        if (!insideCategory)
            showCategories();
    }

    private void showCategories() {

        insideCategory = false;

        title.setText(
                "★ Library"
        );

        newCategory.setEnabled(true);

        List<BookmarkDatabase.Category>
                categories =
                db.getCategories();

        ArrayAdapter<
                BookmarkDatabase.Category>
                adapter =
                new ArrayAdapter<>(

                        this,

                        android.R.layout
                                .simple_list_item_1,

                        categories
                );

        list.setAdapter(adapter);

        list.setOnItemClickListener(
                (parent,
                 view,
                 position,
                 id) ->

                        showBookmarks(
                                categories.get(
                                        position
                                )
                        )
        );

        list.setOnItemLongClickListener(
                (parent,
                 view,
                 position,
                 id) -> {

                    categoryMenu(
                            categories.get(
                                    position
                            )
                    );

                    return true;
                }
        );
    }

    private void showBookmarks(
            BookmarkDatabase.Category category) {

        insideCategory = true;

        title.setText(
                "← " + category.name
        );

        title.setOnClickListener(
                v -> showCategories()
        );

        newCategory.setEnabled(false);

        List<BookmarkDatabase.Bookmark>
                bookmarks =
                db.getBookmarks(
                        category.id
                );

        ArrayAdapter<
                BookmarkDatabase.Bookmark>
                adapter =
                new ArrayAdapter<>(

                        this,

                        android.R.layout
                                .simple_list_item_1,

                        bookmarks
                );

        list.setAdapter(adapter);

        list.setOnItemClickListener(
                (parent,
                 view,
                 position,
                 id) ->

                        openBookmark(
                                bookmarks.get(
                                        position
                                )
                        )
        );
    }

    private void openBookmark(
            BookmarkDatabase.Bookmark bookmark) {

        File file =
                new File(
                        bookmark.path
                );

        if (!file.exists()) {

            Toast.makeText(
                    this,

                    "File no longer exists:\\n" +
                            bookmark.path,

                    Toast.LENGTH_LONG
            ).show();

            return;
        }

        db.markOpened(
                bookmark.path
        );

        Intent intent =
                new Intent(
                        this,
                        DocumentActivity.class
                );

        intent.putExtra(
                "$PATH_EXTRA",
                bookmark.path
        );

        startActivity(intent);
    }

    private void createCategory() {

        EditText input =
                new EditText(this);

        input.setHint(
                "Category name"
        );

        new AlertDialog.Builder(this)

                .setTitle(
                        "New category"
                )

                .setView(input)

                .setPositiveButton(
                        "Create",

                        (dialog, which) -> {

                            String name =
                                    input
                                            .getText()
                                            .toString()
                                            .trim();

                            if (!name.isEmpty()) {

                                db.createCategory(
                                        name
                                );

                                showCategories();
                            }
                        }
                )

                .setNegativeButton(
                        "Cancel",
                        null
                )

                .show();
    }

    private void categoryMenu(
            BookmarkDatabase.Category category) {

        String[] choices = {
                "Rename",
                "Delete"
        };

        new AlertDialog.Builder(this)

                .setTitle(
                        category.name
                )

                .setItems(
                        choices,

                        (dialog, which) -> {

                            if (which == 0)
                                renameCategory(
                                        category
                                );
                            else
                                deleteCategory(
                                        category
                                );
                        }
                )

                .show();
    }

    private void renameCategory(
            BookmarkDatabase.Category category) {

        EditText input =
                new EditText(this);

        input.setText(
                category.name
        );

        new AlertDialog.Builder(this)

                .setTitle(
                        "Rename category"
                )

                .setView(input)

                .setPositiveButton(
                        "Rename",

                        (dialog, which) -> {

                            String name =
                                    input
                                            .getText()
                                            .toString()
                                            .trim();

                            if (!name.isEmpty()) {

                                db.renameCategory(
                                        category.id,
                                        name
                                );

                                showCategories();
                            }
                        }
                )

                .setNegativeButton(
                        "Cancel",
                        null
                )

                .show();
    }

    private void deleteCategory(
            BookmarkDatabase.Category category) {

        new AlertDialog.Builder(this)

                .setTitle(
                        "Delete category?"
                )

                .setMessage(
                        category.name +
                        "\\n\\nThe original files will not be deleted."
                )

                .setPositiveButton(
                        "Delete",

                        (dialog, which) -> {

                            db.deleteCategory(
                                    category.id
                            );

                            showCategories();
                        }
                )

                .setNegativeButton(
                        "Cancel",
                        null
                )

                .show();
    }

    @Override
    public void onBackPressed() {

        if (insideCategory) {

            showCategories();

        } else {

            super.onBackPressed();
        }
    }
}
EOF

ok "Created LibraryActivity.java"

# ============================================================
# activity_home.xml
# ============================================================

cat > "$RES/layout/activity_home.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>

<LinearLayout
    xmlns:android="http://schemas.android.com/apk/res/android"

    android:layout_width="match_parent"
    android:layout_height="match_parent"

    android:orientation="vertical"

    android:gravity="center"

    android:padding="24dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"

        android:text="SBook"

        android:textSize="32sp"

        android:textStyle="bold"

        android:layout_marginBottom="8dp" />

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"

        android:text="Search and Sanskrit Library"

        android:textSize="17sp"

        android:layout_marginBottom="32dp" />

    <Button
        android:id="@+id/openSearch"

        android:layout_width="match_parent"
        android:layout_height="wrap_content"

        android:text="🔎  SEARCH"

        android:textSize="18sp"

        android:layout_marginBottom="16dp" />

    <Button
        android:id="@+id/openLibrary"

        android:layout_width="match_parent"
        android:layout_height="wrap_content"

        android:text="★  LIBRARY"

        android:textSize="18sp" />

</LinearLayout>
EOF

ok "Created activity_home.xml"

# ============================================================
# activity_library.xml
# ============================================================

cat > "$RES/layout/activity_library.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>

<LinearLayout
    xmlns:android="http://schemas.android.com/apk/res/android"

    android:layout_width="match_parent"
    android:layout_height="match_parent"

    android:orientation="vertical"

    android:padding="12dp">

    <TextView
        android:id="@+id/libraryTitle"

        android:layout_width="match_parent"
        android:layout_height="wrap_content"

        android:text="★ Library"

        android:textSize="24sp"

        android:textStyle="bold"

        android:padding="12dp" />

    <Button
        android:id="@+id/newCategory"

        android:layout_width="match_parent"
        android:layout_height="wrap_content"

        android:text="+ New Category" />

    <ListView
        android:id="@+id/libraryList"

        android:layout_width="match_parent"
        android:layout_height="0dp"

        android:layout_weight="1"

        android:dividerHeight="1dp" />

</LinearLayout>
EOF

ok "Created activity_library.xml"

# ============================================================
# Patch AndroidManifest.xml
# ============================================================

info "Updating AndroidManifest.xml..."

python3 - "$MANIFEST" "$PACKAGE" <<'PY'
import sys
import xml.etree.ElementTree as ET

manifest_file = sys.argv[1]
package = sys.argv[2]

ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)

tree = ET.parse(manifest_file)
root = tree.getroot()

app = root.find("application")

if app is None:
    raise SystemExit(
        "No <application> element found."
    )

name_attr = "{" + ANDROID + "}name"
exported_attr = "{" + ANDROID + "}exported"

def normalized(name):
    if name.startswith("."):
        return package + name
    if "." not in name:
        return package + "." + name
    return name

main_activity = None

for activity in app.findall("activity"):

    name = activity.get(name_attr)

    if not name:
        continue

    if normalized(name) == package + ".MainActivity":
        main_activity = activity
        break

if main_activity is None:
    raise SystemExit(
        "MainActivity not found in manifest."
    )

# Remove launcher intent-filter from MainActivity.
for filt in list(
        main_activity.findall("intent-filter")
):

    is_main = False
    is_launcher = False

    for action in filt.findall("action"):

        if action.get(name_attr) == \
           "android.intent.action.MAIN":

            is_main = True

    for category in filt.findall("category"):

        if category.get(name_attr) == \
           "android.intent.category.LAUNCHER":

            is_launcher = True

    if is_main and is_launcher:
        main_activity.remove(filt)

# MainActivity no longer needs to be externally launched.
main_activity.set(
    exported_attr,
    "false"
)

# Avoid duplicate HomeActivity.
for activity in list(app.findall("activity")):

    name = activity.get(name_attr)

    if name and normalized(name) == \
       package + ".HomeActivity":

        app.remove(activity)

# Avoid duplicate LibraryActivity.
for activity in list(app.findall("activity")):

    name = activity.get(name_attr)

    if name and normalized(name) == \
       package + ".LibraryActivity":

        app.remove(activity)

# LibraryActivity
library = ET.SubElement(
    app,
    "activity"
)

library.set(
    name_attr,
    ".LibraryActivity"
)

library.set(
    exported_attr,
    "false"
)

# HomeActivity / launcher
home = ET.SubElement(
    app,
    "activity"
)

home.set(
    name_attr,
    ".HomeActivity"
)

home.set(
    exported_attr,
    "true"
)

intent = ET.SubElement(
    home,
    "intent-filter"
)

action = ET.SubElement(
    intent,
    "action"
)

action.set(
    name_attr,
    "android.intent.action.MAIN"
)

category = ET.SubElement(
    intent,
    "category"
)

category.set(
    name_attr,
    "android.intent.category.LAUNCHER"
)

tree.write(
    manifest_file,
    encoding="utf-8",
    xml_declaration=True
)
PY

ok "HomeActivity is now launcher."
ok "Existing MainActivity preserved."
ok "LibraryActivity registered."

# ============================================================
# Final
# ============================================================

echo
echo "=========================================="
echo " SBook Library installed"
echo "=========================================="
echo
echo "Navigation:"
echo
echo "  SBook"
echo "    |"
echo "    +-- Search  -> existing MainActivity"
echo "    |"
echo "    +-- Library -> LibraryActivity"
echo "                    |"
echo "                    +-- Categories"
echo "                          |"
echo "                          +-- Bookmarks"
echo "                                |"
echo "                                +-- DocumentActivity"
echo
echo "Search/index source code was NOT modified."
echo
echo "Detected DocumentActivity extra:"
echo "  $PATH_EXTRA"
echo

build