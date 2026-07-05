# Subscription fetch & parse for podkop-smartlink
# Supports base64 subscriptions and plain-text URL lists.
# Supported schemes: vless ss trojan hy2 hysteria2 socks socks4 socks5

# Compute 8-char md5 hash of a URL (for cache file naming).
sl_sub_hash() {
    printf '%s' "$1" | md5sum | cut -c1-8
}

# Check if a URL is a supported proxy link (case-insensitive scheme).
sl_sub_is_supported() {
    case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
        vless://*|ss://*|trojan://*|hy2://*|hysteria2://*|socks://*|socks4://*|socks5://*)
            return 0 ;;
    esac
    return 1
}

sl_sub_normalize_url() {
    printf '%s' "$1" | tr '\t\r\n' '   ' | sed 's/ /%20/g'
}

sl_sub_normalize_scheme() {
    local url="$1" scheme rest
    case "$url" in
        *://*)
            scheme="${url%%://*}"
            rest="${url#*://}"
            printf '%s://%s' "$(printf '%s' "$scheme" | tr 'A-Z' 'a-z')" "$rest"
            ;;
        *) printf '%s' "$url" ;;
    esac
}

# Extract the fragment (title) from a proxy URL, after the first '#'.
# Decoded, sanitized (tabs/newlines -> spaces).
sl_sub_extract_title() {
    local title
    title="$(printf '%s' "$1" | sed -n 's/^[^#]*#\(.*\)$/\1/p')"
    [ -z "$title" ] && title="$2"
    printf '%s' "$(sl_url_decode "$title")" | tr '\t\r\n' '   '
}

# Extract the host from a proxy URL.
sl_sub_extract_host() {
    local url="$1" core
    case "$url" in
        vless://*|trojan://*|hy2://*|hysteria2://*|socks://*|socks4://*|socks5://*)
            core="${url#*://}"
            case "$core" in *@*) core="${core#*@}" ;; esac
            core="$(printf '%s' "$core" | sed 's/[/?#].*$//')"
            case "$core" in
                \[*\]*) printf '%s' "$core" | sed 's/^\[\([^]]*\)\].*$/\1/' ;;
                *) printf '%s' "$core" | sed 's/:.*$//' ;;
            esac
            ;;
        ss://*)
            core="${url#ss://}"
            case "$core" in
                *@*)
                    core="${core#*@}"
                    core="$(printf '%s' "$core" | sed 's/[/?#].*$//')"
                    case "$core" in
                        \[*\]*) printf '%s' "$core" | sed 's/^\[\([^]]*\)\].*$/\1/' ;;
                        *) printf '%s' "$core" | sed 's/:.*$//' ;;
                    esac
                    ;;
                *)
                    local enc dec
                    enc="$(printf '%s' "$core" | sed 's/[/?#].*$//')"
                    # Add base64 padding (busybox base64 -d requires it)
                    case $((${#enc} % 4)) in
                        1) enc="${enc}===" ;;
                        2) enc="${enc}==" ;;
                        3) enc="${enc}=" ;;
                    esac
                    dec="$(printf '%s' "$enc" | base64 -d 2>/dev/null || true)"
                    printf '%s' "$dec" | grep -q '@' && printf '%s' "${dec#*@}" | sed 's/:.*$//'
                    ;;
            esac
            ;;
    esac
}

# Check if a host is an IP address (IPv4 or IPv6 bracketed).
sl_sub_is_ip() {
    local host="$1"
    case "$host" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*)
            # Validate: 4 octets, 0-255 each (without set -- to preserve caller $@)
            local valid
            valid="$(printf '%s' "$host" | awk -F. '{
                if (NF != 4) { print 0; exit }
                for (i = 1; i <= 4; i++) {
                    if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) { print 0; exit }
                }
                print 1
            }')"
            [ "$valid" = "1" ] && return 0
            return 1 ;;
        \[*\]|*:*) return 0 ;;
    esac
    return 1
}

# Check if a host resolves via DNS (skips IP addresses).
sl_sub_host_resolvable() {
    local host="$1"
    [ -z "$host" ] && return 1
    sl_sub_is_ip "$host" && return 0
    nslookup "$host" 127.0.0.1 >/dev/null 2>&1 || ping -c1 -W2 "$host" >/dev/null 2>&1
}

