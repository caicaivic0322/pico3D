#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="${1:-$ROOT_DIR/mac-app/Resources/Backend}"
STAMP_EPOCH="$(git -C "$ROOT_DIR" log -1 --format=%ct -- . 2>/dev/null || true)"

if [ -z "$STAMP_EPOCH" ]; then
    STAMP_EPOCH="$(date +%s)"
fi

STAMP_TIME="$(date -r "$STAMP_EPOCH" +"%Y%m%d%H%M.%S")"

rm -rf "$BACKEND_DIR"
mkdir -p "$BACKEND_DIR"

copy_file() {
    local src="$1"
    local dst="$BACKEND_DIR/$src"
    mkdir -p "$(dirname "$dst")"
    cp -p "$ROOT_DIR/$src" "$dst"
}

copy_python_tree() {
    local src_dir="$1"
    local src_root="$ROOT_DIR/$src_dir"

    while IFS= read -r src_path; do
        src_path="${src_path#"$ROOT_DIR"/}"
        copy_file "$src_path"
    done < <(find "$src_root" -type f -name '*.py' | sort)
}

copy_file "setup.sh"
copy_file "generate.py"
copy_file "pyproject.toml"
copy_file "LICENSE"
copy_file "README.md"
copy_python_tree "backends"
copy_python_tree "patches"
copy_file "assets/shoe_3q.png"
copy_file "assets/shoe_front.png"
copy_file "assets/shoe_input.png"
copy_file "assets/shoe_side.png"

find "$BACKEND_DIR" -type f -exec chmod 0644 {} +
find "$BACKEND_DIR" -exec touch -h -t "$STAMP_TIME" {} +

find "$BACKEND_DIR" -type l -print -quit | grep -q . && {
    echo "error: symlink copied into backend bundle" >&2
    exit 1
}

find "$BACKEND_DIR" -type f \
    ! \( \
        -path "$BACKEND_DIR/setup.sh" -o \
        -path "$BACKEND_DIR/generate.py" -o \
        -path "$BACKEND_DIR/pyproject.toml" -o \
        -path "$BACKEND_DIR/LICENSE" -o \
        -path "$BACKEND_DIR/README.md" -o \
        -path "$BACKEND_DIR/backends/*.py" -o \
        -path "$BACKEND_DIR/patches/*.py" -o \
        -path "$BACKEND_DIR/assets/shoe_3q.png" -o \
        -path "$BACKEND_DIR/assets/shoe_front.png" -o \
        -path "$BACKEND_DIR/assets/shoe_input.png" -o \
        -path "$BACKEND_DIR/assets/shoe_side.png" \
    \) \
    -print -quit | grep -q . && {
    echo "error: non-allowlisted file copied into backend bundle" >&2
    exit 1
}

test -f "$BACKEND_DIR/setup.sh"
test -f "$BACKEND_DIR/generate.py"
test -f "$BACKEND_DIR/backends/conv_none.py"
test -f "$BACKEND_DIR/patches/mps_compat.py"

echo "Backend resources staged at $BACKEND_DIR"
