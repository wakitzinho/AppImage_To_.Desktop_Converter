#!/usr/bin/env bash
# appimage-desktop.sh
# Creates a .desktop entry for an AppImage, extracting an icon if possible.
# Usage: ./appimage-desktop.sh /path/to/app.AppImage

set -euo pipefail

# ─── Helpers ────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  → $*"; }

# ─── Argument check ─────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && die "Usage: $0 /path/to/App.AppImage"

APPIMAGE_PATH="$(realpath "$1")"
[[ -f "$APPIMAGE_PATH" ]] || die "File not found: $APPIMAGE_PATH"
[[ "$APPIMAGE_PATH" == *.AppImage || "$APPIMAGE_PATH" == *.appimage ]] \
    || echo "WARNING: File doesn't have .AppImage extension, continuing anyway."

# ─── Derived names ───────────────────────────────────────────────────────────

# e.g. "MyApp-1.0-x86_64.AppImage" → "MyApp"
BASENAME="$(basename "$APPIMAGE_PATH")"
# Strip everything from the first digit-or-dash-after-letter onward, then trim dashes/spaces
APP_NAME="$(echo "$BASENAME" | sed 's/\.AppImage$//I' | sed 's/[-_][0-9].*//' | sed 's/[-_]$//')"
APP_NAME_CLEAN="${APP_NAME// /_}"   # no spaces in filenames

DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons"
DESKTOP_FILE="$DESKTOP_DIR/${APP_NAME_CLEAN}.desktop"
ICON_DEST="$ICON_DIR/${APP_NAME_CLEAN}"   # extension added later

mkdir -p "$DESKTOP_DIR" "$ICON_DIR"

echo ""
echo "AppImage : $APPIMAGE_PATH"
echo "App name : $APP_NAME"
echo ""

# ─── Make the AppImage executable ───────────────────────────────────────────

if [[ ! -x "$APPIMAGE_PATH" ]]; then
    info "Making AppImage executable..."
    chmod +x "$APPIMAGE_PATH"
fi

# ─── Extract AppImage to a temp dir ─────────────────────────────────────────

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT   # always clean up

info "Extracting AppImage contents (this may take a moment)..."
# --appimage-extract dumps contents into ./squashfs-root relative to CWD
cd "$TMPDIR"
"$APPIMAGE_PATH" --appimage-extract > /dev/null 2>&1 || true
EXTRACT_DIR="$TMPDIR/squashfs-root"

# ─── Find an icon ───────────────────────────────────────────────────────────

ICON_PATH=""
ICON_EXT=""

if [[ -d "$EXTRACT_DIR" ]]; then
    info "Searching for icons inside AppImage..."

    # Priority order: .png > .svg > .xpm > any image
    # 1) Look for a .DirIcon (standard AppImage icon) first
    if [[ -f "$EXTRACT_DIR/.DirIcon" ]]; then
        ICON_PATH="$EXTRACT_DIR/.DirIcon"
        # .DirIcon is usually a symlink to a png/svg; resolve extension
        REAL="$(realpath "$ICON_PATH" 2>/dev/null || echo "$ICON_PATH")"
        ICON_EXT="${REAL##*.}"
        [[ "$ICON_EXT" == "$REAL" ]] && ICON_EXT="png"   # no extension → assume png
    fi

    # 2) Highest-res png in usr/share/icons
    if [[ -z "$ICON_PATH" ]]; then
        ICON_PATH="$(find "$EXTRACT_DIR/usr/share/icons" -name "*.png" 2>/dev/null \
            | sort -t'/' -k1,1 | tail -1 || true)"
        [[ -n "$ICON_PATH" ]] && ICON_EXT="png"
    fi

    # 3) Any png at the root level of the AppImage
    if [[ -z "$ICON_PATH" ]]; then
        ICON_PATH="$(find "$EXTRACT_DIR" -maxdepth 1 -name "*.png" 2>/dev/null | head -1 || true)"
        [[ -n "$ICON_PATH" ]] && ICON_EXT="png"
    fi

    # 4) SVG fallback
    if [[ -z "$ICON_PATH" ]]; then
        ICON_PATH="$(find "$EXTRACT_DIR" -name "*.svg" 2>/dev/null | head -1 || true)"
        [[ -n "$ICON_PATH" ]] && ICON_EXT="svg"
    fi

    # 5) XPM fallback
    if [[ -z "$ICON_PATH" ]]; then
        ICON_PATH="$(find "$EXTRACT_DIR" -name "*.xpm" 2>/dev/null | head -1 || true)"
        [[ -n "$ICON_PATH" ]] && ICON_EXT="xpm"
    fi
