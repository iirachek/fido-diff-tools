#!/bin/bash

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Defaults ─────────────────────────────────────────────────────────────────
FORCE=false
DRY_RUN=false
FILES=()

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${NC} $(basename "$0") [OPTIONS] FILE [FILE ...]"
    echo ""
    echo "  Downloads the previous version of FIDO metadata HTML documents."
    echo "  The previous version URL is read from the 'Previous Versions:' entry"
    echo "  near the top of each document. Only the first URL is used."
    echo "  Downloaded files are placed in the same directory as the source file."
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -f, --force     Force redownload even if the file already exists"
    echo "      --dry-run   Preview actions without downloading anything"
    echo "  -h, --help      Show this help message and exit"
    echo ""
    echo -e "${BOLD}Output format:${NC}"
    echo "  ✓ source.html → https://…/prev.html (Downloaded)"
    echo "  ─ source.html → https://…/prev.html (Skipped)"
    echo "  ✗ source.html → https://…/prev.html (Failed, HTTP 404)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $(basename "$0") spec.html"
    echo "  $(basename "$0") -f spec-v3.html spec-v2.html"
    echo "  $(basename "$0") --dry-run *.html"
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            echo "Run with -h or --help for usage." >&2
            exit 1
            ;;
        *)
            FILES+=("$1")
            shift
            ;;
    esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No files specified.${NC}" >&2
    echo "Run with -h or --help for usage." >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${CYAN}${BOLD}[Dry Run] No files will be downloaded.${NC}"
    echo ""
fi

# ─── Main loop ────────────────────────────────────────────────────────────────
for file in "${FILES[@]}"; do
    name=$(basename "$file")

    # Verify the source file exists
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}✗ $name → Source file not found${NC}"
        continue
    fi

    # Extract the first href from within ~10 lines of "Previous Versions:"
    # Works on macOS grep (BSD) without -P flag
    prev_url=$(grep -A10 -iE "Previous Versions?:?" "$file" \
        | grep -o 'href="[^"]*"' \
        | head -1 \
        | sed 's/href="//;s/"//')

    if [[ -z "$prev_url" ]]; then
        echo -e "${RED}✗ $name → Could not find a 'Previous Versions:' URL in document${NC}"
        continue
    fi

    prev_name=$(basename "$prev_url")
    dir=$(dirname "$file")
    dest="$dir/$prev_name"

    # ── Dry-run preview ───────────────────────────────────────────────────────
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$dest" && "$FORCE" == false ]]; then
            echo -e "${YELLOW}─ $name → $prev_url${NC}"
            echo -e "  ${YELLOW}Would skip (file already exists: $dest)${NC}"
        elif [[ -f "$dest" && "$FORCE" == true ]]; then
            echo -e "${CYAN}↺ $name → $prev_url${NC}"
            echo -e "  ${CYAN}Would redownload to: $dest${NC}"
        else
            echo -e "${GREEN}↓ $name → $prev_url${NC}"
            echo -e "  ${GREEN}Would download to: $dest${NC}"
        fi
        continue
    fi

    # ── Skip if already present (and not forcing) ─────────────────────────────
    if [[ -f "$dest" && "$FORCE" == false ]]; then
        echo -e "${YELLOW}─ $name → $prev_url (Skipped)${NC}"
        continue
    fi

    # ── Download ──────────────────────────────────────────────────────────────
    http_code=$(curl --silent --show-error --location \
        --output "$dest" \
        --write-out "%{http_code}" \
        "$prev_url" 2>&1)
    curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        echo -e "${RED}✗ $name → $prev_url (Network error, curl exit code $curl_exit)${NC}"
        rm -f "$dest"
    elif [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        echo -e "${GREEN}✓ $name → $prev_url (Downloaded)${NC}"
    else
        echo -e "${RED}✗ $name → $prev_url (Failed, HTTP $http_code)${NC}"
        rm -f "$dest"
    fi
done
