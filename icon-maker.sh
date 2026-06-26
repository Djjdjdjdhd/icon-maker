#!/bin/bash

# =============================================================================
# Script: icon-maker.sh
# Description: Downloads an icon set from wallpapers-clan.com and packages it as a fully compliant Linux icon theme tarball.
# Usage: ./icon-maker.sh <URL_to_icon_set_page> <theme_name>
# =============================================================================

SCRIPT_INVOCATION_DIR="$(pwd)"

GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# --- Dependency Check ---
if ! command -v curl &> /dev/null; then
    echo "  Would love to help, but 'curl' isn't installed. Could you install it?"
    exit 1
fi

if ! command -v grep &> /dev/null || ! command -v sed &> /dev/null; then
    echo "  Missing some basic tools ('grep', 'sed'). Need those to work."
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "  Python 3 is missing. I kinda need it to run."
    exit 1
fi

if ! python3 -c 'from PIL import Image' &> /dev/null; then
    echo "  The Pillow library for Python isn't installed."
    echo "  Run: pip3 install Pillow"
    exit 1
fi

# Optional GUI tool for interactive icon picking (not required)
HAS_YAD=0
HAS_ZENITY=0
GUI_TOOL=""
if command -v yad &> /dev/null; then
    HAS_YAD=1
    GUI_TOOL="yad"
elif command -v zenity &> /dev/null; then
    HAS_ZENITY=1
    GUI_TOOL="zenity"
fi

# --- Input Validation ---
SHAPE="none"
PICKER_MODE=0
PICKER_THEME=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --shape)
            if [ -n "$2" ] && [[ "$2" =~ ^(rounded|circle)$ ]]; then
                SHAPE="$2"; shift 2
            else
                echo "  --shape requires 'rounded' or 'circle'"
                exit 1
            fi
            ;;
        --picker|-p)
            if [ -n "$2" ]; then
                PICKER_MODE=1; PICKER_THEME="$2"; shift 2
            else
                echo "  --picker requires a theme name"
                exit 1
            fi
            ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ "$PICKER_MODE" -eq 1 ]; then
    ICON_INSTALL_DIR="${HOME}/.icons"
    PICKER_DIR="${ICON_INSTALL_DIR}/${PICKER_THEME}"
    if [ ! -d "$PICKER_DIR" ]; then
        echo -e "  ${BOLD}!${NC} Theme '${PICKER_THEME}' not found in ${ICON_INSTALL_DIR}/"
        exit 1
    fi
fi

