#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PROJECT="$HOME/sbook-search-android"

echo "=== INSTALL PROOT ==="
pkg update -y
pkg install -y proot-distro

if ! proot-distro login debian -- true >/dev/null 2>&1; then
    proot-distro install debian
fi

echo "=== BUILD SBOOK API 37 IN DEBIAN ==="

proot-distro login debian --shared-tmp -- bash -s <<'DEBIAN'
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    openjdk-21-jdk \
    wget \
    unzip \
    git \
    ca-certificates

PROJECT="/data/data/com.termux/files/home/sbook-search-android"
SDK="/root/android-sdk"

export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-arm64"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"

mkdir -p "$SDK/cmdline-tools"

echo "=== SDK COMMAND TOOLS ==="

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then

    cd /root

    rm -rf commandlinetools.zip cmdline

    wget -q -O commandlinetools.zip \
      "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

    mkdir cmdline
    unzip -q commandlinetools.zip -d cmdline

    mkdir -p "$SDK/cmdline-tools/latest"

    cp -a \
      cmdline/cmdline-tools/. \
      "$SDK/cmdline-tools/latest/"

    rm -rf commandlinetools.zip cmdline
fi

export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

echo "=== INSTALL API 37 ==="

yes | sdkmanager --licenses >/dev/null 2>&1 || true

# Prefer exact 37.0 if project requests it.
if sdkmanager --list | grep -q 'platforms;android-37.0'; then
    sdkmanager \
      "platforms;android-37.0" \
      "platform-tools"
else
    sdkmanager \
      "platforms;android-37" \
      "platform-tools"
fi

echo "=== PROJECT ==="

cd "$PROJECT"

# IMPORTANT:
# Remove the Termux aapt2 override.
# Inside Debian Gradle must use its normal modern aapt2.

if [ -f gradle.properties ]; then
    sed -i \
      '/^android\.aapt2FromMavenOverride=/d' \
      gradle.properties
fi

mkdir -p /root/.gradle

if [ -f /root/.gradle/gradle.properties ]; then
    sed -i \
      '/^android\.aapt2FromMavenOverride=/d' \
      /root/.gradle/gradle.properties
fi

cat > local.properties <<EOF
sdk.dir=$SDK
EOF

echo
echo "=== SDK SETTING ==="

grep -RniE \
  'compileSdk|targetSdk|buildToolsVersion' \
  app/build.gradle* \
  gradle/libs.versions.toml \
  2>/dev/null || true

echo
echo "=== ANDROID JAR ==="

find "$SDK/platforms" \
  -maxdepth 2 \
  -name android.jar \
  -exec ls -lh {} \;

echo
echo "=== JAVA ==="

java -version

echo
echo "=== BUILD ==="

chmod +x gradlew

./gradlew --stop 2>/dev/null || true

rm -rf app/build

./gradlew \
  --no-daemon \
  --console=plain \
  assembleDebug

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"

test -f "$APK" || {
    echo "ERROR: APK not generated"
    exit 1
}

echo
echo "=============================="
echo " SBOOK APK BUILT"
echo "=============================="

ls -lh "$APK"
sha256sum "$APK"

DEBIAN

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"

echo
echo "=== COPY TO DOWNLOADS ==="

if [ ! -d "$HOME/storage/downloads" ]; then
    termux-setup-storage
    echo "Grant storage permission, then press ENTER."
    read -r
fi

cp -f "$APK" \
  "$HOME/storage/downloads/SBook-debug.apk"

echo
echo "======================================"
echo " SUCCESS"
echo "======================================"
echo
echo "$HOME/storage/downloads/SBook-debug.apk"
echo
echo "compileSdk 37 retained."
echo "Termux aapt2 2.19 was NOT used."
echo "Existing SBook dataset was NOT touched."
