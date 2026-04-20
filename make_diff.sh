#!/bin/bash

# ─── Resolve script's own directory ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTMLDIFF="$SCRIPT_DIR/htmldiff.pl"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Flags ────────────────────────────────────────────────────────────────────
FORCE=false
DRY_RUN=false
POSITIONAL=()

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${NC} $(basename "$0") [OPTIONS] FILE1 FILE2"
    echo -e "       $(basename "$0") [OPTIONS] DIRECTORY"
    echo ""
    echo "  Generates HTML diffs between FIDO specification document versions"
    echo "  by calling htmldiff.pl, which must be in the same directory as this script."
    echo ""
    echo "  In two-file mode, documents are automatically sorted by version, then"
    echo "  date, then status (ps > rd/fd > wd). If order cannot be determined,"
    echo "  you will be prompted to resolve it manually."
    echo ""
    echo "  In directory mode, all documents sharing a common filename prefix are"
    echo "  compared pairwise (all combinations)."
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -f, --force     Regenerate diff even if output file already exists"
    echo "      --dry-run   Preview pairs and output filenames without running htmldiff.pl"
    echo "  -h, --help      Show this help message and exit"
    echo ""
    echo -e "${BOLD}Naming convention:${NC}"
    echo "  Input files:  fido-registry-v2.2-ps-20220523.html"
    echo "                fido-registry-v2.3-ps-20260105.html"
    echo "  Output:       fido-registry-v2.2-ps-20220523-to-v2.3-ps-20260105.diff.html"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $(basename "$0") ../fido-registry-v2.2-ps-20220523.html ../fido-registry-v2.3-ps-20260105.html"
    echo "  $(basename "$0") --dry-run ../specs/"
    echo "  $(basename "$0") -f ../specs/"
}

# ─── Status rank (higher = newer) ────────────────────────────────────────────
status_rank() {
    case "$1" in
        [Pp][Ss])           echo 3 ;;
        [Rr][Dd]|[Ff][Dd]) echo 2 ;;
        [Ww][Dd])           echo 1 ;;
        *)                  echo 0 ;;
    esac
}