fi

# Also search the AppImage's own directory for images (user request)
APPIMAGE_DIR="$(dirname "$APPIMAGE_PATH")"
if [[ -z "$ICON_PATH" ]]; then
    info "No icon in AppImage — searching AppImage directory..."
    for ext in png svg xpm jpg jpeg; do
        ICON_PATH="$(find "$APPIMAGE_DIR" -maxdepth 2 -iname "*.${ext}" 2>/dev/null | head -1 || true)"
        if [[ -n "$ICON_PATH" ]]; then
            ICON_EXT="$ext"
            break
        fi
    done
fi

# ─── Copy icon ───────────────────────────────────────────────────────────────

ICON_VALUE=""   # empty = no icon found yet

if [[ -n "$ICON_PATH" && -f "$ICON_PATH" ]]; then
    FINAL_ICON="${ICON_DEST}.${ICON_EXT}"
    cp "$ICON_PATH" "$FINAL_ICON"
    ICON_VALUE="$APP_NAME_CLEAN"
    info "Icon saved → $FINAL_ICON"
else
    info "No icon found — desktop entry will be created without an icon."
fi

# ─── Try to read metadata from .desktop inside the AppImage ──────────────────

INNER_DESKTOP=""
if [[ -d "$EXTRACT_DIR" ]]; then
    INNER_DESKTOP="$(find "$EXTRACT_DIR" -maxdepth 1 -name "*.desktop" 2>/dev/null | head -1 || true)"
fi

read_field() {
    local field="$1" file="$2"
    grep -i "^${field}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | xargs || true
}

COMMENT=""
CATEGORIES="Utility;"

if [[ -n "$INNER_DESKTOP" && -f "$INNER_DESKTOP" ]]; then
    info "Found inner .desktop — reading metadata..."
    INNER_NAME="$(read_field "Name" "$INNER_DESKTOP")"
    INNER_COMMENT="$(read_field "Comment" "$INNER_DESKTOP")"
    INNER_CATEGORIES="$(read_field "Categories" "$INNER_DESKTOP")"

    # Use inner name if it looks reasonable
    [[ -n "$INNER_NAME" ]] && APP_NAME="$INNER_NAME"
    [[ -n "$INNER_COMMENT" ]] && COMMENT="$INNER_COMMENT"
    [[ -n "$INNER_CATEGORIES" ]] && CATEGORIES="$INNER_CATEGORIES"
fi

# ─── Write the .desktop file ─────────────────────────────────────────────────

{
    echo "[Desktop Entry]"
    echo "Type=Application"
    echo "Name=${APP_NAME}"
    echo "Comment=${COMMENT}"
    echo "Exec=${APPIMAGE_PATH} %U"
    [[ -n "$ICON_VALUE" ]] && echo "Icon=${ICON_VALUE}"
    echo "Categories=${CATEGORIES}"
    echo "Terminal=false"
    echo "StartupNotify=true"
} > "$DESKTOP_FILE"

chmod +x "$DESKTOP_FILE"
info "Desktop entry saved → $DESKTOP_FILE"

# ─── Refresh desktop database ────────────────────────────────────────────────

if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo ""
echo "Done! '$APP_NAME' should appear in your app launcher."
echo "If it doesn't show up immediately, log out and back in or run:"
echo "  update-desktop-database ~/.local/share/applications"