sl_sub_host_resolvable_cached() {
    local host="$1" cache_file="$2" hit ok
    [ -n "$cache_file" ] || { sl_sub_host_resolvable "$host"; return $?; }
    hit="$(awk -F "$TAB" -v h="$host" '$1==h{print $2; exit}' "$cache_file" 2>/dev/null)"
    case "$hit" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    if sl_sub_host_resolvable "$host"; then
        ok=1
    else
        ok=0
    fi
    printf '%s\t%s\n' "$host" "$ok" >> "$cache_file"
    [ "$ok" = "1" ]
}

# Extract the transport type from a proxy URL (the `type=` query param).
# Defaults to "tcp" if not specified.
sl_sub_extract_transport() {
    local url="$1"
    case "$(printf '%s' "$url" | tr 'A-Z' 'a-z')" in
        ss://*|hy2://*|hysteria2://*|socks://*|socks4://*|socks5://*)
            printf 'tcp'; return ;;
    esac
    local query val
    case "$url" in
        *\?*) query="${url#*\?}" ;;
        *) query="" ;;
    esac
    query="${query%%#*}"
    val="$(printf '%s' "$query" | tr '&' '\n' | awk -F= 'tolower($1)=="type"{print tolower($2); exit}')"
    [ -z "$val" ] && val="tcp"
    printf '%s' "$val"
}

# Check if a transport type is supported.
sl_sub_transport_supported() {
    local t
    for t in $SUPPORTED_TRANSPORTS; do
        [ "$t" = "$1" ] && return 0
    done
    return 1
}

# Process a single proxy link: filter + append to out_file.
# Args: <url> <out_file> <idx> <source_idx> [resolve_cache_file]
# Returns 0 if appended, 1 if skipped.
sl_sub_process_link() {
    local url="$1" out_file="$2" idx="$3" src_idx="$4" resolve_cache="$5"
    url="$(sl_sub_normalize_scheme "$(sl_sub_normalize_url "$url")")"
    sl_sub_is_supported "$url" || return 1
    local title host
    title="$(sl_sub_extract_title "$url" "Config $idx")"
    host="$(sl_sub_extract_host "$url")"
    if [ "$SL_CFG_XHTTP" != "1" ]; then
        local transport
        transport="$(sl_sub_extract_transport "$url")"
        if ! sl_sub_transport_supported "$transport"; then
            log "Skipping unsupported transport '$transport': $title" "debug"
            return 1
        fi
    fi
    if ! sl_sub_host_resolvable_cached "$host" "$resolve_cache"; then
        log "Skipping unresolvable host '$host': $title" "debug"
        return 1
    fi
    printf '%s\t%s\t%s\t%s\n' "$url" "$title" "$host" "$src_idx" >> "$out_file"
}

sl_sub_exclude_match() {
    local url="$1" title="$2" host="$3" filter="$4"
    [ -n "$filter" ] || return 1
    printf '%s' "$filter" | tr ';' '\n' | awk -v hay="$title $host $url" '
        BEGIN { hay = tolower(hay) }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 == "") next
            if (index(hay, tolower($0)) > 0) { print $0; exit 0 }
        }
    '
}

sl_sub_apply_user_filter_file() {
    local in_file="$1" active_file="$2" excluded_file="$3" filter="$4"
    local line url title host src_idx reason
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        url="$(printf '%s' "$line" | cut -f1)"
        title="$(printf '%s' "$line" | cut -f2)"
        host="$(printf '%s' "$line" | cut -f3)"
        src_idx="$(printf '%s' "$line" | cut -f4)"
        reason="$(sl_sub_exclude_match "$url" "$title" "$host" "$filter")"
        if [ -n "$reason" ]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "$url" "$title" "$host" "$src_idx" "$reason" >> "$excluded_file"
        else
            printf '%s\t%s\t%s\t%s\n' "$url" "$title" "$host" "$src_idx" >> "$active_file"
        fi
    done < "$in_file"
}

