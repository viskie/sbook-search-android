#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-ManyStopNav}"
PKG="org.manystop.nav"
BASE="$(pwd)/$PROJECT"

echo "Creating $BASE"

mkdir -p \
 "$BASE/app/src/main/java/org/manystop/nav" \
 "$BASE/app/src/main/res/layout" \
 "$BASE/app/src/main/res/values"

# ============================================================
# settings.gradle
# ============================================================

cat > "$BASE/settings.gradle" <<'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ManyStopNav"
include(":app")
EOF

# ============================================================
# root build.gradle
# ============================================================

cat > "$BASE/build.gradle" <<'EOF'
plugins {
    id 'com.android.application' version '8.7.3' apply false
}
EOF

# ============================================================
# gradle.properties
# ============================================================

cat > "$BASE/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
EOF

# ============================================================
# app/build.gradle
# ============================================================

cat > "$BASE/app/build.gradle" <<'EOF'
plugins {
    id 'com.android.application'
}

android {
    namespace 'org.manystop.nav'
    compileSdk 35

    defaultConfig {
        applicationId "org.manystop.nav"
        minSdk 26
        targetSdk 35
        versionCode 1
        versionName "0.1"
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'org.osmdroid:osmdroid-android:6.1.20'
}
EOF

# ============================================================
# Manifest
# ============================================================

cat > "$BASE/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

    <application
        android:allowBackup="true"
        android:label="Many Stop Nav"
        android:theme="@style/AppTheme"
        android:usesCleartextTraffic="true">

        <activity
            android:name=".MainActivity"
            android:screenOrientation="portrait"
            android:exported="true">

            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

        </activity>

    </application>
</manifest>
EOF

# ============================================================
# styles
# ============================================================

cat > "$BASE/app/src/main/res/values/styles.xml" <<'EOF'
<resources>
    <style name="AppTheme"
        parent="Theme.AppCompat.DayNight.NoActionBar">
        <item name="android:fontFamily">sans</item>
    </style>
</resources>
EOF

# ============================================================
# Layout
# ============================================================

cat > "$BASE/app/src/main/res/layout/activity_main.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>

<LinearLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <TextView
        android:id="@+id/status"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:padding="10dp"
        android:text="Many Stop Navigation"
        android:textSize="18sp"
        android:textStyle="bold"/>

    <org.osmdroid.views.MapView
        android:id="@+id/map"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"/>

    <LinearLayout
        android:orientation="horizontal"
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <Button
            android:id="@+id/previous"
            android:layout_width="0dp"
            android:layout_weight="1"
            android:layout_height="wrap_content"
            android:text="Previous"/>

        <Button
            android:id="@+id/complete"
            android:layout_width="0dp"
            android:layout_weight="1"
            android:layout_height="wrap_content"
            android:text="Complete"/>

        <Button
            android:id="@+id/next"
            android:layout_width="0dp"
            android:layout_weight="1"
            android:layout_height="wrap_content"
            android:text="Next"/>

    </LinearLayout>

</LinearLayout>
EOF

# ============================================================
# Stop model
# ============================================================

cat > "$BASE/app/src/main/java/org/manystop/nav/NavStop.java" <<'EOF'
package org.manystop.nav;

public class NavStop {

    public enum State {
        PENDING,
        ACTIVE,
        COMPLETED,
        SKIPPED
    }

    public long id;

    public String name;

    public double latitude;
    public double longitude;

    public State state = State.PENDING;

    public NavStop(
            long id,
            String name,
            double latitude,
            double longitude) {

        this.id = id;
        this.name = name;
        this.latitude = latitude;
        this.longitude = longitude;
    }
}
EOF

# ============================================================
# Trip model
# ============================================================

cat > "$BASE/app/src/main/java/org/manystop/nav/Trip.java" <<'EOF'
package org.manystop.nav;

import java.util.ArrayList;
import java.util.List;

public class Trip {

    private final List<NavStop> stops =
            new ArrayList<>();

    private int active = 0;

    public void add(NavStop stop) {
        stops.add(stop);

        if (stops.size() == 1) {
            stop.state = NavStop.State.ACTIVE;
        }
    }

    public List<NavStop> stops() {
        return stops;
    }

    public int size() {
        return stops.size();
    }

    public int activeIndex() {
        return active;
    }

    public NavStop active() {

        if (stops.isEmpty())
            return null;

        return stops.get(active);
    }

    public void next() {

        if (stops.isEmpty())
            return;

        stops.get(active).state =
                NavStop.State.PENDING;

        if (active < stops.size() - 1)
            active++;

        stops.get(active).state =
                NavStop.State.ACTIVE;
    }

    public void previous() {

        if (stops.isEmpty())
            return;

        stops.get(active).state =
                NavStop.State.PENDING;

        if (active > 0)
            active--;

        stops.get(active).state =
                NavStop.State.ACTIVE;
    }

    public void completeActive() {

        if (stops.isEmpty())
            return;

        stops.get(active).state =
                NavStop.State.COMPLETED;

        if (active < stops.size() - 1) {

            active++;

            stops.get(active).state =
                    NavStop.State.ACTIVE;
        }
    }
}
EOF

# ============================================================
# Main Activity
# ============================================================

cat > "$BASE/app/src/main/java/org/manystop/nav/MainActivity.java" <<'EOF'
package org.manystop.nav;

import android.Manifest;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.widget.Button;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;

import org.osmdroid.config.Configuration;
import org.osmdroid.events.MapEventsReceiver;
import org.osmdroid.util.GeoPoint;
import org.osmdroid.views.MapView;
import org.osmdroid.views.overlay.MapEventsOverlay;
import org.osmdroid.views.overlay.Marker;

public class MainActivity extends AppCompatActivity {

    private MapView map;

    private TextView status;

    private final Trip trip =
            new Trip();

    private long nextId = 1;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        Configuration.getInstance().load(
                this,
                PreferenceManager
                        .getDefaultSharedPreferences(this)
        );

        setContentView(
                R.layout.activity_main
        );

        map =
                findViewById(
                        R.id.map
                );

        status =
                findViewById(
                        R.id.status
                );

        Button previous =
                findViewById(
                        R.id.previous
                );

        Button complete =
                findViewById(
                        R.id.complete
                );

        Button next =
                findViewById(
                        R.id.next
                );

        map.setMultiTouchControls(true);

        /*
         * Initial India view.
         *
         * GPS centering comes next.
         */
        map.getController()
                .setZoom(5.5);

        map.getController()
                .setCenter(
                        new GeoPoint(
                                22.5,
                                79.0
                        )
                );

        ActivityCompat.requestPermissions(
                this,
                new String[]{
                        Manifest.permission
                                .ACCESS_FINE_LOCATION
                },
                100
        );

        /*
         * LONG PRESS = ADD STOP
         */
        MapEventsOverlay events =
                new MapEventsOverlay(
                        new MapEventsReceiver() {

                            @Override
                            public boolean singleTapConfirmedHelper(
                                    GeoPoint p) {

                                return false;
                            }

                            @Override
                            public boolean longPressHelper(
                                    GeoPoint p) {

                                addStop(p);

                                return true;
                            }
                        }
                );

        map.getOverlays()
                .add(events);

        previous.setOnClickListener(
                v -> {
                    trip.previous();
                    refresh();
                }
        );

        next.setOnClickListener(
                v -> {
                    trip.next();
                    refresh();
                }
        );

        complete.setOnClickListener(
                v -> {
                    trip.completeActive();
                    refresh();
                }
        );

        refresh();
    }

    private void addStop(
            GeoPoint point) {

        int number =
                trip.size() + 1;

        NavStop stop =
                new NavStop(
                        nextId++,
                        "Stop " + number,
                        point.getLatitude(),
                        point.getLongitude()
                );

        trip.add(stop);

        Marker marker =
                new Marker(map);

        marker.setPosition(point);

        marker.setTitle(
                number + ". " +
                        stop.name
        );

        marker.setSubDescription(
                point.getLatitude() +
                        ", " +
                        point.getLongitude()
        );

        marker.setAnchor(
                Marker.ANCHOR_CENTER,
                Marker.ANCHOR_BOTTOM
        );

        map.getOverlays()
                .add(marker);

        refresh();
    }

    private void refresh() {

        NavStop active =
                trip.active();

        if (active == null) {

            status.setText(
                    "Long-press map to add first stop"
            );

        } else {

            status.setText(
                    "Stop " +
                            (trip.activeIndex() + 1) +
                            " / " +
                            trip.size() +
                            " — " +
                            active.name
            );
        }

        map.invalidate();
    }

    @Override
    protected void onResume() {
        super.onResume();
        map.onResume();
    }

    @Override
    protected void onPause() {
        map.onPause();
        super.onPause();
    }
}
EOF