# ─── Version comparison: outputs "gt", "lt", or "eq" ─────────────────────────
compare_versions() {
    local v1="$1" v2="$2"
    local IFS='.'
    local -a p1=($v1) p2=($v2)
    local max=${#p1[@]}
    [[ ${#p2[@]} -gt $max ]] && max=${#p2[@]}
    local i
    for ((i=0; i<max; i++)); do
        local a=$((10#${p1[$i]:-0})) b=$((10#${p2[$i]:-0}))
        if   [[ $a -gt $b ]]; then echo "gt"; return
        elif [[ $a -lt $b ]]; then echo "lt"; return
        fi
    done
    echo "eq"
}

# ─── Parse filename into "prefix version status date" ────────────────────────
# Returns empty string if filename does not match the expected convention.
parse_filename() {
    local filename noext
    filename="$(basename "$1")"
    noext="${filename%.html}"
    local pattern='^(.*)-v([0-9]+(\.[0-9]+)*)-([a-zA-Z]+)-([0-9]{8})$'
    if [[ "$noext" =~ $pattern ]]; then
        # BASH_REMATCH indices: [1]=prefix [2]=version [3]=inner group [4]=status [5]=date
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[4]} ${BASH_REMATCH[5]}"
    else
        echo ""
    fi
}

# ─── Determine which of two files is older ───────────────────────────────────
# Returns "1" (file1 is older), "2" (file2 is older), or "ambiguous"
determine_order() {
    local parsed1="$1" parsed2="$2"
    local dummy v1 s1 d1 v2 s2 d2
    read -r dummy v1 s1 d1 <<< "$parsed1"
    read -r dummy v2 s2 d2 <<< "$parsed2"

    # 1. Compare version
    local vcmp
    vcmp=$(compare_versions "$v1" "$v2")
    if   [[ "$vcmp" == "lt" ]]; then echo "1"; return
    elif [[ "$vcmp" == "gt" ]]; then echo "2"; return
    fi

    # 2. Compare date (YYYYMMDD — lexicographic order is correct)
    if   [[ "$d1" < "$d2" ]]; then echo "1"; return
    elif [[ "$d1" > "$d2" ]]; then echo "2"; return
    fi

    # 3. Compare status rank
    local r1 r2
    r1=$(status_rank "$s1")
    r2=$(status_rank "$s2")
    if   [[ $r1 -lt $r2 ]]; then echo "1"; return
    elif [[ $r1 -gt $r2 ]]; then echo "2"; return
    fi

    echo "ambiguous"
}

# ─── Prompt user to identify the newer document ──────────────────────────────
# Returns "1" (file1 is older) or "2" (file2 is older)
prompt_newer() {
    local file1="$1" file2="$2"
    echo "" >&2
    echo -e "${YELLOW}⚠ Cannot automatically determine which document is newer:${NC}" >&2
    echo -e "  1. $(basename "$file1")" >&2
    echo -e "  2. $(basename "$file2")" >&2
    local choice
    while true; do
        echo -ne "  Which is the ${BOLD}newer${NC} document? Enter 1 or 2: " >&2
        read -r choice < /dev/tty
        case "$choice" in
            1) echo "2"; return ;;  # file1 is newer → file2 is older
            2) echo "1"; return ;;  # file2 is newer → file1 is older
            *) echo -e "  ${RED}Please enter 1 or 2.${NC}" >&2 ;;
        esac
    done
}

# ─── Build output filename ────────────────────────────────────────────────────
build_output_name() {
    local older_parsed="$1" newer_parsed="$2"
    local prefix ov os od nv ns nd dummy
    read -r prefix ov os od <<< "$older_parsed"
    read -r dummy  nv ns nd <<< "$newer_parsed"
    echo "${prefix}-v${ov}-${os}-${od}-to-v${nv}-${ns}-${nd}.diff.html"
}

# ─── Validate htmldiff.pl ─────────────────────────────────────────────────────
validate_htmldiff() {
    if [[ ! -f "$HTMLDIFF" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}⚠ Warning: htmldiff.pl not found at $HTMLDIFF${NC}"
            echo -e "  Continuing dry run — no diffs will actually be executed."
            echo ""
        else
            echo -e "${RED}Error: htmldiff.pl not found at: $HTMLDIFF${NC}" >&2
            exit 1
        fi
    fi
}

# ─── Process a single pair of files ──────────────────────────────────────────
process_pair() {
    local file1="$1" file2="$2"

    # Verify both files exist
    local f
    for f in "$file1" "$file2"; do
        if [[ ! -f "$f" ]]; then
            echo -e "${RED}✗ File not found: $f${NC}"
            return 1
        fi
    done

    # Parse filenames
    local parsed1 parsed2
    parsed1=$(parse_filename "$file1")
    parsed2=$(parse_filename "$file2")

    if [[ -z "$parsed1" ]]; then
        echo -e "${RED}✗ Cannot parse filename: $(basename "$file1")${NC}"
        return 1
    fi
    if [[ -z "$parsed2" ]]; then
        echo -e "${RED}✗ Cannot parse filename: $(basename "$file2")${NC}"
        return 1
    fi

    # Verify same directory
    local dir1 dir2
    dir1="$(cd "$(dirname "$file1")" && pwd)"
    dir2="$(cd "$(dirname "$file2")" && pwd)"
    if [[ "$dir1" != "$dir2" ]]; then
        echo -e "${RED}✗ Files must be in the same directory:${NC}"
        echo -e "  $(basename "$file1") → $dir1"
        echo -e "  $(basename "$file2") → $dir2"
        return 1
    fi
    local dir="$dir1"

    # Determine older/newer
    local order
    order=$(determine_order "$parsed1" "$parsed2")
    if [[ "$order" == "ambiguous" ]]; then
        order=$(prompt_newer "$file1" "$file2")
    fi

    local older_file newer_file older_parsed newer_parsed
    if [[ "$order" == "1" ]]; then
        older_file="$file1"; newer_file="$file2"
        older_parsed="$parsed1"; newer_parsed="$parsed2"
    else
        older_file="$file2"; newer_file="$file1"
        older_parsed="$parsed2"; newer_parsed="$parsed1"
    fi

    # Build output path
    local output_name output_path
    output_name=$(build_output_name "$older_parsed" "$newer_parsed")
    output_path="$dir/$output_name"

    local label
    label="$(basename "$older_file") → $(basename "$newer_file")"

    # Skip if output already exists and not forcing
    if [[ -f "$output_path" && "$FORCE" == false ]]; then
        echo -e "${YELLOW}─ $label (Skipped)${NC}"
        echo -e "  ${YELLOW}Output already exists: $output_name${NC}"
        return 0
    fi

    # Dry run preview
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$output_path" ]]; then
            echo -e "${CYAN}↺ $label${NC}"
            echo -e "  ${CYAN}Would regenerate: $output_name${NC}"
        else
            echo -e "${GREEN}↓ $label${NC}"
            echo -e "  ${GREEN}Would create: $output_name${NC}"
        fi
        return 0
    fi

    # Run htmldiff.pl
    perl "$HTMLDIFF" "$older_file" "$newer_file" "$output_path"
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓ $label${NC}"
        echo -e "  ${GREEN}Created: $output_name${NC}"
    else
        echo -e "${RED}✗ $label${NC}"
        echo -e "  ${RED}htmldiff.pl exited with code $exit_code${NC}"
        return 1
    fi
}

# ─── Process all documents in a directory ────────────────────────────────────
process_directory() {
    local dir="$1"
    local tmpfile
    tmpfile=$(mktemp) || { echo -e "${RED}Error: Could not create temporary file.${NC}" >&2; exit 1; }

    # Collect all HTML files matching the naming convention into tmpfile
    # Format per line: {prefix}<TAB>{filepath}
    local filepath parsed prefix
    while IFS= read -r filepath; do
        parsed=$(parse_filename "$filepath")
        [[ -z "$parsed" ]] && continue
        prefix=$(echo "$parsed" | cut -d' ' -f1)
        printf '%s\t%s\n' "$prefix" "$filepath" >> "$tmpfile"
    done < <(find "$dir" -maxdepth 1 -name "*.html" | sort)

    if [[ ! -s "$tmpfile" ]]; then
        echo -e "${YELLOW}No matching HTML files found in: $dir${NC}"
        rm -f "$tmpfile"
        return
    fi

    # Iterate over each unique prefix
    local unique_prefixes
    unique_prefixes=$(cut -f1 "$tmpfile" | sort -u)

    local prefix
    while IFS= read -r prefix; do
        # Collect all files for this prefix
        local group=()
        local p f
        while IFS=$'\t' read -r p f; do
            [[ "$p" == "$prefix" ]] && group+=("$f")
        done < "$tmpfile"

        local count=${#group[@]}

        if [[ $count -lt 2 ]]; then
            echo -e "${YELLOW}─ Only one document found for prefix '$prefix', skipping.${NC}"
            echo ""
            continue
        fi

        local pairs=$(( count * (count - 1) / 2 ))
        echo -e "${BOLD}Prefix: $prefix — $count documents, $pairs pair(s)${NC}"
        echo ""

        # All pairwise combinations
        local i j
        for ((i=0; i<count; i++)); do
            for ((j=i+1; j<count; j++)); do
                process_pair "${group[$i]}" "${group[$j]}"
                echo ""
            done
        done

    done <<< "$unique_prefixes"

    rm -f "$tmpfile"
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)  FORCE=true; shift ;;
        --dry-run)   DRY_RUN=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            echo "Run with -h or --help for usage." >&2
            exit 1 ;;
        *)
            POSITIONAL+=("$1"); shift ;;
    esac
done

# ─── Entry point ──────────────────────────────────────────────────────────────
if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No input specified.${NC}" >&2
    echo "Run with -h or --help for usage." >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${CYAN}${BOLD}[Dry Run] No files will be generated.${NC}"
    echo ""
fi

validate_htmldiff

if [[ ${#POSITIONAL[@]} -eq 1 ]]; then
    if [[ -d "${POSITIONAL[0]}" ]]; then
        process_directory "${POSITIONAL[0]}"
    else
        echo -e "${RED}Error: '${POSITIONAL[0]}' is not a directory.${NC}" >&2
        echo "Provide a directory, or exactly two HTML files." >&2
        exit 1
    fi
elif [[ ${#POSITIONAL[@]} -eq 2 ]]; then
    process_pair "${POSITIONAL[0]}" "${POSITIONAL[1]}"
else
    echo -e "${RED}Error: Expected 1 directory or 2 files, got ${#POSITIONAL[@]} arguments.${NC}" >&2
    echo "Run with -h or --help for usage." >&2
    exit 1
fi
