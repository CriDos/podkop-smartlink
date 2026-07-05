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

# Return success if stdin contains exactly the given line.
sl_line_in_list() {
    awk -v needle="$1" '$0 == needle { found = 1; exit } END { exit !found }'
}

# Portable file mtime in seconds (busybox stat first, date -r fallback).
sl_file_mtime() {
    stat -c %Y "$1" 2>/dev/null || date -r "$1" +%s 2>/dev/null || echo 0
}

# URL-encode one path segment.
sl_uri_encode() {
    jq -nr --arg v "$1" '$v|@uri' 2>/dev/null || printf '%s' "$1"
}

# Stable key for arbitrary text used in temporary filenames.
sl_text_key() {
    printf '%s' "$1" | md5sum | cut -c1-16
}

# Acquire a mkdir-based lock. Echoes the owner token on success.
sl_lock_acquire() {
    local lock_dir="$1" wait_sec="${2:-0}" waited=0 token pid age owner_pid
    mkdir -p "$STATE_DIR"
    token="$$.$(date +%s)"
    owner_pid="${SL_LOCK_OWNER_PID:-$$}"

    while ! mkdir "$lock_dir" 2>/dev/null; do
        pid="$(cat "$lock_dir/pid" 2>/dev/null)"
        age=$(( $(date +%s) - $(sl_safe_num "$(sl_file_mtime "$lock_dir")") ))
        if [ "$age" -ge 150 ] && { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; }; then
            rm -rf "$lock_dir" 2>/dev/null
            continue
        fi
        [ "$waited" -ge "$wait_sec" ] && return 1
        sleep 1
        waited=$((waited + 1))
    done

    printf '%s\n%s\n' "$owner_pid" "$token" > "$lock_dir/owner"
    printf '%s' "$owner_pid" > "$lock_dir/pid"
    printf '%s' "$token"
    return 0
}

sl_lock_release() {
    local lock_dir="$1" token="$2" cur
    cur="$(sed -n '2p' "$lock_dir/owner" 2>/dev/null)"
    [ -n "$token" ] && [ "$cur" = "$token" ] && rm -rf "$lock_dir" 2>/dev/null
}

sl_lock_set_pid() {
    local lock_dir="$1" token="$2" pid="$3" cur
    cur="$(sed -n '2p' "$lock_dir/owner" 2>/dev/null)"
    [ -n "$token" ] && [ "$cur" = "$token" ] && [ -n "$pid" ] \
        && { printf '%s\n%s\n' "$pid" "$token" > "$lock_dir/owner"; printf '%s' "$pid" > "$lock_dir/pid"; }
}

sl_lock_owner_alive() {
    local lock_dir="$1" token="$2" pid cur
    cur="$(sed -n '2p' "$lock_dir/owner" 2>/dev/null)"
    [ -n "$token" ] && [ "$cur" = "$token" ] || return 1
    pid="$(cat "$lock_dir/pid" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

sl_lock_token() {
    sed -n '2p' "$1/owner" 2>/dev/null
}

sl_lock_active() {
    local lock_dir="$1" pid age
    [ -d "$lock_dir" ] || return 1
    pid="$(cat "$lock_dir/pid" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    age=$(( $(date +%s) - $(sl_safe_num "$(sl_file_mtime "$lock_dir")") ))
    [ "$age" -lt 150 ] && return 0
    return 1
}

sl_refresh_active() {
    sl_lock_active "$STATE_REFRESH_LOCK"
}

sl_refresh_start() {
    local token
    token="$(sl_lock_acquire "$STATE_REFRESH_LOCK" 0)" || return 1
    printf '%s' "$token"
}

sl_refresh_finish() {
    local token="$1"
    sl_lock_release "$STATE_REFRESH_LOCK" "$token"
}

sl_refresh_token() {
    sl_lock_token "$STATE_REFRESH_LOCK"
}

sl_refresh_result_set() {
    local ok="$1" code="$2" message="$3" ts tmp
    ts="$(date +%s)"
    tmp="${STATE_REFRESH_RESULT}.$$"
    jq -c -n --argjson ok "$ok" --arg code "$code" --arg msg "$message" --argjson ts "$ts" \
        '{ok:$ok,code:$code,message:$msg,time:$ts}' > "$tmp" 2>/dev/null \
        && mv "$tmp" "$STATE_REFRESH_RESULT"
}

sl_refresh_result_get() {
    [ -s "$STATE_REFRESH_RESULT" ] && cat "$STATE_REFRESH_RESULT" || printf 'null'
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

# Normalize a semicolon-separated contains-filter list.
sl_filter_normalize() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | tr ';' '\n' | awk '
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 == "") next
            key = tolower($0)
            if (seen[key]++) next
            out = (out == "" ? $0 : out "; " $0)
        }
        END { print out }
    '
}

# Record ping history for all entries in a ping_file using a prebuilt tag map.
# ping_file format: "<latency_or_empty>\t<tag>" per line.
# map_file format:  "<tag>\t<url>\t[...]" per line (only fields 1-2 are used).
# This replaces the 4x-duplicated while-read loop across the codebase.
sl_hist_record_pings() {
    local ping_file="$1"
    local map_file="$2"
    local max_ping
    max_ping="$(sl_safe_num "${SL_CFG_MAX_PING:-0}")"
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
        case "$lat" in
            ''|*[!0-9]*)
                sl_hist_append "$url" "" 0
                ;;
            *)
                if [ "$max_ping" -le 0 ] || [ "$lat" -le "$max_ping" ]; then
                    sl_hist_append "$url" "$lat" 1
                else
                    sl_hist_append "$url" "$lat" 0
                fi
                ;;
        esac
    done
}

# Get URL column (field 1) from a links file, one per line.
sl_links_urls() {
    cut -f1 "$1" 2>/dev/null
}
