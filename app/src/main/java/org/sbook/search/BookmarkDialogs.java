package org.sbook.search;

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
