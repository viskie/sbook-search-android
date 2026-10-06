package org.sbook.search;

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

                    "File no longer exists:\n" +
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
                "path",
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
                        "\n\nThe original files will not be deleted."
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