# ============================================================
# README
# ============================================================

cat > "$BASE/README.md" <<'EOF'
# Many Stop Nav

Android navigation experiment designed around trips containing
100+ ordered stops.

Current bootstrap:

- OpenStreetMap map
- long press to add stops
- unlimited in-memory stops
- numbered stop markers
- previous/next active stop
- complete-stop workflow
- location permission

Next architecture:

GPS
 |
 v
NavigationController
 |
 +-- master trip (100-1000+ stops)
 |
 +-- moving routing window
 |
 v
RoutingEngine interface
 |
 +-- Valhalla
 +-- GraphHopper
 +-- OSRM
 |
 v
route geometry + maneuvers
 |
 v
MapLibre/osmdroid display
 |
 v
voice navigation

Do not send the entire master itinerary to a commercial
waypoint-limited API.

Maintain the full itinerary locally and route a moving window.
EOF

echo
echo "======================================"
echo " ManyStopNav bootstrap complete"
echo "======================================"
echo
echo "Project:"
echo "  $BASE"
echo
echo "Next:"
echo "  cd \"$PROJECT\""
echo
echo "If gradlew already exists:"
echo "  ./gradlew assembleDebug"
echo
echo "Otherwise open the project in Android Studio/AndroidIDE"
echo "or generate/use your Gradle wrapper."