if [ "$PICKER_MODE" -eq 0 ]; then
if [ $# -ne 2 ]; then
    echo "  Usage: $0 [--picker <theme>] [--shape rounded|circle] <URL> <theme_name>"
    echo "  Example: $0 https://wallpapers-clan.com/app-icons/one-piece/ one-piece"
    exit 1
fi

ICON_PAGE_URL="$1"
THEME_NAME="$2"
THEME_NAME=$(echo "$THEME_NAME" | sed 's/[^a-zA-Z0-9_-]//g')
if [ -z "$THEME_NAME" ]; then
    echo "  That theme name won't work. Use letters, numbers, underscores, and hyphens."
    exit 1
fi

# --- Setup Work Directories ---
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
THEME_DIR="${TEMP_DIR}/${THEME_NAME}"
ICON_INSTALL_DIR="${HOME}/.icons"

echo ""
echo -e "  ${BOLD}Pulling icons from:${NC} $ICON_PAGE_URL"
echo -e "  ${BOLD}Theme name:${NC}        $THEME_NAME"
echo ""

# --- Step 1: Download the page HTML ---
echo -e "  ${GREEN}→${NC} Fetching the icon page..."
PAGE_HTML="${TEMP_DIR}/page.html"
CURL_UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
CURL_HEADERS=(
    -A "$CURL_UA"
    -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
    -H 'Accept-Language: en-US,en;q=0.5'
    --compressed
)
if ! curl -s -L "${CURL_HEADERS[@]}" "$ICON_PAGE_URL" -o "$PAGE_HTML"; then
    echo "  Couldn't reach that page. Check the URL and try again."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Detect Cloudflare protection and retry with Firefox if needed
if grep -q 'challenges.cloudflare.com' "$PAGE_HTML" 2>/dev/null; then
    echo -e "  ${GREEN}→${NC} Cloudflare wants to chat. Trying Firefox headless..."
    if command -v firefox >/dev/null 2>&1; then
        if firefox --headless --dump-dom "$ICON_PAGE_URL" > "$PAGE_HTML" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Got the page through Firefox."
        else
            echo -e "  ${BOLD}!${NC} Firefox headless stumbled. Working with what curl gave me."
        fi
    else
        echo -e "  ${BOLD}!${NC} No Firefox available. Sticking with curl's result."
    fi
fi

# --- Step 2: Extract the download zip URL if present ---
echo -e "  ${GREEN}→${NC} Hunting for a download link..."
DOWNLOAD_URL=""
DOWNLOAD_URL=$(grep -oE 'href="[^"]*ICONS[^"]*\.zip"' "$PAGE_HTML" | sed 's/href="//' | sed 's/"$//' | head -1)
if [ -n "$DOWNLOAD_URL" ]; then
    echo -e "  ${GREEN}✓${NC} Found an ICONS pack link."
fi
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(grep -oE 'href="[^"]*\.zip"' "$PAGE_HTML" | sed 's/href="//' | sed 's/"$//' | head -1)
    if [ -n "$DOWNLOAD_URL" ]; then
        echo -e "  ${GREEN}✓${NC} Found a zip link (hoping it's the right one)."
    fi
fi
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(grep -oE 'data-downloadurl="[^"]+"' "$PAGE_HTML" | sed 's/data-downloadurl="//' | sed 's/"$//' | head -1)
    if [ -n "$DOWNLOAD_URL" ]; then
        echo -e "  ${GREEN}✓${NC} Found a data-downloadurl link."
    fi
fi
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(grep -oE "href='[^']*\.zip'" "$PAGE_HTML" | sed "s/href='//" | sed "s/'$//" | head -1)
    if [ -n "$DOWNLOAD_URL" ]; then
        echo -e "  ${GREEN}✓${NC} Found a single-quoted zip link."
    fi
fi
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(grep -oE 'data-(href|url|file)="[^"]*\.zip"' "$PAGE_HTML" | head -1 | sed 's/data-[a-z]*="//' | sed 's/"$//')
    if [ -n "$DOWNLOAD_URL" ]; then
        echo -e "  ${GREEN}✓${NC} Found a data-attribute zip link."
    fi
fi
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(grep -oE '/wp-content/uploads/app-icons/[^"]*\.zip"' "$PAGE_HTML" | sed 's/"$//' | head -1)
    if [ -n "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://wallpapers-clan.com${DOWNLOAD_URL}"
        echo -e "  ${GREEN}✓${NC} Constructed zip URL from known path pattern."
    fi
fi
USE_PACKAGE=0
ZIP_FILE="${TEMP_DIR}/package.zip"
if [ -n "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(echo "$DOWNLOAD_URL" | sed 's/&amp;/\&/g')
    echo -e "  ${GREEN}→${NC} Downloading the package..."
    if curl -s -L "${CURL_HEADERS[@]}" "$DOWNLOAD_URL" -o "$ZIP_FILE"; then
        if python3 -c 'import sys, zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)' "$ZIP_FILE"; then
            echo -e "  ${GREEN}✓${NC} Got it — that's a valid zip."
            USE_PACKAGE=1
        else
            echo -e "  ${BOLD}!${NC} Not a valid zip. Trying to re-fetch the download link..."
            # Re-fetch the page for a fresh download token
            curl -s -L "${CURL_HEADERS[@]}" "$ICON_PAGE_URL" -o "$PAGE_HTML" 2>/dev/null
            DOWNLOAD_URL=""
            DOWNLOAD_URL=$(grep -oE 'data-downloadurl="[^"]+"' "$PAGE_HTML" | sed 's/data-downloadurl="//' | sed 's/"$//' | head -1)
            if [ -n "$DOWNLOAD_URL" ]; then
                DOWNLOAD_URL=$(echo "$DOWNLOAD_URL" | sed 's/&amp;/\&/g')
                echo -e "  ${GREEN}→${NC} Retrying download..."
                if curl -s -L "${CURL_HEADERS[@]}" "$DOWNLOAD_URL" -o "$ZIP_FILE" && \
                   python3 -c 'import sys, zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)' "$ZIP_FILE"; then
                    echo -e "  ${GREEN}✓${NC} Got it on the second try."
                    USE_PACKAGE=1
                fi
            fi
            if [ "$USE_PACKAGE" -eq 0 ]; then
                echo -e "  ${BOLD}!${NC} Could not get a valid package. The download link may have expired."
            fi
        fi
    else
        echo -e "  ${BOLD}!${NC} Download failed."
    fi
fi

if [ "$USE_PACKAGE" -eq 1 ]; then
    echo -e "  ${GREEN}→${NC} Unpacking the icons..."
    ICON_EXTRACT_ROOT="$THEME_DIR"
    mkdir -p "$ICON_EXTRACT_ROOT"
    python3 - "$ZIP_FILE" "$ICON_EXTRACT_ROOT" <<'PY'
import os, sys, zipfile
zip_path, out_root = sys.argv[1], sys.argv[2]
SKIP_DIRS = {'wallpapers', 'widgets', '__macosx'}
IMAGE_EXTS = ('.png', '.svg', '.xpm', '.jpg', '.jpeg', '.webp')
with zipfile.ZipFile(zip_path) as z:
    candidates = []
    for n in z.namelist():
        if n.endswith('/'):
            continue
        top = n.split('/')[0].lower()
        if top in SKIP_DIRS:
            continue
        if n.startswith('._') or '/._' in n:
            continue
        if not n.lower().endswith(IMAGE_EXTS):
            continue
        candidates.append(n)
    if not candidates:
        sys.exit(1)
    groups = {}
    for n in candidates:
        p = n.split('/')[0] + '/' if '/' in n else ''
        groups.setdefault(p, []).append(n)
    if '' in groups and len(groups) > 1:
        del groups['']
    chosen = max(groups, key=lambda k: len(groups[k]))
    for n in candidates:
        if chosen and not n.startswith(chosen):
            continue
        rel = n[len(chosen):] if chosen else n
        rel = rel.lstrip('/')
        if '..' in rel.split('/'):
            continue
        target_path = os.path.join(out_root, rel)
        target_dir = os.path.dirname(target_path)
        os.makedirs(target_dir, exist_ok=True)
        with z.open(n) as src, open(target_path, 'wb') as dst:
            dst.write(src.read())
PY

    # --- Optional Step: Apply shape mask to extracted icons (before symlinks) ---
    if [ "$SHAPE" != "none" ]; then
        echo -e "  ${GREEN}→${NC} Applying ${SHAPE} shape mask to icons..."
        python3 - "$THEME_DIR" "$SHAPE" <<'PY'
import os, sys
from PIL import Image, ImageDraw, ImageChops

root, shape = sys.argv[1], sys.argv[2]
radius_ratio = 0.2
processed = 0
skipped_svg = 0

for dirpath, _dirnames, filenames in os.walk(root):
    for f in filenames:
        if f.lower().endswith('.svg'):
            skipped_svg += 1
            continue
        if not f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.xpm')):
            continue
        path = os.path.join(dirpath, f)
        try:
            img = Image.open(path).convert("RGBA")
        except Exception:
            continue
        w, h = img.size

        mask = Image.new('L', (w, h), 0)
        draw = ImageDraw.Draw(mask)

        if shape == 'circle':
            draw.ellipse((0, 0, w - 1, h - 1), fill=255)
        elif shape == 'rounded':
            r = int(max(w, h) * radius_ratio)
            draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)

        r_ch, g_ch, b_ch, a_ch = img.split()
        new_a = ImageChops.multiply(a_ch, mask)
        result = Image.merge('RGBA', (r_ch, g_ch, b_ch, new_a))
        result.save(path, "PNG")
        processed += 1

print(f"  Shaped {processed} icons ({skipped_svg} SVGs skipped)")
PY
    fi

    # Detect actual image sizes and reorganize into proper size directories.
    python3 - "$THEME_DIR" <<'PY'
import os, sys, struct, io
from PIL import Image
root = sys.argv[1]

entries = []
for dirpath, dirnames, filenames in os.walk(root):
    for f in filenames:
        entries.append((dirpath, f))

for dirpath, f in entries:
    path = os.path.join(dirpath, f)
    ext = f.lower()
    if not (ext.endswith('.png') or ext.endswith('.svg') or ext.endswith('.xpm') or ext.endswith('.jpg') or ext.endswith('.jpeg') or ext.endswith('.webp')):
        continue
    try:
        with Image.open(path) as img:
            w, h = img.size
    except Exception:
        w, h = 48, 48
    if ext.endswith('.svg'):
        context = "apps"
        if "action" in f.lower() or "action" in dirpath.lower():
            context = "actions"
        elif "mime" in f.lower() or "mime" in dirpath.lower():
            context = "mimetypes"
        primary_path = os.path.join(root, "scalable", context, f)
        os.makedirs(os.path.dirname(primary_path), exist_ok=True)
        if os.path.abspath(path) != os.path.abspath(primary_path):
            os.replace(path, primary_path)
    else:
        context = "apps"
        if "action" in f.lower() or "action" in dirpath.lower():
            context = "actions"
        elif "mime" in f.lower() or "mime" in dirpath.lower():
            context = "mimetypes"
        s = max(w, h)
        primary_path = os.path.join(root, f"{s}x{s}", context, f)
        os.makedirs(os.path.dirname(primary_path), exist_ok=True)
        if os.path.abspath(path) != os.path.abspath(primary_path):
            os.replace(path, primary_path)
        # Symlink into every standard size directory so the icon is visible
        for sz in (16, 22, 24, 32, 48, 64, 128, 256):
            link_dir = os.path.join(root, f"{sz}x{sz}", context)
            os.makedirs(link_dir, exist_ok=True)
            link_path = os.path.join(link_dir, f)
            if not os.path.exists(link_path):
                rel = os.path.relpath(primary_path, link_dir)
                os.symlink(rel, link_path)
    # Clean up empty subdirs left behind
    parent = os.path.dirname(path)
    while parent != root:
        try:
            os.rmdir(parent)
        except OSError:
            break
        parent = os.path.dirname(parent)
PY

    DOWNLOAD_COUNT=$(find "$THEME_DIR" -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.xpm' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | wc -l)
    if [ "$DOWNLOAD_COUNT" -eq 0 ]; then
        echo "  Huh — the zip was empty. Nothing to work with."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    echo -e "  Extracted ${GREEN}${DOWNLOAD_COUNT}${NC} original icons from the pack."
else
    echo -e "  ${GREEN}→${NC} Scraping image URLs from the page..."
    IMAGE_URLS=$(grep -oE 'src="[^"]*\.(png|jpg|jpeg|webp)"' "$PAGE_HTML" | sed 's/src="//' | sed 's/"//')
    IMAGE_URLS="${IMAGE_URLS}
$(grep -oE "src='[^']*\.(png|jpg|jpeg|webp)'" "$PAGE_HTML" | sed "s/src='//" | sed "s/'//")"
    IMAGE_URLS="${IMAGE_URLS}
$(grep -oE 'url\([^)]*\.(png|jpg|jpeg|webp)\)' "$PAGE_HTML" | sed 's/url(//' | sed 's/)//')"
    IMAGE_URLS=$(echo "$IMAGE_URLS" | sort -u | grep -v '^$')

    # Filter out non-icon images (previews, logos, banners, avatars, thumbnails)
    FILTERED=""
    while IFS= read -r URL; do
        lower=$(echo "$URL" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            *preview*|*logo*|*banner*|*avatar*|*thumbnail*|*icon-pack*|*w-clan*) ;;
            *) FILTERED="${FILTERED}${URL}
" ;;
        esac
    done <<< "$IMAGE_URLS"
    IMAGE_URLS=$(echo "$FILTERED" | sort -u | grep -v '^$')

    if [ -z "$IMAGE_URLS" ]; then
        echo "  No individual app icons found on the page — only previews and logos."
        echo "  The download link may have expired. Try the URL again later."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    echo -e "  Found $(echo "$IMAGE_URLS" | wc -l) usable images on the page."
fi

# --- Step 3: Create the icon theme directory structure ---
mkdir -p "$THEME_DIR"
echo -e "  ${GREEN}→${NC} Setting up the theme directory layout..."

# --- Step 4: Download each image and place it in the theme structure ---
DOWNLOAD_COUNT=${DOWNLOAD_COUNT:-0}
SCALABLE_COUNT=0

if [ "$USE_PACKAGE" -ne 1 ]; then
    echo -e "  ${GREEN}→${NC} Downloading and organizing icons..."
    for URL in $IMAGE_URLS; do
        # Fix relative URLs
        if [[ "$URL" == /* ]]; then
            DOMAIN=$(echo "$ICON_PAGE_URL" | sed -E 's|(https?://[^/]+).*|\1|')
            URL="${DOMAIN}${URL}"
        elif [[ "$URL" != http* ]]; then
            BASE_DIR=$(echo "$ICON_PAGE_URL" | sed -E 's|(https?://[^/]+/[^/]*)/.*|\1|')
            URL="${BASE_DIR}/${URL}"
        fi

        if [[ ! "$URL" =~ ^https?:// ]]; then
            echo -e "    ${BOLD}!${NC} Skipping non-HTTP URL: $URL"
            continue
        fi

        FILENAME=$(basename "$URL" | sed 's/\?.*//' | sed 's/[^a-zA-Z0-9._-]//g' | sed 's/^\.//')
        [ -z "$FILENAME" ] && continue
        # Determine if it's an SVG
        if echo "$FILENAME" | grep -iq '\.svg$'; then
            # Place in scalable directory
            TARGET_DIR="$THEME_DIR/scalable/apps"
            mkdir -p "$TARGET_DIR"
            SCALABLE_COUNT=$((SCALABLE_COUNT + 1))
        else
            # Try to determine size from filename or URL
            TARGET_SIZE=48  # default
            if echo "$FILENAME" | grep -Eiq '(16|22|24|32|48|64|128|256)'; then
                SIZE_NUM=$(echo "$FILENAME" | grep -Eo '(16|22|24|32|48|64|128|256)' | head -1)
                TARGET_SIZE=$SIZE_NUM
            elif echo "$URL" | grep -Eiq '(16|22|24|32|48|64|128|256)'; then
                SIZE_NUM=$(echo "$URL" | grep -Eo '(16|22|24|32|48|64|128|256)' | head -1)
                TARGET_SIZE=$SIZE_NUM
            fi
            # Determine context (default to apps)
            CONTEXT="apps"
            if echo "$FILENAME" | grep -iq 'action'; then
                CONTEXT="actions"
            elif echo "$FILENAME" | grep -iq 'mime'; then
                CONTEXT="mimetypes"
            fi
            TARGET_DIR="$THEME_DIR/${TARGET_SIZE}x${TARGET_SIZE}/${CONTEXT}"
            mkdir -p "$TARGET_DIR"
        fi

        ICON_PATH="$TARGET_DIR/$FILENAME"
        echo "    Downloading: $URL"
        if curl -s -L --fail "$URL" -o "$ICON_PATH"; then
            DOWNLOAD_COUNT=$((DOWNLOAD_COUNT + 1))
        else
            echo "    Warning: Failed to download $URL"
        fi
    done
fi

if [ "$USE_PACKAGE" -eq 1 ]; then
    if [ $DOWNLOAD_COUNT -eq 0 ]; then
        echo "  Nothing came out of that package. Something's wrong."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    if [ $DOWNLOAD_COUNT -eq 0 ]; then
        echo "  No icons could be downloaded. Check the URL."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# --- Optional Step: Apply shape mask to icons (for page-scrape path; package path already shaped) ---
if [ "$SHAPE" != "none" ] && [ "$USE_PACKAGE" -ne 1 ]; then
    echo -e "  ${GREEN}→${NC} Applying ${SHAPE} shape mask to icons..."
    python3 - "$THEME_DIR" "$SHAPE" <<'PY'
import os, sys
from PIL import Image, ImageDraw, ImageChops

root, shape = sys.argv[1], sys.argv[2]
radius_ratio = 0.2
processed = 0
skipped_svg = 0

for dirpath, _dirnames, filenames in os.walk(root):
    for f in filenames:
        if f.lower().endswith('.svg'):
            skipped_svg += 1
            continue
        if not f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.xpm')):
            continue
        path = os.path.join(dirpath, f)
        try:
            img = Image.open(path).convert("RGBA")
        except Exception:
            continue
        w, h = img.size

        mask = Image.new('L', (w, h), 0)
        draw = ImageDraw.Draw(mask)

        if shape == 'circle':
            draw.ellipse((0, 0, w - 1, h - 1), fill=255)
        elif shape == 'rounded':
            r = int(max(w, h) * radius_ratio)
            draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)

        r_ch, g_ch, b_ch, a_ch = img.split()
        new_a = ImageChops.multiply(a_ch, mask)
        result = Image.merge('RGBA', (r_ch, g_ch, b_ch, new_a))
        result.save(path, "PNG")
        processed += 1

print(f"  Shaped {processed} icons ({skipped_svg} SVGs skipped)")
PY
fi

echo ""
echo -e "  ${GREEN}→${NC} Normalizing filenames and converting to standard formats..."
python3 - "$THEME_DIR" <<'PY'
import os, sys, re
from PIL import Image

root = sys.argv[1]
converted = renamed = 0

entries = []
for dirpath, dirnames, filenames in os.walk(root):
    for f in filenames:
        entries.append((dirpath, f))

for dirpath, f in entries:
    if os.path.islink(os.path.join(dirpath, f)):
        continue
    path = os.path.join(dirpath, f)
    name, ext = os.path.splitext(f)
    ext_lower = ext.lower()

    if ext_lower not in ('.png', '.jpg', '.jpeg', '.webp', '.svg', '.xpm'):
        continue

    new_ext = ext
    if ext_lower in ('.jpg', '.jpeg', '.webp'):
        try:
            img = Image.open(path).convert('RGBA')
            new_ext = '.png'
            new_path = os.path.join(dirpath, name + new_ext)
            img.save(new_path, 'PNG')
            os.remove(path)
            path = new_path
            converted += 1
        except Exception:
            new_ext = ext_lower

    new_name = name.lower()
    new_name = new_name.replace(' ', '-').replace('_', '-')
    new_name = re.sub(r'-+', '-', new_name)
    new_name = re.sub(r'[^a-z0-9.-]', '', new_name)
    new_name = new_name.strip('-')
    if not new_name:
        new_name = 'icon'

    final_name = new_name + new_ext
    final_path = os.path.join(dirpath, final_name)
    if final_path != path:
        if os.path.exists(final_path):
            os.remove(path)
        else:
            os.rename(path, final_path)
        renamed += 1

# Normalize symlink names and repair broken symlinks
repaired = 0
entry_set = set()
for dirpath, dirnames, filenames in os.walk(root):
    for f in filenames:
        entry_set.add((dirpath, f))
for dirpath, f in list(entry_set):
    path = os.path.join(dirpath, f)
    if not os.path.islink(path):
        continue
    target = os.readlink(path)
    abs_target = os.path.normpath(os.path.join(dirpath, target))
    target_name = os.path.basename(abs_target)
    target_dir = os.path.dirname(abs_target)
    t_name, t_ext = os.path.splitext(target_name)
    t_lower = t_name.lower().replace(' ', '-').replace('_', '-')
    t_lower = re.sub(r'-+', '-', t_lower)
    t_lower = re.sub(r'[^a-z0-9.-]', '', t_lower).strip('-') or 'icon'
    t_candidates = [t_lower + t_ext.lower()]
    if t_ext.lower() in ('.jpg', '.jpeg', '.webp'):
        t_candidates.append(t_lower + '.png')
    resolved_target = None
    for candidate in t_candidates:
        cand_path = os.path.join(target_dir, candidate)
        if os.path.exists(cand_path):
            resolved_target = os.path.relpath(cand_path, dirpath)
            break
    if not resolved_target:
        continue
    s_name, s_ext = os.path.splitext(f)
    s_lower = s_name.lower().replace(' ', '-').replace('_', '-')
    s_lower = re.sub(r'-+', '-', s_lower)
    s_lower = re.sub(r'[^a-z0-9.-]', '', s_lower).strip('-') or 'icon'
    s_ext = '.png' if s_ext.lower() in ('.jpg', '.jpeg', '.webp') else s_ext
    s_final = s_lower + s_ext
    s_final_path = os.path.join(dirpath, s_final)
    if s_final_path != path or resolved_target != target:
        os.remove(path)
        os.symlink(resolved_target, s_final_path)
        repaired += 1

print(f"  Normalized {renamed} files ({converted} converted to PNG, {repaired} symlinks normalized)")
PY

echo -e "  ${GREEN}→${NC} Creating normalized name aliases..."
find "$THEME_DIR" -type d -print0 | while IFS= read -r -d '' DIR; do
    for FILE in "$DIR"/*.png "$DIR"/*.svg "$DIR"/*.xpm; do
        [ -f "$FILE" ] || continue
        BASENAME=$(basename "$FILE")
        EXT="${BASENAME##*.}"
        NAME_NO_EXT="${BASENAME%.*}"
        case "$NAME_NO_EXT" in
            *[!a-z0-9.-]*)
                NORM=$(echo "$NAME_NO_EXT" | tr '[:upper:]' '[:lower:]' | sed 's/[ _]/-/g' | sed 's/[^a-z0-9.-]//g')
                if [ "$NORM" != "$NAME_NO_EXT" ] && [ ! -e "$DIR/$NORM.$EXT" ]; then
                    (cd "$DIR" && ln -s "$BASENAME" "$NORM.$EXT")
                fi
                ;;
        esac
    done
done

# Create symlinks: map every Linux desktop icon name to one of the pack icons.
# Two-tier approach:
#   1. Known-name map (iOS app → Linux equivalent) for quality on common apps.
#   2. Hash distribution for everything else (covers every icon on any system).
echo -e "  ${GREEN}→${NC} Mapping Linux app names to pack icons..."
python3 - "$THEME_DIR" <<'PY'
import os, sys, hashlib, re
from collections import defaultdict

root = sys.argv[1]

# ---- curated name map: pack icon name → best Linux equivalent icon names ----
NAME_MAP = {
    # ── Social ──
    "discord":        ["discord", "vesktop", "com.discordapp.Discord"],
    "messenger":      ["messenger", "facebook-messenger"],
    "whatsapp":       ["whatsapp", "whatsapp-desktop"],
    "telegram":       ["telegram", "telegram-desktop", "org.telegram.desktop"],
    "signal":         ["signal-desktop", "org.signal.Signal"],
    "slack":          ["slack", "com.slack.Slack"],
    "teams":          ["teams", "teams-for-linux", "com.microsoft.Teams"],
    "facebook":       ["facebook"],
    "instagram":      ["instagram", "org.instagram.Instagram"],
    "twitter":        ["twitter"],
    "linkedin":       ["linkedin", "org.linkedin.LinkedIn"],
    "reddit":         ["reddit"],
    "snapchat":       ["snapchat", "com.snapchat.Snapchat"],
    "tiktok":         ["tiktok", "com.tiktok.Tiktok"],
    "skype":          ["skype"],
    "viber":          ["viber"],
    "tumblr":         ["tumblr"],
    "pinterest":      ["pinterest"],
    "tinder":         ["tinder"],
    "hangouts":       ["hangouts"],

    # ── Browsers ──
    "safari":         ["epiphany", "org.gnome.Epiphany", "gnome-web", "midori", "falkon", "qutebrowser", "surf", "helium-browser", "zen-browser", "zen"],
    "chrome":         ["chrome", "google-chrome", "google-chrome-stable", "chromium", "brave-browser", "brave", "microsoft-edge", "edge", "opera", "vivaldi", "yandex-browser"],
    "chromium":       ["chromium", "chromium-browser", "google-chrome", "brave-browser", "brave", "chrome", "org.chromium.Chromium"],
    "google-chrome":  ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome", "brave-browser", "brave", "microsoft-edge", "edge", "org.chromium.Chromium", "opera", "vivaldi"],
    "firefox":        ["firefox", "mozilla-firefox", "org.mozilla.firefox", "org.mozilla.firefox-esr", "iceweasel"],

    # ── Media & Music ──
    "spotify":        ["spotify", "spotify-client", "spotify-launcher", "com.spotify.Client"],
    "music":          ["rhythmbox", "org.gnome.Music", "lollypop", "audacious", "strawberry", "clementine", "elisa", "pragha", "sayonara"],
    "youtube":        ["freetube", "io.github.Helio"],
    "netflix":        ["netflix", "com.netflix.Netflix"],
    "twitch":         ["twitch", "com.twitch.Twitch"],
    "pandora":        ["pandora"],
    "shazam":         ["shazam", "songrec"],
    "garageband":     ["lmms", "ardour", "musescore", "hydrogen"],
    "sound":          ["pavucontrol", "org.pulseaudio.pavucontrol", "volume-control"],
    "amazon-music":   ["amazon-music"],

    # ── Video & TV ──
    "tv":             ["mpv", "totem", "vlc", "org.gnome.Totem", "haruna"],
    "video":          ["mpv", "totem", "vlc", "org.gnome.Totem", "haruna", "celluloid", "clapper"],
    "videos":         ["mpv", "totem", "vlc", "org.gnome.Totem", "haruna", "celluloid", "clapper"],
    "vimeo":          ["vimeo"],
    "hulu":           ["hulu"],
    "movies":         ["mpv", "totem", "vlc", "org.gnome.Totem"],

    # ── Shopping & Finance ──
    "amazon":         ["amazon", "com.amazon.Amazon"],
    "paypal":         ["paypal"],
    "walmart":        ["walmart"],
    "cash":           ["gnucash", "homebank"],
    "stocks":         ["stocks"],

    # ── Travel & Transport ──
    "airbnb":         ["airbnb"],
    "lyft":           ["lyft"],
    "uber":           ["uber"],
    "airplane":       ["airplane-mode"],
    "google-maps":    ["google-maps", "org.gnome.Maps", "gnome-maps", "maps"],
    "maps":           ["org.gnome.Maps", "gnome-maps", "maps", "google-maps"],

    # ── Communication ──
    "mail":           ["thunderbird", "org.gnome.Geary", "geary", "evolution", "claws-mail", "sylpheed", "mailspring", "betterbird"],
    "gmail":          ["thunderbird", "org.gnome.Geary", "geary", "evolution", "mailspring", "betterbird"],
    "messages":       ["conversations", "gajim", "dino", "fractal", "element"],
    "phone":          ["call", "gnome-calls", "org.gnome.Calls"],
    "facetime":       ["gnome-connections", "org.gnome.Connections"],
    "contacts":       ["org.gnome.Contacts", "gnome-contacts", "kaddressbook"],

    # ── Productivity ──
    "calendar":       ["org.gnome.Calendar", "gnome-calendar", "evolution", "gnome-todo", "california"],
    "notes":          ["org.gnome.Notes", "bijiben", "org.gnome.gedit", "xournalpp", "joplin", "simplenote", "standardnotes", "cherrytree", "zim"],
    "notion":         ["notion", "logseq", "obsidian"],
    "reminders":      ["org.gnome.Todo", "gnome-todo", "todoist"],
    "clock":          ["org.gnome.Clocks", "gnome-clocks", "alarm-clock"],
    "calculator":     ["org.gnome.Calculator", "gnome-calculator", "qalculate-gtk", "kcalc", "galculator"],
    "files":          ["org.gnome.Nautilus", "nautilus", "caja", "dolphin", "thunar", "nemo", "pcmanfm", "pcmanfm-qt", "doublecmd", "spacefm"],
    "home":           ["user-home", "go-home"],
    "pass":           ["keepassxc", "bitwarden", "seahorse"],
    "wallet":         ["org.gnome.Wallet", "gnome-wallet", "seahorse"],
    "search":         ["gnome-shell-search", "tracker", "locate"],
    "measure":        ["measure"],
    "translate":      ["org.gnome.Translate", "dialect", "gnome-translate", "crow-translate"],
    "compass":        ["compass"],

    # ── Documents & Office ──
    "pages":          ["libreoffice-writer", "abiword", "onlyoffice-desktopeditors"],
    "numbers":        ["libreoffice-calc", "gnumeric"],
    "books":          ["foliate", "org.gnome.Books", "calibre", "bookworm", "evince", "okular", "zathura"],

    # ── Health & Fitness ──
    "fitness":        ["health", "org.gnome.Health"],
    "health":         ["health", "org.gnome.Health"],

    # ── Weather ──
    "weather":        ["org.gnome.Weather", "gnome-weather"],

    # ── Camera & Photo ──
    "camera":         ["org.gnome.Camera", "cheese", "snapshot", "guvcview", "kamoso"],
    "photos":         ["org.gnome.Photos", "eog", "shotwell", "gthumb", "gwenview", "sxiv", "ristretto"],
    "draw":           ["krita", "mypaint", "pinta", "gimp", "inkscape"],

    # ── Gaming ──
    "playstation":    ["steam", "lutris", "heroic", "net.lutris.Lutris", "games", "steam-native", "steam-runtime", "com.valvesoftware.Steam", "prismlauncher", "bottles", "game"],
    "xbox":           ["steam", "lutris", "heroic", "net.lutris.Lutris", "games", "game", "xbox"],
    "among-us":       ["among-us"],

    # ── Development ──
    "terminal":       ["org.gnome.Terminal", "gnome-terminal", "Alacritty", "kitty", "konsole", "kgx", "io.mitchellh.ghostty", "foot", "st", "urxvt", "xfce4-terminal", "pantheon-terminal", "terminator", "guake", "wezterm", "tilix"],
    "code":           ["code", "vscode", "visual-studio-code", "com.visualstudio.code", "codium", "code-oss", "code-insiders", "jetbrains-idea", "jetbrains-pycharm", "android-studio", "eclipse"],

    # ── System ──
    "settings":       ["gnome-control-center", "preferences-system", "org.gnome.Settings", "xfce4-settings-manager", "systemsettings", "cinnamon-settings", "mate-control-center"],
    "app-store":      ["gnome-software", "org.gnome.Software", "pamac", "plasma-discover", "octopi"],
    "wi-fi":          ["network", "nm-connection-editor", "gnome-network-panel"],
    "sleep":          ["gnome-session-sleep", "system-lock-screen"],
    "fonts":          ["font-manager", "fontmatrix", "org.gnome.FontManager"],
    "download":       ["transmission", "transmission-qt", "transmission-gtk", "org.gnome.Downloads", "qbittorrent", "deluge"],
    "zoom":           ["zoom", "zoom-client", "us.zoom.Zoom"],

    # ── News & Podcasts ──
    "news":           ["org.gnome.News", "liferea", "newsboat", "quite-rss"],
    "podcasts":       ["gpodder", "org.gnome.Podcasts", "vocal", "kasts"],

    # ── Miscellaneous ──
    "emoji":          ["gnome-characters", "org.gnome.Characters", "gucharmap"],
    "google":         ["google"],
    "google-translate": ["org.gnome.Translate", "dialect", "gnome-translate", "crow-translate"],
    "chatgpt":        ["chatgpt"],
    "clips":          ["copyq", "clipit"],
    "voice-memos":    ["gnome-sound-recorder", "org.gnome.SoundRecorder"],
    "tips":           ["gnome-tips", "org.gnome.Tips"],
    "shortcuts":      ["gnome-shortcuts"],
}

# ── collect icon names the system may request ──────────────────────────────
def collect_desktop_icons():
    icons = {}
    search_dirs = [
        "/usr/share/applications",
        "/usr/local/share/applications",
        os.path.expanduser("~/.local/share/applications"),
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
        "/var/lib/flatpak/exports/share/applications",
        "/var/lib/snapd/desktop/applications",
        os.path.expanduser("~/.local/share/flatpak/app"),
        os.path.expanduser("~/.config/autostart"),
        "/etc/skel/.local/share/applications",
    ]
    for base in search_dirs:
        if not os.path.isdir(base):
            continue
        for rootd, _dirs, files in os.walk(base):
            for f in files:
                if not f.endswith(".desktop"):
                    continue
                try:
                    with open(os.path.join(rootd, f), "r", errors="replace") as fh:
                        for line in fh:
                            if line.startswith("Icon="):
                                icon = line.split("=", 1)[1].strip()
                                if icon and not icon.startswith("/"):
                                    icons.setdefault(icon.lower(), []).append(icon)
                except:
                    pass
    return icons

icon_names = defaultdict(list)
for k, v in collect_desktop_icons().items():
    icon_names[k].extend(v)

# ── collect original pack icons ────────────────────────────────────────────
pack_icons = []  # (dirpath, filename, context)
for dirpath, _dirnames, filenames in os.walk(root):
    context = "apps"
    base = os.path.basename(dirpath)
    if base in ("apps", "actions", "mimetypes"):
        context = base
    else:
        parent = os.path.basename(os.path.dirname(dirpath))
        if parent in ("apps", "actions", "mimetypes"):
            context = parent
    for f in filenames:
        name, ext = os.path.splitext(f)
        if ext.lower() not in ('.png', '.svg', '.xpm', '.jpg', '.jpeg', '.webp'):
            continue
        if not name or name.startswith('.'):
            continue
        full = os.path.join(dirpath, f)
        if not os.path.islink(full):
            pack_icons.append((dirpath, f, context))

if not pack_icons:
    print("  No original pack icons found — nothing to map.")
    sys.exit(0)
print(f"  System has {len(icon_names)} unique icon names.")
print(f"  Pack has {len(pack_icons)} original icons.")

def pick_icon(seed_str):
    idx = int(hashlib.md5(seed_str.encode()).hexdigest(), 16) % len(pack_icons)
    return pack_icons[idx]

def sanitize(name):
    return re.sub(r'[^a-zA-Z0-9._+-]', '', name)

primary_paths = {}  # (context, source_file) -> actual file path
for dirpath, fname, ctx in pack_icons:
    primary_paths[(ctx, fname)] = os.path.join(dirpath, fname)

def create_link_all(dirpath, source_file, context, link_name):
    found_ext = os.path.splitext(source_file)[1]
    if not found_ext:
        return False
    primary_path = primary_paths.get((context, source_file))
    if not primary_path:
        primary_path = os.path.join(dirpath, source_file)
        if not os.path.exists(primary_path):
            return False

    names = [link_name]
    link_lower = link_name.lower()
    if link_lower != link_name:
        names.append(link_lower)
    created = False

    for name in names:
        primary_link = os.path.join(dirpath, f"{name}{found_ext}")
        if not os.path.exists(primary_link):
            os.symlink(source_file, primary_link)
            created = True
    return created

# ── track names already present ────────────────────────────────────────────
existing = set()
for dirpath, _dirs, files in os.walk(root):
    for f in files:
        existing.add(os.path.splitext(f)[0])
existing = {name.lower() for name in existing}

# ── Phase 1: curated name map ─────────────────────────────────────────────
mapped = 0
for dirpath, source_file, ctx in list(pack_icons):
    base = os.path.splitext(source_file)[0].lower()
    if base in NAME_MAP:
        for target in NAME_MAP[base]:
            sane = sanitize(target)
            if sane and sane.lower() not in existing:
                if create_link_all(dirpath, source_file, ctx, sane):
                    existing.add(sane.lower())
                    mapped += 1
print(f"  Phase 1 — curated names: {mapped} symlinks created")

# ── Phase 2: hash-distribute remaining system icons ────────────────────────
hashed = 0
for lower, originals in icon_names.items():
    if lower in existing:
        continue
    dirpath, source_file, ctx = pick_icon(lower)
    for orig in originals:
        sane = sanitize(orig)
        if sane and sane.lower() not in existing:
            if create_link_all(dirpath, source_file, ctx, sane):
                existing.add(sane.lower())
                hashed += 1
    sane_lower = re.sub(r'[^a-z0-9._+-]', '', lower)
    if sane_lower and sane_lower not in existing:
        if create_link_all(dirpath, source_file, ctx, sane_lower):
            existing.add(sane_lower)
            hashed += 1
print(f"  Phase 2 — hash distribution: {hashed} symlinks created")
print(f"  Total: {mapped + hashed} icon names mapped")

PY

# Build the Directories list by scanning actual non-empty directories
DIRS_LIST=""
CONTEXT_TYPES="apps:Applications actions:Actions mimetypes:MimeTypes"
while IFS= read -r -d '' DIR; do
    REL=${DIR#"$THEME_DIR/"}
    HAS_FILES=$(find "$DIR" -maxdepth 1 \( -type f -o -type l \) \( -iname '*.png' -o -iname '*.svg' -o -iname '*.xpm' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | head -1)
    if [ -z "$HAS_FILES" ]; then
        continue
    fi
    if echo "$REL" | grep -qE '^[0-9]+x[0-9]+/(apps|actions|mimetypes)$'; then
        if [ -z "$DIRS_LIST" ]; then
            DIRS_LIST="$REL"
        else
            DIRS_LIST="${DIRS_LIST},$REL"
        fi
    elif echo "$REL" | grep -qE '^scalable/(apps|actions|mimetypes)$'; then
        if [ -z "$DIRS_LIST" ]; then
            DIRS_LIST="$REL"
        else
            DIRS_LIST="${DIRS_LIST},$REL"
        fi
    fi
done < <(find "$THEME_DIR" -type d -print0 | sort -z)

# Write the main [Icon Theme] section
cat > "$THEME_DIR/index.theme" <<EOF
[Icon Theme]
Name=$THEME_NAME
Comment=$THEME_NAME icons from Wallpapers-Clan.com
Inherits=hicolor
Directories=$DIRS_LIST
EOF

# Write per-directory sections by scanning actual non-empty directories
while IFS= read -r -d '' DIR; do
    REL=${DIR#"$THEME_DIR/"}
    HAS_FILES=$(find "$DIR" -maxdepth 1 \( -type f -o -type l \) \( -iname '*.png' -o -iname '*.svg' -o -iname '*.xpm' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | head -1)
    if [ -z "$HAS_FILES" ]; then
        continue
    fi
    if echo "$REL" | grep -qE '^[0-9]+x[0-9]+/(apps|actions|mimetypes)$'; then
        SIZE=$(echo "$REL" | sed -n 's/^\([0-9]\+\)x[0-9]\+\/.*$/\1/p')
        CTX=$(echo "$REL" | sed -n 's/^[0-9]\+x[0-9]\+\/\(.*\)$/\1/p')
        CONTEXT_TYPE="Applications"
        for pair in $CONTEXT_TYPES; do
            c=$(echo "$pair" | cut -d: -f1)
            t=$(echo "$pair" | cut -d: -f2)
            if [ "$CTX" = "$c" ]; then
                CONTEXT_TYPE="$t"
                break
            fi
        done
        STD_SIZES="16 22 24 32 48 64 128 256"
        if echo " $STD_SIZES " | grep -q " $SIZE "; then
            cat >> "$THEME_DIR/index.theme" <<EOF
[$REL]
Size=$SIZE
Context=$CONTEXT_TYPE
Type=Fixed
EOF
        else
            cat >> "$THEME_DIR/index.theme" <<EOF
[$REL]
Size=$SIZE
Context=$CONTEXT_TYPE
Type=Scalable
MinSize=1
MaxSize=512
EOF
        fi
    elif echo "$REL" | grep -qE '^scalable/(apps|actions|mimetypes)$'; then
        CTX=$(echo "$REL" | sed 's/^scalable\///')
        CONTEXT_TYPE="Applications"
        for pair in $CONTEXT_TYPES; do
            c=$(echo "$pair" | cut -d: -f1)
            t=$(echo "$pair" | cut -d: -f2)
            if [ "$CTX" = "$c" ]; then
                CONTEXT_TYPE="$t"
                break
            fi
        done
        cat >> "$THEME_DIR/index.theme" <<EOF
[$REL]
Size=48
Context=$CONTEXT_TYPE
Type=Scalable
MinSize=1
MaxSize=512
EOF
    fi
done < <(find "$THEME_DIR" -type d -print0)
fi

# --- Step 5.5: Interactive icon picker (optional GUI) ---
# --- Restore any previously customized .desktop files ---
function restore_icon_overrides() {
    local local_apps="${HOME}/.local/share/applications"
    local count=0
    while IFS= read -r -d '' f; do
        local orig_icon
        orig_icon=$(grep -m1 '^# OriginalIcon=' "$f" 2>/dev/null | sed 's/^# OriginalIcon=//')
        if [ -n "$orig_icon" ]; then
            if grep -q '^Icon=' "$f" 2>/dev/null; then
                sed -i "s|^Icon=.*|Icon=$orig_icon|" "$f"
                sed -i '/^# OriginalIcon=/d' "$f"
                count=$((count + 1))
            fi
        fi
    done < <(find "$local_apps" -name "*.desktop" -print0 2>/dev/null)
    if [ "$count" -gt 0 ]; then
        echo -e "  ${GREEN}↻${NC} Restored $count overridden app icon(s) to theme defaults"
    fi
}

function launch_icon_picker() {
    local theme_path="$1"
    if [ ! -t 0 ]; then
        return
    fi
    echo -e "  ${GREEN}→${NC} Want to hand-pick which icon maps to which app? (y/n)"
    read -r CUSTOMIZE
    if [[ ! "$CUSTOMIZE" =~ ^[Yy]$ ]]; then
        return
    fi
    if [ "$HAS_YAD" -eq 0 ] && [ "$HAS_ZENITY" -eq 0 ]; then
        echo -e "  ${BOLD}!${NC} No GUI picker found — install 'yad' or 'zenity' for interactive selection."
        echo -e "  ${BOLD}  ${NC}   pacman -S yad        (Arch-based)"
        echo -e "  ${BOLD}  ${NC}   apt install yad      (Debian/Ubuntu)"
        return
    fi

    local picker="$GUI_TOOL"

    # Gather all .desktop files from the system
    local desktop_files=()
    while IFS= read -r -d '' f; do
        desktop_files+=("$f")
    done < <(find /usr/share/applications /usr/local/share/applications "$HOME/.local/share/applications" -name "*.desktop" -print0 2>/dev/null)

    if [ ${#desktop_files[@]} -eq 0 ]; then
        echo -e "  ${BOLD}!${NC} No .desktop files found on the system."
        return
    fi

    # Build a list of icon files available in the theme
    local icon_files=()
    while IFS= read -r -d '' f; do
        icon_files+=("$f")
    done < <(find "$theme_path" -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.xpm' \) -print0 2>/dev/null)

    if [ ${#icon_files[@]} -eq 0 ]; then
        echo -e "  ${BOLD}!${NC} No icon files found in the theme."
        return
    fi

    # Let user pick an app from the list
    local app_list=()
    for df in "${desktop_files[@]}"; do
        local name
        name=$(grep -m1 '^Name=' "$df" 2>/dev/null | cut -d= -f2-)
        [ -z "$name" ] && name=$(basename "$df" .desktop)
        app_list+=("$name" "$df")
    done

    while true; do
        local selected
        selected=$("$picker" --list --width=600 --height=450 \
            --title="Icon Picker — Select an App" \
            --text="Choose an application to customize its icon:" \
            --column="Application" --column=".desktop" \
            --print-column=2 \
            --hide-column=2 \
            "${app_list[@]}" 2>/dev/null)
        local pick_exit=$?
        if [ "$pick_exit" -ne 0 ] || [ -z "$selected" ]; then
            echo -e "  ${GREEN}✓${NC} Icon customization done."
            break
        fi

        local app_name
        app_name=$(grep -m1 '^Name=' "$selected" 2>/dev/null | cut -d= -f2-)
        [ -z "$app_name" ] && app_name=$(basename "$selected" .desktop)

        # Build icon preview list for this app
        local icon_entries=()
        for ic in "${icon_files[@]}"; do
            local base
            base=$(basename "$ic")
            icon_entries+=("$base" "$ic")
        done

        local chosen_icon
        chosen_icon=$("$picker" --list --width=700 --height=500 \
            --title="Pick icon for: $app_name" \
            --text="Select an icon from your theme for <b>$app_name</b>:" \
            --column="Icon Name" --column="Path" \
            --print-column=2 \
            "${icon_entries[@]}" 2>/dev/null)
        local icon_exit=$?

        if [ "$icon_exit" -eq 0 ] && [ -n "$chosen_icon" ]; then
            local current_icon
            current_icon=$(grep -m1 '^Icon=' "$selected" 2>/dev/null | cut -d= -f2-)
            if [ -n "$current_icon" ]; then
                local target_file="$selected"
                if [ ! -w "$target_file" ]; then
                    local local_dir="${HOME}/.local/share/applications"
                    mkdir -p "$local_dir"
                    local base_name
                    base_name=$(basename "$target_file")
                    target_file="${local_dir}/${base_name}"
                    if [ ! -f "$target_file" ]; then
                        cp "$selected" "$target_file"
                    fi
                fi
                if [ -w "$target_file" ]; then
                    local icon_stem
                    icon_stem=$(basename "$chosen_icon" | sed 's/\.[^.]*$//')
                    if ! grep -q "^# OriginalIcon=" "$target_file" 2>/dev/null; then
                        sed -i "s|^Icon=\(.*\)|# OriginalIcon=\1\nIcon=$icon_stem|" "$target_file"
                    else
                        sed -i "s|^Icon=.*|Icon=$icon_stem|" "$target_file"
                    fi
                    echo -e "  ${GREEN}✓${NC} $app_name → $icon_stem"
                else
                    echo -e "  ${BOLD}!${NC} Cannot modify $app_name (no write permission)"
                fi
            fi
        fi
    done
    local theme_basename
    theme_basename=$(basename "$theme_path")
    echo -e "  ${GREEN}→${NC} Tip: run \`$(basename "$0") --picker ${theme_basename}\` later to re-open the icon picker"
}

if [ "$PICKER_MODE" -eq 0 ]; then

# --- Step 6: Package into a tarball ---
echo ""
echo -e "  ${GREEN}→${NC} Wrapping everything into a tarball..."
TAR_NAME="${THEME_NAME}.tar.gz"
cd "$TEMP_DIR" || exit 1
    if tar -czf "$TAR_NAME" "$THEME_NAME" > /dev/null 2>&1; then
        mv "$TAR_NAME" "$SCRIPT_INVOCATION_DIR"
        echo ""
        echo -e "  ${GREEN}✓${NC} ${BOLD}Done!${NC} Theme packaged as: ${GREEN}$SCRIPT_INVOCATION_DIR/$TAR_NAME${NC}"
    if [ $SCALABLE_COUNT -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Includes $SCALABLE_COUNT scalable SVGs."
    fi

        echo -e "  ${GREEN}→${NC} Installing to ${BOLD}$ICON_INSTALL_DIR/$THEME_NAME${NC}..."
        mkdir -p "$ICON_INSTALL_DIR"

        # Remove stale symlink in XDG icons dir that would cause duplicate listing
        XDG_LINK="${XDG_DATA_HOME:-$HOME/.local/share}/icons/$THEME_NAME"
        [ -L "$XDG_LINK" ] && rm "$XDG_LINK"

        if cp -a "$THEME_DIR" "$ICON_INSTALL_DIR/"; then
            echo -e "  ${GREEN}✓${NC} Installed."

            if command -v gtk-update-icon-cache &> /dev/null; then
                if gtk-update-icon-cache -f "$ICON_INSTALL_DIR/$THEME_NAME" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✓${NC} Cache updated."
                else
                    echo -e "  ${BOLD}!${NC} Icon cache update failed (theme may still work)."
                fi
            fi

            # Force GTK to re-read icon theme via gsettings (works on most setups)
            if command -v gsettings &> /dev/null; then
                CURRENT=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" 2>/dev/null)
                if [ -n "$CURRENT" ]; then
                    echo -e "  ${GREEN}→${NC} Giving GTK a nudge to refresh..."
                    gsettings set org.gnome.desktop.interface icon-theme "" 2>/dev/null || true
                    gsettings set org.gnome.desktop.interface icon-theme "$CURRENT" 2>/dev/null || true
                    echo -e "  ${GREEN}✓${NC} GTK refreshed."
                fi
            fi

            echo ""
            echo -e "  ${GREEN}✓✓${NC} ${BOLD}All set!${NC} New apps will see your theme."
            echo -e "  ${BOLD}  Tip:${NC} Running apps (especially on standalone WMs) may need a restart."
            echo ""

            # Restore previous overrides so new theme takes effect, then launch picker
            restore_icon_overrides
            launch_icon_picker "$ICON_INSTALL_DIR/$THEME_NAME"

            echo ""
        else
            echo -e "  ${BOLD}!${NC} Couldn't install to ~/.icons/. The tarball is still there for manual use."
        fi
else
    echo "  Something went wrong creating the tarball. Sorry about that."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Step 7: Cleanup ---
echo -e "  ${GREEN}→${NC} Cleaning up temporary files..."
cd "$SCRIPT_INVOCATION_DIR" || exit 1
rm -rf "$TEMP_DIR"

echo -e "  ${GREEN}✓${NC} All done. Enjoy your icons!"
echo ""
fi

# --- Picker-only mode: skip download/processing, just run picker on installed theme ---
if [ "$PICKER_MODE" -eq 1 ]; then
    echo -e "  ${GREEN}→${NC} Running icon picker for installed theme: ${PICKER_THEME}"
    launch_icon_picker "$PICKER_DIR"
    echo -e "  ${GREEN}✓${NC} Done."
fi

exit 0