# Fetch a single subscription URL and append parsed lines to out_file.
# Line format: "<url>\t<title>\t<host>\t<source_idx>"
# Args: <sub_url> <out_file> <start_idx> <source_idx> [resolve_cache_file]
# Returns 0 if at least one line appended.
sl_sub_fetch_one() {
    local sub_url="$1" out_file="$2" idx="$3" src_idx="$4" resolve_cache="$5"
    local raw_file dec_file attempt
    raw_file="${out_file}.raw.$$"
    dec_file="${out_file}.dec.$$"

    for attempt in 1 2 3; do
        if wget -q -O "$raw_file" --timeout=10 --no-check-certificate --user-agent="v2rayNG" "$sub_url" 2>/dev/null && [ -s "$raw_file" ]; then
            break
        fi
        rm -f "$raw_file"
        [ "$attempt" -lt 3 ] && { log "Download attempt $attempt failed, retrying: $sub_url" "debug"; sleep 2; }
    done

    if [ ! -s "$raw_file" ]; then
        rm -f "$raw_file" "$dec_file"
        log "Failed to download subscription after 3 attempts: $sub_url" "warn"
        return 1
    fi

    local norm_file="${out_file}.norm.$$"
    tr '_-' '/+' < "$raw_file" > "$norm_file" 2>/dev/null || cp "$raw_file" "$norm_file"
    case $(($(wc -c < "$norm_file" 2>/dev/null || echo 0) % 4)) in
        2) printf '==' >> "$norm_file" ;;
        3) printf '=' >> "$norm_file" ;;
    esac
    if base64 -d "$norm_file" > "$dec_file" 2>/dev/null && grep -q '://' "$dec_file" 2>/dev/null; then
        :
    elif base64 -d "$raw_file" > "$dec_file" 2>/dev/null && grep -q '://' "$dec_file" 2>/dev/null; then
        :
    else
        cp "$raw_file" "$dec_file"
    fi
    rm -f "$norm_file"

    local appended=0 skipped=0 line
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | sed 's/\r//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        if sl_sub_process_link "$line" "$out_file" "$idx" "$src_idx" "$resolve_cache"; then
            idx=$((idx + 1))
            appended=1
        else
            skipped=$((skipped + 1))
        fi
    done < "$dec_file"

    [ "$skipped" -gt 0 ] && log "Filtered $skipped server(s) from subscription" "info"
    rm -f "$raw_file" "$dec_file" "$norm_file"
    [ "$appended" -eq 1 ] && return 0
    return 2
}

# Record last-update timestamp for a source (keyed by hash).
# Args: <hash>
sl_sub_mark_time() {
    local key="$1" ts
    ts="$(date +%s)"
    local times_file="${STATE_SOURCE_TIMES}.$$"
    : > "$times_file"
    if [ -s "$STATE_SOURCE_TIMES" ]; then
        grep -v "^${key}${TAB}" "$STATE_SOURCE_TIMES" > "$times_file" 2>/dev/null || :
    fi
    printf '%s\t%s\n' "$key" "$ts" >> "$times_file"
    mv "$times_file" "$STATE_SOURCE_TIMES"
}

# Get last-update timestamp for a source (keyed by hash).
# Args: <hash>
sl_sub_get_time() {
    local key="$1"
    [ -s "$STATE_SOURCE_TIMES" ] || { echo 0; return; }
    local ts
    ts="$(awk -F "$TAB" -v k="$key" '$1==k{print $2; exit}' "$STATE_SOURCE_TIMES" 2>/dev/null)"
    echo "${ts:-0}"
}

