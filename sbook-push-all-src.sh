#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

PROJECT="$HOME/sbook-search-android"
cd "$PROJECT" || exit 1

echo "========================================"
echo " SBOOK — ADD ALL SOURCE + PUSH"
echo "========================================"

# ----------------------------------------------------------
# Ensure generated/cache/local files are ignored
# ----------------------------------------------------------

touch .gitignore

cat >> .gitignore <<'EOF'

# ===== local/generated files =====
.gradle/
**/.gradle/

build/
**/build/

.cxx/
**/.cxx/

.externalNativeBuild/
**/.externalNativeBuild/

.idea/
*.iml

local.properties

*.apk
*.aab
*.ap_
*.dex
*.class

captures/

.DS_Store
Thumbs.db

*.log
*.tmp
*.temp
*.cache

__pycache__/
*.pyc

# Android generated output
generated/
**/generated/

intermediates/
**/intermediates/

outputs/
**/outputs/

tmp/
**/tmp/
EOF

# Remove duplicate .gitignore lines while preserving order.
python - <<'PY'
from pathlib import Path

p = Path(".gitignore")
seen = set()
out = []

for line in p.read_text().splitlines():
    key = line.rstrip()

    if key and not key.startswith("#"):
        if key in seen:
            continue
        seen.add(key)

    out.append(line)

p.write_text("\n".join(out) + "\n")
PY

# ----------------------------------------------------------
# If generated files were tracked previously, untrack them.
# Does NOT delete local copies.
# ----------------------------------------------------------

git rm -r --cached --ignore-unmatch \
    .gradle \
    app/build \
    build \
    .idea \
    local.properties \
    2>/dev/null || true

# ----------------------------------------------------------
# ADD EVERYTHING ELSE IN REPOSITORY
# ----------------------------------------------------------

echo
echo "=== ADD ALL REPOSITORY SOURCE ==="

git add -A

# Safety: explicitly unstage anything that should never be committed.
git reset -- \
    local.properties \
    .gradle \
    app/build \
    build \
    .idea \
    2>/dev/null || true

# Catch nested build/cache directories.
git diff --cached --name-only |
while IFS= read -r f; do

    case "$f" in
        */build/*|\
        build/*|\
        */.gradle/*|\
        .gradle/*|\
        */.idea/*|\
        .idea/*|\
        */generated/*|\
        */intermediates/*|\
        */outputs/*|\
        */tmp/*|\
        *.apk|\
        *.aab|\
        *.dex|\
        *.class|\
        *.log|\
        local.properties)

            git reset -- "$f" >/dev/null 2>&1 || true
            ;;
    esac

done

echo
echo "========================================"
echo " FILES TO COMMIT"
echo "========================================"

git status --short

echo
echo "=== STAGED FILE COUNT ==="

git diff --cached --name-only | wc -l

echo
echo "=== STAGED FILES ==="

git diff --cached --name-only

echo
echo "=== CHECK FOR CACHE/BUILD FILES ==="

BAD="$(
git diff --cached --name-only |
grep -E '(^|/)(build|\.gradle|\.idea|generated|intermediates|outputs|tmp)/|local\.properties$|\.(apk|aab|dex|class|log)$' \
|| true
)"

if [ -n "$BAD" ]; then

    echo "ERROR: generated/cache files are still staged:"
    echo "$BAD"
    exit 20

fi

echo "PASS — no cache/build output staged."

# ----------------------------------------------------------
# COMMIT
# ----------------------------------------------------------

echo
echo "========================================"
echo " COMMIT"
echo "========================================"

if git diff --cached --quiet; then

    echo "Nothing new to commit."

else

    git commit -m \
      "Update SBook source and filename substring search"

    if [ $? -ne 0 ]; then
        echo "ERROR: commit failed."
        exit 30
    fi

fi

# ----------------------------------------------------------
# PUSH
# ----------------------------------------------------------

echo
echo "========================================"
echo " PUSH"
echo "========================================"

BRANCH="$(git branch --show-current)"

if [ -z "$BRANCH" ]; then
    echo "ERROR: detached HEAD."
    exit 40
fi

echo "Remote:"
git remote -v

echo
echo "Branch: $BRANCH"
echo "Commit: $(git rev-parse --short HEAD)"

git push origin "$BRANCH"
PUSH_RC=$?

echo
echo "========================================"
echo " RESULT"
echo "========================================"

echo "Branch: $BRANCH"
echo "Commit: $(git rev-parse --short HEAD)"

if [ "$PUSH_RC" -eq 0 ]; then
    echo "GitHub push: SUCCESS"
else
    echo "GitHub push: FAILED ($PUSH_RC)"
fi

exit "$PUSH_RC"
