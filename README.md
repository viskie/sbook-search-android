# SBook Search for Android

An offline-first Android search app for the split dataset published at
[`viskie/sbook_data_hashed`](https://github.com/viskie/sbook_data_hashed).
The app does not bundle the dataset. On request it downloads the repository's
four archive segments (313.5 MiB total), logically joins them as one stream,
extracts the BZip2/TAR archive into app-private storage, and builds on-device
SQLite FTS4 indexes.

## What it does

- Resumable HTTPS downloads of all four `*.tar.bz2aa` through `*.tar.bz2ad`
  parts directly from the repository's raw GitHub URLs.
- Streaming join and extraction: no second 313.5 MiB joined archive is created.
- Zip-slip/path traversal protection while writing extracted files.
- Separate indexed **File names** and **Document text** searches, with prefix
  matching and a 100-result interactive limit.
- Unicode `unicode61` tokenization for Devanagari and other scripts.
- Built-in searchable-script keyboards for Devanagari, Bengali, Gujarati,
  Gurmukhi, Odia, Tamil, Telugu, Kannada, and Malayalam. The custom keyboard is
  hidden by default; **ABC · System** uses the normal Android keyboard.
- Selectable offline document viewer with search-term highlighting.
- Foreground download/index service with resumable downloads, phase labels,
  byte/file counts, a progress bar, and notification progress.
- Bright orange/black interface with no account, ads, or telemetry.

Text formats indexed and previewed include Org, TXT, Markdown, HTML, XML, JSON,
CSV/TSV, TeX, subtitle, and YAML files. Individual text files up to 32 MiB are
indexed; previews are capped at 16 MiB to avoid device memory pressure. Other
file types are still extracted and included in filename search.

## Storage and first run

The initial download is 328,699,105 bytes. The app also needs space for the
extracted library and the full-text index. Exact total storage depends on the
dataset version; keeping several gigabytes free is recommended. Successfully
downloaded parts are deleted after extraction/indexing, while interrupted parts
are retained so a retry resumes rather than starts over.

The data remains in Android's app-private storage and is removed if the app is
uninstalled or its storage is cleared. The upstream repository controls the
dataset and its licensing; this project does not redistribute those files.

## Build

Requirements: JDK 17+, Android SDK 37, and network access to Maven Central for
Apache Commons Compress.

Create `local.properties` (ignored by Git):

```properties
sdk.dir=/absolute/path/to/android-sdk
```

Then build:

```bash
./gradlew assembleRelease
```

The installable output is `app/build/outputs/apk/release/app-release.apk`.
`release/SBookSearch-v1.0.0.apk` is committed as a directly downloadable build.

The committed release artifact is signed with Android's local debug certificate
so it can be installed immediately for evaluation. Before publishing through an
app store, replace `signingConfig = signingConfigs.getByName("debug")` with a
protected production signing configuration and increment the version.

## Implementation map

- `LibraryService.java` — resumable download, streaming archive reconstruction,
  secure extraction, indexing, and foreground progress.
- `IndexDatabase.java` — filename and multilingual content FTS indexes.
- `MainActivity.java` — setup progress, search-mode switcher, and result list.
- `ScriptKeyboardView.java` — optional nine-script custom keyboard.
- `DocumentActivity.java` — offline text viewer and match highlighting.