# Rebuild links from caches + fetch only sources without cache.
# Args: <out_file> [changed_hashes_comma_separated]
# Sets: SL_FETCH_COUNT, SL_FETCH_OK.
sl_sub_rebuild() {
    local out_file="$1" changed="$2"
    local work="${out_file}.work"
    local excluded_work="${out_file}.excluded.work"
    local resolve_cache="${out_file}.resolve.$$"
    : > "$work"
    : > "$excluded_work"
    : > "$resolve_cache"
    SL_FETCH_EMPTY_ACTIVE=0

    local sources
    sources="$(sl_source_list)"
    [ -z "$sources" ] && { SL_FETCH_OK=0; SL_FETCH_COUNT=0; SL_EXCLUDED_COUNT=0; SL_FETCH_EMPTY_ACTIVE=0; rm -f "$work" "$excluded_work" "$resolve_cache"; return 1; }

    local idx=1 any_src=0 src_idx=0 hard_fail=0
    mkdir -p "$STATE_SUB_CACHE"

    local line src_type need_fetch url_hash cache_file exclude_filter
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed 's/\r//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        src_type="$(sl_source_type "$line")"
        url_hash="$(sl_sub_hash "$line")"
        cache_file="${STATE_SUB_CACHE}/sub_${url_hash}"
        exclude_filter="$(sl_filter_normalize "$(uci -q get "$SL_NAME.main.exclude_${url_hash}" 2>/dev/null)")"

        # Only fetch if this hash is in changed list (or no changed list = scheduled full refresh).
        # A non-empty list with no matching hashes means rebuild from cache, fetching only missing caches.
        need_fetch=1
        if [ -n "$changed" ]; then
            need_fetch=0
            case ",$changed," in
                *,"$url_hash",*) need_fetch=1 ;;
            esac
        fi

        if [ "$src_type" = "manual" ]; then
            # Direct link — always process (instant, no download)
            local manual_tmp="${STATE_DIR}/manual_${url_hash}.$$"
            : > "$manual_tmp"
            if sl_sub_process_link "$line" "$manual_tmp" "$idx" "$src_idx" "$resolve_cache"; then
                sl_sub_apply_user_filter_file "$manual_tmp" "$work" "$excluded_work" "$exclude_filter"
                idx=$((idx + 1))
                any_src=1
            fi
            rm -f "$manual_tmp"
            sl_sub_mark_time "$url_hash"
        else
            if [ "$need_fetch" = "1" ] || [ ! -s "$cache_file" ]; then
                # Fetch this source into a temp file, then merge
                local src_tmp="${STATE_DIR}/src_${url_hash}.tmp"
                : > "$src_tmp"
                sl_sub_fetch_one "$line" "$src_tmp" "$idx" "$src_idx" "$resolve_cache"
                local fetch_rc=$?
                if [ "$fetch_rc" -eq 0 ]; then
                    sl_sub_apply_user_filter_file "$src_tmp" "$work" "$excluded_work" "$exclude_filter"
                    cut -f1-3 "$src_tmp" > "${cache_file}.new" 2>/dev/null
                    mv "${cache_file}.new" "$cache_file" 2>/dev/null
                    any_src=1
                    sl_sub_mark_time "$url_hash"
                elif [ "$fetch_rc" -eq 2 ]; then
                    log "Subscription has no usable servers, clearing cache for: $line" "warn"
                    rm -f "$cache_file" "${cache_file}.new" 2>/dev/null
                    sl_sub_mark_time "$url_hash"
                elif [ -s "$cache_file" ]; then
                    log "Sub fetch failed, using cache for: $line" "warn"
                    local cache_tmp="${STATE_DIR}/cache_${url_hash}.$$"
                    awk -v si="$src_idx" -F "$TAB" '{print $1"\t"$2"\t"$3"\t"si}' "$cache_file" > "$cache_tmp"
                    sl_sub_apply_user_filter_file "$cache_tmp" "$work" "$excluded_work" "$exclude_filter"
                    rm -f "$cache_tmp"
                    any_src=1
                else
                    log "Sub fetch failed and no cache: $line" "warn"
                    hard_fail=1
                fi
                rm -f "$src_tmp"
            elif [ -s "$cache_file" ]; then
                # Use cache, don't re-download
                local cache_tmp="${STATE_DIR}/cache_${url_hash}.$$"
                awk -v si="$src_idx" -F "$TAB" '{print $1"\t"$2"\t"$3"\t"si}' "$cache_file" > "$cache_tmp"
                sl_sub_apply_user_filter_file "$cache_tmp" "$work" "$excluded_work" "$exclude_filter"
                rm -f "$cache_tmp"
                any_src=1
            fi
            idx=$((idx + 10000))
        fi
        src_idx=$((src_idx + 1))
    done <<EOF
$sources
EOF

    [ "$hard_fail" -eq 1 ] && { SL_FETCH_OK=0; SL_FETCH_COUNT=0; SL_EXCLUDED_COUNT=0; SL_FETCH_EMPTY_ACTIVE=0; rm -f "$work" "$excluded_work" "$resolve_cache"; return 1; }
    [ "$any_src" -ne 1 ] && { SL_FETCH_OK=0; SL_FETCH_COUNT=0; SL_EXCLUDED_COUNT=0; SL_FETCH_EMPTY_ACTIVE=0; rm -f "$work" "$excluded_work" "$resolve_cache"; return 1; }

    awk -F "$TAB" '!seen[$1]++' "$work" > "$out_file"
    awk -F "$TAB" '!seen[$1 FS $4]++' "$excluded_work" > "${out_file}.excluded"
    rm -f "$work" "$excluded_work" "$resolve_cache"
    SL_FETCH_COUNT="$(wc -l < "$out_file" 2>/dev/null || echo 0)"
    SL_EXCLUDED_COUNT="$(wc -l < "${out_file}.excluded" 2>/dev/null || echo 0)"
    if [ "$(sl_safe_num "$SL_FETCH_COUNT")" -le 0 ]; then
        log "No active servers left after subscription filters" "warn"
        SL_FETCH_EMPTY_ACTIVE=1
        SL_FETCH_OK=0
        return 1
    fi
    SL_FETCH_OK=1
    return 0
}
