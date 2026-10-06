package org.sbook.search;

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
