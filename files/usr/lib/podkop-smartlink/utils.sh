# Shared utilities for podkop-smartlink

# Tab character for TSV field separators
TAB="$(printf '\t')"

# Safe JSON number: echo 0 for empty/non-numeric
sl_safe_num() {
    case "$1" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$1" ;;
    esac
}

# URL-decode (percent-decoding).
# Uses printf %b after sed conversion. Safe for VPN proxy URLs where
# backslashes are always percent-encoded (%5C), not literal.
sl_url_decode() {
    printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')" 2>/dev/null || printf '%s' "$1"
}

# Read the UCI source list as raw URLs (no prefix).
# Outputs one URL per line, order = priority.
sl_source_list() {
    uci -q get "$SL_NAME.main.source" 2>/dev/null | tr ' ' '\n'
}

# Detect source type from URL: "sub" for http(s)://, "manual" for proxy links.
sl_source_type() {
    case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
        vless://*|ss://*|trojan://*|hy2://*|hysteria2://*|socks://*|socks4://*|socks5://*)
            echo "manual" ;;
        *) echo "sub" ;;
    esac
}

# Record ping history for all entries in a ping_file using a prebuilt tag map.
# ping_file format: "<latency_or_empty>\t<tag>" per line.
# map_file format:  "<tag>\t<url>\t[...]" per line (only fields 1-2 are used).
# This replaces the 4x-duplicated while-read loop across the codebase.
sl_hist_record_pings() {
    local ping_file="$1"
    local map_file="$2"
    [ -s "$ping_file" ] || return 0
    [ -s "$map_file" ] || return 0

    awk -F "$TAB" '
        NR == FNR {
            url[$1] = $2
            next
        }
        {
            tag = $2
            lat = $1
            if (tag in url) {
                u = url[tag]
                print u "\t" lat
            }
        }
    ' "$map_file" "$ping_file" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        local url lat
        url="$(printf '%s' "$line" | cut -f1)"
        lat="$(printf '%s' "$line" | cut -f2)"
        if [ -n "$lat" ]; then
            sl_hist_append "$url" "$lat" 1
        else
            sl_hist_append "$url" "" 0
        fi
    done
}

# Get URL column (field 1) from a links file, one per line.
sl_links_urls() {
    cut -f1 "$1" 2>/dev/null
}
