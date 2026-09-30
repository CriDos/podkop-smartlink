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
# Batched: one awk pass for the tag join, one md5sum for all keys and one awk
# pass that appends/trims the history files (instead of ~10 forks per entry).
sl_hist_record_pings() {
    local ping_file="$1"
    local map_file="$2"
    local max_ping
    max_ping="$(sl_safe_num "${SL_CFG_MAX_PING:-0}")"
    [ -s "$ping_file" ] || return 0
    [ -s "$map_file" ] || return 0

    local rows="${STATE_DIR}/hist_rows.$$" keys="${STATE_DIR}/hist_keys.$$"
    awk -F "$TAB" -v max="$max_ping" '
        NR == FNR { url[$1] = $2; next }
        {
            tag = $2
            if (tag in url) {
                lat = $1
                ok = 0
                if (lat ~ /^[0-9]+$/) {
                    if (max <= 0 || lat + 0 <= max) ok = 1
                } else {
                    lat = ""
                }
                printf "%s\t%s\t%s\n", url[tag], lat, ok
            }
        }
    ' "$map_file" "$ping_file" > "$rows" 2>/dev/null
    if [ ! -s "$rows" ]; then
        rm -f "$rows" "$keys"
        return 0
    fi

    # md5 keys for the unique URLs (one md5sum per URL; md5sum can only hash
    # whole streams, and the per-URL cost is still far below the old path)
    local uniq="${STATE_DIR}/hist_urls.$$" u
    awk -F "$TAB" '{ print $1 }' "$rows" | sort -u > "$uniq" 2>/dev/null
    : > "$keys"
    while IFS= read -r u || [ -n "$u" ]; do
        [ -n "$u" ] || continue
        printf '%s\t%s\n' "$u" "$(sl_hist_key "$u")" >> "$keys"
    done < "$uniq"
    rm -f "$uniq"
    if [ ! -s "$keys" ]; then
        rm -f "$rows" "$keys"
        return 0
    fi
    awk -F "$TAB" -v kf="$keys" '
        NR == FNR { k[$1] = $2; next }
        { print $0 "\t" k[$1] }
    ' "$keys" "$rows" > "${rows}.keyed" 2>/dev/null \
        && mv "${rows}.keyed" "$rows" \
        || { rm -f "$rows" "$keys" "${rows}.keyed"; return 1; }

    local ts
    ts="$(date +%s)"
    mkdir -p "$STATE_HISTORY_DIR"
    _sl_hist_lock || { rm -f "$rows" "$keys"; return 1; }

    awk -F "$TAB" -v dir="$STATE_HISTORY_DIR" -v cap="$HISTORY_MAX_SAMPLES" -v ts="$ts" '
        NF >= 4 && $4 != "" {
            key = $4
            lat = ($2 == "" ? "-" : $2)
            new[key] = new[key] ts "\t" lat "\t" $3 "\n"
            cnt[key]++
        }
        END {
            for (key in new) {
                file = dir "/" key
                n = 0
                while ((getline line < file) > 0) { n++; old[key, n] = line }
                close(file)
                if (n + cnt[key] <= cap) {
                    printf "%s", new[key] >> file
                    close(file)
                    continue
                }
                keep = cap - cnt[key]
                if (keep < 0) keep = 0
                out = ""
                for (i = n - keep + 1; i <= n; i++) out = out old[key, i] "\n"
                printf "%s", out new[key] > file ".tmp"
                close(file ".tmp")
                system("mv " file ".tmp " file)
            }
        }
    ' "$rows" 2>/dev/null

    _sl_hist_unlock
    rm -f "$rows" "$keys"
    return 0
}

# Get URL column (field 1) from a links file, one per line.
sl_links_urls() {
    cut -f1 "$1" 2>/dev/null
}
